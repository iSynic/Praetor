//! The calendar in `Data TD3`: the entries the game checks each time a day turns over. An entry runs a story
//! on its day, then comes due again after its interval, when its chance, its item, its flag and its place allow.
use crate::{Edit, Files, Result, span, word};
use serde_json::{Value, json};

/// Bytes of one entry.
pub const ENTRY: usize = 40;
/// The scan reaches records 0 to 150 and no further.
pub const REACHED: usize = 151;
/// The mission flags run from 0 to 127.
const FLAGS: i16 = 128;
/// The items the game holds run from 1 to 999.
const ITEMS: i16 = 999;
/// A map holds 20 regions.
const REGIONS: i16 = 20;

/// How an entry that is switched off is written, as the bundled scenario writes its own.
const UNUSED: [i16; 11] = [-1, 0, -1, 0, -1, -1, -1, -1, -1, -1, -1];

/// How many entries the calendar holds.
pub fn count(files: &Files) -> usize {
    files.get("Data TD3").map_or(0, |b| b.len() / ENTRY)
}

/// The fields of entry `slot`: day, interval, chance, story, map, region, x, y, item, flag and place.
fn fields(files: &Files, slot: usize) -> Result<[i16; 11]> {
    let row = span(
        files.get("Data TD3").ok_or("missing Data TD3")?,
        slot * ENTRY,
        ENTRY,
    )?;
    let mut all = [0i16; 11];
    for (n, value) in all.iter_mut().enumerate() {
        *value = word(row, n * 2)?;
    }
    Ok(all)
}

/// The calendar, each entry with what the scan does with it.
pub fn view(files: &Files) -> Result<Value> {
    let total = count(files);
    let mut entries = Vec::with_capacity(total);
    let mut ended = None;
    for slot in 0..total {
        let [
            day,
            interval,
            chance,
            story,
            map,
            region,
            x,
            y,
            item,
            flag,
            place,
        ] = fields(files, slot)?;
        // An entry with day zero ends the calendar; the ones after it, and those past the 151st, are never read.
        let reached = ended.is_none() && slot < REACHED;
        if day == 0 && ended.is_none() {
            ended = Some(slot);
        }
        entries.push(json!({"slot":slot,"day":day,"interval":interval,"chance":chance,"story":story,"map":map,
            "region":region,"x":x,"y":y,"item":item,"flag":flag,"place":place,"reached":reached}));
    }
    Ok(json!({"entries":entries,"count":total,"reached":REACHED,"ends_at":ended}))
}

/// Sets the fields of one entry. A slot just past the last adds an entry; the bytes the original does not read
/// stay as they are, and a new entry has zeros there.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    let Edit::CalendarEntry {
        slot,
        day,
        interval,
        chance,
        story,
        map,
        region,
        x,
        y,
        item,
        flag,
        place,
    } = edit
    else {
        return Err("not a calendar edit".into());
    };
    let total = count(files);
    if *slot > total || *slot >= REACHED {
        return Err(format!(
            "the calendar holds entries 0 to {}; the game reads no further",
            REACHED - 1
        ));
    }
    let stories = files.get("Data ED3").map_or(0, |b| b.len() / 42);
    // An entry that never comes due may keep a number that names nothing.
    let live = *day > 0;
    if live && (*story < 0 || usize::try_from(*story).is_ok_and(|s| s >= stories)) {
        return Err(format!("story {story} is not in the scenario"));
    }
    let maps = files
        .get("Data LD")
        .map_or(0, |b| b.len() / crate::MAP_BYTES);
    if live && *place == 1 {
        if *map < 0 || usize::try_from(*map).is_ok_and(|m| m >= maps) {
            return Err(format!("map {map} is not in the scenario"));
        }
        if *region >= REGIONS {
            return Err("a map holds regions 0 to 19".into());
        }
        if (*x >= 0 && !(0..90).contains(x)) || (*x >= 0 && !(0..90).contains(y)) {
            return Err("a cell lies inside the 90 by 90 map".into());
        }
    }
    if *item > ITEMS {
        return Err("an item is a number from 1 to 999".into());
    }
    if *flag >= FLAGS {
        return Err("a mission flag is a number from 0 to 127".into());
    }
    let bytes = files.get_mut("Data TD3").ok_or("missing Data TD3")?;
    if *slot == total {
        bytes.resize((total + 1) * ENTRY, 0);
    }
    let values = [
        day, interval, chance, story, map, region, x, y, item, flag, place,
    ];
    for (n, value) in values.into_iter().enumerate() {
        let at = slot * ENTRY + n * 2;
        bytes[at..at + 2].copy_from_slice(&value.to_be_bytes());
    }
    Ok(())
}

/// What a switched-off entry holds.
pub fn unused() -> [i16; 11] {
    UNUSED
}

/// Findings about the calendar: entries the scan never reaches and fields the scan does not take.
pub fn findings(files: &Files) -> Vec<Value> {
    let Ok(view) = view(files) else {
        return vec![];
    };
    let mut found = vec![];
    let finding = |slot: usize, message: String| {
        json!({"severity":"warning","message":message,"count":null,"unit":null,
            "where":{"kind":"calendar","id":slot,"label":format!("Calendar · entry {slot}")}})
    };
    let entries = view["entries"].as_array().cloned().unwrap_or_default();
    let end = view["ends_at"].as_u64().map(|e| e as usize);
    let stories = files.get("Data ED3").map_or(0, |b| b.len() / 42) as i64;
    let mut unreachable = 0;
    let mut first_unreached = None;
    for entry in &entries {
        let slot = entry["slot"].as_u64().unwrap_or(0) as usize;
        let value = |name: &str| entry[name].as_i64().unwrap_or(0);
        if entry["reached"] != true {
            unreachable += 1;
            first_unreached.get_or_insert(slot);
            continue;
        }
        if value("day") <= 0 {
            continue;
        }
        if value("story") >= stories {
            found.push(finding(
                slot,
                format!(
                    "Entry {slot} runs story {}, which the scenario does not hold",
                    value("story")
                ),
            ));
        }
        if value("place") > 1 {
            found.push(finding(
                slot,
                format!("Entry {slot} has a place test of {}; the game skips such an entry and never runs it", value("place")),
            ));
        }
        if value("flag") >= i64::from(FLAGS) {
            found.push(finding(
                slot,
                format!(
                    "Entry {slot} tests mission flag {}; the game has flags 0 to 127",
                    value("flag")
                ),
            ));
        }
        if value("place") == 1 && value("region") >= i64::from(REGIONS) {
            found.push(finding(
                slot,
                format!(
                    "Entry {slot} tests region {}; a map holds regions 0 to 19",
                    value("region")
                ),
            ));
        }
    }
    if let (Some(slot), true) = (first_unreached, unreachable > 0) {
        let why = match end {
            Some(end) => format!("entry {end} has day 0, which ends the calendar"),
            None => format!("the game reads entries 0 to {} only", REACHED - 1),
        };
        found.push(finding(
            slot,
            format!("{unreachable} entries from {slot} on are never read: {why}"),
        ));
    }
    found
}
