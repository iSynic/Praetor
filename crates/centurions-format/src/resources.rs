//! The resources of the scenario's own resource file that the editor authors: scrolling texts (a `TEXT` and the
//! `styl` that sets its fonts, shown by code 62 and the opening prologue) and, for pictures, icons and sounds, any
//! resource set as bytes.
use crate::resource_fork::{self, Fork};
use crate::{Edit, Files, Result, StyleRun, text};
use serde_json::{Value, json};

const FILE: &str = "Scenario.rsrc";
const LIMIT: usize = 8 * 1024 * 1024;
/// The resource types an edit may set.
const KINDS: [&[u8; 4]; 6] = [b"TEXT", b"styl", b"PICT", b"cicn", b"snd ", b"STR#"];

fn kind_of(name: &str) -> Result<[u8; 4]> {
    let bytes = name.as_bytes();
    let kind: [u8; 4] = bytes
        .try_into()
        .map_err(|_| format!("a resource type is four characters, not {name:?}"))?;
    if !KINDS.contains(&&kind) {
        return Err(format!("the editor does not author {name:?} resources"));
    }
    Ok(kind)
}

/// Bytes as the lowercase hex a resource edit holds.
pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub fn unhex(hex: &str) -> Result<Vec<u8>> {
    let digits = hex.as_bytes();
    if !digits.len().is_multiple_of(2) || digits.len() / 2 > LIMIT {
        return Err("a resource is hex of at most 8 MB".into());
    }
    let value = |digit: u8| {
        char::from(digit)
            .to_digit(16)
            .ok_or_else(|| "a resource is written in the hex digits 0 to 9 and a to f".to_string())
    };
    digits
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| Ok((value(pair[0])? * 16 + value(pair[1])?) as u8))
        .collect()
}

fn fork(files: &Files) -> Result<Fork> {
    let file = files
        .get(FILE)
        .ok_or("the scenario holds no resource file")?;
    Fork::read(resource_fork::fork_of(file)?)
}

fn store(files: &mut Files, fork: &Fork) -> Result<()> {
    let file = files
        .get_mut(FILE)
        .ok_or("the scenario holds no resource file")?;
    *file = resource_fork::with_fork(file, &fork.write()?)?;
    Ok(())
}

/// The `STR#` list of the scenario's item names: 200 names for items 800 to 999.
pub const ITEM_LIST: i16 = 801;
pub const ITEM_NAMES: usize = 200;
/// The two lists of the Maps and Notes menu's labels, and how many strings each holds; labels 1 to 19 are shown.
pub const NOTE_UNKNOWN: i16 = -101;
pub const NOTE_KNOWN: i16 = -102;
pub const NOTE_STRINGS: usize = 20;
pub const NOTES: usize = 19;

/// The strings of a `STR#` resource as bytes, as many as it says it holds.
fn string_list(payload: &[u8]) -> Vec<Vec<u8>> {
    let count = payload
        .get(..2)
        .map_or(0, |c| usize::from(u16::from_be_bytes([c[0], c[1]])));
    let mut at = 2;
    let mut names = vec![];
    for _ in 0..count {
        let Some(length) = payload.get(at).map(|b| usize::from(*b)) else {
            break;
        };
        names.push(
            payload
                .get(at + 1..at + 1 + length)
                .unwrap_or_default()
                .to_vec(),
        );
        at += 1 + length;
    }
    names
}

fn string_list_bytes(names: &[Vec<u8>]) -> Vec<u8> {
    let mut out = (names.len() as u16).to_be_bytes().to_vec();
    for name in names {
        out.push(name.len() as u8);
        out.extend_from_slice(name);
    }
    out
}

/// Reads the runs of a `styl` resource.
pub fn runs_of(styl: &[u8]) -> Vec<StyleRun> {
    let count = styl
        .get(..2)
        .map_or(0, |c| usize::from(u16::from_be_bytes([c[0], c[1]])));
    (0..count)
        .filter_map(|run| {
            let b = styl.get(2 + run * 20..22 + run * 20)?;
            let word = |at: usize| i16::from_be_bytes([b[at], b[at + 1]]);
            Some(StyleRun {
                start: u32::from_be_bytes([b[0], b[1], b[2], b[3]]),
                height: word(4),
                ascent: word(6),
                font: word(8),
                face: b[10],
                size: word(12),
                color: [word(14) as u16, word(16) as u16, word(18) as u16],
            })
        })
        .collect()
}

