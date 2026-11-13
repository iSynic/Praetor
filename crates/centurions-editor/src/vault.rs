//! The monster vault: monsters kept beside the editor, apart from any scenario, that a scenario can be filled from and
//! that any scenario's monsters can be added to. A scenario brings its own monsters (the game reads them from the
//! scenario's `Data MD`), so the vault is the editor's own store, not a file of the game.
//!
//! An entry holds the 288 bytes of the monster's row, its description, and the picture of its icon when the icon
//! comes from a resource file, so that it can travel to a scenario that does not hold that icon.
use crate::installation;
use centurions_format::monsters::{self, DESCRIPTION, ROW};
use centurions_format::resources::{hex, unhex};
use centurions_format::{Edit, Files, Result, combat_view, digest, graphics};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

/// The folder of the vault, beside the file of the editor's settings.
pub fn folder(preferences: Option<&Path>) -> Result<PathBuf> {
    let settings = preferences.ok_or("the vault needs the editor's settings folder")?;
    Ok(settings
        .parent()
        .ok_or("the settings file has no folder")?
        .join("centurions-monster-vault"))
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub key: String,
    pub name: String,
    /// Where it came from: the scenario and the monster's number there.
    pub source: String,
    pub added: String,
    /// The row of `Data MD`, hex.
    pub record: String,
    pub description: String,
    /// The `cicn` the row names, and its resource when a resource file holds it.
    pub icon: i16,
    pub icon_data: Option<String>,
    /// A stock monster belongs to one of the game's own scenarios: it is read from the installation, never saved in the
    /// vault's file, and cannot be removed.
    #[serde(skip)]
    pub stock: bool,
}

#[derive(Default, Serialize, Deserialize)]
struct Store {
    version: u32,
    monsters: Vec<Entry>,
}

fn file(dir: &Path) -> PathBuf {
    dir.join("vault.json")
}

fn load(dir: &Path) -> Result<Store> {
    match std::fs::read_to_string(file(dir)) {
        Ok(text) => {
            let store: Store =
                serde_json::from_str(&text).map_err(|e| format!("the vault is unreadable: {e}"))?;
            if store.version > 1 {
                return Err("the vault was written by a newer editor".into());
            }
            Ok(store)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Store {
            version: 1,
            ..Store::default()
        }),
        Err(e) => Err(e.to_string()),
    }
}

fn save(dir: &Path, store: &Store) -> Result<()> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let text = serde_json::to_string_pretty(store).map_err(|e| e.to_string())?;
    let temporary = dir.join("vault.json.new");
    std::fs::write(&temporary, text).map_err(|e| e.to_string())?;
    std::fs::rename(&temporary, file(dir)).map_err(|e| e.to_string())
}

/// What to call the scenario a monster came from: the label of the project, or, when that is only the number of the
/// level's folder, the scenario's name, which a scenario folder carries as the name of its own header file.
pub fn scenario_name(label: &str, files: &Files) -> String {
    if !label.chars().all(|c| c.is_ascii_digit()) {
        return label.to_string();
    }
    files
        .keys()
        .find(|name| {
            !name.contains('/')
                && !name.starts_with("Data ")
                && !name.ends_with(".rsrc")
                && !["Global", "Layout", "Scenario", "Icon_"].contains(&name.as_str())
        })
        .cloned()
        .unwrap_or_else(|| label.to_string())
}

fn icon_of(row: &[u8]) -> i16 {
    i16::from_be_bytes([row[0x50], row[0x51]])
}

fn key_of(record: &[u8], description: &str) -> String {
    let mut bytes = record.to_vec();
    bytes.push(0);
    bytes.extend(description.as_bytes());
    digest(&bytes)[..16].to_string()
}

fn today() -> String {
    // Days since 1970 as a calendar date, without a date library.
    let days = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() / 86_400) as i64;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let day_of_era = z.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_part = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_part + 2) / 5 + 1;
    let month = if month_part < 10 {
        month_part + 3
    } else {
        month_part - 9
    };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!("{year}-{month:02}-{day:02}")
}

