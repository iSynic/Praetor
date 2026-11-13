//! Bounded fields verified against original trigger/encounter instruction paths.
use crate::{ConditionField as F, Edit, Files, Result, ScriptFamily as S, span, word};
use serde_json::{Value, json};

fn walking(files: &Files, id: usize) -> Result<usize> {
    let b = files.get("Data LD").ok_or("missing Data LD")?;
    let maps = b.len() / crate::MAP_BYTES;
    if !(1..=20).contains(&maps) || b.len() % crate::MAP_BYTES != 0 || id >= maps * 100 {
        return Err("walking record is outside native maps".into());
    }
    let at = id.checked_mul(42).ok_or("walking index overflow")?;
    span(files.get("Data DD").ok_or("missing Data DD")?, at, 42)?;
    Ok(at)
}

fn descriptor(family: S, field: F, index: usize) -> Result<(usize, usize, i16, i16)> {
    Ok(match (family, field, index) {
        (S::Menu, F::ChoiceSelector, 0..4) => (96 + index, 1, 0, 4),
        (S::Menu, F::CanBackOut, 0) => (100, 1, -128, 127),
        (S::Menu, F::Attempts, 0) => (101, 1, -128, 127),
        (S::Typed, F::PhysicalSelector, 0) => (96, 1, 0, 4),
        (S::Typed, F::PasswordSelector, 0) => (97, 1, 0, 4),
        (S::Typed, F::Attempts, 0) => (152, 1, -128, 127),
        (S::Typed, F::Dialogue, 0) => (154, 2, -32768, 32767),
        (S::Typed, F::CanBackOut, 0) => (151, 1, -128, 127),
        (S::Typed, F::RequiredAction, 0..8) => (98 + index, 1, 0, 1),
        (S::Typed, F::SpellCriterion, 0..10) => (106 + index * 2, 2, 0, 32767),
        (S::Typed, F::SpellSelector, 0..10) => (126 + index, 1, 0, 4),
        (S::Typed, F::ItemCriterion, 0..5) => (136 + index * 2, 2, 0, 32767),
        (S::Typed, F::ItemSelector, 0..5) => (146 + index, 1, 0, 4),
        _ => return Err("unresolved condition field or invalid index".into()),
    })
}

pub fn projection(files: &Files, family: S, id: usize) -> Result<Value> {
    let row = span(
        files.get(family.path()).ok_or("missing native table")?,
        id.checked_mul(family.stride())
            .ok_or("record index overflow")?,
        family.stride(),
    )?;
    let mut fields = Vec::new();
    let layout: Vec<(F, usize, &str)> = match family {
        S::Walking => {
            return Ok(
                json!({"fields":[],"chance":row[7] as i8,"chance_authorable":walking(files,id).is_ok()}),
            );
        }
        S::Story => vec![],
        S::Menu => vec![
            (
                F::ChoiceSelector,
                4,
                "Choice selector (0 hides, 1–4 branches)",
            ),
            (F::CanBackOut, 1, "Can back out (0 no, anything else yes)"),
            (F::Attempts, 1, "Tries the party gets"),
        ],
        S::Typed => vec![
            (
                F::PhysicalSelector,
                1,
                "Physical result selector (0 disables)",
            ),
            (
                F::PasswordSelector,
                1,
                "Password result selector (0 disables typed input)",
            ),
            (F::RequiredAction, 8, "Required physical action"),
            (
                F::SpellCriterion,
                10,
                "Spell ID / category criterion (first entry gates UI)",
            ),
            (F::SpellSelector, 10, "Spell result selector"),
            (
                F::ItemCriterion,
                5,
                "Item ID criterion (first entry gates UI)",
            ),
            (F::ItemSelector, 5, "Item result selector"),
            (F::CanBackOut, 1, "Can back out (0 no, anything else yes)"),
            (F::Attempts, 1, "Tries the party gets"),
            (F::Dialogue, 1, "Dialogue message shown with the encounter"),
        ],
    };
    for (field, count, label) in layout {
        for index in 0..count {
            let (at, width, min, max) = descriptor(family, field, index)?;
            let value = if width == 1 {
                i16::from(row[at] as i8)
            } else {
                word(row, at)?
            };
            let authorable = (min..=max).contains(&value);
            fields.push(json!({"field":field,"index":index,"value":value,"minimum":min,"maximum":max,"label":format!("{label} {}",index+1),"authorable":authorable}));
        }
    }
    Ok(
        json!({"fields":fields,"note":"Selectors 1–4 name program branches 0–3. Physical actions require an exact nonempty set; failure uses branch 3. The password text and the labels are edited as labels; the bytes the original does not read are kept."}),
    )
}

pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    match edit {
        Edit::WalkingLocation { map, slot, x, y } => {
            if *slot >= 100 || *x >= 90 || *y >= 90 {
                return Err("trigger placement outside map or native 100 slots".into());
            }
            let id = map
                .checked_mul(100)
                .and_then(|m| m.checked_add(*slot))
                .ok_or("walking index overflow")?;
            let at = walking(files, id)?;
            let key = (map * 10000 + y * 100 + x) as i32;
            let b = files.get_mut("Data DD").unwrap();
            if b[at..at + 4] != key.to_be_bytes()
                && (0..100).any(|s| {
                    s != *slot
                        && b[(map * 100 + s) * 42..(map * 100 + s) * 42 + 4] == key.to_be_bytes()
                })
            {
                return Err("another header already owns this location; native first-match shadowing would apply".into());
            }
            b[at..at + 4].copy_from_slice(&key.to_be_bytes());
        }
        Edit::WalkingChance { id, chance } => {
            if !(0..=100).contains(chance) {
                return Err("authorable chance must be 0..100".into());
            }
            let at = walking(files, *id)?;
            files.get_mut("Data DD").unwrap()[at + 7] = *chance as u8;
        }
        Edit::EncounterCondition {
            family,
            id,
            field,
            index,
            value,
        } => {
            let (offset, width, min, max) = descriptor(*family, *field, *index)?;
            if !(min..=max).contains(value) {
                return Err("condition value outside supported native range".into());
            }
            let at = id
                .checked_mul(family.stride())
                .ok_or("record index overflow")?;
            let b = files
                .get_mut(family.path())
                .ok_or("missing encounter table")?;
            let row = span(b, at, family.stride())?;
            let old = if width == 1 {
                i16::from(row[offset] as i8)
            } else {
                word(row, offset)?
            };
            if !(min..=max).contains(&old) {
                return Err("unresolved imported condition value is read-only".into());
            }
            if width == 1 {
                b[at + offset] = *value as u8;
            } else {
                b[at + offset..at + offset + 2].copy_from_slice(&value.to_be_bytes());
            }
        }
        _ => return Err("not a condition edit".into()),
    }
    Ok(())
}
