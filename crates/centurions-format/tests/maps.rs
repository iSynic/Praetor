use centurions_format::{Edit, Files, MAP_BYTES, maps};

/// Two maps. Map 1 holds a walking trigger at column 3, row 4 (cell 3 * 90 + 4), a floor of tile 7, an object, and a
/// region record whose look bytes are set.
fn files() -> Files {
    let mut ld = vec![0u8; MAP_BYTES * 2];
    let cell = 3 * 90 + 4;
    let base = MAP_BYTES;
    for at in ld[base..base + 16200].as_chunks_mut::<2>().0 {
        *at = 7i16.to_be_bytes();
    }
    ld[base + 16200 + cell * 2..base + 16200 + cell * 2 + 2].copy_from_slice(&2i16.to_be_bytes());
    let key: i32 = 10000 + 4 * 100 + 3;
    ld[base + 32400 + cell * 4..base + 32400 + cell * 4 + 4].copy_from_slice(&key.to_be_bytes());
    let mut dd = vec![0u8; 4200 * 2];
    for row in dd.as_chunks_mut::<42>().0 {
        row[..4].copy_from_slice(&(-1i32).to_be_bytes());
    }
    dd[4200..4204].copy_from_slice(&key.to_be_bytes());
    dd[4204] = 1; // returns to map 1
    let mut rd = vec![0u8; 644 * 2];
    rd[644 + 520..644 + 524].copy_from_slice(&[5, 15, 9, 1]);
    rd[644 + 8..644 + 16].copy_from_slice(&[0, 1, 0, 2, 0, 9, 0, 9]);
    let mut files = Files::new();
    files.insert("Data LD".into(), ld);
    files.insert("Data DD".into(), dd);
    files.insert("Data RD".into(), rd);
    files
}

/// The edit that adds the next map as a copy of `copy_of` (or blank), made from the files as they stand.
fn add(files: &Files, copy_of: Option<usize>, triggers: bool, regions: bool) -> Edit {
    maps::prepare(files, copy_of, 12, true, true, triggers, regions).unwrap()
}

#[test]
fn a_copied_map_renumbers_the_keys_of_its_triggers_and_keeps_the_rest() {
    let mut files = files();
    let edit = add(&files, Some(1), true, true);
    maps::patch(&mut files, &edit).unwrap();
    let ld = &files["Data LD"];
    assert_eq!(ld.len(), MAP_BYTES * 3);
    let cell = 3 * 90 + 4;
    let new = MAP_BYTES * 2;
    assert_eq!(
        &ld[new + 16200 + cell * 2..new + 16200 + cell * 2 + 2],
        &2i16.to_be_bytes(),
        "objects are copied"
    );
    let key: i32 = 20000 + 4 * 100 + 3;
    assert_eq!(
        &ld[new + 32400 + cell * 4..new + 32400 + cell * 4 + 4],
        &key.to_be_bytes(),
        "the event cell carries the new map's number"
    );
    let dd = &files["Data DD"];
    assert_eq!(&dd[8400..8404], &key.to_be_bytes());
    assert_eq!(
        dd[8404], 2,
        "a return to the map the trigger stood on stays on the new map"
    );
    assert_eq!(&files["Data RD"][1288 + 520..1288 + 524], &[5, 15, 9, 1]);
    assert_eq!(
        &files["Data RD"][1288 + 8..1288 + 16],
        &[0, 1, 0, 2, 0, 9, 0, 9],
        "regions are copied"
    );
}

#[test]
fn a_blank_map_keeps_the_look_and_takes_a_record_the_game_files_already_hold() {
    let mut files = files();
    // Data DD and Data RD already hold a third record, as the bundled scenario's do beyond its maps.
    files.get_mut("Data DD").unwrap().extend(vec![0xaa; 4200]);
    files.get_mut("Data RD").unwrap().extend(vec![0xbb; 644]);
    let review = maps::review(&files, None, true, true, true, true).unwrap();
    assert_eq!(review["replaces"].as_array().unwrap().len(), 2);
    let edit = add(&files, None, false, false);
    maps::patch(&mut files, &edit).unwrap();
    assert_eq!(
        files["Data DD"].len(),
        4200 * 3,
        "the existing record is replaced, not added after"
    );
    assert_eq!(&files["Data DD"][8400..8404], &(-1i32).to_be_bytes());
    assert_eq!(
        &files["Data RD"][1288 + 520..1288 + 524],
        &[0, 0, 0, 0],
        "a blank map takes the first map's look, which here is empty"
    );
    assert_eq!(
        &files["Data LD"][MAP_BYTES * 2..MAP_BYTES * 2 + 2],
        &12i16.to_be_bytes(),
        "the floor is the chosen tile"
    );
    // Only the next number is accepted, and no more than twenty maps.
    let mut skipping = add(&files, None, false, false);
    if let Edit::AddMap { map, .. } = &mut skipping {
        *map = 5;
    }
    assert!(maps::patch(&mut files, &skipping).is_err());
    let mut full = files.clone();
    for _ in 3..20 {
        let edit = add(&full, None, false, false);
        maps::patch(&mut full, &edit).unwrap();
    }
    let mut over = add(&files, None, false, false);
    if let Edit::AddMap { map, .. } = &mut over {
        *map = 20;
    }
    assert!(maps::patch(&mut full, &over).is_err());
}

