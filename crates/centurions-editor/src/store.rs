use crate::paths;
use centurions_format::{Files, Origin, Project, Result, SourceFile, digest};
use std::fs;
use std::io::Write;
use std::path::Path;

const MANIFEST: &str = "project.json";

pub fn import(source: &Path, destination: &Path) -> Result<Project> {
    let source = paths::checked_existing(source)?;
    if !source.is_dir() {
        return Err("import input must be a scenario-level folder".into());
    }
    let output = paths::new_destination(destination, &[&source])?;
    let mut project = Project {
        kind: centurions_format::KIND.into(),
        version: centurions_format::VERSION,
        origin: Origin::Imported {
            label: source
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into(),
        },
        files: Default::default(),
        directories: Default::default(),
        edits: Vec::new(),
        allocations: Vec::new(),
        native: None,
    };
    let mut files = Files::new();
    read_tree(&source, &source, &mut project, &mut files)?;
    if let Some(name) = source
        .parent()
        .and_then(Path::file_name)
        .and_then(|n| n.to_str())
        && files.contains_key(name)
        && files.contains_key("Data Mission")
    {
        let binding = centurions_format::NativeScenario {
            name: name.into(),
            startup_header_source: name.into(),
        };
        if centurions_format::native::validate(&binding, &files).is_ok() {
            project.native = Some(binding);
        }
    }
    paths::manifest(&project)?;
    publish_project(&project, &files, &output)?;
    Ok(project)
}

fn read_tree(
    root: &Path,
    directory: &Path,
    project: &mut Project,
    files: &mut Files,
) -> Result<()> {
    let mut children = fs::read_dir(directory)
        .map_err(|e| e.to_string())?
        .collect::<std::io::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    children.sort_by_key(|e| e.file_name());
    for child in children {
        let path = child.path();
        paths::no_link(&path)?;
        let name = path
            .strip_prefix(root)
            .map_err(|e| e.to_string())?
            .to_str()
            .ok_or("non-UTF8 scenario path")?
            .replace('\\', "/");
        paths::relative(&name)?;
        if path.is_dir() {
            project.directories.insert(name);
            read_tree(root, &path, project, files)?;
        } else if path.is_file() {
            let bytes = fs::read(&path).map_err(|e| e.to_string())?;
            project.files.insert(
                name.clone(),
                SourceFile {
                    sha256: digest(&bytes),
                    size: bytes.len(),
                },
            );
            files.insert(name, bytes);
        } else {
            return Err(format!("unsupported filesystem entry {}", path.display()));
        }
    }
    Ok(())
}

pub fn open(root: &Path) -> Result<(Project, Files)> {
    let root = paths::checked_existing(root)?;
    paths::no_link(&root.join(MANIFEST))?;
    let mut project: Project =
        serde_json::from_slice(&fs::read(root.join(MANIFEST)).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    paths::manifest(&project)?;
    let mut files = Files::new();
    if !project.files.is_empty() {
        paths::checked_existing(&root.join("blobs"))?;
    }
    for (name, entry) in &project.files {
        validate_hash(&entry.sha256)?;
        let path = root.join("blobs").join(&entry.sha256);
        paths::no_link(&path)?;
        let bytes = fs::read(path).map_err(|e| e.to_string())?;
        if bytes.len() != entry.size || digest(&bytes) != entry.sha256 {
            return Err(format!("corrupt source blob for {name}"));
        }
        files.insert(name.clone(), bytes);
    }
    if project.version == 1
        && let Origin::MinimalTemplate { label, .. } = &project.origin
    {
        project.native = Some(centurions_format::NativeScenario {
            name: label.clone(),
            startup_header_source: centurions_format::native::inherited_header(&files)?,
        });
        project.version = centurions_format::VERSION;
        paths::manifest(&project)?;
    }
    // A persisted manifest cannot bypass typed edit validation.
    centurions_format::apply(&project, &files)?;
    Ok((project, files))
}

fn validate_hash(hash: &str) -> Result<()> {
    if hash.len() != 64
        || !hash
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("invalid source blob SHA-256".into());
    }
    Ok(())
}

