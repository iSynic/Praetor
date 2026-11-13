use centurions_format::resource_fork::{Fork, fork_of, with_fork};
use centurions_format::{Edit, Files, StyleRun, resources};

fn apple_double(fork: &[u8]) -> Vec<u8> {
    // Two entries: the Finder info (9) and the resource fork (2), the fork last.
    let mut file = vec![0, 5, 0x16, 7, 0, 2, 0, 0];
    file.extend_from_slice(&[0; 16]);
    file.extend_from_slice(&2u16.to_be_bytes());
    for (id, at, length) in [(9u32, 50u32, 32u32), (2, 82, fork.len() as u32)] {
        file.extend_from_slice(&id.to_be_bytes());
        file.extend_from_slice(&at.to_be_bytes());
        file.extend_from_slice(&length.to_be_bytes());
    }
    file.extend_from_slice(&[0xab; 32]);
    file.extend_from_slice(fork);
    file
}

fn scenario(fork: &Fork) -> Files {
    let mut files = Files::new();
    files.insert("Scenario.rsrc".into(), apple_double(&fork.write().unwrap()));
    files
}

#[test]
fn a_fork_keeps_what_it_holds_when_a_resource_is_added_changed_and_removed() {
    let mut fork = Fork::empty();
    fork.set(b"TEXT", 1000, Some(b"first".to_vec()));
    fork.set(b"cicn", 3000, Some(vec![1, 2, 3]));
    fork.set(b"TEXT", 1001, Some(b"second".to_vec()));
    let back = Fork::read(&fork.write().unwrap()).unwrap();
    assert_eq!(back.ids(b"TEXT"), [1000, 1001]);
    assert_eq!(back.get(b"cicn", 3000).unwrap().data, [1, 2, 3]);
    // The write of what was read is the same fork, byte for byte.
    assert_eq!(back.write().unwrap(), fork.write().unwrap());
    let mut changed = back.clone();
    changed.set(b"TEXT", 1000, Some(b"longer first".to_vec()));
    changed.set(b"cicn", 3000, None);
    let again = Fork::read(&changed.write().unwrap()).unwrap();
    assert_eq!(again.get(b"TEXT", 1000).unwrap().data, b"longer first");
    assert!(again.get(b"cicn", 3000).is_none());
    assert_eq!(again.get(b"TEXT", 1001).unwrap().data, b"second");
}

#[test]
fn a_scrolling_text_is_edited_in_a_wrapped_fork_that_keeps_its_other_entries() {
    let mut files = scenario(&Fork::empty());
    let before = files["Scenario.rsrc"].clone();
    let edit = Edit::ScrollText {
        id: 1000,
        text: "A long road.\nIt begins here.".into(),
        runs: None,
    };
    resources::patch(&mut files, &edit).unwrap();
    let file = &files["Scenario.rsrc"];
    assert_eq!(&file[50..82], &before[50..82], "the Finder info is kept");
    let read = resources::scroll_text(&files, 1000).unwrap();
    assert_eq!(read["text"], "A long road.\nIt begins here.");
    assert_eq!(
        read["runs"].as_array().unwrap().len(),
        1,
        "a new text gets a style"
    );
    // A shorter text cuts the runs that began past its end, and the first run stays.
    let runs: Vec<StyleRun> = (0..3)
        .map(|n| StyleRun {
            start: n * 10,
            height: 14,
            ascent: 11,
            font: 3,
            face: 0,
            size: 12,
            color: [0; 3],
        })
        .collect();
    let set = Edit::ScrollText {
        id: 1000,
        text: "0123456789ABCDEFGHIJ0123".into(),
        runs: Some(runs),
    };
    resources::patch(&mut files, &set).unwrap();
    let short = Edit::ScrollText {
        id: 1000,
        text: "short".into(),
        runs: None,
    };
    resources::patch(&mut files, &short).unwrap();
    let read = resources::scroll_text(&files, 1000).unwrap();
    assert_eq!(read["runs"].as_array().unwrap().len(), 1);
    assert_eq!(read["length"], 5);
    resources::patch(&mut files, &Edit::ScrollTextRemove { id: 1000 }).unwrap();
    assert!(resources::scroll_text(&files, 1000).is_err());
    assert_eq!(
        fork_of(&files["Scenario.rsrc"]).unwrap().len(),
        Fork::empty().write().unwrap().len()
    );
    // Text outside Mac Roman and a resource of a type the editor does not author are refused.
    let bad = Edit::ScrollText {
        id: 1,
        text: "日本".into(),
        runs: None,
    };
    assert!(resources::patch(&mut files, &bad).is_err());
    let foreign = Edit::ResourceChange {
        resource_type: "CODE".into(),
        id: 1,
        data: Some("00".into()),
    };
    assert!(resources::patch(&mut files, &foreign).is_err());
}

