//! Derived artwork only. Source forks remain opaque project blobs.
use centurions_format::resource_fork::Fork;
use centurions_format::{Files, Result, digest, graphics};
use serde_json::{Value, json};
use std::borrow::Borrow;
use std::path::Path;
use std::sync::Arc;

fn span(b: &[u8], at: usize, n: usize) -> Result<&[u8]> {
    b.get(at..at.checked_add(n).ok_or("resource offset overflow")?)
        .ok_or("truncated resource fork".into())
}
fn word(b: &[u8], at: usize) -> Result<usize> {
    Ok(u16::from_be_bytes(span(b, at, 2)?.try_into().unwrap()) as usize)
}
fn long(b: &[u8], at: usize) -> Result<usize> {
    Ok(u32::from_be_bytes(span(b, at, 4)?.try_into().unwrap()) as usize)
}

pub fn fork(b: &[u8]) -> Result<&[u8]> {
    if ![b"\x00\x05\x16\x07", b"\x00\x05\x16\x00"]
        .iter()
        .any(|magic| b.starts_with(*magic))
    {
        return Ok(b);
    }
    let mut result = None;
    for i in 0..word(b, 24)? {
        let at = 26 + i * 12;
        let kind = long(b, at)?;
        let value = span(b, long(b, at + 4)?, long(b, at + 8)?)?;
        if kind == 2 {
            if result.is_some() {
                return Err("duplicate resource fork entry".into());
            }
            result = Some(value);
        }
    }
    Ok(result.unwrap_or_default())
}

pub fn picture(b: &[u8], id: i16) -> Result<Option<Vec<u8>>> {
    resource(b, b"PICT", id)
}

pub fn resource(b: &[u8], kind: &[u8; 4], id: i16) -> Result<Option<Vec<u8>>> {
    let b = fork(b)?;
    if b.is_empty() {
        return Ok(None);
    }
    let data = span(b, long(b, 0)?, long(b, 8)?)?;
    let map = span(b, long(b, 4)?, long(b, 12)?)?;
    let types = word(map, 24)?;
    let n = word(map, types)?;
    if n == 0xffff {
        return Ok(None);
    }
    let mut found = None;
    for i in 0..=n {
        let at = types + 2 + i * 8;
        if span(map, at, 4)? != kind {
            continue;
        }
        let refs = types + word(map, at + 6)?;
        for j in 0..=word(map, at + 4)? {
            let r = refs + j * 12;
            if word(map, r)? as u16 as i16 != id {
                continue;
            }
            if found.is_some() {
                return Err(format!("ambiguous resource {:?} {id}", kind));
            }
            let offset = span(map, r + 5, 3)?
                .iter()
                .fold(0usize, |a, b| a * 256 + usize::from(*b));
            found = Some(span(data, offset + 4, long(data, offset)?)?.to_vec());
        }
    }
    Ok(found)
}

/// The strings of a `STR#` resource, in order.
fn strings(payload: &[u8]) -> Result<Vec<String>> {
    let count = word(payload, 0)?;
    let mut at = 2;
    let mut out = Vec::new();
    for _ in 0..count {
        let Some(length) = payload.get(at) else {
            break;
        };
        let length = usize::from(*length);
        out.push(centurions_format::text::decode(span(
            payload,
            at + 1,
            length,
        )?));
        at += 1 + length;
    }
    Ok(out)
}

fn held<F: Borrow<Fork>>(sources: &[F], kind: &[u8; 4], id: i16) -> bool {
    crate::installation::find(sources, kind, id).is_some()
}

fn finding(family: centurions_format::ScriptFamily, record: usize, slot: u8, text: &str) -> Value {
    let label = centurions_format::navigation::program_label(family, record, slot);
    json!({"severity":"warning","message":format!("{label} · {text}"),
        "count":null,"unit":null,"where":{"kind":match family {
            centurions_format::ScriptFamily::Walking => "walking",
            centurions_format::ScriptFamily::Story => "story",
            centurions_format::ScriptFamily::Menu => "choice",
            centurions_format::ScriptFamily::Typed => "typed",
        },"id":record,"slot":slot,"label":label}})
}