pub fn save_as(
    project: &Project,
    files: &Files,
    source_root: &Path,
    destination: &Path,
) -> Result<()> {
    let output = paths::new_destination(destination, &[source_root])?;
    publish_project(project, files, &output)
}

fn publish_project(project: &Project, files: &Files, output: &Path) -> Result<()> {
    paths::manifest(project)?;
    centurions_format::apply(project, files)?;
    let staging = tempfile::Builder::new()
        .prefix(".centurions-project-")
        .tempdir_in(output.parent().ok_or("missing output parent")?)
        .map_err(|e| e.to_string())?;
    fs::create_dir(staging.path().join("blobs")).map_err(|e| e.to_string())?;
    for (name, entry) in &project.files {
        let bytes = files
            .get(name)
            .ok_or_else(|| format!("missing source bytes for {name}"))?;
        if bytes.len() != entry.size || digest(bytes) != entry.sha256 {
            return Err(format!("source integrity failure: {name}"));
        }
        let path = staging.path().join("blobs").join(&entry.sha256);
        if !path.exists() {
            synced_write(&path, bytes)?;
        }
    }
    let mut manifest = serde_json::to_vec_pretty(project).map_err(|e| e.to_string())?;
    manifest.push(b'\n');
    synced_write(&staging.path().join(MANIFEST), &manifest)?;
    // Reopen the complete checkpoint before making it visible.
    open(staging.path())?;
    publish_directory(staging, output)
}

pub fn export(project_root: &Path, destination: &Path) -> Result<serde_json::Value> {
    let (project, source) = open(project_root)?;
    export_snapshot(&project, &source, project_root, destination)
}

pub fn export_snapshot(
    project: &Project,
    source: &Files,
    project_root: &Path,
    destination: &Path,
) -> Result<serde_json::Value> {
    let output = paths::new_destination(destination, &[project_root])?;
    let files = centurions_format::apply(project, source)?;
    let staging = tempfile::Builder::new()
        .prefix(".centurions-export-")
        .tempdir_in(output.parent().ok_or("missing output parent")?)
        .map_err(|e| e.to_string())?;
    for dir in &project.directories {
        fs::create_dir_all(staging.path().join(dir)).map_err(|e| e.to_string())?;
    }
    for (name, bytes) in &files {
        synced_write(&staging.path().join(name), bytes)?;
    }
    let exact = &files == source;
    publish_directory(staging, &output)?;
    Ok(
        serde_json::json!({"files":files.len(),"directories":project.directories.len(),
        "byte_exact_to_import":exact,"original_runtime_verified":false,
        "native_scenario_name":project.native.as_ref().map(|binding| &binding.name),
        "native_installation":"Scenario folder and matching Mission menu slot must be installed separately"}),
    )
}

fn synced_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|e| e.to_string())?;
    file.write_all(bytes).map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())
}

fn publish_directory(staging: tempfile::TempDir, output: &Path) -> Result<()> {
    // Claim a fresh directory first: rename must never replace another writer's output.
    fs::create_dir(output).map_err(|e| format!("cannot claim new output directory: {e}"))?;
    // Windows refuses renaming a directory over an existing empty directory. Keep the
    // claim and move each validated entry; readers require project.json (moved last).
    let mut entries = fs::read_dir(staging.path())
        .map_err(|e| e.to_string())?
        .collect::<std::io::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    entries.sort_by_key(|entry| (entry.file_name() == MANIFEST, entry.file_name()));
    for entry in entries {
        fs::rename(entry.path(), output.join(entry.file_name())).map_err(|e| {
            format!(
                "publication incomplete at {}: {e}; choose a new output",
                output.display()
            )
        })?;
    }
    Ok(())
}
