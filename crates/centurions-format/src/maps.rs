//! Adding a map. A map is one record in each of `Data LD` (cells), `Data DD` (walking triggers) and `Data RD`
//! (regions and look); the game builds its lands from the walking records and reads the other two beside them, so
//! the three always grow together.
use crate::{Edit, Files, MAP_BYTES, Result, SIDE, span};
use serde_json::{Value, json};

/// Most maps a level holds: the reconstruction's own loaders and saves assume it, and the original holds the
/// map in a signed byte of the walking row, so nothing found in the original is lower.
pub const MAX_MAPS: usize = 20;
const WALKING: usize = 4200;
const REGIONS: usize = 644;
const ROW: usize = 42;
const FLOOR: usize = crate::CELLS * 2;
const EVENTS: usize = crate::CELLS * 4;
/// The look of a map in its regions record: its tile set, then the two bytes after it, the light level and
/// whether sight is limited.
const LOOK: std::ops::Range<usize> = 520..524;

/// How many maps `Data LD` holds.
pub fn count(files: &Files) -> usize {
    files.get("Data LD").map_or(0, |b| b.len() / MAP_BYTES)
}

/// A walking record with every row unused: key -1 and the map the record belongs to.
fn blank_walking(map: usize) -> Vec<u8> {
    let mut record = vec![0u8; WALKING];
    for row in record.as_chunks_mut::<ROW>().0 {
        row[..4].copy_from_slice(&(-1i32).to_be_bytes());
        row[4] = map as u8;
    }
    record
}

/// The key a walking trigger carries is `map * 10000 + row * 100 + column`. Zero names no trigger, and neither does a
/// value whose row or column is off the map. The key with the map number changed, for a key of map `from`.
fn renumber(key: i32, from: usize, to: usize) -> Option<i32> {
    let (from, to) = (i32::try_from(from).ok()?, i32::try_from(to).ok()?);
    let place = key.checked_sub(from * 10000)?;
    (key > 0 && (0..10000).contains(&place) && place / 100 < 90 && place % 100 < 90)
        .then_some(to * 10000 + place)
}

/// Everything the new map is made of.
struct Built {
    cells: Vec<u8>,
    walking: Vec<u8>,
    regions: Vec<u8>,
    cells_renumbered: usize,
    rows_renumbered: usize,
}

#[allow(clippy::too_many_arguments)]
fn build(
    files: &Files,
    map: usize,
    copy_of: Option<usize>,
    tile: i16,
    floor: bool,
    objects: bool,
    triggers: bool,
    regions: bool,
) -> Result<Built> {
    let ld = files.get("Data LD").ok_or("missing Data LD")?;
    let mut cells = vec![0u8; MAP_BYTES];
    let mut walking = blank_walking(map);
    let mut region_record = vec![0u8; REGIONS];
    let (mut cells_renumbered, mut rows_renumbered) = (0, 0);
    let mut template = None;
    if let Some(source) = copy_of {
        if source >= count(files) {
            return Err(format!("map {source} is not in the scenario"));
        }
        let from = span(ld, source * MAP_BYTES, MAP_BYTES)?;
        if floor {
            cells[..FLOOR].copy_from_slice(&from[..FLOOR]);
        }
        if objects {
            cells[FLOOR..FLOOR * 2].copy_from_slice(&from[FLOOR..FLOOR * 2]);
        }
        if triggers {
            for (index, (at, value)) in cells[FLOOR * 2..FLOOR * 2 + EVENTS]
                .as_chunks_mut::<4>()
                .0
                .iter_mut()
                .zip(from[FLOOR * 2..].as_chunks::<4>().0)
                .enumerate()
            {
                // An event cell holds the key of its own place; any other value is copied as it is.
                let key = i32::from_be_bytes(*value);
                let own = source * 10000 + (index % 90) * 100 + index / 90;
                let key = renumber(key, source, map).filter(|_| usize::try_from(key) == Ok(own));
                cells_renumbered += usize::from(key.is_some());
                *at = key.map_or(*value, i32::to_be_bytes);
            }
            let dd = files.get("Data DD").ok_or("missing Data DD")?;
            walking = span(dd, source * WALKING, WALKING)?.to_vec();
            for row in walking.as_chunks_mut::<ROW>().0 {
                let key = i32::from_be_bytes(row[..4].try_into().unwrap());
                if let Some(key) = renumber(key, source, map) {
                    row[..4].copy_from_slice(&key.to_be_bytes());
                    rows_renumbered += 1;
                    // A return to the map the trigger stood on stays on the new map.
                    if usize::from(row[4]) == source {
                        row[4] = map as u8;
                    }
                }
            }
        }
        let rd = files.get("Data RD").ok_or("missing Data RD")?;
        template = Some(span(rd, source * REGIONS, REGIONS)?.to_vec());
    } else if let Some(rd) = files.get("Data RD").filter(|rd| rd.len() >= REGIONS) {
        template = Some(rd[..REGIONS].to_vec());
    }
    if !floor || copy_of.is_none() {
        for at in cells[..FLOOR].as_chunks_mut::<2>().0 {
            *at = tile.to_be_bytes();
        }
    }
    if let Some(template) = template {
        if regions && copy_of.is_some() {
            region_record = template;
        } else {
            region_record[LOOK].copy_from_slice(&template[LOOK]);
        }
    }
    Ok(Built {
        cells,
        walking,
        regions: region_record,
        cells_renumbered,
        rows_renumbered,
    })
}

