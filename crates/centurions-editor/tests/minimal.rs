use centurions_editor::{minimal, store};
use centurions_format::{Edit, Result, ownership};
use std::fs;

#[test]
fn minimal_candidate_is_gated_and_retains_all_unowned_template_bytes() -> Result<()> {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("level");
    fs::create_dir(&source).unwrap();
    let mut cs = vec![0x8a; 316];
    for (at, v) in [(8, 0_i32), (12, 2), (16, 3)] {
        cs[at..at + 4].copy_from_slice(&v.to_be_bytes());
    }
    fs::write(source.join("Template Scenario"), &cs).unwrap();
    fs::write(source.join("Template Scenario.rsrc"), [1, 2, 3]).unwrap();
    for (name, bytes) in [
        ("Data CS", cs),
        ("Data LD", vec![0x82; 64800]),
        ("Data DD", vec![0x83; 4205]),
        ("Data RD", vec![0x84; 647]),
        ("Data Mission", vec![0x85; 464 * 2 + 3]),
        ("Data TD3", vec![0x86; 80]),
        ("Scenario.rsrc", vec![0x87; 33]),
    ] {
        fs::write(source.join(name), bytes).unwrap();
    }
    let template = temp.path().join("template");
    store::import(&source, &template)?;
    let (_, original) = store::open(&template)?;
    let destination = temp.path().join("new-project");
    let receipt = minimal::create(&template, &destination, "First Patrol")?;
    assert_eq!(receipt["original_runtime_verified"], false);
    assert_eq!(receipt["source_free_construction"], false);
    assert_eq!(receipt["summary"]["stages"].as_array().unwrap().len(), 1);
    assert_eq!(receipt["summary"]["opening"]["x"], 2);
    assert_eq!(receipt["summary"]["opening"]["y"], 3);
    let exported = temp.path().join("new-level");
    store::export(&destination, &exported)?;
    assert_eq!(
        fs::read(exported.join("First Patrol")).unwrap(),
        original["Template Scenario"]
    );
    assert_eq!(
        fs::read(exported.join("First Patrol.rsrc")).unwrap(),
        [1, 2, 3]
    );
    assert_eq!(
        fs::read(exported.join("Template Scenario")).unwrap(),
        original["Template Scenario"]
    );
    let (candidate, original_blobs) = store::open(&destination)?;
    let changed = centurions_format::update(
        &candidate,
        &original_blobs,
        vec![Edit::Opening { map: 0, x: 4, y: 5 }],
    )?;
    let compiled = centurions_format::apply(&changed, &original_blobs)?;
    assert_eq!(
        &compiled["First Patrol"][8..20],
        &compiled["Data CS"][8..20]
    );
    assert_eq!(compiled["Template Scenario"], original["Template Scenario"]);
    assert_eq!(
        &compiled["First Patrol"][20..],
        &original["Template Scenario"][20..]
    );
    for bad in ["Data LD", "a/b", "a".repeat(32).as_str()] {
        let rejected = temp.path().join(format!("bad-name-{}", bad.len()));
        assert!(minimal::create(&template, &rejected, bad).is_err());
        assert!(!rejected.exists());
    }
    assert_eq!(
        fs::read(exported.join("Data LD")).unwrap(),
        original["Data LD"]
    );
    assert_eq!(
        fs::read(exported.join("Scenario.rsrc")).unwrap(),
        original["Scenario.rsrc"]
    );
    for name in ["Data Mission", "Data DD", "Data RD", "Data TD3"] {
        let bytes = fs::read(exported.join(name)).unwrap();
        let ranges = match name {
            "Data Mission" => vec![0..6, 6..19, 262..264, 470..471],
            "Data DD" => (0..100).map(|i| i * 42..i * 42 + 4).collect(),
            "Data RD" => vec![160..280, 400..520],
            _ => std::iter::once(0..2).collect(),
        };
        assert_eq!(
            ownership::inspect(&original[name], &bytes, &ranges).unowned_changes,
            0,
            "{name}"
        );
    }
    let (project, files) = store::open(&template)?;
    let modified =
        centurions_format::update(&project, &files, vec![Edit::Opening { map: 0, x: 1, y: 1 }])?;
    let modified_root = temp.path().join("modified");
    store::save_as(&modified, &files, &template, &modified_root)?;
    let rejected = temp.path().join("rejected");
    assert!(minimal::create(&modified_root, &rejected, "Bad template").is_err());
    assert!(!rejected.exists());
    // Old First Patrol checkpoints migrate in memory; their source manifest stays intact.
    let manifest_path = destination.join("project.json");
    let mut legacy: serde_json::Value =
        serde_json::from_slice(&fs::read(&manifest_path).unwrap()).unwrap();
    legacy["version"] = 1.into();
    legacy.as_object_mut().unwrap().remove("native");
    let legacy_bytes = serde_json::to_vec(&legacy).unwrap();
    fs::write(&manifest_path, &legacy_bytes).unwrap();
    let repaired_export = temp.path().join("legacy-repaired");
    store::export(&destination, &repaired_export)?;
    assert_eq!(
        fs::read(repaired_export.join("First Patrol")).unwrap(),
        original["Template Scenario"]
    );
    assert_eq!(fs::read(&manifest_path).unwrap(), legacy_bytes);
    Ok(())
}