/// The first word of an Extra Codes row.
fn first_word(files: &Files, row: i16) -> Option<i16> {
    let at = usize::try_from(row).ok()? * 10;
    let bytes = files.get("Data EDCD")?.get(at..at + 2)?;
    Some(i16::from_be_bytes([bytes[0], bytes[1]]))
}

/// The steps that name a resource neither the scenario nor the game holds. A missing picture (code 27)
/// or a missing text with its styles (code 62) crashes the game. An animation (code 128) is eight icons
/// from 12000 + 8 times its number; a missing icon is skipped, so an animation with none draws nothing.
pub fn missing_resources(files: &Files, installation: &Path) -> Result<Vec<Value>> {
    // Nothing is reported without the installation, because the stock resources live there.
    if installation.as_os_str().is_empty() {
        return Ok(vec![]);
    }
    let chain = crate::installation::chain(files, installation)?;
    if chain.len() < 2 {
        return Ok(vec![]);
    }
    missing_in(files, &chain)
}

/// The same findings for resources already read.
pub fn missing_in<F: Borrow<Fork>>(files: &Files, sources: &[F]) -> Result<Vec<Value>> {
    use centurions_format::navigation::steps_of;
    let mut missing = vec![];
    for (family, record, slot, picture) in steps_of(files, 27) {
        if !held(sources, b"PICT", picture) {
            missing.push(finding(family, record, slot, &format!("picture {picture} is in neither the scenario nor the game's data, and the game crashes on a missing picture")));
        }
    }
    for (family, record, slot, text) in steps_of(files, 62) {
        if !held(sources, b"TEXT", text) || !held(sources, b"styl", text) {
            missing.push(finding(family, record, slot, &format!("text {text} needs a TEXT and a styl resource, and the scenario and the game's data lack one, so the game crashes")));
        }
    }
    for (family, record, slot, row) in steps_of(files, 128) {
        let Some(animation) = first_word(files, row) else {
            continue;
        };
        let first = 12000 + 8 * i32::from(animation);
        let mut drawn = false;
        for icon in first..first + 8 {
            drawn |= held(sources, b"cicn", icon as i16);
        }
        if !drawn {
            missing.push(finding(family, record, slot, &format!("animation {animation} has none of its eight icons ({first} to {}) in the scenario or the game's data, so it draws nothing", first + 7)));
        }
    }
    missing.extend(missing_objects(files, sources));
    missing.extend(missing_notes(files, sources));
    Ok(missing)
}

/// The text a note plays, the picture it shows and the icons of its marks that neither the scenario nor the game holds: a text
/// without its `TEXT` and `styl` stops the game, a picture or an icon that is missing draws nothing.
fn missing_notes<F: Borrow<Fork>>(files: &Files, sources: &[F]) -> Vec<Value> {
    let Ok(view) = centurions_format::notes::view(files) else {
        return vec![];
    };
    let mut missing = vec![];
    let finding = |note: &Value, message: String| {
        json!({"severity":"warning","message":format!("Note {} · {message}", note["note"]),"count":null,"unit":null,
            "where":{"kind":"note","id":note["note"],"label":format!("Note {}", note["note"])}})
    };
    let reachable = centurions_format::notes::reachable(files);
    for note in view["notes"]
        .as_array()
        .into_iter()
        .flatten()
        .take(centurions_format::notes::NOTES)
    {
        if !note["note"]
            .as_u64()
            .is_some_and(|n| reachable.contains(&(n as usize)))
        {
            continue;
        }
        let number = |name: &str| i16::try_from(note[name].as_i64().unwrap_or(0)).unwrap_or(0);
        if number("show") != 0 {
            let text = number("show");
            if !held(sources, b"TEXT", text) || !held(sources, b"styl", text) {
                missing.push(finding(note, format!("text {text} needs a TEXT and a styl resource, and the scenario and the game's data lack one, so the game stops")));
            }
        } else if number("picture") != 0 {
            if !held(sources, b"PICT", number("picture")) {
                missing.push(finding(note, format!("picture {} is in neither the scenario nor the game's data, so nothing is drawn", number("picture"))));
            }
        } else {
            for mark in note["marks"].as_array().into_iter().flatten() {
                let icon = i16::try_from(mark[0].as_i64().unwrap_or(0)).unwrap_or(0);
                if icon != 0 && !held(sources, b"cicn", icon) {
                    missing.push(finding(note, format!("icon {icon} is in neither the scenario nor the game's data, so its mark draws nothing")));
                }
            }
        }
    }
    missing
}

