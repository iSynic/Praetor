//! Template-derived construction; unresolved support bytes remain inherited.
use crate::{paths, store};
use centurions_format::{Edit, Origin, Result, digest, inspect};
use serde_json::{Value, json};
use std::path::Path;

pub fn create(template: &Path, destination: &Path, name: &str) -> Result<Value> {
    // Validate destination before the gate creates even temporary output.
    let output = paths::new_destination(destination, &[template])?;
    let (project, files) = store::open(template)?;
    if !project.edits.is_empty()
        || !project.allocations.is_empty()
        || !matches!(project.origin, Origin::Imported { .. })
    {
        return Err("minimal construction requires an unchanged imported template project".into());
    }
    if name.is_empty() {
        return Err("stage name must not be empty".into());
    }
    let stages = files
        .get("Data Mission")
        .ok_or("template lacks Data Mission")?
        .len()
        / 464;
    if stages == 0 {
        return Err("template has no complete mission record".into());
    }
    let opening = inspect::project(&files)["opening"].clone();
    let value = |key: &str| -> Result<i32> {
        i32::try_from(
            opening[key]
                .as_i64()
                .ok_or("template has no valid opening")?,
        )
        .map_err(|_| "opening value overflow".into())
    };
    let (map, x, y) = (value("map")?, value("x")?, value("y")?);
    let to_word = |v| i16::try_from(v).map_err(|_| "opening value outside stage word range");
    let edits = std::iter::once(Edit::Opening { map, x, y })
        .chain([
            Edit::StageName {
                id: 0,
                name: name.into(),
            },
            Edit::StageStart {
                id: 0,
                map: to_word(map)?,
                x: to_word(x)?,
                y: to_word(y)?,
            },
            Edit::ClearStageScript { id: 0 },
            Edit::QuietMap {
                map: usize::try_from(map).map_err(|_| "negative opening map")?,
            },
            Edit::DisableSchedule,
        ])
        .chain((1..stages).map(|id| Edit::DisableStage { id }))
        .collect();
    let mut next = centurions_format::update(&project, &files, edits)?;
    next.native = Some(centurions_format::NativeScenario {
        name: name.into(),
        startup_header_source: project
            .native
            .as_ref()
            .map(|binding| binding.startup_header_source.clone())
            .map(Ok)
            .unwrap_or_else(|| centurions_format::native::inherited_header(&files))?,
    });
    centurions_format::apply(&next, &files)?;
    let gate = unchanged_gate(template, output.parent().ok_or("missing parent")?)?;
    next.origin = Origin::MinimalTemplate {
        label: name.into(),
        unchanged_gate: gate.clone(),
    };
    store::save_as(&next, &files, template, &output)?;
    let final_files = centurions_format::apply(&next, &files)?;
    Ok(json!({"project":output,"unchanged_gate":gate,
        "summary":inspect::project(&final_files),
        "inherited_support":true,"source_free_construction":false,"original_runtime_verified":false,
        "limitations":["All maps and supporting catalogs are inherited and retained",
            "Global hooks, prologue, media and unresolved bootstrap bytes remain inherited",
            "The original Mission menu needs a matching scenario name and compatible slot; no installation is performed",
            "Floor passability and original-game scenario loading require separate verification"]}))
}

/// Materialize, independently reimport, reopen, and compare the complete folder envelope.
pub fn unchanged_gate(template: &Path, scratch_parent: &Path) -> Result<String> {
    let (project, files) = store::open(template)?;
    if !project.edits.is_empty() || !project.allocations.is_empty() {
        return Err("unchanged gate requires a project without edits".into());
    }
    let scratch = tempfile::Builder::new()
        .prefix(".centurions-gate-")
        .tempdir_in(scratch_parent)
        .map_err(|e| e.to_string())?;
    let level = scratch.path().join("level");
    let reimport = scratch.path().join("reimport");
    let receipt = store::export(template, &level)?;
    store::import(&level, &reimport)?;
    let (reopened, actual) = store::open(&reimport)?;
    if actual != files
        || reopened.directories != project.directories
        || receipt["byte_exact_to_import"] != true
    {
        return Err("unchanged import/export gate failed".into());
    }
    let envelope =
        serde_json::to_vec(&json!({"files":project.files,"directories":project.directories}))
            .map_err(|e| e.to_string())?;
    Ok(digest(&envelope))
}
