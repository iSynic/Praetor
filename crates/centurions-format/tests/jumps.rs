use centurions_format::{Files, ScriptFamily as S, extras, scripts};

fn fixture() -> Files {
    let mut f = Files::new();
    for (name, stride, rows) in [
        ("Data ED3", 42, 3),
        ("Data ED", 426, 3),
        ("Data ED2", 516, 3),
        ("Data EDCD", 10, 6),
    ] {
        f.insert(name.into(), vec![0; stride * rows]);
    }
    f.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    f
}

/// Story 1 has the code in its first step, naming Extra Codes row 1.
fn with_code(code: i16) -> Files {
    let mut f = fixture();
    scripts::patch(&mut f, S::Story, 1, 0, 0, code, 1).unwrap();
    f
}

#[test]
fn the_target_of_a_jump_is_what_its_jump_type_says() {
    // Code 33: the standard jump in words 3 to 5.
    let mut f = with_code(33);
    extras::set_row(&mut f, 1, [100, 0, 0, 2, 0]).unwrap(); // a script that exists
    extras::set_row(&mut f, 1, [100, 0, 1, 3, 7]).unwrap(); // branch 3, from the eighth step
    extras::set_row(&mut f, 1, [100, 0, 3, 999, 99]).unwrap(); // ends the script: nothing else is read
    assert!(extras::set_row(&mut f, 1, [100, 0, 0, 999, 0]).is_err());
    assert!(extras::set_row(&mut f, 1, [100, 0, 2, 4, 0]).is_err());
    assert!(extras::set_row(&mut f, 1, [100, 0, 1, 0, 8]).is_err());

    // Code 21: the first selector says what the fourth word names.
    let mut f = with_code(21);
    extras::set_row(&mut f, 1, [5, 1, 3, 2, 0]).unwrap(); // simple encounter 2
    assert!(extras::set_row(&mut f, 1, [5, 1, 3, 9, 0]).is_err());
    extras::set_row(&mut f, 1, [5, 5, 3, 9999, 0]).unwrap(); // selector 5 carries on: no target

    // Code 7: a map event, or a branch of an encounter.
    let mut f = with_code(7);
    extras::set_row(&mut f, 1, [0, 99, 1, 0, 0]).unwrap();
    assert!(extras::set_row(&mut f, 1, [0, 100, 1, 0, 0]).is_err());
    assert!(extras::set_row(&mut f, 1, [4, 0, 1, 0, 0]).is_err());
    extras::set_row(&mut f, 1, [-2, 1, 1, 0, 3]).unwrap();
    assert!(extras::set_row(&mut f, 1, [-2, 1, 1, 0, 4]).is_err());
}

#[test]
fn a_code_that_reads_the_next_row_too_gets_two_rows_of_its_own() {
    let mut f = fixture();
    scripts::patch(&mut f, S::Story, 1, 0, 0, 92, 1).unwrap();
    assert_eq!(extras::callers(&f, 1).len(), 1);
    let second = extras::callers(&f, 2);
    assert_eq!(second.len(), 1);
    assert!(second[0].companion);
    extras::set_word(&mut f, 2, 0, -5).unwrap(); // a side may be negative
    extras::set_word(&mut f, 1, 1, 19).unwrap();
    assert!(extras::set_word(&mut f, 1, 1, 20).is_err());
    // Two steps share the pair; the second takes rows of its own, side by side.
    scripts::patch(&mut f, S::Story, 2, 0, 0, 92, 1).unwrap();
    extras::make_independent(&mut f, S::Story, 2, 0, 0).unwrap();
    let program = scripts::program(&f, S::Story, 2, 0).unwrap();
    let target = program["steps"][0]["operand"].as_u64().unwrap() as usize;
    assert!(target >= 3);
    assert_eq!(
        &f["Data EDCD"][target * 10..target * 10 + 20],
        &f["Data EDCD"][10..30]
    );
}

#[test]
fn the_flow_and_the_callers_follow_the_words_of_a_jump() {
    use centurions_format::navigation;
    let mut f = with_code(21);
    extras::set_row(&mut f, 1, [5, 0, 0, 2, 0]).unwrap(); // found: script 2; not found: script 0 (step 5 is unused)
    let uses = navigation::uses(&f, "story", 2).unwrap();
    assert_eq!(uses["total"], 1);
    let flow = navigation::flow(&f, S::Story, 1).unwrap();
    let edges = flow["edges"].as_array().unwrap();
    assert!(
        edges
            .iter()
            .any(|e| e["from"] == "story:1" && e["to"] == "story:2")
    );
}

#[test]
fn a_value_a_scenario_already_holds_stays_editable_and_is_listed_but_a_new_one_is_refused() {
    use centurions_format::navigation;
    let mut f = fixture();
    // Code -12 with the right column 90, as a shipped scenario has it.
    scripts::patch(&mut f, S::Story, 1, 0, 0, -12, 1).unwrap();
    let row = &mut f.get_mut("Data EDCD").unwrap()[10..20];
    for (index, value) in [0i16, 79, 90, 0, 12].iter().enumerate() {
        row[index * 2..index * 2 + 2].copy_from_slice(&value.to_be_bytes());
    }
    extras::set_row(&mut f, 1, [0, 78, 90, 0, 12]).unwrap(); // another word changes; the 90 stays
    assert!(extras::set_row(&mut f, 1, [0, 78, 91, 0, 12]).is_err());
    let found = navigation::script_findings(&f);
    assert_eq!(found.len(), 1);
    assert!(
        found[0]["message"]
            .as_str()
            .unwrap()
            .contains("Extra Code 3")
    );
}

#[test]
fn a_value_the_game_handles_but_the_manual_advises_against_is_written_and_listed() {
    use centurions_format::navigation;
    let mut f = fixture();
    // Picking nine warriors: the game lowers the count to those available, though the manual says 1 to 6.
    scripts::patch(&mut f, S::Story, 1, 0, 0, 14, 9).unwrap();
    let found = navigation::script_findings(&f);
    assert_eq!(found.len(), 1);
    assert!(
        found[0]["message"]
            .as_str()
            .unwrap()
            .contains("manual advises")
    );
    // The same for a word of a row: a count of 22 random items.
    scripts::patch(&mut f, S::Story, 1, 0, 1, 65, 1).unwrap();
    extras::set_word(&mut f, 1, 0, 22).unwrap();
    assert_eq!(navigation::script_findings(&f).len(), 2);
}
