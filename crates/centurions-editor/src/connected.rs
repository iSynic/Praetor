use crate::{minimal, paths, store};
use centurions_format::{Result, connected::MissionSpec};
use serde_json::Value;
use std::path::Path;

pub fn create(template: &Path, destination: &Path, spec: &MissionSpec) -> Result<Value> {
    let destination = paths::new_destination(destination, &[template])?;
    let scratch = tempfile::Builder::new()
        .prefix(".connected-mission-")
        .tempdir_in(destination.parent().ok_or("output needs a parent")?)
        .map_err(|e| e.to_string())?;
    let base = scratch.path().join("base");
    minimal::create(template, &base, &spec.name)?;
    let (project, files) = store::open(&base)?;
    let (next, mut recipe) = centurions_format::connected::build(&project, &files, spec)?;
    store::save_as(&next, &files, &base, &destination)?;
    recipe["project"] = serde_json::json!(destination);
    Ok(recipe)
}