fn styl_of(runs: &[StyleRun]) -> Vec<u8> {
    let mut out = (runs.len() as u16).to_be_bytes().to_vec();
    for run in runs {
        out.extend_from_slice(&run.start.to_be_bytes());
        out.extend_from_slice(&run.height.to_be_bytes());
        out.extend_from_slice(&run.ascent.to_be_bytes());
        out.extend_from_slice(&run.font.to_be_bytes());
        out.push(run.face);
        out.push(0);
        out.extend_from_slice(&run.size.to_be_bytes());
        for channel in run.color {
            out.extend_from_slice(&channel.to_be_bytes());
        }
    }
    out
}

/// The runs that remain valid for a text of `length` characters: those that start inside it, always the first.
fn clamp(mut runs: Vec<StyleRun>, length: usize) -> Vec<StyleRun> {
    runs.sort_by_key(|run| run.start);
    runs.dedup_by_key(|run| run.start);
    let mut kept: Vec<StyleRun> = runs
        .into_iter()
        .enumerate()
        .filter(|(index, run)| *index == 0 || (run.start as usize) < length)
        .map(|(_, run)| run)
        .collect();
    if let Some(first) = kept.first_mut() {
        first.start = 0;
    }
    kept
}

/// The style a new text starts with: the first run of the lowest text that has one, else Geneva 12 in black.
fn default_run(fork: &Fork) -> StyleRun {
    let mut ids = fork.ids(b"styl");
    ids.sort_unstable();
    ids.first()
        .and_then(|id| fork.get(b"styl", *id))
        .and_then(|resource| runs_of(&resource.data).first().copied())
        .unwrap_or(StyleRun {
            start: 0,
            height: 14,
            ascent: 11,
            font: 3,
            face: 0,
            size: 12,
            color: [0, 0, 0],
        })
}

/// Applies one resource edit.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    patch_many(files, &[edit])
}

/// Applies resource edits in order, reading the resource file once and writing it once.
pub fn patch_many(files: &mut Files, edits: &[&Edit]) -> Result<()> {
    if edits.is_empty() {
        return Ok(());
    }
    let mut fork = fork(files)?;
    for edit in edits {
        change(&mut fork, edit)?;
    }
    store(files, &fork)
}

fn change(fork: &mut Fork, edit: &Edit) -> Result<()> {
    match edit {
        Edit::ResourceChange {
            resource_type,
            id,
            data,
        } => {
            let data = data.as_deref().map(unhex).transpose()?;
            fork.set(&kind_of(resource_type)?, *id, data);
        }
        Edit::ScrollText {
            id,
            text: body,
            runs,
        } => {
            let bytes = text::encode(body)?;
            if bytes.len() > 32_000 {
                return Err("a scrolling text holds at most 32,000 characters".into());
            }
            let saved = fork
                .get(b"styl", *id)
                .map(|resource| runs_of(&resource.data))
                .filter(|runs| !runs.is_empty());
            // A text always has a style: the one given, the one it has, or the first of the scenario's texts.
            let runs = runs
                .clone()
                .filter(|runs| !runs.is_empty())
                .or(saved)
                .unwrap_or_else(|| vec![default_run(fork)]);
            let runs = clamp(runs, bytes.len());
            fork.set(b"TEXT", *id, Some(bytes));
            fork.set(b"styl", *id, Some(styl_of(&runs)));
        }
        Edit::ItemName { index, name } => {
            if *index >= ITEM_NAMES {
                return Err(format!(
                    "a scenario has {ITEM_NAMES} item names, numbered 0 to {}",
                    ITEM_NAMES - 1
                ));
            }
            let bytes = text::encode(name)?;
            if bytes.len() > 255 {
                return Err("an item name is at most 255 characters".into());
            }
            let mut names = fork
                .get(b"STR#", ITEM_LIST)
                .map(|resource| string_list(&resource.data))
                .unwrap_or_default();
            names.resize(names.len().max(ITEM_NAMES), vec![]);
            names[*index] = bytes;
            fork.set(b"STR#", ITEM_LIST, Some(string_list_bytes(&names)));
        }
        Edit::NoteLabel {
            note,
            identified,
            text,
        } => {
            if !(1..=NOTES).contains(note) {
                return Err(format!("the Maps and Notes menu holds notes 1 to {NOTES}"));
            }
            let bytes = text::encode(text)?;
            if bytes.len() > 255 {
                return Err("a note label is at most 255 characters".into());
            }
            let list = if *identified {
                NOTE_KNOWN
            } else {
                NOTE_UNKNOWN
            };
            let mut labels = fork
                .get(b"STR#", list)
                .map(|resource| string_list(&resource.data))
                .unwrap_or_default();
            // A list the scenario lacks starts with the dashes the bundled scenario's unused labels hold.
            labels.resize(
                labels.len().max(NOTE_STRINGS),
                b"--------------------".to_vec(),
            );
            labels[note - 1] = bytes;
            fork.set(b"STR#", list, Some(string_list_bytes(&labels)));
        }
        Edit::ScrollTextRemove { id } => {
            fork.set(b"TEXT", *id, None);
            fork.set(b"styl", *id, None);
        }
        _ => return Err("not a resource edit".into()),
    }
    Ok(())
}

