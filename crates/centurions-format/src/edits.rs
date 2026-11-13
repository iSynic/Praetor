use crate::{Edit, Files, MAP_BYTES, Project, Result, SIDE, ownership, span};
use std::collections::BTreeMap;
use std::ops::Range;

pub fn update(project: &Project, files: &Files, edits: Vec<Edit>) -> Result<Project> {
    let mut next = project.clone();
    next.version = crate::VERSION;
    if next.native.is_none()
        && edits
            .iter()
            .any(|edit| matches!(edit, Edit::Opening { .. }))
    {
        let header = crate::native::inherited_header(files)?;
        next.native = Some(crate::NativeScenario {
            name: header.clone(),
            startup_header_source: header,
        });
    }
    let mut selected: BTreeMap<_, _> = next
        .edits
        .into_iter()
        .map(|edit| (edit.identity(), edit))
        .collect();
    for edit in edits {
        selected.insert(edit.identity(), edit);
    }
    next.edits = selected.into_values().collect();
    apply(&next, files)?;
    Ok(next)
}

pub fn apply(project: &Project, source: &Files) -> Result<Files> {
    let mut files = crate::authoring::materialize(project, source)?;
    let mut resource_edits: Vec<&Edit> = vec![];
    for edit in &project.edits {
        // The maps counted are those the earlier edits left, so an edit may name a map that an edit before it added.
        check_map_references(edit, &files)?;
        if crate::authoring::handles(edit) {
            crate::authoring::patch(&mut files, edit)?;
        } else if matches!(
            edit,
            Edit::WalkingLocation { .. }
                | Edit::WalkingChance { .. }
                | Edit::EncounterCondition { .. }
        ) {
            crate::conditions::patch(&mut files, edit)?;
        } else if let Edit::ScriptStep {
            family,
            id,
            branch,
            slot,
            opcode,
            operand,
        } = edit
        {
            crate::scripts::patch(&mut files, *family, *id, *branch, *slot, *opcode, *operand)?;
        } else if matches!(edit, Edit::ItemField { .. } | Edit::ItemDescription { .. }) {
            crate::items::patch(&mut files, edit)?;
        } else if matches!(
            edit,
            Edit::MonsterField { .. }
                | Edit::MonsterDescription { .. }
                | Edit::MonsterImport { .. }
        ) {
            crate::monsters::patch(&mut files, edit)?;
        } else if matches!(edit, Edit::ShopStock { .. } | Edit::ShopPrice { .. }) {
            crate::shops::patch(&mut files, edit)?;
        } else if matches!(
            edit,
            Edit::ExtraWord { .. } | Edit::ExtraRow { .. } | Edit::ExtraIndependent { .. }
        ) {
            crate::extras::patch(&mut files, edit)?;
        } else if matches!(
            edit,
            Edit::ResourceChange { .. }
                | Edit::ScrollText { .. }
                | Edit::ScrollTextRemove { .. }
                | Edit::NoteLabel { .. }
                | Edit::ItemName { .. }
        ) {
            // They change only the scenario's resource file, so they are gathered and applied in one pass.
            resource_edits.push(edit);
        } else if matches!(edit, Edit::Region { .. } | Edit::MapLook { .. }) {
            crate::regions::patch(&mut files, edit)?;
        } else if matches!(edit, Edit::CalendarEntry { .. }) {
            crate::calendar::patch(&mut files, edit)?;
        } else if matches!(edit, Edit::MapNote { .. }) {
            crate::notes::patch(&mut files, edit)?;
        } else if matches!(edit, Edit::AddMap { .. } | Edit::RemoveMap { .. }) {
            crate::maps::patch(&mut files, edit)?;
        } else if let Edit::QuietMap { map } = edit {
            quiet_map(&mut files, *map)?;
        } else {
            let path = edit.path();
            let bytes = files
                .get_mut(path)
                .ok_or_else(|| format!("missing {path}"))?;
            let before = bytes.clone();
            let owned = edit_row(edit, bytes)?;
            require_owned(&before, bytes, &owned)?;
        }
    }
    crate::resources::patch_many(&mut files, &resource_edits)?;
    crate::native::overlay(project, source, &mut files)?;
    drop_stale_bestiary_menu(source, &mut files);
    crate::references::validate(project, &files)?;
    Ok(files)
}

