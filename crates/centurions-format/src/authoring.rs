//! Template-derived record allocation and the fields needed by a connected mission.
//! Original blobs stay immutable; complete records are inserted before retained tails.
pub use crate::allocation::{allocate, materialize};
pub use crate::record_view::{catalogue, inspect};
pub use crate::trigger_placement::{TriggerPlacement, create_trigger, place_trigger};
use crate::{BattleUnit, Edit, Files, RecordFamily as R, Result, span, text};

pub(crate) fn error(path: &str, id: usize, field: &str, message: &str) -> String {
    format!("{path} record {id} field {field}: {message}")
}
pub(crate) fn row(files: &Files, family: R, id: usize) -> Result<&[u8]> {
    span(
        files
            .get(family.path())
            .ok_or_else(|| format!("missing {}", family.path()))?,
        id.checked_mul(family.stride())
            .ok_or("record index overflow")?,
        family.stride(),
    )
    .map_err(|e| error(family.path(), id, "record", &e))
}
fn reference(
    files: &Files,
    family: R,
    id: i16,
    field: &str,
    path: &str,
    owner: usize,
) -> Result<()> {
    if id < 0 || row(files, family, id as usize).is_err() {
        return Err(error(
            path,
            owner,
            field,
            &format!("dangling {} reference {id}", family.path()),
        ));
    }
    Ok(())
}
pub fn handles(edit: &Edit) -> bool {
    matches!(
        edit,
        Edit::MonsterNoDrops { .. }
            | Edit::EventActivation { .. }
            | Edit::ChoiceLabel { .. }
            | Edit::TypedLabel { .. }
            | Edit::ChoicePrompt { .. }
            | Edit::StageScript { .. }
            | Edit::WalkingTarget { .. }
            | Edit::WalkingRemove { .. }
            | Edit::BattleExtra { .. }
            | Edit::BattlePopulation { .. }
            | Edit::BattleSetting { .. }
            | Edit::MonsterStats { .. }
            | Edit::MonsterTurnStory { .. }
            | Edit::MonsterRetreatThreshold { .. }
            | Edit::MonsterDeathStory { .. }
            | Edit::MonsterSpellSlots { .. }
            | Edit::SelectedBattleExtra { .. }
            | Edit::Reward { .. }
            | Edit::RewardItem { .. }
    )
}
fn pascal(bytes: &mut [u8], at: usize, maximum: usize, value: &str) -> Result<()> {
    let encoded = text::encode(value)?;
    if encoded.len() > maximum {
        return Err(format!("text exceeds {maximum} Mac Roman bytes"));
    }
    span(bytes, at, maximum + 1)?;
    bytes[at] = encoded.len() as u8;
    bytes[at + 1..at + 1 + encoded.len()].copy_from_slice(&encoded);
    Ok(())
}
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    let path = edit.path();
    match edit {
        Edit::MonsterNoDrops { id } => {
            row(files, R::Monster, *id)?;
            let b = files.get_mut(path).unwrap();
            b[id * 288 + 0x26..id * 288 + 0x32].fill(0);
            b[id * 288 + 0x3a..id * 288 + 0x3c].fill(0);
        }
        Edit::EventActivation { map, x, y, enabled } => {
            if *map >= 20 || *x >= 90 || *y >= 90 {
                return Err("Data LD activation coordinates outside native maps".into());
            }
            let at = map * crate::MAP_BYTES + 32400 + (x * 90 + y) * 4;
            let b = files.get_mut(path).ok_or("missing Data LD")?;
            let old = i32::from_be_bytes(span(b, at, 4)?.try_into().unwrap());
            let key = (map * 10000 + y * 100 + x) as i32;
            if old != -1 && old != 0 && old != key && old != 1 {
                return Err(format!(
                    "Data LD map {map} cell ({x},{y}) field activation: retained value {old} is outside the supported empty/location-gate subset"
                ));
            }
            let value = if *enabled { key.max(1) } else { old.min(0) };
            b[at..at + 4].copy_from_slice(&value.to_be_bytes());
        }
        Edit::ChoiceLabel { id, choice, text } => {
            if *choice >= 4 {
                return Err(error(path, *id, "choice", "must be 0..3"));
            }
            row(files, R::Choice, *id)?;
            pascal(
                files.get_mut(path).unwrap(),
                id * 426 + 106 + choice * 80,
                79,
                text,
            )
            .map_err(|e| error(path, *id, "label", &e))?;
        }
        Edit::TypedLabel { id, index, text } => {
            if *index >= 9 {
                return Err(error(path, *id, "typed", "label must be 0..8"));
            }
            span(
                files.get(path).ok_or("missing Data ED2")?,
                id.checked_mul(516).ok_or("record index overflow")?,
                516,
            )
            .map_err(|e| error(path, *id, "record", &e))?;
            pascal(
                files.get_mut(path).unwrap(),
                id * 516 + 156 + index * 40,
                39,
                text,
            )
            .map_err(|e| error(path, *id, "label", &e))?;
        }
        Edit::ChoicePrompt { id, message } => {
            row(files, R::Choice, *id)?;
            reference(files, R::Message, *message, "prompt", path, *id)?;
            files.get_mut(path).unwrap()[id * 426 + 104..id * 426 + 106]
                .copy_from_slice(&message.to_be_bytes());
        }
        Edit::StageScript { id, story } => {
            if *id >= 20 {
                return Err(error(path, *id, "stage", "native stage must be 0..19"));
            }
            let at = id * 464;
            span(files.get(path).ok_or("missing Data Mission")?, at, 464)?;
            if *story != 0 {
                reference(files, R::Story, *story, "start_script", path, *id)?;
            }
            files.get_mut(path).unwrap()[at + 262..at + 264].copy_from_slice(&story.to_be_bytes());
        }
        Edit::WalkingTarget {
            id,
            map,
            x,
            y,
            level,
        } => {
            let count = files
                .get("Data LD")
                .map_or(0, |b| b.len() / crate::MAP_BYTES);
            if id / 100 >= count
                || *map < 0
                || *map as usize >= count
                || !(0..90).contains(x)
                || !(0..90).contains(y)
                || *level != 0
            {
                return Err(error(
                    path,
                    *id,
                    "return_destination",
                    "requires an existing map, coordinates 0..89 and captured level 0",
                ));
            }
            let at = id.checked_mul(42).ok_or("walking index overflow")?;
            span(files.get(path).ok_or("missing Data DD")?, at, 42)?;
            let b = files.get_mut(path).unwrap();
            b[at + 4] = *map as u8;
            b[at + 5] = *x as u8;
            b[at + 6] = *y as u8;
            b[at + 40] = *level;
        }
        Edit::WalkingRemove { id } => {
            let count = files
                .get("Data LD")
                .map_or(0, |b| b.len() / crate::MAP_BYTES);
            if id / 100 >= count {
                return Err(error(path, *id, "location", "outside existing maps"));
            }
            let at = id.checked_mul(42).ok_or("walking index overflow")?;
            span(files.get(path).ok_or("missing Data DD")?, at, 42)?;
            let b = files.get_mut(path).unwrap();
            b[at..at + 4].copy_from_slice(&(-1i32).to_be_bytes());
            b[at + 7] = 0;
        }
        Edit::BattleExtra {
            id,
            minimum,
            maximum,
            sound,
            message,
            cleanup_mode,
        } => {
            row(files, R::BattleExtra, *id)?;
            reference(files, R::Battle, *minimum, "minimum_battle", path, *id)?;
            if *maximum != 0 {
                reference(files, R::Battle, *maximum, "maximum_battle", path, *id)?;
                if maximum < minimum {
                    return Err(error(
                        path,
                        *id,
                        "maximum_battle",
                        "must be zero or at least minimum_battle",
                    ));
                }
            }
            if *sound < 0 {
                return Err(error(path, *id, "sound", "must be nonnegative"));
            }
            if *message != 0 {
                reference(files, R::Message, *message, "message", path, *id)?;
            }
            if !matches!(*cleanup_mode, 0 | 5) {
                return Err(error(
                    path,
                    *id,
                    "cleanup_mode",
                    "supported ordinary modes are 0 (ordinary loot) or 5 (no monster loot); this field is not a reward-record ID",
                ));
            }
            let b = files.get_mut(path).unwrap();
            for (index, value) in [minimum, maximum, sound, message, cleanup_mode]
                .iter()
                .enumerate()
            {
                b[id * 10 + index * 2..id * 10 + index * 2 + 2]
                    .copy_from_slice(&value.to_be_bytes());
            }
        }
        Edit::SelectedBattleExtra {
            id,
            minimum,
            maximum,
            sound,
            message,
            treasure,
        } => {
            row(files, R::BattleExtra, *id)?;
            reference(files, R::Battle, *minimum, "minimum_battle", path, *id)?;
            if *maximum != 0 {
                reference(files, R::Battle, *maximum, "maximum_battle", path, *id)?;
                if maximum < minimum {
                    return Err(error(
                        path,
                        *id,
                        "maximum_battle",
                        "must be zero or at least minimum_battle",
                    ));
                }
            }
            if *sound < 0 {
                return Err(error(path, *id, "sound", "must be nonnegative"));
            }
            if *message != 0 {
                reference(files, R::Message, *message, "message", path, *id)?;
            }
            if *treasure != 0 {
                reference(files, R::Reward, *treasure, "treasure", path, *id)?;
            }
            let b = files.get_mut(path).unwrap();
            for (index, value) in [minimum, maximum, sound, message, treasure]
                .iter()
                .enumerate()
            {
                b[id * 10 + index * 2..id * 10 + index * 2 + 2]
                    .copy_from_slice(&value.to_be_bytes());
            }
        }
        Edit::MonsterTurnStory { id, chance, story } => {
            row(files, R::Monster, *id)?;
            if !(-100..=100).contains(chance) {
                return Err(error(
                    path,
                    *id,
                    "turn_story_chance",
                    "signed chance must be -100..100",
                ));
            }
            reference(files, R::Story, *story, "turn_story", path, *id)?;
            let b = files.get_mut(path).unwrap();
            b[id * 288 + 0x5c..id * 288 + 0x5e].copy_from_slice(&chance.to_be_bytes());
            b[id * 288 + 0x5e..id * 288 + 0x60].copy_from_slice(&story.to_be_bytes());
        }
        Edit::MonsterRetreatThreshold { id, value } => {
            row(files, R::Monster, *id)?;
            let b = files.get_mut(path).unwrap();
            b[id * 288 + 0x44..id * 288 + 0x46].copy_from_slice(&value.to_be_bytes());
        }
        Edit::MonsterDeathStory { id, story } => {
            row(files, R::Monster, *id)?;
            if *story != 0 {
                reference(files, R::Story, *story, "death_story", path, *id)?;
            }
            let b = files.get_mut(path).unwrap();
            b[id * 288 + 0x60..id * 288 + 0x62].copy_from_slice(&story.to_be_bytes());
        }
        Edit::MonsterSpellSlots { id, slots } => {
            row(files, R::Monster, *id)?;
            crate::references::monster_spell_slots(*id, slots)?;
            let b = files.get_mut(path).unwrap();
            for (slot, spell) in slots.iter().enumerate() {
                let at = id * 288 + 0x12 + slot * 2;
                b[at..at + 2].copy_from_slice(&spell.to_be_bytes());
            }
        }
        Edit::BattleSetting {
            id,
            field,
            index,
            value,
        } => {
            use crate::BattleSettingField as B;
            row(files, R::Battle, *id)?;
            let (at, width, low, high) = match (field, index) {
                (B::BeforeMessage, 0) => (1352, 2, 0, i16::MAX),
                (B::AfterMessage, 0) => (1354, 2, 0, i16::MAX),
                (B::SquadX, 0) => (1356, 2, 0, 25),
                (B::SquadY, 0) => (1358, 2, 0, 25),
                (B::RoundScript, 0..5) => (1360 + index * 2, 2, 0, i16::MAX),
                (B::Distance, 0) => (1370, 1, -128, 127),
                _ => return Err(error(path, *id, "setting", "no such battle setting")),
            };
            if !(low..=high).contains(value) {
                return Err(error(
                    path,
                    *id,
                    "setting",
                    &format!("{field:?} is {low}..{high}"),
                ));
            }
            match field {
                B::BeforeMessage | B::AfterMessage if *value != 0 => {
                    reference(files, R::Message, *value, "message", path, *id)?
                }
                B::RoundScript if *value != 0 => {
                    reference(files, R::Story, *value, "round_script", path, *id)?
                }
                _ => {}
            }
            let bytes = files.get_mut(path).unwrap();
            let start = id * 1372 + at;
            if width == 2 {
                bytes[start..start + 2].copy_from_slice(&value.to_be_bytes());
            } else {
                bytes[start] = *value as i8 as u8;
            }
        }
        Edit::BattlePopulation { id, units } => {
            row(files, R::Battle, *id)?;
            if units.is_empty() || units.len() > 100 {
                return Err(error(path, *id, "population", "requires 1..100 actors"));
            }
            let mut seen = std::collections::BTreeSet::new();
            for BattleUnit { x, y, monster } in units {
                if *x >= 26 || *y >= 26 || !seen.insert((*x, *y)) {
                    return Err(error(
                        path,
                        *id,
                        "population",
                        "coordinates outside 26x26 or duplicate cell",
                    ));
                }
                if *monster == 0 || *monster == i16::MIN {
                    return Err(error(path, *id, "monster", "zero/overflow is not an actor"));
                }
                reference(files, R::Monster, monster.abs(), "monster", path, *id)?;
            }
            let b = files.get_mut(path).unwrap();
            b[id * 1372..id * 1372 + 1352].fill(0);
            for unit in units {
                let at = id * 1372 + (unit.x * 26 + unit.y) * 2;
                b[at..at + 2].copy_from_slice(&unit.monster.to_be_bytes());
            }
        }
        Edit::MonsterStats {
            id,
            name,
            level,
            stamina,
            speed,
            movement,
        } => {
            row(files, R::Monster, *id)?;
            if !(0..=127).contains(level)
                || !(0..=30000).contains(stamina)
                || !(1..=32767).contains(speed)
                || !(0..=127).contains(movement)
            {
                return Err(error(
                    path,
                    *id,
                    "statistics",
                    "level 0..127, base stamina 0..30000, speed 1..32767, movement 0..127 required",
                ));
            }
            let b = files.get_mut(path).unwrap();
            pascal(b, id * 288 + 218, 29, name).map_err(|e| error(path, *id, "name", &e))?;
            for (index, value) in [level, stamina, speed, movement].iter().enumerate() {
                b[id * 288 + index * 2..id * 288 + index * 2 + 2]
                    .copy_from_slice(&value.to_be_bytes());
            }
        }
        Edit::RewardItem {
            id,
            slot,
            item,
            level,
        } => {
            row(files, R::Reward, *id)?;
            if *slot >= 20 || *item > 999 || *item == i16::MIN {
                return Err(error(
                    path,
                    *id,
                    "booty",
                    "a reward holds twenty items, each an id up to 999 (0 or less gives none)",
                ));
            }
            let b = files.get_mut(path).unwrap();
            let at = id * 88 + slot * 2;
            b[at..at + 2].copy_from_slice(&item.to_be_bytes());
            b[at + 40..at + 42].copy_from_slice(&level.to_be_bytes());
        }
        Edit::Reward {
            id,
            credits,
            experience,
        } => {
            row(files, R::Reward, *id)?;
            // A negative award is a random one: the game rolls up to its magnitude, and only a
            // magnitude that fits a word is rolled as written.
            let award = -32767..=i32::MAX;
            if !award.contains(credits) || !award.contains(experience) {
                return Err(error(
                    path,
                    *id,
                    "award",
                    "an award is -32767 (random up to that) or more",
                ));
            }
            let b = files.get_mut(path).unwrap();
            b[id * 88 + 80..id * 88 + 84].copy_from_slice(&experience.to_be_bytes());
            b[id * 88 + 84..id * 88 + 88].copy_from_slice(&credits.to_be_bytes());
        }
        _ => return Err("not a mission authoring edit".into()),
    }
    Ok(())
}
