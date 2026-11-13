use centurions_format::{Project, Result};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

pub fn relative(name: &str) -> Result<()> {
    if name.is_empty() || name.contains('\\') {
        return Err(format!("invalid relative path {name:?}"));
    }
    for component in name.split('/') {
        if component.is_empty()
            || component == "."
            || component == ".."
            || component.ends_with([' ', '.'])
            || component.chars().any(|c| c < ' ' || ":*?\"<>|".contains(c))
        {
            return Err(format!("unsafe path {name:?}"));
        }
        let stem = component.split('.').next().unwrap().to_uppercase();
        if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(&stem.as_str())
            || (stem.starts_with("COM") || stem.starts_with("LPT"))
                && stem.chars().count() == 4
                && "123456789¹²³".contains(stem.chars().last().unwrap())
        {
            return Err(format!("reserved path {name:?}"));
        }
    }
    Ok(())
}

pub fn manifest(project: &Project) -> Result<()> {
    if project.kind != centurions_format::KIND
        || !(1..=centurions_format::VERSION).contains(&project.version)
    {
        return Err("unsupported project kind or version".into());
    }
    if project.version == 1 && project.native.is_some() {
        return Err("native startup bindings require project version 2".into());
    }
    if let Some(binding) = &project.native {
        relative(&binding.name)?;
        relative(&binding.startup_header_source)?;
        if project.directories.iter().any(|dir| {
            dir.eq_ignore_ascii_case(&binding.name)
                || dir.eq_ignore_ascii_case(&format!("{}.rsrc", binding.name))
        }) {
            return Err("native startup filename collides with an imported directory".into());
        }
    }
    let mut seen = BTreeSet::new();
    for path in project.files.keys().chain(project.directories.iter()) {
        relative(path)?;
        if !seen.insert(path.to_lowercase()) {
            return Err(format!("case/path collision: {path}"));
        }
        let mut parent = Path::new(path).parent();
        while let Some(p) = parent.filter(|p| !p.as_os_str().is_empty()) {
            let name = p.to_str().ok_or("non-UTF8 path")?.replace('\\', "/");
            if !project.directories.contains(&name) {
                return Err(format!("missing parent directory {name}"));
            }
            parent = p.parent();
        }
    }
    let mut edits = BTreeSet::new();
    for edit in &project.edits {
        if !edits.insert(edit.identity()) {
            return Err("duplicate field edits".into());
        }
    }
    Ok(())
}

pub fn no_link(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if metadata.file_type().is_symlink() || reparse(&metadata) {
        return Err(format!(
            "links/reparse points are unsupported: {}",
            path.display()
        ));
    }
    Ok(())
}

#[cfg(windows)]
fn reparse(metadata: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    metadata.file_attributes() & 0x400 != 0
}
#[cfg(not(windows))]
fn reparse(_metadata: &fs::Metadata) -> bool {
    false
}

pub fn checked_existing(path: &Path) -> Result<PathBuf> {
    let absolute = std::path::absolute(path).map_err(|e| e.to_string())?;
    for ancestor in absolute.ancestors() {
        no_link(ancestor)?;
    }
    fs::canonicalize(absolute).map_err(|e| e.to_string())
}

pub fn new_destination(path: &Path, inputs: &[&Path]) -> Result<PathBuf> {
    let absolute = std::path::absolute(path).map_err(|e| e.to_string())?;
    let name = absolute
        .file_name()
        .ok_or("output needs a directory name")?
        .to_str()
        .ok_or("non-UTF8 output")?;
    relative(name)?;
    let parent = checked_existing(absolute.parent().ok_or("output needs a parent")?)?;
    if !parent.is_dir() {
        return Err("output parent is not a directory".into());
    }
    let output = parent.join(name);
    if fs::symlink_metadata(&output).is_ok() {
        return Err("destination already exists; choose a new directory".into());
    }
    for input in inputs {
        let source = checked_existing(input)?;
        if output.starts_with(&source) || source.starts_with(&output) {
            return Err("output and input directories overlap".into());
        }
    }
    // These local donors are never writable outputs, even if explicitly supplied.
    for donor in [
        r"D:\The New Centurions Codex",
        r"F:\Realmz - Providence",
        r"C:\Users\Eric\Documents\ChatGPT\New project 2",
    ] {
        let root = Path::new(donor);
        if root.exists() && output.starts_with(checked_existing(root)?) {
            return Err("output is inside a read-only reference checkout".into());
        }
    }
    Ok(output)
}
