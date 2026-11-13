//! Centurions-specific projections and bounded source overlays. No filesystem or UI.
mod allocation;
pub mod authoring;
pub mod calendar;
pub mod codecs;
pub mod combat_view;
pub mod conditions;
pub mod connected;
pub mod edits;
pub mod extras;
pub mod graphics;
pub mod inspect;
pub mod items;
pub mod maps;
pub mod model;
pub mod monsters;
pub mod native;
pub mod navigation;
pub mod notes;
pub mod ownership;
pub mod record_view;
pub mod references;
pub mod regions;
pub mod resource_fork;
pub mod resources;
pub mod script_codes;
pub mod scripts;
pub mod shops;
pub mod text;
mod trigger_placement;

pub use edits::{apply, update};
pub use model::*;
use sha2::{Digest, Sha256};

pub type Result<T> = std::result::Result<T, String>;

pub fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

pub(crate) fn span(bytes: &[u8], at: usize, len: usize) -> Result<&[u8]> {
    bytes
        .get(at..at.checked_add(len).ok_or("offset overflow")?)
        .ok_or_else(|| {
            format!(
                "short record at {at}: need {len} bytes, have {}",
                bytes.len()
            )
        })
}

pub(crate) fn word(bytes: &[u8], at: usize) -> Result<i16> {
    Ok(i16::from_be_bytes(span(bytes, at, 2)?.try_into().unwrap()))
}

pub(crate) fn long(bytes: &[u8], at: usize) -> Result<i32> {
    Ok(i32::from_be_bytes(span(bytes, at, 4)?.try_into().unwrap()))
}
