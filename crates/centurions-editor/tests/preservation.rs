use centurions_editor::store;
use centurions_format::{Edit, Result};
use std::fs;

#[test]
fn arbitrary_folder_round_trip_and_owned_edits_survive_reopen() -> Result<()> {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("source");
    fs::create_dir_all(source.join("unknown/empty")).unwrap();
    let mut messages = (0..515).map(|i| (i * 17) as u8).collect::<Vec<_>>();
    messages[256] = 3;
    messages[257..260].copy_from_slice(&[0x8e, 13, 0xdb]);
    fs::write(source.join("Data SD2"), &messages).unwrap();
    fs::write(source.join("Scenario.rsrc"), [0xff, 0, 13, 0x80]).unwrap();
    fs::write(source.join("unknown/file"), [5, 4, 3, 2, 1]).unwrap();
    let project_root = temp.path().join("project");
    store::import(&source, &project_root)?;
    let exported = temp.path().join("export");
    assert_eq!(
        store::export(&project_root, &exported)?["byte_exact_to_import"],
        true
    );
    assert_eq!(fs::read(exported.join("Data SD2")).unwrap(), messages);
    assert_eq!(
        fs::read(exported.join("Scenario.rsrc")).unwrap(),
        [0xff, 0, 13, 0x80]
    );
    assert_eq!(
        fs::read(exported.join("unknown/file")).unwrap(),
        [5, 4, 3, 2, 1]
    );
    assert!(exported.join("unknown/empty").is_dir());
    assert!(store::export(&project_root, &exported).is_err());
    assert!(store::export(&project_root, &project_root.join("nested")).is_err());
    assert!(store::import(&source, &source.join("nested")).is_err());

    let (project, files) = store::open(&project_root)?;
    let noop = centurions_format::update(
        &project,
        &files,
        vec![Edit::Message {
            id: 1,
            text: "é\n€".into(),
        }],
    )?;
    assert_eq!(centurions_format::apply(&noop, &files)?, files);
    let next = centurions_format::update(
        &project,
        &files,
        vec![Edit::Message {
            id: 1,
            text: "Å".into(),
        }],
    )?;
    let edited_root = temp.path().join("edited");
    store::save_as(&next, &files, &project_root, &edited_root)?;
    let edited_export = temp.path().join("edited-export");
    store::export(&edited_root, &edited_export)?;
    let edited = fs::read(edited_export.join("Data SD2")).unwrap();
    let mut expected = messages.clone();
    expected[256..258].copy_from_slice(&[1, 0x81]);
    assert_eq!(edited, expected);
    assert_eq!(fs::read(source.join("Data SD2")).unwrap(), messages);
    Ok(())
}

#[test]
fn corrupt_or_unsafe_projects_and_unsupported_edits_never_publish() -> Result<()> {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("source");
    fs::create_dir(&source).unwrap();
    fs::write(source.join("Data SD2"), [0; 256]).unwrap();
    let root = temp.path().join("project");
    store::import(&source, &root)?;
    let (project, files) = store::open(&root)?;
    for edit in [
        Edit::Message {
            id: 0,
            text: "😀".into(),
        },
        Edit::Message {
            id: 0,
            text: "a".repeat(256),
        },
        Edit::Message {
            id: usize::MAX,
            text: "a".into(),
        },
        Edit::Floor {
            map: 0,
            x: 90,
            y: 0,
            tile: 1,
        },
    ] {
        assert!(centurions_format::update(&project, &files, vec![edit]).is_err());
    }
    let original_manifest = fs::read(root.join("project.json")).unwrap();
    let mut value: serde_json::Value = serde_json::from_slice(&original_manifest).unwrap();
    value["version"] = 999.into();
    fs::write(
        root.join("project.json"),
        serde_json::to_vec(&value).unwrap(),
    )
    .unwrap();
    let output = temp.path().join("bad-export");
    assert!(store::export(&root, &output).is_err());
    assert!(!output.exists());
    value["version"] = 1.into();
    let entry = value["files"]["Data SD2"].take();
    value["files"] = serde_json::json!({"../escape":entry});
    fs::write(
        root.join("project.json"),
        serde_json::to_vec(&value).unwrap(),
    )
    .unwrap();
    assert!(store::export(&root, &output).is_err());
    assert!(!output.exists());
    fs::write(root.join("project.json"), original_manifest).unwrap();
    let hash = &project.files["Data SD2"].sha256;
    fs::write(root.join("blobs").join(hash), [1; 256]).unwrap();
    assert!(store::export(&root, &output).is_err());
    assert!(!output.exists());
    Ok(())
}

#[test]
fn map_axis_and_story_record_geometry_are_centurions_specific() -> Result<()> {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("source");
    fs::create_dir(&source).unwrap();
    let land = vec![0xa5; 64800];
    fs::write(source.join("Data LD"), &land).unwrap();
    let mut stories = vec![0; 85];
    stories[50..52].copy_from_slice(&(-7_i16).to_be_bytes());
    stories[66..68].copy_from_slice(&1234_i16.to_be_bytes());
    fs::write(source.join("Data ED3"), &stories).unwrap();
    let root = temp.path().join("project");
    store::import(&source, &root)?;
    let (project, files) = store::open(&root)?;
    let next = centurions_format::update(
        &project,
        &files,
        vec![Edit::Floor {
            map: 0,
            x: 3,
            y: 7,
            tile: -300,
        }],
    )?;
    let result = centurions_format::apply(&next, &files)?;
    let mut expected = land;
    let offset = (3 * 90 + 7) * 2;
    expected[offset..offset + 2].copy_from_slice(&(-300_i16).to_be_bytes());
    assert_eq!(result["Data LD"], expected);
    let view = centurions_format::inspect::story(&result, 1)?;
    assert_eq!(view["actions"][0]["opcode"], -7);
    assert_eq!(view["actions"][0]["operand"], 1234);
    assert_eq!(result["Data ED3"], stories);
    Ok(())
}
