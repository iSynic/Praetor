//! Atomic walking header and ordinary-movement activation edits.
use crate::{Edit, Files, Project, Result, span};
pub struct TriggerPlacement {
    pub id: usize,
    pub x: usize,
    pub y: usize,
    pub chance: i16,
    pub remove: bool,
    pub follow: bool,
}

/// Place/move or retire a header together with its ordinary-movement gate.
pub fn place_trigger(
    project: &Project,
    source: &Files,
    placement: &TriggerPlacement,
) -> Result<Project> {
    let TriggerPlacement {
        id,
        x,
        y,
        chance,
        remove,
        follow,
    } = *placement;
    if x >= 90 || y >= 90 || !(0..=100).contains(&chance) {
        return Err("Data DD trigger coordinates 0..89 and chance 0..100 required".into());
    }
    let files = crate::apply(project, source)?;
    let map = id / 100;
    let slot = id % 100;
    let dd = files.get("Data DD").ok_or("missing Data DD")?;
    let header = span(dd, id.checked_mul(42).ok_or("walking index overflow")?, 42)?;
    let old_key = i32::from_be_bytes(header[..4].try_into().unwrap());
    let new_key = (map * 10000 + y * 100 + x) as i32;
    let table = span(dd, map * 4200, 4200)?;
    if !remove
        && chance > 0
        && (0..slot).any(|s| table[s * 42..s * 42 + 4] == new_key.to_be_bytes())
    {
        return Err(format!(
            "Data DD record {id} field location: an earlier matching header shadows this trigger"
        ));
    }
    let mut edits = Vec::new();
    if old_key >= 0 && (remove || old_key != new_key) {
        let ox = (old_key % 100) as usize;
        let oy = (old_key / 100 % 100) as usize;
        if old_key / 10000 == map as i32 && ox < 90 && oy < 90 {
            let table = span(dd, map * 4200, 4200)?;
            let shared =
                (0..100).any(|s| s != slot && table[s * 42..s * 42 + 4] == old_key.to_be_bytes());
            if !shared {
                edits.push(Edit::EventActivation {
                    map,
                    x: ox,
                    y: oy,
                    enabled: false,
                });
            }
        }
    }
    if remove {
        edits.push(Edit::WalkingRemove { id });
    } else {
        edits.push(Edit::WalkingLocation { map, slot, x, y });
        edits.push(Edit::WalkingChance { id, chance });
        let shared =
            (0..100).any(|s| s != slot && table[s * 42..s * 42 + 4] == new_key.to_be_bytes());
        if chance > 0 || !shared {
            edits.push(Edit::EventActivation {
                map,
                x,
                y,
                enabled: chance > 0,
            });
        }
        if follow {
            edits.push(Edit::WalkingTarget {
                id,
                map: map as i16,
                x: x as i16,
                y: y as i16,
                level: 0,
            });
        }
    }
    crate::update(project, source, edits)
}

pub fn create_trigger(
    project: &Project,
    source: &Files,
    map: usize,
    x: usize,
    y: usize,
) -> Result<(Project, usize)> {
    if map >= 20 {
        return Err("Data DD map outside native range".into());
    }
    let files = crate::apply(project, source)?;
    let b = files.get("Data DD").ok_or("missing Data DD")?;
    let table = span(b, map * 4200, 4200)?;
    let slot=(0..100).find(|slot|{let row=&table[slot*42..(slot+1)*42];i32::from_be_bytes(row[..4].try_into().unwrap())<0&&row[8..40].iter().all(|v|*v==0)}).ok_or_else(||format!("Data DD map {map} field capacity: no unplaced empty program slot; imported programs will not be erased"))?;
    let id = map * 100 + slot;
    Ok((
        place_trigger(
            project,
            source,
            &TriggerPlacement {
                id,
                x,
                y,
                chance: 100,
                remove: false,
                follow: true,
            },
        )?,
        id,
    ))
}
