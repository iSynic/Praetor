use centurions_format::{Edit, Files, calendar};

fn files() -> Files {
    let mut files = Files::new();
    // Two entries whose bytes past the fields the game reads are marked, and ten stories.
    let mut entries = vec![0xeeu8; 80];
    for (slot, fields) in [
        [120i16, 30, 100, 1, -1, -1, -1, -1, -1, -1, -1],
        [0, 0, 0, 0, -1, -1, -1, -1, -1, -1, -1],
    ]
    .iter()
    .enumerate()
    {
        for (n, value) in fields.iter().enumerate() {
            entries[slot * 40 + n * 2..slot * 40 + n * 2 + 2].copy_from_slice(&value.to_be_bytes());
        }
    }
    files.insert("Data TD3".into(), entries);
    files.insert("Data ED3".into(), vec![0; 42 * 10]);
    files.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES * 2]);
    files
}

fn entry(slot: usize, day: i16, story: i16) -> Edit {
    Edit::CalendarEntry {
        slot,
        day,
        interval: 5,
        chance: 100,
        story,
        map: 1,
        region: 3,
        x: 7,
        y: 4,
        item: 800,
        flag: 12,
        place: 1,
    }
}

#[test]
fn an_entry_is_changed_or_added_and_keeps_the_bytes_the_game_does_not_read() {
    let mut files = files();
    calendar::patch(&mut files, &entry(0, 200, 9)).unwrap();
    calendar::patch(&mut files, &entry(2, 300, 2)).unwrap();
    let bytes = &files["Data TD3"];
    assert_eq!(bytes.len(), 120);
    assert_eq!(&bytes[0..2], &200i16.to_be_bytes());
    assert!(
        bytes[22..40].iter().all(|b| *b == 0xee),
        "an existing entry keeps its padding"
    );
    assert!(
        bytes[102..120].iter().all(|b| *b == 0),
        "a new entry has zeros past its fields"
    );
    // A slot beyond the next, a story the scenario lacks, a flag and an item out of range are refused.
    assert!(calendar::patch(&mut files, &entry(4, 1, 1)).is_err());
    assert!(calendar::patch(&mut files, &entry(0, 10, 10)).is_err());
    assert!(calendar::patch(&mut files, &entry(151, 10, 1)).is_err());
    let mut flagged = entry(0, 10, 1);
    if let Edit::CalendarEntry { flag, .. } = &mut flagged {
        *flag = 128;
    }
    assert!(calendar::patch(&mut files, &flagged).is_err());
    // An entry that never comes due may name a story the scenario lacks.
    assert!(calendar::patch(&mut files, &entry(0, -1, 99)).is_ok());
}

#[test]
fn the_scan_ends_at_day_zero_and_the_entries_after_it_are_reported_unreached() {
    let files = files();
    let view = calendar::view(&files).unwrap();
    assert_eq!(view["ends_at"], 1);
    assert_eq!(view["entries"][0]["reached"], true);
    assert_eq!(view["entries"][1]["reached"], true);
    let mut later = files.clone();
    calendar::patch(&mut later, &entry(2, 50, 1)).unwrap();
    let view = calendar::view(&later).unwrap();
    assert_eq!(view["entries"][2]["reached"], false);
    let findings = calendar::findings(&later);
    assert!(
        findings
            .iter()
            .any(|f| f["message"].as_str().unwrap().contains("never read"))
    );
}