#[test]
fn edits_to_a_map_added_in_the_same_batch_apply_after_it() {
    use centurions_format::{KIND, Origin, Project, VERSION, update};
    let files = files();
    let project = Project {
        kind: KIND.into(),
        version: VERSION,
        origin: Origin::Imported {
            label: "test".into(),
        },
        files: Default::default(),
        directories: Default::default(),
        edits: vec![],
        allocations: vec![],
        native: None,
    };
    let edits = vec![
        Edit::Floor {
            map: 2,
            x: 5,
            y: 6,
            tile: 40,
        },
        Edit::MapObject {
            map: 2,
            x: 5,
            y: 6,
            value: -3001,
        },
        add(&files, None, false, false),
    ];
    let next = update(&project, &files, edits).unwrap();
    let built = centurions_format::apply(&next, &files).unwrap();
    let at = MAP_BYTES * 2 + (5 * 90 + 6) * 2;
    assert_eq!(&built["Data LD"][at..at + 2], &40i16.to_be_bytes());
    assert_eq!(
        &built["Data LD"][at + 16200..at + 16202],
        &(-3001i16).to_be_bytes()
    );
}

#[test]
fn only_the_last_map_that_nothing_names_can_be_removed() {
    let mut files = files();
    let edit = add(&files, None, false, false);
    maps::patch(&mut files, &edit).unwrap();
    // A map that is not the last would renumber the ones after it.
    assert!(maps::patch(&mut files, &Edit::RemoveMap { map: 1 }).is_err());
    // A stage that starts on the map keeps it.
    let mut stages = vec![0u8; 464];
    stages[4..6].copy_from_slice(&2i16.to_be_bytes());
    stages[6] = 1;
    let mut named = files.clone();
    named.insert("Data Mission".into(), stages);
    let refused = maps::patch(&mut named, &Edit::RemoveMap { map: 2 }).unwrap_err();
    assert!(refused.contains("Stage 0 starts on Map 2"), "{refused}");
    // Nothing names it: the three files are as they were before the map was added.
    let before = self::files();
    maps::patch(&mut files, &Edit::RemoveMap { map: 2 }).unwrap();
    for name in ["Data LD", "Data DD", "Data RD"] {
        assert_eq!(files[name], before[name], "{name}");
    }
    // The only map stays.
    let mut one = Files::new();
    for name in ["Data LD", "Data DD", "Data RD"] {
        let stride = [MAP_BYTES, 4200, 644][["Data LD", "Data DD", "Data RD"]
            .iter()
            .position(|n| *n == name)
            .unwrap()];
        one.insert(name.into(), vec![0; stride]);
    }
    assert!(maps::patch(&mut one, &Edit::RemoveMap { map: 0 }).is_err());
}

#[test]
fn a_floor_cell_between_the_sheet_and_a_secret_is_reported_with_where() {
    let mut files = files();
    assert!(maps::findings(&files).is_empty());
    // Map 1: a hidden cell (3012) and an icon number (-3012) are not findings; 1012 is, at column 7, row 1.
    for (cell, value) in [(5 * 90 + 6, 3012i16), (7 * 90 + 1, 1012), (8 * 90, -3012)] {
        let at = MAP_BYTES + cell * 2;
        files.get_mut("Data LD").unwrap()[at..at + 2].copy_from_slice(&value.to_be_bytes());
    }
    let found = maps::findings(&files);
    assert_eq!(found.len(), 1);
    let place = &found[0]["where"];
    assert_eq!(
        (
            place["map"].as_u64(),
            place["x"].as_u64(),
            place["y"].as_u64()
        ),
        (Some(1), Some(7), Some(1))
    );
    let message = found[0]["message"].as_str().unwrap();
    assert!(message.contains("1 floor cell numbered"), "{message}");
}