/// Appends a table to a file so that it holds `maps` records, then replaces record `map`.
fn put(
    files: &mut Files,
    name: &str,
    stride: usize,
    map: usize,
    record: &[u8],
    fill: &dyn Fn(usize) -> Vec<u8>,
) -> Result<()> {
    let bytes = files
        .get_mut(name)
        .ok_or_else(|| format!("missing {name}"))?;
    if bytes.len() % stride != 0 {
        return Err(format!("{name} does not hold whole records"));
    }
    while bytes.len() / stride < map {
        let next = bytes.len() / stride;
        bytes.extend(fill(next));
    }
    if bytes.len() / stride == map {
        bytes.extend_from_slice(record);
    } else {
        bytes[map * stride..(map + 1) * stride].copy_from_slice(record);
    }
    Ok(())
}

/// The edit that adds the next map, made from a blank map or a copy of another as `files` hold it. `tile` fills
/// the floor that is not copied.
#[allow(clippy::too_many_arguments)]
pub fn prepare(
    files: &Files,
    copy_of: Option<usize>,
    tile: i16,
    floor: bool,
    objects: bool,
    triggers: bool,
    regions: bool,
) -> Result<Edit> {
    if !(0..=300).contains(&tile) {
        return Err("a floor tile is 0 to 300".into());
    }
    let map = count(files);
    let built = build(files, map, copy_of, tile, floor, objects, triggers, regions)?;
    Ok(Edit::AddMap {
        map,
        cells: crate::resources::hex(&built.cells),
        walking: crate::resources::hex(&built.walking),
        regions: crate::resources::hex(&built.regions),
    })
}

/// Adds map `map`, which must be the next number, to the three files; removes the last map.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    if let Edit::RemoveMap { map } = edit {
        return remove(files, *map);
    }
    let Edit::AddMap {
        map,
        cells,
        walking,
        regions,
    } = edit
    else {
        return Err("not a map edit".into());
    };
    let maps = count(files);
    if files
        .get("Data LD")
        .is_some_and(|b| b.len() % MAP_BYTES != 0)
    {
        return Err("Data LD does not hold whole maps".into());
    }
    if *map != maps {
        return Err(format!("the next map is Map {maps}"));
    }
    if maps >= MAX_MAPS {
        return Err(format!("a level holds at most {MAX_MAPS} maps"));
    }
    let record = |hex: &str, size: usize| {
        let bytes = crate::resources::unhex(hex)?;
        if bytes.len() == size {
            Ok(bytes)
        } else {
            Err(format!("a map record is {size} bytes"))
        }
    };
    let (cells, walking, regions) = (
        record(cells, MAP_BYTES)?,
        record(walking, WALKING)?,
        record(regions, REGIONS)?,
    );
    put(files, "Data LD", MAP_BYTES, *map, &cells, &|_| {
        vec![0; MAP_BYTES]
    })?;
    put(files, "Data DD", WALKING, *map, &walking, &blank_walking)?;
    put(files, "Data RD", REGIONS, *map, &regions, &|_| {
        vec![0; REGIONS]
    })?;
    Ok(())
}

