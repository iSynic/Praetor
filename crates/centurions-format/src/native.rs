//! Native startup opens the scenario-named file, independently of Data CS.
use crate::{Edit, Files, NativeScenario, Project, Result, text};

pub fn validate(binding: &NativeScenario, files: &Files) -> Result<()> {
    if binding.name.is_empty()
        || binding.name.contains(['/', '\\', ':'])
        || text::encode(&binding.name)?.len() > 31
    {
        return Err("native scenario name must be a single Mac Roman name of 1..31 bytes".into());
    }
    let source = files
        .get(&binding.startup_header_source)
        .ok_or("native startup header source is missing")?;
    if source.len() < 60 {
        return Err("native startup header needs at least 60 bytes".into());
    }
    if binding.name != binding.startup_header_source {
        for target in [&binding.name, &format!("{}.rsrc", binding.name)] {
            if files.keys().any(|path| path.eq_ignore_ascii_case(target)) {
                return Err(format!(
                    "native startup filename collides with imported file {target}"
                ));
            }
        }
    }
    Ok(())
}

pub fn inherited_header(files: &Files) -> Result<String> {
    let setup = files
        .get("Data CS")
        .ok_or("template lacks Data CS; native header must be identified explicitly")?;
    let candidates: Vec<_> = files
        .iter()
        .filter(|(name, bytes)| {
            !name.starts_with("Data ") && !name.ends_with(".rsrc") && *bytes == setup
        })
        .map(|(name, _)| name.clone())
        .collect();
    if candidates.len() != 1 {
        return Err(
            "native startup header is ambiguous; reimport the original named scenario-level folder"
                .into(),
        );
    }
    Ok(candidates[0].clone())
}

pub fn overlay(project: &Project, source: &Files, output: &mut Files) -> Result<()> {
    let Some(binding) = &project.native else {
        return Ok(());
    };
    validate(binding, source)?;
    let mut header = source[&binding.startup_header_source].clone();
    for edit in &project.edits {
        if let Edit::Opening { map, x, y } = edit {
            for (at, value) in [(8, *map), (12, *x), (16, *y)] {
                header[at..at + 4].copy_from_slice(&value.to_be_bytes());
            }
        }
    }
    output.insert(binding.name.clone(), header);
    let sidecar = format!("{}.rsrc", binding.startup_header_source);
    if let Some(bytes) = source.get(&sidecar) {
        output.insert(format!("{}.rsrc", binding.name), bytes.clone());
    }
    Ok(())
}