/// The pictures and icons the object layers name that neither the scenario nor the game holds: a building
/// (the picture 23000 plus its value) or an icon the game cannot find is not drawn.
fn missing_objects<F: Borrow<Fork>>(files: &Files, sources: &[F]) -> Vec<Value> {
    const MAP: usize = centurions_format::MAP_BYTES;
    const OBJECTS: usize = centurions_format::CELLS * 2;
    let mut missing = vec![];
    let Some(ld) = files.get("Data LD") else {
        return missing;
    };
    for (map, record) in ld.as_chunks::<MAP>().0.iter().enumerate() {
        let mut seen: std::collections::BTreeMap<i16, (usize, usize)> = Default::default();
        for (index, value) in record[OBJECTS..OBJECTS * 2]
            .as_chunks::<2>()
            .0
            .iter()
            .enumerate()
        {
            let value = i16::from_be_bytes(*value);
            if value != 0 {
                seen.entry(value).or_insert((index / 90, index % 90));
            }
        }
        for (value, (x, y)) in seen {
            let (kind, wanted, found) = if value < 0 {
                (
                    "icon",
                    i32::from(value).abs(),
                    held(sources, b"cicn", value.saturating_abs()),
                )
            } else {
                (
                    "building",
                    i32::from(value),
                    held(sources, b"PICT", 23000 + value),
                )
            };
            if !found {
                missing.push(json!({"severity":"warning","message":format!("Map {map} · the object at ({x}, {y}) is the {kind} {wanted}, which is in neither the scenario nor the game's data, so nothing is drawn there"),
                    "count":null,"unit":null,"where":{"kind":"cell","map":map,"x":x,"y":y,"label":format!("Map {map} · ({x}, {y})")}}));
            }
        }
    }
    missing
}

/// Icons the game keeps from before the scenario opens, so a scenario's icon of the same number is not drawn. Only
/// the party marker has been observed (a level whose icon 192 was imported still showed the game's marker).
const KEPT_BY_THE_GAME: [i16; 1] = [192];

/// Findings about icons a scenario holds that the game will not draw.
pub fn icon_findings(files: &Files) -> Vec<Value> {
    let Some(fork) = crate::installation::scenario(files) else {
        return vec![];
    };
    KEPT_BY_THE_GAME
        .iter()
        .filter(|id| fork.get(b"cicn", **id).is_some())
        .map(|id| {
            json!({"severity":"warning","message":format!("The scenario holds icon {id}, but the game keeps the icon {id} it loaded before the scenario opened (the party marker), so the scenario's is never drawn"),
                "count":null,"unit":null,"where":{"kind":"file","label":"Resources"}})
        })
        .collect()
}

/// The longest item name the game's own lists hold; a longer one is advised against.
pub const ITEM_NAME_ADVISED: usize = 30;