/// What names map `map` outside the map itself: the stages and the opening that start on it, the walking triggers of
/// other maps that return to it, the calendar entries that wait on it and the steps that take it as a map number.
pub fn references(files: &Files, map: usize) -> Vec<String> {
    use crate::navigation::{FAMILIES, live_rows, steps};
    use crate::script_codes::{Kind, code, uses_extra};
    let mut found = vec![];
    let number = i64::try_from(map).unwrap_or(-1);
    if let Some(stages) = files.get("Data Mission") {
        for (id, row) in stages.as_chunks::<464>().0.iter().enumerate() {
            if row[6] != 0 && i64::from(i16::from_be_bytes([row[4], row[5]])) == number {
                found.push(format!("Stage {id} starts on Map {map}"));
            }
        }
    }
    if let Some(opening) = files.get("Data CS")
        && opening
            .get(8..12)
            .is_some_and(|b| i64::from(i32::from_be_bytes(b.try_into().unwrap())) == number)
    {
        found.push(format!("The opening starts on Map {map}"));
    }
    if let Some(dd) = files.get("Data DD") {
        for (table, record) in dd
            .chunks(WALKING)
            .enumerate()
            .filter(|(table, _)| *table != map)
        {
            for (slot, row) in record.as_chunks::<ROW>().0.iter().enumerate() {
                let key = i32::from_be_bytes(row[..4].try_into().unwrap());
                if key >= 0 && usize::from(row[4]) == map {
                    found.push(format!(
                        "Walking trigger W{slot} of Map {table} returns to Map {map}"
                    ));
                }
            }
        }
    }
    if let Ok(view) = crate::calendar::view(files) {
        for entry in view["entries"].as_array().into_iter().flatten() {
            if entry["day"].as_i64().unwrap_or(0) > 0
                && entry["place"] == 1
                && entry["map"].as_i64() == Some(number)
            {
                found.push(format!(
                    "Calendar entry {} waits on Map {map}",
                    entry["slot"]
                ));
            }
        }
    }
    let words = |operand: i16| -> Vec<i16> {
        let at = usize::from(operand.unsigned_abs()) * 10;
        files
            .get("Data EDCD")
            .and_then(|b| b.get(at..at + 10))
            .map(|row| {
                row.as_chunks::<2>()
                    .0
                    .iter()
                    .map(|w| i16::from_be_bytes(*w))
                    .collect()
            })
            .unwrap_or_default()
    };
    for family in FAMILIES {
        for record in 0..live_rows(files, family) {
            // The walking triggers of the map go with it.
            if family == crate::ScriptFamily::Walking && record / 100 == map {
                continue;
            }
            for step in steps(files, family, record) {
                let Some(code) = code(step.op) else { continue };
                let mut names =
                    matches!(code.id, Some(Kind::Map { .. })) && i64::from(step.operand) == number;
                if uses_extra(step.op) && step.operand >= 0 {
                    let row = words(step.operand);
                    for (index, kind) in code.extra.iter().flatten().enumerate() {
                        names |= matches!(kind, Kind::Map { .. })
                            && row.get(index).is_some_and(|w| i64::from(*w) == number);
                    }
                    if let Some(companion) = &code.companion {
                        let next = words(step.operand + 1);
                        for (index, kind) in companion.iter().enumerate() {
                            names |= matches!(kind, Kind::Map { .. })
                                && next.get(index).is_some_and(|w| i64::from(*w) == number);
                        }
                    }
                }
                if names {
                    let place = crate::navigation::program_label(family, record, step.slot);
                    found.push(format!("{place} (code {}) names Map {map}", step.op));
                }
            }
        }
    }
    found
}