/// The game builds its bestiary menu from the monsters' names, and a scenario that
/// changes them, or adds a monster, must not keep the old menu: the game makes a new
/// one when the file is missing.
fn drop_stale_bestiary_menu(source: &Files, files: &mut Files) {
    const ROW: usize = 288;
    const NAME: std::ops::Range<usize> = 218..248;
    const HIDDEN: usize = 0xa7;
    let (Some(before), Some(after)) = (source.get("Data MD"), files.get("Data MD")) else {
        return;
    };
    let stale = before.len() != after.len()
        || before.chunks(ROW).zip(after.chunks(ROW)).any(|(a, b)| {
            a.len() == ROW && b.len() == ROW && (a[NAME] != b[NAME] || a[HIDDEN] != b[HIDDEN])
        });
    if stale {
        files.remove("Data MENU");
        files.remove("Data MENU.rsrc");
    }
}

fn check_map_references(edit: &Edit, files: &Files) -> Result<()> {
    let map = match edit {
        Edit::Opening { map, x, y } => {
            if !(0..90).contains(x) || !(0..90).contains(y) {
                return Err("opening outside 90x90 map".into());
            }
            Some(i64::from(*map))
        }
        Edit::StageStart { map, x, y, .. } => {
            if !(0..90).contains(x) || !(0..90).contains(y) {
                return Err("stage outside 90x90 map".into());
            }
            Some(i64::from(*map))
        }
        Edit::Floor { map, x, y, .. } | Edit::MapObject { map, x, y, .. } => {
            if *x >= SIDE || *y >= SIDE {
                return Err("cell outside 90x90 map".into());
            }
            Some(i64::try_from(*map).map_err(|_| "map overflow")?)
        }
        Edit::QuietMap { map } => Some(i64::try_from(*map).map_err(|_| "map overflow")?),
        _ => None,
    };
    if let Some(map) = map {
        let bytes = files.get("Data LD").ok_or("missing Data LD")?;
        let count = bytes.len() / MAP_BYTES;
        if bytes.len() % MAP_BYTES != 0
            || !(1..=20).contains(&count)
            || map < 0
            || map as u64 >= count as u64
        {
            return Err("unavailable map or malformed Data LD geometry".into());
        }
    }
    Ok(())
}

fn row_at(bytes: &[u8], id: usize, stride: usize) -> Result<usize> {
    let at = id.checked_mul(stride).ok_or("record index overflow")?;
    span(bytes, at, stride)?;
    Ok(at)
}

#[allow(clippy::single_range_in_vec_init)] // Each element declares an owned byte span.
fn edit_row(edit: &Edit, bytes: &mut [u8]) -> Result<Vec<Range<usize>>> {
    let owned = match edit {
        Edit::MonsterNoDrops { .. } => unreachable!(),
        Edit::EventActivation { .. } => unreachable!(),
        Edit::ChoiceLabel { .. }
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
        | Edit::RewardItem { .. }
        | Edit::Reward { .. } => unreachable!(),
        Edit::WalkingLocation { .. }
        | Edit::WalkingChance { .. }
        | Edit::Region { .. }
        | Edit::MapLook { .. }
        | Edit::ExtraWord { .. }
        | Edit::ExtraRow { .. }
        | Edit::ExtraIndependent { .. }
        | Edit::ShopStock { .. }
        | Edit::ShopPrice { .. }
        | Edit::MonsterField { .. }
        | Edit::MonsterDescription { .. }
        | Edit::MonsterImport { .. }
        | Edit::ItemField { .. }
        | Edit::ItemDescription { .. }
        | Edit::EncounterCondition { .. } => unreachable!(),
        Edit::ScriptStep { .. } => unreachable!(),
        Edit::ResourceChange { .. }
        | Edit::ScrollText { .. }
        | Edit::ScrollTextRemove { .. }
        | Edit::ItemName { .. }
        | Edit::AddMap { .. }
        | Edit::RemoveMap { .. }
        | Edit::MapNote { .. }
        | Edit::NoteLabel { .. }
        | Edit::CalendarEntry { .. } => {
            unreachable!()
        }
        Edit::Message { id, text } => {
            let at = row_at(bytes, *id, 256)?;
            vec![pascal(bytes, at, text, 255)?]
        }
        Edit::StageName { id, name } => {
            let at = row_at(bytes, *id, 464)?;
            vec![pascal(bytes, at + 6, name, 255)?]
        }
        Edit::StageStart { id, x, y, map } => {
            let at = row_at(bytes, *id, 464)?;
            for (offset, value) in [(0, *x), (2, *y), (4, *map)] {
                bytes[at + offset..at + offset + 2].copy_from_slice(&value.to_be_bytes());
            }
            vec![at..at + 6]
        }
        Edit::Opening { map, x, y } => {
            span(bytes, 8, 12)?;
            for (at, value) in [(8, *map), (12, *x), (16, *y)] {
                bytes[at..at + 4].copy_from_slice(&value.to_be_bytes());
            }
            vec![8..20]
        }
        Edit::Floor { map, x, y, tile } => {
            let base = row_at(bytes, *map, MAP_BYTES)?;
            let at = base + (*x * SIDE + *y) * 2;
            bytes[at..at + 2].copy_from_slice(&tile.to_be_bytes());
            vec![at..at + 2]
        }
        Edit::MapObject { map, x, y, value } => {
            // A building is the picture numbered 23000 plus its value, and a picture number is a signed word.
            if *value > 32767 - 23000 {
                return Err("a building number is at most 9767".into());
            }
            // The object layer follows the floor in the map's record.
            let base = row_at(bytes, *map, MAP_BYTES)? + crate::CELLS * 2;
            let at = base + (*x * SIDE + *y) * 2;
            bytes[at..at + 2].copy_from_slice(&value.to_be_bytes());
            vec![at..at + 2]
        }
        Edit::DisableStage { id } => {
            let at = row_at(bytes, *id, 464)? + 6;
            bytes[at] = 0;
            vec![at..at + 1]
        }
        Edit::ClearStageScript { id } => {
            let at = row_at(bytes, *id, 464)? + 262;
            bytes[at..at + 2].fill(0);
            vec![at..at + 2]
        }
        Edit::DisableSchedule => {
            row_at(bytes, 0, 40)?;
            bytes[..2].fill(0);
            vec![0..2]
        }
        Edit::QuietMap { .. } => unreachable!(),
    };
    Ok(owned)
}

