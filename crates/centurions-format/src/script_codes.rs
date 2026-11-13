//! The table of script codes (`data/script_codes.json`, built by `tools/build_script_codes.py` from the
//! scripting manual and the capability map). It says, for each code, what its ID and its five Extra Codes
//! are and what they may be. Validation and forms read it; nothing is written per code elsewhere.
use crate::{Files, Result, span};
use serde::Deserialize;
use std::sync::OnceLock;

/// What a value of a step or of an Extra Codes row is.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Kind {
    /// The original reads nothing from it.
    Ignored,
    /// A word the code does not read; it is kept as it is.
    Unused,
    /// The number of a row of a table. The sign says how a negative value is read: `magnitude` uses its
    /// absolute value, `nonnegative` refuses it, `negative_ok` takes any negative value as "none" and
    /// `minus_one_ok` takes -1.
    Record {
        file: String,
        stride: usize,
        sign: String,
    },
    /// The number of an Extra Codes row.
    Extra,
    /// A sound number; the sign tells the game whether to wait for the sound.
    Sound,
    /// Any word: a count, an amount, a picture or text number, or a setting.
    Number,
    /// A whole number from `min` to `max`.
    Range {
        min: i16,
        max: i16,
    },
    /// A count whose sign the code reads; its magnitude is `min` to `max`.
    SignedCount {
        min: i16,
        max: i16,
    },
    /// One of the listed values.
    Enum {
        values: Vec<i16>,
    },
    /// A stage counted from 1, with a sign.
    Stage,
    /// A spell or scan number: thousands, hundreds and units each hold the school, level or index plus one, and
    /// the descriptor must lie inside the spell table (schools 1 to 4, levels and indexes 1 to 7).
    Spell,
    /// A value the game handles whatever it is, though the manual advises the inner kind: it is accepted, and Problems
    /// lists a value outside the inner kind. The form offers the inner kind's values.
    /// `hard`, when there is one, is what the game does not handle and is refused.
    Soft {
        inner: Box<Kind>,
        #[serde(default)]
        hard: Option<Box<Kind>>,
    },
    /// A map of the scenario; a negative number means the current map where the code says so.
    Map {
        keep_negative: bool,
    },
    /// A treasure row above 0, or a shop (zero or negative: its number without the sign).
    TreasureOrShop,
    /// A battle number; whether the battle exists is checked with the whole record.
    Battle,
    BattleOrZero,
    TextOrZero,
    TreasureOrZero,
}

/// A condition on one word of an Extra Codes row: its value is one of `values`, or from `min` to `max`.
#[derive(Clone, Debug, Deserialize)]
pub struct Cond {
    pub word: usize,
    pub values: Option<Vec<i16>>,
    pub min: Option<i16>,
    pub max: Option<i16>,
}

/// A word that must be of a kind when the conditions hold: the target of a jump is a script, a
/// simple or a typed encounter, or a branch, as the jump type says.
#[derive(Clone, Debug, Deserialize)]
pub struct Then {
    pub word: usize,
    pub kind: Kind,
}

#[derive(Clone, Debug, Deserialize)]
pub struct Rule {
    pub when: Vec<Cond>,
    pub then: Vec<Then>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct Code {
    pub code: i16,
    pub name: String,
    pub id_class: String,
    pub ecodes: Vec<Option<String>>,
    pub evidence: String,
    pub authorable: bool,
    pub label: Option<String>,
    pub order: Option<i32>,
    pub id: Option<Kind>,
    pub extra: Option<Vec<Kind>>,
    pub rules: Option<Vec<Rule>>,
    /// The kinds of the words of the row that follows the one the ID names, for a code that reads it too.
    pub companion: Option<Vec<Kind>>,
    pub companion_labels: Option<Vec<Option<String>>>,
}

#[derive(Deserialize)]
struct Table {
    codes: Vec<Code>,
}

/// Every code the manual describes, in code order.
pub fn codes() -> &'static [Code] {
    static TABLE: OnceLock<Vec<Code>> = OnceLock::new();
    TABLE.get_or_init(|| {
        serde_json::from_str::<Table>(include_str!("../data/script_codes.json"))
            .expect("the script code table is valid")
            .codes
    })
}

pub fn code(op: i16) -> Option<&'static Code> {
    codes().iter().find(|c| c.code == op)
}