/// The labels of the Maps and Notes menu, as the scenario holds them: for each of notes 1 to 19 the label before the party has it
/// and the label after. A list the scenario lacks reads as the dashes the game shows for an unused note.
pub fn note_labels(files: &Files) -> Result<Value> {
    let fork = fork(files)?;
    let read = |list: i16| -> Vec<String> {
        let mut labels: Vec<Vec<u8>> = fork
            .get(b"STR#", list)
            .map(|resource| string_list(&resource.data))
            .unwrap_or_default();
        labels.resize(
            labels.len().max(NOTE_STRINGS),
            b"--------------------".to_vec(),
        );
        labels
            .iter()
            .take(NOTES)
            .map(|label| text::decode(label))
            .collect()
    };
    Ok(
        json!({"unknown":read(NOTE_UNKNOWN),"known":read(NOTE_KNOWN),"dashes":"--------------------"}),
    )
}

/// The scrolling texts of the scenario: each `TEXT`, how long it is, how it begins and how many style runs it has.
pub fn scroll_texts(files: &Files) -> Result<Value> {
    let fork = fork(files)?;
    let mut ids = fork.ids(b"TEXT");
    ids.sort_unstable();
    let rows: Vec<Value> = ids
        .into_iter()
        .filter_map(|id| {
            let body = &fork.get(b"TEXT", id)?.data;
            // The words it begins with: the first line that is not the banner the game's own texts open with.
            let first: String = text::decode(&body[..body.len().min(2000)])
                .lines()
                .map(str::trim)
                .find(|line| !line.is_empty() && !line.starts_with("<<<"))
                .unwrap_or("")
                .chars()
                .take(80)
                .collect();
            let runs = fork.get(b"styl", id).map_or(0, |s| runs_of(&s.data).len());
            let words = text::decode(body);
            Some(json!({"id":id,"length":body.len(),"first":first,"runs":runs,"words":words}))
        })
        .collect();
    Ok(json!({"rows":rows}))
}

/// The whole words of every scrolling text, by number, so that a search can look in all of them and not only in what
/// each begins with.
pub fn scroll_text_words(files: &Files) -> Result<Vec<(i16, String)>> {
    let fork = fork(files)?;
    let mut ids = fork.ids(b"TEXT");
    ids.sort_unstable();
    Ok(ids
        .into_iter()
        .filter_map(|id| Some((id, text::decode(&fork.get(b"TEXT", id)?.data))))
        .collect())
}

/// One scrolling text with its style runs.
pub fn scroll_text(files: &Files, id: i16) -> Result<Value> {
    let fork = fork(files)?;
    let body = fork
        .get(b"TEXT", id)
        .ok_or_else(|| format!("no scrolling text {id}"))?;
    let runs = fork
        .get(b"styl", id)
        .map(|s| runs_of(&s.data))
        .unwrap_or_default();
    let uses: Vec<Value> = crate::navigation::steps_of(files, 62)
        .into_iter()
        .filter(|(_, _, _, operand)| *operand == id)
        .map(|(family, record, slot, _)| {
            json!({"family":family,"id":record,"slot":slot,
                "label":crate::navigation::program_label(family, record, slot)})
        })
        .collect();
    Ok(
        json!({"id":id,"text":text::decode(&body.data),"length":body.data.len(),"runs":runs,
        "has_styl":fork.get(b"styl", id).is_some(),"uses":uses}),
    )
}