/// Findings about the scenario's item names. The game draws a name as far as the place for it reaches and cuts the
/// rest (the item information shows about 60 characters, the lists fewer), so a long name is advice, not an error.
pub fn name_findings(files: &Files) -> Vec<Value> {
    let Some(fork) = crate::installation::scenario(files) else {
        return vec![];
    };
    let Some(list) = fork.get(b"STR#", 801) else {
        return vec![];
    };
    let Ok(names) = strings(&list.data) else {
        return vec![];
    };
    // A name is a Pascal string: the game counts bytes, which are the characters of Mac Roman.
    names
        .iter()
        .take(200)
        .enumerate()
        .filter(|(_, name)| name.chars().count() > ITEM_NAME_ADVISED)
        .map(|(index, name)| {
            json!({"severity":"warning","message":format!("Item {} is named with {} characters; the longest name the game holds has {ITEM_NAME_ADVISED}, and the game cuts a name where its place ends",
                800 + index, name.chars().count()),"count":null,"unit":null,
                "where":{"kind":"item","id":800 + index,"label":format!("Item {}",800 + index)}})
        })
        .collect()
}

/// The names of items 0 to 999, as the game names them: ids below 800 are
/// the first 200 strings of `STR#` 1, 201, 401 and 601 of the installation's
/// `Data ID` fork, ids from 800 the first 200 of `STR#` 801 of the scenario's
/// own fork. A name that cannot be read is null.
pub fn item_names(files: &Files, installation: &Path) -> Result<Value> {
    let mut names: Vec<Option<String>> = vec![None; 1000];
    let mut fill = |source: &Fork, list: i16| -> Result<bool> {
        let Some(resource) = source.get(b"STR#", list) else {
            return Ok(false);
        };
        for (index, name) in strings(&resource.data)?.into_iter().take(200).enumerate() {
            let id = usize::try_from(list - 1).unwrap_or(0) + index;
            if id < names.len() {
                names[id] = Some(name);
            }
        }
        Ok(true)
    };
    let scenario = match crate::installation::scenario(files) {
        Some(fork) => fill(&fork, 801)?,
        None => false,
    };
    let mut stock = false;
    if let Some(fork) = crate::installation::fork(installation, "Data Files/Data ID.rsrc")? {
        for list in [1, 201, 401, 601] {
            stock |= fill(&fork, list)?;
        }
    }
    Ok(
        json!({"names":names,"stock":stock,"scenario":scenario,"icons":item_icons(files, installation)?}),
    )
}

/// The picture with this number as a PNG file in the cache: the scenario's own, then the game's.
pub fn picture_png(files: &Files, id: i16, installation: &Path, cache: &Path) -> Result<Value> {
    let chain = crate::installation::chain(files, installation)?;
    let Some(resource) = crate::installation::find(&chain, b"PICT", id) else {
        return Ok(json!({"status":"absent"}));
    };
    match graphics::decode_pict(&resource.data) {
        Ok(image) => Ok(
            json!({"status":"available","png":cache_image(cache, &resource.data, &image)?,"width":image.width,"height":image.height}),
        ),
        Err(reason) => Ok(json!({"status":"unconverted","reason":reason.to_string()})),
    }
}

/// The icon (a `cicn` number) of each item 0 to 999: the first 800 from the game's `Data ID` definitions, the
/// next 200 from the scenario's `Data NI`. An item whose definition is absent has no icon (null).
fn item_icons(files: &Files, installation: &Path) -> Result<Vec<Option<i16>>> {
    const ROW: usize = 150;
    let mut icons: Vec<Option<i16>> = vec![None; 1000];
    let icon_of = |bytes: &[u8], index: usize| -> Option<i16> {
        let row = bytes.get(index * ROW..(index + 1) * ROW)?;
        Some(i16::from_be_bytes([row[10], row[11]]))
    };
    if let Some(bytes) = crate::installation::file(installation, "Data Files/Data ID")? {
        for (id, slot) in icons.iter_mut().enumerate().take(800) {
            *slot = icon_of(&bytes, id);
        }
    }
    if let Some(bytes) = files.get("Data NI") {
        for (index, slot) in icons.iter_mut().skip(800).enumerate() {
            *slot = icon_of(bytes, index).or(*slot);
        }
    }
    Ok(icons)
}