/// Whether the editor writes this code.
pub fn authorable(op: i16) -> bool {
    code(op).is_some_and(|c| c.authorable)
}

/// Whether the number names no code. The game skips such a step and goes on to the next, so it is
/// kept and may be written; Problems lists it.
pub fn is_noop(op: i16) -> bool {
    code(op).is_none()
}

/// Whether the code's ID names an Extra Codes row.
pub fn uses_extra(op: i16) -> bool {
    code(op).is_some_and(|c| c.authorable && matches!(c.id, Some(Kind::Extra)))
}

fn row_exists(files: &Files, file: &str, stride: usize, index: usize) -> bool {
    files.get(file).is_some_and(|b| {
        index
            .checked_mul(stride)
            .is_some_and(|at| span(b, at, stride).is_ok())
    })
}

fn maps(files: &Files) -> usize {
    files
        .get("Data LD")
        .map_or(0, |b| b.len() / crate::MAP_BYTES)
}

/// Checks a value against its kind. `what` names the value in the message.
fn check(files: &Files, op: i16, kind: &Kind, value: i16, what: &str) -> Result<()> {
    let unavailable = |file: &str| format!("code {op} {what}: unavailable reference in {file}");
    match kind {
        Kind::Ignored
        | Kind::Unused
        | Kind::Sound
        | Kind::Number
        | Kind::Battle
        | Kind::BattleOrZero
        | Kind::TextOrZero
        | Kind::TreasureOrZero => Ok(()),
        Kind::Soft { hard, .. } => match hard {
            Some(hard) => check(files, op, hard, value, what),
            None => Ok(()),
        },
        Kind::Range { min, max } => {
            if (*min..=*max).contains(&value) {
                Ok(())
            } else {
                Err(format!("code {op} {what} is {min} to {max}"))
            }
        }
        Kind::Record { file, stride, sign } => {
            let index = match (sign.as_str(), value) {
                ("magnitude", _) => usize::from(value.unsigned_abs()),
                ("negative_ok", v) if v < 0 => return Ok(()),
                ("minus_one_ok", -1) => return Ok(()),
                (_, v) => usize::try_from(v).map_err(|_| {
                    format!("code {op} {what}: a negative value names no row of {file}")
                })?,
            };
            if row_exists(files, file, *stride, index) {
                Ok(())
            } else {
                Err(unavailable(file))
            }
        }
        Kind::Extra => {
            let index = usize::try_from(value).map_err(|_| {
                format!("code {op} {what}: a negative value names no Extra Codes row")
            })?;
            if row_exists(files, "Data EDCD", 10, index) {
                Ok(())
            } else {
                Err(unavailable("Data EDCD"))
            }
        }
        Kind::SignedCount { min, max } => {
            if (*min..=*max).contains(&value.saturating_abs()) {
                Ok(())
            } else {
                Err(format!(
                    "code {op} {what}: the count, without its sign, is {min} to {max}"
                ))
            }
        }
        Kind::Enum { values } => {
            if values.contains(&value) {
                Ok(())
            } else {
                Err(format!("code {op} {what} is one of {values:?}"))
            }
        }
        Kind::Stage => {
            let target = usize::from(value.unsigned_abs())
                .checked_sub(1)
                .ok_or("stage transition uses a signed one-based stage number")?;
            if target >= 20 || !row_exists(files, "Data Mission", 464, target) {
                return Err(format!(
                    "Data Mission record {target} field transition: unavailable stage"
                ));
            }
            Ok(())
        }
        Kind::Spell => {
            let v = i32::from(value);
            if (0..4).contains(&(v / 1000 - 1))
                && (0..7).contains(&(v % 1000 / 100 - 1))
                && (0..7).contains(&(v % 100 - 1))
            {
                Ok(())
            } else {
                Err(format!(
                    "code {op} {what}: {value} names no spell of the spell table"
                ))
            }
        }
        Kind::Map { keep_negative } => {
            if value < 0 && *keep_negative
                || usize::try_from(value).is_ok_and(|map| map < maps(files))
            {
                Ok(())
            } else {
                Err(format!(
                    "code {op} {what}: the scenario holds no map {value}"
                ))
            }
        }
        Kind::TreasureOrShop => {
            let ok = if value > 0 {
                row_exists(files, "Data TD", 88, usize::from(value.unsigned_abs()))
            } else {
                row_exists(files, "Data SD", 3002, usize::from(value.unsigned_abs()))
            };
            if ok {
                Ok(())
            } else {
                Err(format!("code {op} {what}: no such treasure or shop"))
            }
        }
    }
}