/// The stock monsters: those of the scenarios the installation holds, each level's `Data MD` in turn. A monster that an
/// earlier level already gave (the same row and description) is not listed again, and nor is an empty row.
pub fn stock(installation: &Path) -> Result<Vec<Entry>> {
    let root = installation.join("Scenarios");
    if installation.as_os_str().is_empty() || !root.is_dir() {
        return Ok(vec![]);
    }
    let root = crate::paths::checked_existing(&root)?;
    let folders = |dir: &Path| -> Vec<PathBuf> {
        let mut found: Vec<PathBuf> = std::fs::read_dir(dir)
            .map(|read| {
                read.flatten()
                    .map(|e| e.path())
                    .filter(|p| p.is_dir())
                    .collect()
            })
            .unwrap_or_default();
        found.sort();
        found
    };
    let mut seen = BTreeSet::new();
    let mut found = vec![];
    for scenario in folders(&root) {
        let name = scenario
            .file_name()
            .map_or(String::new(), |n| n.to_string_lossy().into_owned());
        for level in folders(&scenario) {
            let Ok(table) = std::fs::read(level.join("Data MD")) else {
                continue;
            };
            let words = std::fs::read(level.join("Data DES")).unwrap_or_default();
            let fork = std::fs::read(level.join("Scenario.rsrc"))
                .ok()
                .and_then(|bytes| {
                    centurions_format::resource_fork::fork_of(&bytes)
                        .ok()
                        .and_then(|f| centurions_format::resource_fork::Fork::read(f).ok())
                });
            let number = level
                .file_name()
                .map_or(String::new(), |n| n.to_string_lossy().into_owned());
            for (id, row) in table.as_chunks::<ROW>().0.iter().enumerate() {
                let monster = combat_view::name(row);
                if monster.is_empty() {
                    continue;
                }
                let length = words.get(id * DESCRIPTION).copied().map_or(0, usize::from);
                let description = words
                    .get(id * DESCRIPTION + 1..id * DESCRIPTION + 1 + length)
                    .map(centurions_format::text::decode)
                    .unwrap_or_default();
                let key = key_of(row, &description);
                if !seen.insert(key.clone()) {
                    continue;
                }
                let icon = icon_of(row);
                let icon_data = fork
                    .as_ref()
                    .filter(|_| icon > 0)
                    .and_then(|f| f.get(b"cicn", icon))
                    .map(|resource| hex(&resource.data));
                let place = if number == "0" {
                    String::new()
                } else {
                    format!(" · level {number}")
                };
                found.push(Entry {
                    key,
                    name: monster,
                    source: format!("{name}{place} · monster {id}"),
                    added: String::new(),
                    record: hex(row),
                    description,
                    icon,
                    icon_data,
                    stock: true,
                });
            }
        }
    }
    Ok(found)
}

/// The stock monsters and then the ones kept in the vault's file.
fn all(dir: &Path, installation: &Path) -> Result<Vec<Entry>> {
    let mut found = stock(installation)?;
    found.extend(load(dir)?.monsters);
    Ok(found)
}

/// The vault's entries for the monsters page, with whether each is already a monster of the scenario and a picture
/// of its icon.
pub fn list(dir: &Path, files: &Files, installation: &Path, cache: &Path) -> Result<Value> {
    let kept = all(dir, installation)?;
    let table = files.get("Data MD").map(Vec::as_slice).unwrap_or_default();
    let chain = installation::chain(files, installation)?;
    let present: BTreeSet<&[u8]> = table
        .as_chunks::<ROW>()
        .0
        .iter()
        .map(<[u8; ROW]>::as_slice)
        .collect();
    let mut entries = vec![];
    for entry in &kept {
        let row = unhex(&entry.record)?;
        let data = entry.icon_data.as_deref().map(unhex).transpose()?;
        let held = installation::find(&chain, b"cicn", entry.icon).map(|resource| resource.data);
        // What a copy does with the icon: nothing (a game icon, or the same picture is there), import the picture, or
        // import it under the next free number because another picture holds the number.
        let icon_state = match (&data, &held) {
            (Some(_), None) if entry.icon > 0 => "imported",
            (Some(picture), Some(there)) if entry.icon > 0 && picture != there => "renumbered",
            (Some(_), Some(_)) if entry.icon > 0 => "present",
            _ => "game",
        };
        let payload = data.or(held);
        let image = payload
            .as_deref()
            .and_then(|bytes| {
                graphics::decode_cicn(bytes)
                    .ok()
                    .and_then(|image| crate::media::cache_image(cache, bytes, &image).ok())
            })
            .map(|path| path.to_string_lossy().into_owned());
        entries.push(
            json!({"key":entry.key,"name":entry.name,"source":entry.source,"added":entry.added,
            "description":entry.description,"icon":entry.icon,"icon_image":image,
            "stock":entry.stock,"icon_travels":entry.icon_data.is_some(),"icon_state":icon_state,
            "in_scenario":present.contains(row.as_slice()),
            "fields":monsters::projection(&row)}),
        );
    }
    Ok(json!({"entries":entries,"count":entries.len(),"folder":dir}))
}