/// The game's own resource files read and write back to the same bytes. It needs the installation, named
/// by `CENTURIONS_INSTALLATION`, and is skipped without it.
#[test]
fn the_resource_files_of_the_installation_write_back_unchanged() {
    let Ok(root) = std::env::var("CENTURIONS_INSTALLATION") else {
        return;
    };
    let root = std::path::PathBuf::from(root);
    for relative in [
        "Scenarios/The Thunder of Guns/0/Scenario.rsrc",
        "Data Files/Cargo Pod.rsrc",
        "Data Files/Tacticals.rsrc",
    ] {
        let Ok(file) = std::fs::read(root.join(relative)) else {
            continue;
        };
        let fork = fork_of(&file).unwrap();
        let written = Fork::read(fork).unwrap().write().unwrap();
        let first = written.iter().zip(fork.iter()).position(|(a, b)| a != b);
        assert!(
            written == fork,
            "{relative} does not write back unchanged: {} bytes written, {} read, first difference at {first:?}",
            written.len(),
            fork.len()
        );
        assert_eq!(
            with_fork(&file, &written).unwrap(),
            file,
            "{relative} wrapped"
        );
    }
}

#[test]
fn an_item_name_changes_its_own_string_and_nothing_else_of_the_list() {
    let mut fork = Fork::empty();
    // The scenario's names: three set, the rest the list's own empty strings.
    let mut list = 200u16.to_be_bytes().to_vec();
    for name in [&b"Rations"[..], b"Flashlight", b"Cargo Pod"] {
        list.push(name.len() as u8);
        list.extend_from_slice(name);
    }
    list.extend(std::iter::repeat_n(0u8, 197));
    fork.set(b"STR#", 801, Some(list));
    let mut files = scenario(&fork);
    let edit = Edit::ItemName {
        index: 1,
        name: "Disposable Lamp".into(),
    };
    resources::patch(&mut files, &edit).unwrap();
    let read = Fork::read(fork_of(&files["Scenario.rsrc"]).unwrap()).unwrap();
    let names = &read.get(b"STR#", 801).unwrap().data;
    assert_eq!(&names[..2], &200u16.to_be_bytes());
    assert_eq!(&names[2..10], b"\x07Rations");
    assert_eq!(&names[10..26], b"\x0fDisposable Lamp");
    assert_eq!(&names[26..36], b"\x09Cargo Pod");
    // Without a list a name starts one of two hundred; a number past the last is refused.
    let mut empty = scenario(&Fork::empty());
    resources::patch(
        &mut empty,
        &Edit::ItemName {
            index: 199,
            name: "Last".into(),
        },
    )
    .unwrap();
    let list = Fork::read(fork_of(&empty["Scenario.rsrc"]).unwrap()).unwrap();
    assert_eq!(list.get(b"STR#", 801).unwrap().data.len(), 2 + 199 + 5);
    assert!(
        resources::patch(
            &mut empty,
            &Edit::ItemName {
                index: 200,
                name: "x".into()
            }
        )
        .is_err()
    );
}

#[test]
fn malformed_resource_edits_are_refused_without_a_panic_and_a_text_always_has_a_style() {
    let mut files = scenario(&Fork::empty());
    // A multi-byte character in the hex used to split a character and panic.
    let bad = Edit::ResourceChange {
        resource_type: "PICT".into(),
        id: 1,
        data: Some("\u{e9}0".into()),
    };
    assert!(resources::patch(&mut files, &bad).is_err());
    // An empty list of runs falls back to a style, so the styl never holds none.
    let edit = Edit::ScrollText {
        id: 5,
        text: "words".into(),
        runs: Some(vec![]),
    };
    resources::patch(&mut files, &edit).unwrap();
    assert_eq!(
        resources::scroll_text(&files, 5).unwrap()["runs"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    // Many edits are applied in one pass, in order.
    let edits: Vec<Edit> = (0..3)
        .map(|n| Edit::ItemName {
            index: n,
            name: format!("Item {n}"),
        })
        .collect();
    let refs: Vec<&Edit> = edits.iter().collect();
    resources::patch_many(&mut files, &refs).unwrap();
    let read = Fork::read(fork_of(&files["Scenario.rsrc"]).unwrap()).unwrap();
    assert_eq!(&read.get(b"STR#", 801).unwrap().data[2..9], b"\x06Item 0");
}

#[test]
fn a_fork_too_large_for_its_sixteen_bit_offsets_is_refused_not_truncated() {
    let mut fork = Fork::empty();
    for id in 0..6000 {
        fork.set(b"cicn", id, Some(vec![0]));
    }
    assert!(fork.write().is_err());
}

#[test]
fn a_note_label_changes_its_own_string_of_the_list_it_names_and_starts_a_missing_list_with_dashes()
{
    let mut files = scenario(&Fork::empty());
    let edit = Edit::NoteLabel {
        note: 3,
        identified: true,
        text: "Old Repair Facility".into(),
    };
    resources::patch(&mut files, &edit).unwrap();
    let read = Fork::read(fork_of(&files["Scenario.rsrc"]).unwrap()).unwrap();
    assert!(
        read.get(b"STR#", -101).is_none(),
        "the other list is not made"
    );
    let labels = resources::note_labels(&files).unwrap();
    assert_eq!(labels["known"][2], "Old Repair Facility");
    assert_eq!(labels["known"][0], "--------------------");
    assert_eq!(labels["unknown"][2], "--------------------");
    // The menu holds notes 1 to 19 only.
    for note in [0, 20] {
        let bad = Edit::NoteLabel {
            note,
            identified: false,
            text: "x".into(),
        };
        assert!(resources::patch(&mut files, &bad).is_err());
    }
}