/// What the manual advises against in a step: the soft kinds whose inner kind the value is outside of.
pub fn soft_problems(files: &Files, op: i16, id: i16, words: Option<&[i16]>) -> Vec<String> {
    let Some(code) = code(op).filter(|c| c.authorable) else {
        return vec![];
    };
    let mut found = vec![];
    if let Some(Kind::Soft { inner, .. }) = &code.id
        && let Err(message) = check(files, op, inner, id, "ID")
    {
        found.push(message);
    }
    if let (Some(words), Some(kinds)) = (words, &code.extra) {
        for (index, kind) in kinds.iter().enumerate() {
            if let Kind::Soft { inner, .. } = kind
                && let Some(value) = words.get(index)
                && let Err(message) = check(
                    files,
                    op,
                    inner,
                    *value,
                    &format!("Extra Code {}", index + 1),
                )
            {
                found.push(message);
            }
        }
    }
    found
}

/// Checks the ID a step gives a code.
pub fn validate_id(files: &Files, op: i16, id: i16) -> Result<()> {
    if is_noop(op) {
        return Ok(());
    }
    let code = code(op)
        .filter(|c| c.authorable)
        .ok_or("unsupported operations are preserved and read-only")?;
    let Some(kind) = &code.id else {
        return Err("unsupported operations are preserved and read-only".into());
    };
    check(files, op, kind, id, "ID")
}

/// Whether an ID read from a program has a value the code takes, without looking for the rows it names.
pub fn id_shape_ok(op: i16, id: i16) -> bool {
    if is_noop(op) {
        return true;
    }
    let Some(code) = code(op).filter(|c| c.authorable) else {
        return false;
    };
    code.id.as_ref().is_none_or(|kind| shape(kind, id))
}

/// Whether a value looks like the kind, without looking for the rows it names.
fn shape(kind: &Kind, id: i16) -> bool {
    match kind {
        Kind::Record { sign, .. } => sign == "magnitude" || id >= 0,
        Kind::Extra => id >= 0,
        Kind::SignedCount { min, max } => (*min..=*max).contains(&id.saturating_abs()),
        Kind::Range { min, max } => (*min..=*max).contains(&id),
        Kind::Enum { values } => values.contains(&id),
        Kind::Stage => id != 0 && id.unsigned_abs() <= 20,
        Kind::Soft { hard, .. } => hard.as_ref().is_none_or(|hard| shape(hard, id)),
        _ => true,
    }
}

/// Checks one word of an Extra Codes row against what the code that reads it takes there.
pub fn validate_extra_word(files: &Files, op: i16, index: usize, value: i16) -> Result<()> {
    let Some(kind) = code(op)
        .and_then(|c| c.extra.as_ref())
        .and_then(|e| e.get(index))
    else {
        return Err(format!("code {op} has no Extra Code {}", index + 1));
    };
    check(files, op, kind, value, &format!("Extra Code {}", index + 1))
}

/// Checks the five words of a row against the code that reads them: each word by its kind, then the
/// words a jump type decides.
pub fn validate_row(files: &Files, op: i16, words: &[i16]) -> Result<()> {
    for (index, value) in words.iter().enumerate() {
        validate_extra_word(files, op, index, *value)?;
    }
    for rule in code(op)
        .and_then(|c| c.rules.as_ref())
        .into_iter()
        .flatten()
    {
        let holds = rule.when.iter().all(|c| {
            let v = words.get(c.word).copied().unwrap_or(0);
            c.values.as_ref().is_none_or(|values| values.contains(&v))
                && c.min.is_none_or(|min| v >= min)
                && c.max.is_none_or(|max| v <= max)
        });
        if holds {
            for then in &rule.then {
                let value = words.get(then.word).copied().unwrap_or(0);
                check(
                    files,
                    op,
                    &then.kind,
                    value,
                    &format!("Extra Code {}", then.word + 1),
                )?;
            }
        }
    }
    Ok(())
}

