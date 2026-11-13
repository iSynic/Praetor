use centurions_format::{Files, ScriptFamily as S, extras};

fn put(files: &mut Files, name: &str, at: usize, value: i16) {
    files.get_mut(name).unwrap()[at..at + 2].copy_from_slice(&value.to_be_bytes());
}

/// Two stories whose first step is a battle naming Extra Codes row 1, and a row 2 of zeros.
fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data ED3".into(), vec![0; 42 * 3]);
    f.insert("Data EDCD".into(), vec![0; 10 * 3]);
    f.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    for story in [0, 1] {
        put(&mut f, "Data ED3", story * 42 + 8, 2);
        put(&mut f, "Data ED3", story * 42 + 24, 1);
    }
    put(&mut f, "Data EDCD", 10 + 6, 2200);
    f
}

#[test]
fn a_shared_row_lists_its_steps_checks_a_word_against_each_and_a_step_can_leave_it() {
    let mut files = fixture();
    let found = extras::callers(&files, 1);
    assert_eq!(found.len(), 2);
    assert!(found.iter().all(|c| c.op == 2 && c.family == S::Story));
    // The reward mode of a battle is 0 or 5.
    assert!(extras::set_word(&mut files, 1, 4, 3).is_err());
    extras::set_word(&mut files, 1, 4, 5).unwrap();
    assert_eq!(&files["Data EDCD"][10 + 8..10 + 10], &5i16.to_be_bytes());
    assert!(extras::set_word(&mut files, 1, 5, 0).is_err());
    assert!(extras::set_word(&mut files, 9, 0, 0).is_err());

    // Story 1 takes the first row that no step names and that holds only zeros: row 0.
    extras::make_independent(&mut files, S::Story, 1, 0, 0).unwrap();
    assert_eq!(&files["Data ED3"][42 + 24..42 + 26], &0i16.to_be_bytes());
    assert_eq!(&files["Data EDCD"][0..10], &files["Data EDCD"][10..20]);
    assert_eq!(extras::callers(&files, 1).len(), 1);
    // Story 0 still names row 1 and takes the zero row 2.
    extras::make_independent(&mut files, S::Story, 0, 0, 0).unwrap();
    assert_eq!(files["Data EDCD"].len(), 30);
    assert_eq!(&files["Data ED3"][24..26], &2i16.to_be_bytes());
    // No row is both free and zero now (row 1 is unnamed but not zero), so the file grows.
    extras::make_independent(&mut files, S::Story, 1, 0, 0).unwrap();
    assert_eq!(files["Data EDCD"].len(), 40);
    assert_eq!(&files["Data ED3"][42 + 24..42 + 26], &3i16.to_be_bytes());
}
