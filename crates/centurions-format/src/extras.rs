//! Extra Codes rows in `Data EDCD`: five signed words (ten bytes) that a step names by its ID.
//! A row can be named by any number of steps, and the original editor changes it in place, so every
//! step that names it changes with it. A code may also read the row after the one it names. This module
//! lists those steps, writes a word or a whole row after checking it against what each step reads there,
//! and gives a step a row of its own.
use crate::{Edit, Files, Result, ScriptFamily, navigation, ownership, script_codes, span};
use serde_json::{Value, json};

const ROW: usize = 10;

/// A step that names an Extra Codes row, or whose code reads the row after the one it names.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Caller {
    pub family: ScriptFamily,
    pub id: usize,
    pub branch: u8,
    pub slot: u8,
    pub op: i16,
    /// The row is the one after the step's own.
    pub companion: bool,
}

fn rows(files: &Files) -> usize {
    files.get("Data EDCD").map_or(0, |b| b.len() / ROW)
}

fn words_of(row: &[u8]) -> Vec<i16> {
    row.chunks(2)
        .map(|w| i16::from_be_bytes([w[0], w[1]]))
        .collect()
}

/// Every step of every program that reads an Extra Codes row, with that row.
fn named(files: &Files) -> Vec<(usize, Caller)> {
    let mut found = vec![];
    for family in navigation::FAMILIES {
        for id in 0..navigation::live_rows(files, family) {
            for step in navigation::steps(files, family, id) {
                if step.op == 0 || !script_codes::uses_extra(step.op) || step.operand < 0 {
                    continue;
                }
                let caller = |companion| Caller {
                    family,
                    id,
                    branch: step.branch,
                    slot: step.slot,
                    op: step.op,
                    companion,
                };
                found.push((step.operand as usize, caller(false)));
                if script_codes::has_companion(step.op) {
                    found.push((step.operand as usize + 1, caller(true)));
                }
            }
        }
    }
    found
}

/// The steps that read the row.
pub fn callers(files: &Files, record: usize) -> Vec<Caller> {
    named(files)
        .into_iter()
        .filter(|(row, _)| *row == record)
        .map(|(_, caller)| caller)
        .collect()
}

/// What changing the row touches: its words and the steps that read them.
pub fn impact(files: &Files, record: usize) -> Result<Value> {
    let bytes = span(
        files.get("Data EDCD").ok_or("missing Data EDCD")?,
        record * ROW,
        ROW,
    )?;
    let callers: Vec<Value> = callers(files, record)
        .into_iter()
        .map(|c| {
            let code = script_codes::code(c.op);
            let labels = if c.companion {
                code.and_then(|x| x.companion_labels.clone())
            } else {
                code.map(|x| x.ecodes.clone())
            };
            json!({"family":c.family,"id":c.id,"branch":c.branch,"slot":c.slot,"code":c.op,"companion":c.companion,
                "name":code.map_or(String::new(), |x| x.name.clone()),
                "labels":labels.unwrap_or_default()})
        })
        .collect();
    Ok(json!({"record":record,"rows":rows(files),"words":words_of(bytes),"callers":callers}))
}

/// Checks the words a row would hold against each step that reads it, the ones that change.
fn check_row(files: &Files, record: usize, old: &[i16], words: &[i16]) -> Result<()> {
    for caller in callers(files, record) {
        if caller.companion {
            script_codes::validate_companion_changes(files, caller.op, old, words)?;
        } else {
            script_codes::validate_row_changes(files, caller.op, old, words)?;
        }
    }
    Ok(())
}

#[allow(clippy::single_range_in_vec_init)] // The element declares the owned byte span.
fn write(files: &mut Files, record: usize, words: &[i16]) -> Result<()> {
    let bytes = files.get_mut("Data EDCD").ok_or("missing Data EDCD")?;
    let before = bytes.clone();
    let at = record * ROW;
    for (index, word) in words.iter().enumerate() {
        bytes[at + index * 2..at + index * 2 + 2].copy_from_slice(&word.to_be_bytes());
    }
    if ownership::inspect(&before, bytes, &[at..at + ROW]).unowned_changes != 0 {
        return Err("unowned Extra Codes edit".into());
    }
    Ok(())
}

