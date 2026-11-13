//! User settings live outside immutable projects and application packages.
use centurions_format::Result;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::{fs, io::Write, path::Path};

/// The most recent projects the settings file keeps.
pub const RECENT_LIMIT: usize = 12;

/// One project the editor opened or saved, with what the Project page shows
/// about it before it is opened again.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Recent {
    pub path: String,
    pub name: String,
    pub origin: String,
    pub label: String,
    pub version: u64,
    pub edits: u64,
    pub source_files: u64,
    /// Seconds since the Unix epoch when the project was last opened or saved.
    pub saved: u64,
    pub contents: Value,
    pub notices: Vec<String>,
}

/// The settings file. Keys the adapter does not own, such as the workspace
/// choices the workbench stores, are kept as they were.
#[derive(Default, Serialize, Deserialize)]
pub struct Preferences {
    #[serde(default)]
    pub installation: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub recent: Vec<Recent>,
    #[serde(flatten)]
    pub other: Map<String, Value>,
}

pub fn load(path: &Path) -> Result<Preferences> {
    if !path.exists() {
        return Ok(Preferences::default());
    }
    let path = crate::paths::checked_existing(path)?;
    serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?)
        .map_err(|e| format!("Cannot read editor preferences: {e}"))
}

fn write(path: &Path, preferences: &Preferences) -> Result<()> {
    let parent = crate::paths::checked_existing(path.parent().ok_or("settings need a parent")?)?;
    crate::paths::new_destination(&parent.join(".centurions-settings-write-check"), &[])?;
    let mut temp = tempfile::NamedTempFile::new_in(&parent).map_err(|e| e.to_string())?;
    serde_json::to_writer_pretty(&mut temp, preferences).map_err(|e| e.to_string())?;
    temp.write_all(b"\n").map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn save(path: &Path, installation: &Path) -> Result<Preferences> {
    let mut preferences = load(path)?;
    preferences.installation = if installation.as_os_str().is_empty() {
        String::new()
    } else {
        let root = crate::paths::checked_existing(installation)?;
        let cargo = root.join("Data Files/Cargo Pod.rsrc");
        crate::paths::checked_existing(&cargo).map_err(
            |_| "Choose the extracted TheNewCenturions folder containing Data Files/Cargo Pod.rsrc",
        )?;
        crate::media::fork(&fs::read(cargo).map_err(|e| e.to_string())?)?;
        root.to_string_lossy()
            .trim_start_matches(r"\\?\")
            .replace('\\', "/")
    };
    write(path, &preferences)?;
    Ok(preferences)
}

/// Puts `entry` first in the recent list, replacing an earlier entry for the
/// same project folder.
pub fn remember(path: &Path, entry: Recent) -> Result<()> {
    let mut preferences = load(path)?;
    preferences.recent.retain(|known| known.path != entry.path);
    preferences.recent.insert(0, entry);
    preferences.recent.truncate(RECENT_LIMIT);
    write(path, &preferences)
}