/// The icons with the given numbers as PNG files in the cache; a number no resource file holds is left out.
pub fn icons(files: &Files, ids: &[i16], installation: &Path, cache: &Path) -> Result<Value> {
    let chain = crate::installation::chain(files, installation)?;
    let mut found = serde_json::Map::new();
    for id in ids {
        let Some(resource) = crate::installation::find(&chain, b"cicn", *id) else {
            continue;
        };
        if let Ok(image) = graphics::decode_cicn(&resource.data) {
            found.insert(
                id.to_string(),
                json!(cache_image(cache, &resource.data, &image)?),
            );
        }
    }
    Ok(json!({"icons":found}))
}

/// The strings of `STR#` `list` in the game's `Cargo Pod.rsrc`.
fn game_strings(installation: &Path, list: i16) -> Result<Vec<String>> {
    let Some(fork) = crate::installation::fork(installation, "Data Files/Cargo Pod.rsrc")? else {
        return Ok(vec![]);
    };
    match fork.get(b"STR#", list) {
        Some(resource) => strings(&resource.data),
        None => Ok(vec![]),
    }
}

/// The samples of a `snd ` resource as a WAV file: format 1 or 2 with a standard or extended sound header, 8-bit
/// unsigned or 16-bit signed. A compressed sound is not converted. Returns the file, its sample rate and its length
/// in seconds.
pub fn snd_to_wav(payload: &[u8]) -> Result<(Vec<u8>, u32, f64)> {
    let format = word(payload, 0)?;
    let mut at = match format {
        1 => 4 + word(payload, 2)? * 6,
        2 => 4,
        other => return Err(format!("sound format {other} is not supported")),
    };
    let commands = word(payload, at)?;
    at += 2;
    let mut header = None;
    for _ in 0..commands {
        let command = word(payload, at)? & 0x7fff;
        if command == 0x50 || command == 0x51 {
            header = Some(long(payload, at + 4)?);
            break;
        }
        at += 8;
    }
    let start = header.ok_or("the sound holds no samples")?;
    let encoding = *payload.get(start + 20).ok_or("truncated sound header")?;
    let rate = (long(payload, start + 8)? >> 16) as u32;
    let rate = if rate == 0 { 22050 } else { rate };
    let (channels, bits, data) = match encoding {
        0x00 => {
            let length = long(payload, start + 4)?;
            (1usize, 8usize, span(payload, start + 22, length)?)
        }
        0xff => {
            let channels = long(payload, start + 4)?.max(1);
            let frames = long(payload, start + 22)?;
            let bits = word(payload, start + 48)?;
            if bits != 8 && bits != 16 {
                return Err(format!("{bits}-bit samples are not supported"));
            }
            (
                channels,
                bits,
                span(payload, start + 64, frames * channels * bits / 8)?,
            )
        }
        _ => return Err("a compressed sound is not converted".into()),
    };
    if channels > 2 {
        return Err("more than two channels are not supported".into());
    }
    let mut samples = data.to_vec();
    if bits == 16 {
        for pair in samples.as_chunks_mut::<2>().0 {
            pair.swap(0, 1);
        }
    }
    let seconds = (samples.len() * 8 / bits / channels) as f64 / f64::from(rate);
    let block = (channels * bits / 8) as u32;
    let mut wav = Vec::with_capacity(44 + samples.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&((36 + samples.len()) as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&(channels as u16).to_le_bytes());
    wav.extend_from_slice(&rate.to_le_bytes());
    wav.extend_from_slice(&(rate * block).to_le_bytes());
    wav.extend_from_slice(&(block as u16).to_le_bytes());
    wav.extend_from_slice(&(bits as u16).to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&(samples.len() as u32).to_le_bytes());
    wav.extend_from_slice(&samples);
    Ok((wav, rate, seconds))
}

/// The sound with this number as a WAV file in the cache. The scenario's sounds come before the game's.
pub fn sound(files: &Files, id: i16, installation: &Path, cache: &Path) -> Result<Value> {
    let chain = crate::installation::chain(files, installation)?;
    let Some(resource) = crate::installation::find(&chain, b"snd ", id) else {
        return Ok(json!({"status":"absent"}));
    };
    match snd_to_wav(&resource.data) {
        Ok((wav, rate, seconds)) => Ok(
            json!({"status":"available","wav":cache_bytes(cache, &resource.data, "wav", &wav)?,"rate":rate,"seconds":seconds}),
        ),
        Err(reason) => Ok(json!({"status":"unconverted","reason":reason})),
    }
}

/// The names the game gives the numbers a record holds: conditions, special attacks, races, castes, monster
/// kinds, item classes, calibers and spells (key `school * 1000 + level * 100 + number`).
pub fn names(installation: &Path) -> Result<Value> {
    let mut spells = serde_json::Map::new();
    for school in 1..=4i16 {
        for level in 1..=7i16 {
            let list = game_strings(installation, school * 1000 + level - 1)?;
            for (index, name) in list.into_iter().enumerate() {
                spells.insert(
                    (school * 1000 + level * 100 + index as i16 + 1).to_string(),
                    json!(name),
                );
            }
        }
    }
    Ok(json!({
        "conditions": game_strings(installation, 133)?,
        "special_attacks": game_strings(installation, 137)?,
        "races": game_strings(installation, 129)?,
        "castes": game_strings(installation, 131)?,
        "monster_kinds": game_strings(installation, 130)?,
        "item_classes": game_strings(installation, -11000)?,
        "calibers": game_strings(installation, 142)?,
        "spells": spells,
    }))
}

pub fn artwork(files: &Files, map: usize, installation: &Path, cache: &Path) -> Result<Value> {
    if map
        >= files
            .get("Data LD")
            .map_or(0, |bytes| bytes.len() / centurions_format::MAP_BYTES)
    {
        return Err("unavailable map".into());
    }
    let terrain = files
        .get("Data RD")
        .and_then(|b| b.get(map.checked_mul(644)?.checked_add(520)?))
        .copied()
        .ok_or("missing map terrain selector")?;
    let id = i16::from(terrain) + 299;
    let placeholder = |reason: String| json!({"status":"unresolved","terrain":terrain,"picture":id,"reason":reason});
    let mut sources: Vec<(String, Arc<Vec<u8>>)> = Vec::new();
    if let Some(b) = files.get("Scenario.rsrc") {
        sources.push(("Scenario.rsrc".to_string(), Arc::new(b.clone())));
    }
    for relative in ["Data Files/Cargo Pod.rsrc", "New Centurions.rsrc"] {
        if let Some(bytes) = crate::installation::file(installation, relative)? {
            sources.push((relative.to_string(), bytes));
        }
    }
    let installed = !installation.as_os_str().is_empty();
    let resolve = |kind: &[u8; 4], id: i16| -> Result<Option<(Vec<u8>, String)>> {
        for (owner, b) in &sources {
            if let Some(p) = resource(b, kind, id)? {
                return Ok(Some((p, owner.clone())));
            }
        }
        Ok(None)
    };
    let resolved = resolve(b"PICT", id)?;
    let Some((payload, owner)) = resolved else {
        return Ok(placeholder(
            "Choose the extracted TheNewCenturions installation; this picture may be absent".into(),
        ));
    };
    let image = match graphics::decode_pict(&payload) {
        Ok(image) => image,
        Err(e) => return Ok(placeholder(e.to_string())),
    };
    if (image.width, image.height) != (640, 480) {
        return Ok(placeholder(format!(
            "unresolved atlas geometry {}x{}",
            image.width, image.height
        )));
    }
    let hash = digest(&payload);
    let path = cache_image(cache, &payload, &image)?;
    let property_name = match terrain {
        1 => Some("Data P BD"),
        2 => Some("Data Swamp BD"),
        3 => Some("Data Snow BD"),
        4 => Some("Data Sub BD"),
        5 => Some("Data Desert BD"),
        6 => Some("Data Lava BD"),
        7 => Some("Data Castle BD"),
        8 => Some("Data Techno BD"),
        9 => Some("Data Biologic BD"),
        _ => None,
    };
    let properties = if let (true, Some(name)) = (installed, property_name) {
        crate::installation::file(installation, &format!("Data Files/{name}"))?.map(|b| b.to_vec())
    } else if (15..=19).contains(&terrain) {
        let candidates = files
            .iter()
            .filter(|(name, _)| name.ends_with(" BD"))
            .collect::<Vec<_>>();
        if candidates.len() == 1 {
            Some(candidates[0].1.clone())
        } else {
            None
        }
    } else {
        None
    };
    let default_tile = properties
        .as_ref()
        .and_then(|p| p.get(..2))
        .map(|p| i16::from_be_bytes([p[0], p[1]]));
    let map_data = &files["Data LD"]
        [map * centurions_format::MAP_BYTES..(map + 1) * centurions_format::MAP_BYTES];
    let ids = map_data[..16200]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|b| i16::from_be_bytes(*b))
        .filter(|id| *id <= 0)
        .collect::<std::collections::BTreeSet<_>>();
    let mut icons = serde_json::Map::new();
    let mut unresolved = Vec::new();
    for icon in ids {
        match resolve(b"cicn", icon)? {
            Some((p, owner)) => match graphics::decode_cicn(&p) {
                Ok(img) if (img.width, img.height) == (32, 32) => {
                    icons.insert(icon.to_string(),json!({"png":cache_image(cache,&p,&img)?,"source_sha256":digest(&p),"owner":owner}));
                }
                Ok(img) => unresolved.push(format!(
                    "cicn {icon}: unsupported {}x{} geometry",
                    img.width, img.height
                )),
                Err(e) => unresolved.push(format!("cicn {icon}: {e}")),
            },
            None => unresolved.push(format!("cicn {icon}: resource absent")),
        }
    }
    if default_tile.is_none() {
        unresolved.push("Default floor tile is unresolved".into());
    }
    Ok(
        json!({"status":"available","terrain":terrain,"picture":id,"owner":owner,"source_sha256":hash,
        "png":path,"tile_size":32,"columns":20,"rows":15,"first_tile":1,"last_tile":300,
        "default_tile":default_tile,"icons":icons,"warnings":unresolved}),
    )
}