/// Adds monsters of the scenario to the vault; one already there (the same row and description) is skipped, and so is
/// an empty one.
pub fn add(
    dir: &Path,
    files: &Files,
    installation: &Path,
    ids: &[usize],
    source: &str,
) -> Result<Value> {
    let mut store = load(dir)?;
    let stock_keys: BTreeSet<String> = stock(installation)?
        .into_iter()
        .map(|entry| entry.key)
        .collect();
    let chain = installation::chain(files, installation)?;
    let table = files.get("Data MD").ok_or("missing Data MD")?;
    let (mut added, mut skipped) = (0, 0);
    for id in ids {
        let Some(row) = table.get(id * ROW..(id + 1) * ROW) else {
            return Err(format!("monster {id} is not in Data MD"));
        };
        let name = combat_view::name(row);
        let (description, _) = monsters::description(files, *id);
        let key = key_of(row, &description);
        if name.is_empty()
            || stock_keys.contains(&key)
            || store.monsters.iter().any(|entry| entry.key == key)
        {
            skipped += 1;
            continue;
        }
        let icon = icon_of(row);
        let icon_data = (icon > 0)
            .then(|| installation::find(&chain, b"cicn", icon))
            .flatten()
            .map(|resource| hex(&resource.data));
        store.monsters.push(Entry {
            key,
            name,
            source: format!("{source} · monster {id}"),
            added: today(),
            record: hex(row),
            description,
            icon,
            icon_data,
            stock: false,
        });
        added += 1;
    }
    save(dir, &store)?;
    Ok(json!({"added":added,"skipped":skipped,"count":store.monsters.len()}))
}

/// Takes entries out of the vault. A stock monster stays: only the monsters the author added can be removed.
pub fn remove(dir: &Path, keys: &[String]) -> Result<Value> {
    let mut store = load(dir)?;
    if keys
        .iter()
        .any(|key| !store.monsters.iter().any(|entry| &entry.key == key))
    {
        return Err(
            "a stock monster stays in the vault; only monsters that were added can be removed"
                .into(),
        );
    }
    let before = store.monsters.len();
    store.monsters.retain(|entry| !keys.contains(&entry.key));
    save(dir, &store)?;
    Ok(json!({"removed":before - store.monsters.len(),"count":store.monsters.len()}))
}

/// The entries with these keys, in the order of the keys.
pub fn entries(dir: &Path, keys: &[String], installation: &Path) -> Result<Vec<Entry>> {
    let store = all(dir, installation)?;
    keys.iter()
        .map(|key| {
            store
                .iter()
                .find(|entry| &entry.key == key)
                .cloned()
                .ok_or_else(|| "a vault monster is no longer there".to_string())
        })
        .collect()
}

/// The edits that put `entries` in the scenario as the monsters from `first_id` on: each row and description, and the
/// icon of a monster whose icon the scenario and the game do not hold. When a different picture already has the icon's
/// number, the monster takes the next number nothing holds, and so does every monster that carries the same picture.
pub fn copy_edits(
    entries: &[Entry],
    first_id: usize,
    files: &Files,
    installation: &Path,
) -> Result<Vec<Edit>> {
    let chain = installation::chain(files, installation)?;
    let mut edits = vec![];
    let mut taken: Vec<(i16, Vec<u8>)> = vec![];
    for (offset, entry) in entries.iter().enumerate() {
        let mut row = unhex(&entry.record)?;
        if row.len() != ROW {
            return Err("a vault monster is damaged".into());
        }
        if entry.icon > 0
            && let Some(data) = entry.icon_data.as_deref().map(unhex).transpose()?
        {
            let number = if let Some((number, _)) = taken.iter().find(|(_, held)| *held == data) {
                *number
            } else {
                let mut number = entry.icon;
                let mut needs_picture = true;
                loop {
                    let held = taken
                        .iter()
                        .find(|(n, _)| *n == number)
                        .map(|(_, d)| d.clone());
                    let found = held.or_else(|| {
                        installation::find(&chain, b"cicn", number).map(|resource| resource.data)
                    });
                    match found {
                        None => break,
                        Some(same) if same == data => {
                            needs_picture = false;
                            break;
                        }
                        Some(_) => {
                            number = number.checked_add(1).ok_or("no icon number is free")?
                        }
                    }
                }
                if needs_picture {
                    edits.push(Edit::ResourceChange {
                        resource_type: "cicn".into(),
                        id: number,
                        data: Some(hex(&data)),
                    });
                }
                taken.push((number, data));
                number
            };
            row[0x50..0x52].copy_from_slice(&number.to_be_bytes());
        }
        edits.push(Edit::MonsterImport {
            id: first_id + offset,
            record: hex(&row),
            description: entry.description.clone(),
        });
    }
    debug_assert!(entries.iter().all(|e| e.description.len() < DESCRIPTION));
    Ok(edits)
}
