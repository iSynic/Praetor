//! The map notes of `Data MD2`: 340-byte records that the Maps and Notes menu shows, each a section of a map with marks, a
//! picture, or a scrolling text, and the words of its dialog. The evidence is `docs/original-evidence/notes.md`.
use crate::{Edit, Files, Result, span, text, word};
use serde_json::{Value, json};

/// Bytes of a note.
pub const RECORD: usize = 340;
/// The notes the menu holds and the note flags allow: numbers 0 to 18.
pub const NOTES: usize = 19;
/// Marks of a note.
pub const MARKS: usize = 10;
const WORDS: usize = 84;

/// How many notes the file holds.
pub fn count(files: &Files) -> usize {
    files.get("Data MD2").map_or(0, |b| b.len() / RECORD)
}

fn put(bytes: &mut [u8], at: usize, value: i16) {
    bytes[at..at + 2].copy_from_slice(&value.to_be_bytes());
}

/// The notes a player can reach: those a step gives with code 29, and those with a label of their own in the menu. The rest are
/// leftovers of the file (the bundled scenario's records 5 to 10), which are not checked.
pub fn reachable(files: &Files) -> std::collections::BTreeSet<usize> {
    let mut found: std::collections::BTreeSet<usize> = crate::navigation::steps_of(files, 29)
        .into_iter()
        .map(|(_, _, _, operand)| usize::from(operand.unsigned_abs()))
        .collect();
    if let Ok(labels) = crate::resources::note_labels(files) {
        let dashes = labels["dashes"].as_str().unwrap_or_default();
        for (note, label) in labels["known"].as_array().into_iter().flatten().enumerate() {
            if label.as_str().is_some_and(|label| label != dashes) {
                found.insert(note);
            }
        }
    }
    found
}

/// The notes as the scenario holds them, with the maps and pictures they name.
pub fn view(files: &Files) -> Result<Value> {
    let total = count(files);
    let mut notes = Vec::with_capacity(total);
    for note in 0..total {
        let row = span(&files["Data MD2"], note * RECORD, RECORD)?;
        let marks: Vec<Value> = (0..MARKS)
            .map(|m| {
                Ok(json!([
                    word(row, m * 6)?,
                    word(row, m * 6 + 2)?,
                    word(row, m * 6 + 4)?
                ]))
            })
            .collect::<Result<_>>()?;
        let length = usize::from(row[WORDS]);
        let words = text::decode(&row[WORDS + 1..(WORDS + 1 + length).min(RECORD)]);
        notes.push(json!({"note":note,"marks":marks,"start_x":word(row,60)?,"start_y":word(row,62)?,"level":word(row,64)?,
            "picture":word(row,66)?,"icon_size":word(row,68)?,"show":word(row,70)?,
            "bottom":word(row,80)?,"right":word(row,82)?,"text":words,"text_bytes":length}));
    }
    Ok(json!({"notes":notes,"count":total,"limit":NOTES}))
}

/// Writes the fields of one note; a number just past the last adds a note. The bytes the game does not read are kept.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    let Edit::MapNote {
        note,
        marks,
        start_x,
        start_y,
        level,
        picture,
        icon_size,
        show,
        bottom,
        right,
        text: words,
    } = edit
    else {
        return Err("not a note edit".into());
    };
    let total = count(files);
    if *note > total || *note >= NOTES {
        return Err(format!("the menu holds notes 0 to {}", NOTES - 1));
    }
    if !(1..=320).contains(icon_size) {
        return Err(
            "a note cell is 1 to 320 pixels: a size of 0 divides by zero in the game".into(),
        );
    }
    let maps = files
        .get("Data LD")
        .map_or(0, |b| b.len() / crate::MAP_BYTES);
    if *picture == 0 && *show == 0 && usize::try_from(*level).map_or(true, |l| l >= maps) {
        return Err(format!(
            "a note section is taken from one of the {maps} maps"
        ));
    }
    if !(0..90).contains(start_x) || !(0..90).contains(start_y) {
        return Err("a section starts on a cell of the 90 by 90 map".into());
    }
    if *picture < 0 || *show < 0 {
        return Err("a picture and a text are numbered from 1 (0 for none)".into());
    }
    let bytes = text::encode(words)?;
    if bytes.len() > 255 {
        return Err("a note's words are at most 255 characters".into());
    }
    let file = files.entry("Data MD2".into()).or_default();
    if *note == total {
        file.resize((total + 1) * RECORD, 0);
    }
    let row = &mut file[note * RECORD..(note + 1) * RECORD];
    for (m, mark) in marks.iter().enumerate() {
        for (n, value) in mark.iter().enumerate() {
            put(row, m * 6 + n * 2, *value);
        }
    }
    for (at, value) in [
        (60, start_x),
        (62, start_y),
        (64, level),
        (66, picture),
        (68, icon_size),
        (70, show),
        (80, bottom),
        (82, right),
    ] {
        put(row, at, *value);
    }
    row[WORDS] = bytes.len() as u8;
    row[WORDS + 1..WORDS + 1 + bytes.len()].copy_from_slice(&bytes);
    Ok(())
}

/// Findings about the notes: a section past the map's edge, marks off the section, notes a step names that do not exist or
/// that the flags cannot hold.
pub fn findings(files: &Files) -> Vec<Value> {
    let Ok(view) = view(files) else {
        return vec![];
    };
    let mut found = vec![];
    let finding = |note: usize, message: String| {
        json!({"severity":"warning","message":message,"count":null,"unit":null,
            "where":{"kind":"note","id":note,"label":format!("Note {note}")}})
    };
    let total = view["count"].as_u64().unwrap_or(0) as usize;
    let reachable = reachable(files);
    for entry in view["notes"].as_array().into_iter().flatten().take(NOTES) {
        let value = |name: &str| entry[name].as_i64().unwrap_or(0);
        let note = value("note") as usize;
        if !reachable.contains(&note) {
            continue;
        }
        if value("show") != 0 || value("picture") != 0 {
            continue;
        }
        let size = value("icon_size");
        if size <= 0 {
            found.push(finding(
                note,
                format!(
                    "Note {note} has a cell size of {size}; the game divides by zero and stops"
                ),
            ));
            continue;
        }
        let cells = (320 / size + i64::from(320 / size * size < 320)).max(1);
        if value("start_x") + cells > 90 || value("start_y") + cells > 90 {
            found.push(finding(note, format!("Note {note} shows {cells} cells from ({}, {}), past the edge of the map; the game reads what follows the map's cells there", value("start_x"), value("start_y"))));
        }
    }
    for (family, record, slot, operand) in crate::navigation::steps_of(files, 29) {
        let number = usize::from(operand.unsigned_abs());
        let place = crate::navigation::program_label(family, record, slot);
        let kind = match family.key() {
            "menu" => "choice",
            other => other,
        };
        if number >= NOTES {
            found.push(json!({"severity":"warning","message":format!("{place} gives note {number}; the notes are numbered 0 to {}, and a flag past them writes over the game's own variables", NOTES - 1),
                "count":null,"unit":null,"where":{"kind":kind,"id":record,"slot":slot,"label":place}}));
        } else if number >= total {
            found.push(json!({"severity":"warning","message":format!("{place} gives note {number}, which the scenario does not hold"),
                "count":null,"unit":null,"where":{"kind":kind,"id":record,"slot":slot,"label":place}}));
        }
    }
    found
}