/// Writes one word of the row. Each step that reads the row must accept the value as that Extra Code.
pub fn set_word(files: &mut Files, record: usize, index: usize, value: i16) -> Result<()> {
    if index >= 5 {
        return Err("an Extra Codes row has five words".into());
    }
    let row = span(
        files.get("Data EDCD").ok_or("missing Data EDCD")?,
        record * ROW,
        ROW,
    )
    .map_err(|_| format!("Data EDCD record {record}: unavailable reference"))?;
    let mut words = words_of(row);
    words[index] = value;
    for caller in callers(files, record) {
        if caller.companion {
            let kinds = script_codes::code(caller.op).and_then(|c| c.companion.as_ref());
            if kinds.is_none_or(|k| k.len() <= index) {
                return Err(format!(
                    "code {} has no second-row Extra Code {}",
                    caller.op,
                    index + 1
                ));
            }
            script_codes::validate_companion_row(files, caller.op, &words)?;
        } else {
            script_codes::validate_extra_word(files, caller.op, index, value)?;
        }
    }
    write(files, record, &words)
}

/// Writes the whole row, checking the words one by one and the words a jump type decides.
pub fn set_row(files: &mut Files, record: usize, words: [i16; 5]) -> Result<()> {
    let old = words_of(
        span(
            files.get("Data EDCD").ok_or("missing Data EDCD")?,
            record * ROW,
            ROW,
        )
        .map_err(|_| format!("Data EDCD record {record}: unavailable reference"))?,
    );
    check_row(files, record, &old, &words)?;
    write(files, record, &words)
}

/// Gives the step an Extra Codes row of its own: a copy of the row it names, in the first row that no
/// step reads and that holds only zeros, else in a new row at the end. A code that also reads the
/// next row gets two such rows side by side. Other steps keep the original.
pub fn make_independent(
    files: &mut Files,
    family: ScriptFamily,
    id: usize,
    branch: u8,
    slot: u8,
) -> Result<()> {
    let step = navigation::steps(files, family, id)
        .into_iter()
        .find(|s| s.branch == branch && s.slot == slot)
        .ok_or("no such step")?;
    if !script_codes::uses_extra(step.op) || step.operand < 0 {
        return Err("the step does not name an Extra Codes row".into());
    }
    let width = if script_codes::has_companion(step.op) {
        2
    } else {
        1
    };
    let source = step.operand as usize;
    let copy = span(
        files.get("Data EDCD").ok_or("missing Data EDCD")?,
        source * ROW,
        ROW * width,
    )?
    .to_vec();
    let referenced: std::collections::BTreeSet<usize> =
        named(files).into_iter().map(|(row, _)| row).collect();
    let bytes = files.get("Data EDCD").unwrap();
    let count = bytes.len() / ROW;
    let free = |row: usize| {
        !referenced.contains(&row) && bytes[row * ROW..(row + 1) * ROW].iter().all(|b| *b == 0)
    };
    let found =
        (0..count).find(|start| *start + width <= count && (*start..*start + width).all(free));
    let target = match found {
        Some(row) => row,
        None => {
            if count + width > i16::MAX as usize {
                return Err("Data EDCD holds no more rows".into());
            }
            files
                .get_mut("Data EDCD")
                .unwrap()
                .extend(std::iter::repeat_n(0, ROW * width));
            count
        }
    };
    files.get_mut("Data EDCD").unwrap()[target * ROW..(target + width) * ROW]
        .copy_from_slice(&copy);
    crate::scripts::patch(files, family, id, branch, slot, step.op, target as i16)
}

/// Routes the edits of this module.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    match edit {
        Edit::ExtraWord {
            record,
            index,
            value,
        } => set_word(files, *record, *index, *value),
        Edit::ExtraRow { record, words } => set_row(files, *record, *words),
        Edit::ExtraIndependent {
            family,
            id,
            branch,
            slot,
        } => make_independent(files, *family, *id, *branch, *slot),
        _ => Err("not an Extra Codes edit".into()),
    }
}