pub(crate) fn cache_image(
    cache: &Path,
    payload: &[u8],
    image: &graphics::Image,
) -> Result<std::path::PathBuf> {
    let mut png = Vec::new();
    {
        let mut encoder =
            png::Encoder::new(&mut png, u32::from(image.width), u32::from(image.height));
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder
            .write_header()
            .map_err(|e| e.to_string())?
            .write_image_data(&image.rgba)
            .map_err(|e| e.to_string())?;
    }
    cache_bytes(cache, payload, "png", &png)
}

/// Writes derived bytes into the cache under the hash of the resource they came from; a file already there
/// must hold the same bytes.
pub(crate) fn cache_bytes(
    cache: &Path,
    payload: &[u8],
    extension: &str,
    bytes: &[u8],
) -> Result<std::path::PathBuf> {
    let hash = digest(payload);
    if !cache.exists() {
        let destination = crate::paths::new_destination(cache, &[])?;
        std::fs::create_dir(destination).map_err(|e| e.to_string())?;
    }
    let cache = crate::paths::checked_existing(cache)?;
    let path = cache.join(format!("{hash}.{extension}"));
    if path.exists() {
        crate::paths::no_link(&path)?;
        if std::fs::read(&path).map_err(|e| e.to_string())? != bytes {
            return Err("derived artwork cache integrity failure".into());
        }
    } else {
        use std::io::Write;
        let path = crate::paths::new_destination(&path, &[])?;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .map_err(|e| e.to_string())?;
        file.write_all(bytes).map_err(|e| e.to_string())?;
    }
    Ok(path)
}