/// Removes map `map`, which must be the last, from the three files when nothing refers to it and the files hold no
/// record beyond the maps.
fn remove(files: &mut Files, map: usize) -> Result<()> {
    let maps = count(files);
    if map + 1 != maps {
        return Err(format!(
            "only the last map, Map {}, can be removed: the numbers of the maps after another would change",
            maps.saturating_sub(1)
        ));
    }
    if maps <= 1 {
        return Err("a scenario holds at least one map".into());
    }
    for (name, stride) in [("Data DD", WALKING), ("Data RD", REGIONS)] {
        if files.get(name).is_some_and(|b| b.len() != maps * stride) {
            return Err(format!(
                "{name} holds a record beyond the maps, which the game would then count as a map; it is not removed"
            ));
        }
    }
    let named = references(files, map);
    if !named.is_empty() {
        return Err(format!("Map {map} is still named: {}", named.join("; ")));
    }
    for (name, stride) in [
        ("Data LD", MAP_BYTES),
        ("Data DD", WALKING),
        ("Data RD", REGIONS),
    ] {
        let bytes = files
            .get_mut(name)
            .ok_or_else(|| format!("missing {name}"))?;
        bytes.truncate((maps - 1) * stride);
    }
    Ok(())
}

/// What adding a map would do, for the review before it is drafted.
pub fn review(
    files: &Files,
    copy_of: Option<usize>,
    floor: bool,
    objects: bool,
    triggers: bool,
    regions: bool,
) -> Result<Value> {
    let maps = count(files);
    let built = build(files, maps, copy_of, 0, floor, objects, triggers, regions)?;
    let holds = |name: &str, stride: usize| files.get(name).map_or(0, |b| b.len() / stride);
    let mut adds = vec![json!({"file":"Data LD","bytes":MAP_BYTES,"note":"1 map"})];
    let mut replaces = vec![];
    for (name, stride, bytes, note) in [
        ("Data DD", WALKING, built.walking.len(), "100 walking rows"),
        (
            "Data RD",
            REGIONS,
            built.regions.len(),
            "20 regions and the map's look",
        ),
    ] {
        let have = holds(name, stride);
        if have > maps {
            replaces.push(json!({"file":name,"record":maps,"note":format!("{name} already holds a record {maps} that no map used; the new map takes it")}));
        } else {
            adds.push(json!({"file":name,"bytes":bytes + (maps - have) * stride,"note":note}));
        }
    }
    Ok(
        json!({"map":maps,"maps":maps,"limit":MAX_MAPS,"adds":adds,"replaces":replaces,
        "renumbered_cells":built.cells_renumbered,"renumbered_rows":built.rows_renumbered}),
    )
}

/// Findings about the floor of each map: cells numbered from 301 to 1999. The game draws such a cell as nothing and the party
/// walks it as the map's own tile. A number from 2000 up is a hidden or revealed secret, which the editor offers, and
/// is not reported (`docs/original-evidence/maps.md`).
pub fn findings(files: &Files) -> Vec<Value> {
    let mut found = vec![];
    let Some(land) = files.get("Data LD") else {
        return found;
    };
    for map in 0..count(files) {
        let Some(floor) = land.get(map * MAP_BYTES..map * MAP_BYTES + crate::CELLS * 2) else {
            continue;
        };
        let mut above = 0usize;
        let mut first = None;
        for (index, pair) in floor.as_chunks::<2>().0.iter().enumerate() {
            if (301..=1999).contains(&i16::from_be_bytes(*pair)) {
                above += 1;
                first.get_or_insert(index);
            }
        }
        let Some(index) = first else { continue };
        let (x, y) = (index / SIDE, index % SIDE);
        let cells = if above == 1 { "cell" } else { "cells" };
        found.push(json!({"severity":"warning","message":format!("Map {map} has {above} floor {cells} numbered from 301 to 1999 (the first at ({x}, {y})); the game draws them as nothing and the party walks them as the map's own tile"),
            "count":null,"unit":null,"where":{"kind":"cell","map":map,"x":x,"y":y,"label":format!("Map {map} · ({x}, {y})")}}));
    }
    found
}
