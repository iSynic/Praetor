//! The game's own files, read once and kept while they do not change on disk, and the chain of resource files
//! the game searches for a picture, text, icon or sound: the scenario's own first, then these.
//!
//! Every request that looks something up used to read the installation's resource files again (the 9.7 MB
//! `Cargo Pod.rsrc` among them) and parse them; here each is read and parsed once.
use centurions_format::resource_fork::{self, Fork, Resource};
use centurions_format::{Files, Result};
use std::borrow::Borrow;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;

/// The resource files of the game that hold pictures, icons and sounds, in the order they are searched.
pub const CHAIN: [&str; 6] = [
    "Data Files/Cargo Pod.rsrc",
    "Data Files/Buildings.rsrc",
    "Data Files/Tacticals.rsrc",
    "Data Files/Portraits.rsrc",
    "Data Files/Weapon Sounds.rsrc",
    "New Centurions.rsrc",
];

struct Entry {
    length: u64,
    modified: Option<SystemTime>,
    bytes: Arc<Vec<u8>>,
    fork: Option<Arc<Fork>>,
}

fn cache() -> &'static Mutex<HashMap<PathBuf, Entry>> {
    static CACHE: OnceLock<Mutex<HashMap<PathBuf, Entry>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn locate(installation: &Path, relative: &str) -> Result<Option<PathBuf>> {
    if installation.as_os_str().is_empty() {
        return Ok(None);
    }
    let path = crate::paths::checked_existing(installation)?.join(relative);
    if !path.exists() {
        return Ok(None);
    }
    Ok(Some(crate::paths::checked_existing(&path)?))
}

/// The bytes of a file of the installation, or `None` when there is no installation or no such file. The file
/// is read again only when its size or its time changes.
pub fn file(installation: &Path, relative: &str) -> Result<Option<Arc<Vec<u8>>>> {
    let Some(path) = locate(installation, relative)? else {
        return Ok(None);
    };
    let meta = std::fs::metadata(&path).map_err(|e| e.to_string())?;
    let (length, modified) = (meta.len(), meta.modified().ok());
    let mut held = cache()
        .lock()
        .map_err(|_| "the file cache is unavailable")?;
    if let Some(entry) = held.get(&path)
        && entry.length == length
        && entry.modified == modified
    {
        return Ok(Some(entry.bytes.clone()));
    }
    let bytes = Arc::new(std::fs::read(&path).map_err(|e| e.to_string())?);
    held.insert(
        path,
        Entry {
            length,
            modified,
            bytes: bytes.clone(),
            fork: None,
        },
    );
    Ok(Some(bytes))
}

/// The resources of a resource file of the installation, parsed once.
pub fn fork(installation: &Path, relative: &str) -> Result<Option<Arc<Fork>>> {
    let Some(bytes) = file(installation, relative)? else {
        return Ok(None);
    };
    let Some(path) = locate(installation, relative)? else {
        return Ok(None);
    };
    if let Ok(held) = cache().lock()
        && let Some(fork) = held.get(&path).and_then(|entry| entry.fork.clone())
    {
        return Ok(Some(fork));
    }
    let parsed = Arc::new(Fork::read(resource_fork::fork_of(&bytes)?)?);
    if let Ok(mut held) = cache().lock()
        && let Some(entry) = held.get_mut(&path)
    {
        entry.fork = Some(parsed.clone());
    }
    Ok(Some(parsed))
}

/// The scenario's own resource file, parsed.
pub fn scenario(files: &Files) -> Option<Arc<Fork>> {
    let file = files.get("Scenario.rsrc")?;
    Fork::read(resource_fork::fork_of(file).ok()?)
        .ok()
        .map(Arc::new)
}

/// The resource files of the game that exist, each with its name.
pub fn named(installation: &Path) -> Result<Vec<(&'static str, Arc<Fork>)>> {
    let mut found = vec![];
    for relative in CHAIN {
        if let Some(fork) = fork(installation, relative)? {
            found.push((relative, fork));
        }
    }
    Ok(found)
}

/// Every resource file the game searches, the scenario's first.
pub fn chain(files: &Files, installation: &Path) -> Result<Vec<Arc<Fork>>> {
    let mut forks: Vec<Arc<Fork>> = scenario(files).into_iter().collect();
    forks.extend(named(installation)?.into_iter().map(|(_, fork)| fork));
    Ok(forks)
}

/// The first resource of a type and number in the chain.
pub fn find<F: Borrow<Fork>>(chain: &[F], kind: &[u8; 4], id: i16) -> Option<Resource> {
    chain
        .iter()
        .find_map(|fork| fork.borrow().get(kind, id).cloned())
}