/// The programs a step can hand the scene to through the words of its row: a script ("story"), a simple
/// encounter ("choice") or a typed encounter ("typed"), by the kinds the table gives the words and the
/// jump types that decide them. A fresh row of zeros names none.
pub fn row_targets(op: i16, words: &[i16]) -> Vec<(&'static str, i64)> {
    let Some(code) = code(op).filter(|c| c.authorable) else {
        return vec![];
    };
    if words.iter().all(|w| *w == 0) {
        return vec![];
    }
    let kind_of = |kind: &Kind| match kind {
        Kind::Record { file, sign, .. } if sign != "magnitude" => match file.as_str() {
            "Data ED3" => Some("story"),
            "Data ED" => Some("choice"),
            "Data ED2" => Some("typed"),
            _ => None,
        },
        _ => None,
    };
    let mut found: Vec<(&'static str, i64)> = vec![];
    let mut add = |kind: &Kind, value: i16| {
        if value >= 0
            && let Some(name) = kind_of(kind)
            && !found.contains(&(name, i64::from(value)))
        {
            found.push((name, i64::from(value)));
        }
    };
    for (index, kind) in code.extra.iter().flatten().enumerate() {
        add(kind, words.get(index).copied().unwrap_or(0));
    }
    for rule in code.rules.iter().flatten() {
        let holds = rule.when.iter().all(|c| {
            let v = words.get(c.word).copied().unwrap_or(0);
            c.values.as_ref().is_none_or(|values| values.contains(&v))
                && c.min.is_none_or(|min| v >= min)
                && c.max.is_none_or(|max| v <= max)
        });
        if holds {
            for then in &rule.then {
                add(&then.kind, words.get(then.word).copied().unwrap_or(0));
            }
        }
    }
    found
}

/// Checks a row against the code that reads it, but only the words that differ from the old row, and the
/// rules that involve one of them. A scenario may hold a value the code does not take (the original
/// writes past a map layer when a column is 90); it stays editable, and Problems lists it.
pub fn validate_row_changes(files: &Files, op: i16, old: &[i16], new: &[i16]) -> Result<()> {
    let changed = |index: usize| old.get(index) != new.get(index);
    for (index, value) in new.iter().enumerate() {
        if changed(index) {
            validate_extra_word(files, op, index, *value)?;
        }
    }
    for rule in code(op)
        .and_then(|c| c.rules.as_ref())
        .into_iter()
        .flatten()
    {
        let involved = rule
            .when
            .iter()
            .map(|c| c.word)
            .chain(rule.then.iter().map(|t| t.word));
        if !involved.into_iter().any(changed) {
            continue;
        }
        let holds = rule.when.iter().all(|c| {
            let v = new.get(c.word).copied().unwrap_or(0);
            c.values.as_ref().is_none_or(|values| values.contains(&v))
                && c.min.is_none_or(|min| v >= min)
                && c.max.is_none_or(|max| v <= max)
        });
        if holds {
            for then in &rule.then {
                let value = new.get(then.word).copied().unwrap_or(0);
                check(
                    files,
                    op,
                    &then.kind,
                    value,
                    &format!("Extra Code {}", then.word + 1),
                )?;
            }
        }
    }
    Ok(())
}

/// The same for the row after the one a code's ID names.
pub fn validate_companion_changes(files: &Files, op: i16, old: &[i16], new: &[i16]) -> Result<()> {
    let kinds = code(op)
        .and_then(|c| c.companion.as_ref())
        .ok_or("the code reads no second row")?;
    for (index, value) in new.iter().enumerate() {
        if old.get(index) != Some(value) {
            let kind = kinds
                .get(index)
                .ok_or("an Extra Codes row has five words")?;
            check(
                files,
                op,
                kind,
                *value,
                &format!("second row, Extra Code {}", index + 1),
            )?;
        }
    }
    Ok(())
}

/// Whether the code also reads the row after the one its ID names.
pub fn has_companion(op: i16) -> bool {
    code(op).is_some_and(|c| c.authorable && c.companion.is_some())
}

/// Checks the five words of the row after the one a code's ID names.
pub fn validate_companion_row(files: &Files, op: i16, words: &[i16]) -> Result<()> {
    let kinds = code(op)
        .and_then(|c| c.companion.as_ref())
        .ok_or("the code reads no second row")?;
    for (index, value) in words.iter().enumerate() {
        let kind = kinds
            .get(index)
            .ok_or("an Extra Codes row has five words")?;
        check(
            files,
            op,
            kind,
            *value,
            &format!("second row, Extra Code {}", index + 1),
        )?;
    }
    Ok(())
}
