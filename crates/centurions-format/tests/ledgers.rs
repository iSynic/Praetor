//! The editor's item and monster field tables against the evidence ledgers in `docs/original-evidence`.
//!
//! A ledger records the offset, width and range each field was audited at. The editor's tables and the
//! ledgers must name the same fields at the same places, so a table never changes without its audit.
use centurions_format::{Files, items, monsters};
use serde_json::Value;
use std::collections::BTreeMap;

const ITEMS: &str = include_str!("../../../docs/original-evidence/data-ni-ledger.md");
const MONSTERS: &str = include_str!("../../../docs/original-evidence/data-md-ledger.md");

/// A field slot: its offset, its width and its range.
type Slot = (usize, usize, i64, i64);

/// The rows of a ledger's field table: `name | 0xOFFSET/WIDTH | LOW..HIGH | …`. A row whose range is not
/// a pair of numbers (a field the ledger lists only for its offset) is left out.
fn ledger(text: &str) -> BTreeMap<String, Slot> {
    let mut rows = BTreeMap::new();
    for line in text.lines() {
        let cells: Vec<&str> = line.split('|').map(str::trim).collect();
        let [_, name, place, range, ..] = cells.as_slice() else {
            continue;
        };
        let (Some(place), Some((low, high))) = (place.strip_prefix("0x"), range.split_once(".."))
        else {
            continue;
        };
        let Some((offset, width)) = place.split_once('/') else {
            continue;
        };
        let (Ok(offset), Ok(width), Ok(low), Ok(high)) = (
            usize::from_str_radix(offset, 16),
            width.parse(),
            low.parse(),
            high.parse(),
        ) else {
            continue;
        };
        assert!(
            rows.insert((*name).to_string(), (offset, width, low, high))
                .is_none(),
            "the ledger lists {name} twice"
        );
    }
    rows
}

fn number(field: &Value, key: &str) -> i64 {
    field[key]
        .as_i64()
        .unwrap_or_else(|| panic!("{key} of {field}"))
}

/// The editor's slots by the name the ledger gives them: the field, with `[n]` after it where it has several.
fn editor(
    fields: &[Value],
    name: impl Fn(&str) -> String,
    always_indexed: bool,
) -> BTreeMap<String, Slot> {
    let mut count: BTreeMap<&str, usize> = BTreeMap::new();
    for field in fields {
        *count.entry(field["field"].as_str().unwrap()).or_default() += 1;
    }
    fields
        .iter()
        .map(|field| {
            let key = field["field"].as_str().unwrap();
            let label = if always_indexed || count[key] > 1 {
                format!("{}[{}]", name(key), number(field, "index"))
            } else {
                name(key)
            };
            let slot = (
                number(field, "offset") as usize,
                number(field, "width") as usize,
                number(field, "minimum"),
                number(field, "maximum"),
            );
            (label, slot)
        })
        .collect()
}

/// `snake_case` as the ledger spells an item field: `ElementalDamage`.
fn pascal(name: &str) -> String {
    name.split('_')
        .map(|word| word[..1].to_uppercase() + &word[1..])
        .collect()
}

fn same(kind: &str, editor: &BTreeMap<String, Slot>, ledger: &BTreeMap<String, Slot>) {
    for (name, slot) in editor {
        assert_eq!(
            ledger.get(name),
            Some(slot),
            "the editor's {kind} field {name} is not in the ledger as the editor has it"
        );
    }
    for name in ledger.keys() {
        assert!(
            editor.contains_key(name),
            "the ledger's {kind} field {name} is not in the editor"
        );
    }
}

#[test]
fn the_item_fields_are_the_ones_the_ledger_audited() {
    let mut files = Files::new();
    files.insert("Data NI".into(), vec![0; items::ROW]);
    files.insert("Data NI Des".into(), vec![0; items::DESCRIPTION]);
    let view = items::view(&files, 0).unwrap();
    same(
        "item",
        &editor(view["fields"].as_array().unwrap(), pascal, false),
        &ledger(ITEMS),
    );
}

#[test]
fn the_monster_fields_are_the_ones_the_ledger_audited() {
    let projection = monsters::projection(&vec![0; monsters::ROW]);
    // The stats, stories, spells and name are edited apart from the projection; the ledger lists them for
    // their offsets only ("see edits"), and `ledger` leaves those rows out.
    let audited = ledger(MONSTERS);
    same(
        "monster",
        &editor(projection.as_array().unwrap(), str::to_string, true),
        &audited,
    );
}