fn pascal(bytes: &mut [u8], at: usize, text: &str, limit: usize) -> Result<Range<usize>> {
    let encoded = crate::text::encode(text)?;
    if encoded.len() > limit {
        return Err(format!(
            "text encodes to {} bytes; maximum {limit}",
            encoded.len()
        ));
    }
    // Retain original encodings and unused suffix when the projected value is unchanged.
    let old_len = usize::from(bytes[at]);
    let old = span(bytes, at + 1, old_len)?;
    if crate::text::decode(old) == text {
        return Ok(at..at);
    }
    bytes[at] = encoded.len() as u8;
    bytes[at + 1..at + 1 + encoded.len()].copy_from_slice(&encoded);
    Ok(at..at + 1 + encoded.len())
}

fn quiet_map(files: &mut Files, map: usize) -> Result<()> {
    let bytes = files.get_mut("Data DD").ok_or("missing Data DD")?;
    let at = row_at(bytes, map, 4200)?;
    let before = bytes.clone();
    let mut ranges = Vec::new();
    for slot in 0..100 {
        let key = at + slot * 42;
        bytes[key..key + 4].copy_from_slice(&(-1_i32).to_be_bytes());
        ranges.push(key..key + 4);
    }
    require_owned(&before, bytes, &ranges)?;
    let bytes = files.get_mut("Data RD").ok_or("missing Data RD")?;
    let at = row_at(bytes, map, 644)?;
    let before = bytes.clone();
    // Activation: encounter chances, battle ranges, and regional story chances.
    bytes[at + 160..at + 280].fill(0);
    bytes[at + 400..at + 520].fill(0);
    require_owned(&before, bytes, &[at + 160..at + 280, at + 400..at + 520])
}

fn require_owned(before: &[u8], after: &[u8], ranges: &[Range<usize>]) -> Result<()> {
    let diff = ownership::inspect(before, after, ranges);
    if diff.unowned_changes != 0 {
        return Err(format!("unowned changes: {:?}", diff.unowned_sample));
    }
    Ok(())
}

#[cfg(test)]
mod bestiary_menu {
    use super::*;

    #[test]
    fn a_renamed_or_added_monster_drops_the_menu_and_a_stat_change_keeps_it() {
        let mut source = Files::new();
        source.insert("Data MD".into(), vec![0; 288 * 2]);
        source.insert("Data MENU".into(), vec![0; 502]);
        let mut stats = source.clone();
        stats.get_mut("Data MD").unwrap()[288 + 8] = 5;
        drop_stale_bestiary_menu(&source, &mut stats);
        assert!(stats.contains_key("Data MENU"));
        let mut renamed = source.clone();
        renamed.get_mut("Data MD").unwrap()[288 + 219] = b'Z';
        drop_stale_bestiary_menu(&source, &mut renamed);
        assert!(!renamed.contains_key("Data MENU"));
        let mut added = source.clone();
        added.get_mut("Data MD").unwrap().extend([0; 288]);
        drop_stale_bestiary_menu(&source, &mut added);
        assert!(!added.contains_key("Data MENU"));
    }
}
