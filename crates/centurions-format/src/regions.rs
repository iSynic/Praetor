//! A map's regions in Data RD: where each lies, the battles it draws, the
//! stories it runs and the chance the party avoids a battle in it.
use crate::{Edit, Files, Result, ownership, span};

pub const ROW: usize = 644;
pub const REGIONS: usize = 20;

/// Edits one region of one map; a region whose rectangle is all zero is empty.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    if let Edit::MapLook {
        map,
        terrain,
        limits_sight,
        light,
    } = edit
    {
        return look(files, *map, *terrain, *limits_sight, *light);
    }
    let Edit::Region {
        map,
        slot,
        first_y,
        first_x,
        last_y,
        last_x,
        encounter_chance,
        battle_min,
        battle_max,
        scripts,
        script_chances,
        exclusive,
        avoid_chance,
        avoid_sound,
        avoid_dialogue,
    } = edit
    else {
        return Err("not a region edit".into());
    };
    if *slot >= REGIONS {
        return Err("a map holds regions 0..19".into());
    }
    let maps = files
        .get("Data LD")
        .map_or(0, |b| b.len() / crate::MAP_BYTES);
    if !(1..=20).contains(&maps) || *map >= maps {
        return Err("unavailable map or malformed Data LD geometry".into());
    }
    let empty = [first_y, first_x, last_y, last_x].iter().all(|v| **v == 0);
    if !empty {
        for (first, last, edge) in [(first_y, last_y, "rows"), (first_x, last_x, "columns")] {
            if !(0..90).contains(first) || !(0..90).contains(last) || first > last {
                return Err(format!(
                    "region {edge} must run from a first to a last inside the 90x90 map"
                ));
            }
        }
        if *encounter_chance < 0 {
            return Err("a region's encounter chance is 0 or more in 10000".into());
        }
        if *battle_min < 0 || *battle_max < 0 || (*battle_min != 0 && battle_max < battle_min) {
            return Err("a region's battles run from its lowest to its highest number".into());
        }
        if scripts.iter().any(|s| *s < 0)
            || script_chances.iter().any(|c| !(-100..=100).contains(c))
        {
            return Err("a region's stories are numbers from 0 and chances are -100..100".into());
        }
        if !(-128..=127).contains(avoid_chance) {
            return Err("a region's avoidance chance is a signed byte, -128..127".into());
        }
    }
    let rd = files.get_mut("Data RD").ok_or("missing Data RD")?;
    let base = map * ROW;
    span(rd, base, ROW)?;
    let before = rd.clone();
    let row = &mut rd[base..base + ROW];
    let slot = *slot;
    let keep = |value: i16| if empty { 0 } else { value };
    for (n, value) in [first_y, first_x, last_y, last_x].into_iter().enumerate() {
        row[slot * 8 + n * 2..slot * 8 + n * 2 + 2].copy_from_slice(&value.to_be_bytes());
    }
    row[160 + slot * 2..162 + slot * 2].copy_from_slice(&keep(*encounter_chance).to_be_bytes());
    row[200 + slot * 4..202 + slot * 4].copy_from_slice(&keep(*battle_min).to_be_bytes());
    row[202 + slot * 4..204 + slot * 4].copy_from_slice(&keep(*battle_max).to_be_bytes());
    for n in 0..3 {
        row[280 + slot * 6 + n * 2..282 + slot * 6 + n * 2]
            .copy_from_slice(&keep(scripts[n]).to_be_bytes());
        row[400 + slot * 6 + n * 2..402 + slot * 6 + n * 2]
            .copy_from_slice(&keep(script_chances[n]).to_be_bytes());
    }
    row[524 + slot] = u8::from(*exclusive && !empty);
    row[544 + slot] = keep(*avoid_chance) as i8 as u8;
    row[564 + slot * 2..566 + slot * 2].copy_from_slice(&keep(*avoid_sound).to_be_bytes());
    row[604 + slot * 2..606 + slot * 2].copy_from_slice(&keep(*avoid_dialogue).to_be_bytes());
    let owned = [
        base + slot * 8..base + slot * 8 + 8,
        base + 160 + slot * 2..base + 162 + slot * 2,
        base + 200 + slot * 4..base + 204 + slot * 4,
        base + 280 + slot * 6..base + 286 + slot * 6,
        base + 400 + slot * 6..base + 406 + slot * 6,
        base + 524 + slot..base + 525 + slot,
        base + 544 + slot..base + 545 + slot,
        base + 564 + slot * 2..base + 566 + slot * 2,
        base + 604 + slot * 2..base + 606 + slot * 2,
    ];
    if ownership::inspect(&before, rd, &owned).unowned_changes != 0 {
        return Err("unowned region edit".into());
    }
    Ok(())
}

/// The tile sets with a property file: the nine stock sets and the five custom sets the
/// scenario carries. The others quit the original when the land loads.
const TILE_SETS: [std::ops::RangeInclusive<i16>; 2] = [1..=9, 15..=19];
const TERRAIN: usize = 520;
const LIGHT: usize = 522;
const SIGHT: usize = 523;

/// Sets a map's tile set, whether it shows only the squares the party has seen, and its light
/// level, a byte that only the story codes read and compare.
fn look(files: &mut Files, map: usize, terrain: i16, limits_sight: bool, light: i16) -> Result<()> {
    if !(0..=255).contains(&light) {
        return Err("a map's light level is a byte, 0..255".into());
    }
    if !TILE_SETS.iter().any(|set| set.contains(&terrain)) {
        return Err("a map's tile set is 1 to 9 or 15 to 19".into());
    }
    let maps = files
        .get("Data LD")
        .map_or(0, |b| b.len() / crate::MAP_BYTES);
    if !(1..=20).contains(&maps) || map >= maps {
        return Err("unavailable map or malformed Data LD geometry".into());
    }
    let rd = files.get_mut("Data RD").ok_or("missing Data RD")?;
    let base = map * ROW;
    span(rd, base, ROW)?;
    let before = rd.clone();
    rd[base + TERRAIN] = terrain as u8;
    rd[base + LIGHT] = light as u8;
    rd[base + SIGHT] = u8::from(limits_sight);
    let owned = [
        base + TERRAIN..base + TERRAIN + 1,
        base + LIGHT..base + SIGHT + 1,
    ];
    if ownership::inspect(&before, rd, &owned).unowned_changes != 0 {
        return Err("unowned map look edit".into());
    }
    Ok(())
}
