use centurions_editor::preferences;
use std::fs;

#[test]
fn settings_round_trip_replacement_and_failed_selection_preserve_previous_path() {
    let t = tempfile::tempdir().unwrap();
    let settings = t.path().join("settings.json");
    assert!(
        preferences::load(&settings)
            .unwrap()
            .installation
            .is_empty()
    );
    let install = t.path().join("installation");
    fs::create_dir_all(install.join("Data Files")).unwrap();
    fs::write(install.join("Data Files/Cargo Pod.rsrc"), []).unwrap();
    let chosen = preferences::save(&settings, &install).unwrap();
    assert_eq!(
        preferences::load(&settings).unwrap().installation,
        chosen.installation
    );
    let before = fs::read(&settings).unwrap();
    assert!(preferences::save(&settings, t.path()).is_err());
    assert_eq!(fs::read(&settings).unwrap(), before);
    preferences::save(&settings, &install).unwrap();
    assert_eq!(fs::read(&settings).unwrap(), before);
    preferences::save(&settings, std::path::Path::new("")).unwrap();
    assert!(
        preferences::load(&settings)
            .unwrap()
            .installation
            .is_empty()
    );
    fs::write(&settings, b"unrecognized data").unwrap();
    assert!(preferences::save(&settings, &install).is_err());
    assert_eq!(fs::read(&settings).unwrap(), b"unrecognized data");
}

#[test]
fn recent_projects_move_to_the_front_and_workbench_keys_survive_saves() {
    let t = tempfile::tempdir().unwrap();
    let settings = t.path().join("settings.json");
    fs::write(&settings, br#"{"installation":"","seed":12,"grid":true}"#).unwrap();
    let entry = |path: &str, edits| preferences::Recent {
        path: path.into(),
        name: "Patrol".into(),
        edits,
        ..Default::default()
    };
    preferences::remember(&settings, entry("a", 1)).unwrap();
    preferences::remember(&settings, entry("b", 2)).unwrap();
    preferences::remember(&settings, entry("a", 3)).unwrap();
    let loaded = preferences::load(&settings).unwrap();
    let order: Vec<_> = loaded
        .recent
        .iter()
        .map(|known| (known.path.as_str(), known.edits))
        .collect();
    assert_eq!(order, [("a", 3), ("b", 2)]);
    for index in 0..preferences::RECENT_LIMIT + 3 {
        preferences::remember(&settings, entry(&format!("p{index}"), 0)).unwrap();
    }
    let loaded = preferences::load(&settings).unwrap();
    assert_eq!(loaded.recent.len(), preferences::RECENT_LIMIT);
    assert_eq!(loaded.other["seed"], 12);
    assert_eq!(loaded.other["grid"], true);
}
