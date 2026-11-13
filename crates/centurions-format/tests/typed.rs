use centurions_format::{ConditionField, Edit, Files, ScriptFamily, authoring, conditions};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    f.insert("Data ED2".into(), vec![0; 516 * 2]);
    f
}

#[test]
fn a_typed_label_owns_only_its_forty_bytes_and_reads_back() {
    let before = fixture();
    let mut after = before.clone();
    authoring::patch(
        &mut after,
        &Edit::TypedLabel {
            id: 1,
            index: 8,
            text: "Open sesame".into(),
        },
    )
    .unwrap();
    let base = 516 + 156 + 8 * 40;
    for at in 0..before["Data ED2"].len() {
        assert!(
            before["Data ED2"][at] == after["Data ED2"][at]
                || (base..base + 40).contains(&at)
                || at == base + 11 + 1,
            "byte {at}"
        );
    }
    let program = centurions_format::scripts::program(&after, ScriptFamily::Typed, 1, 0).unwrap();
    assert_eq!(program["labels"][8], "Open sesame");
    assert!(
        authoring::patch(
            &mut after,
            &Edit::TypedLabel {
                id: 1,
                index: 9,
                text: "x".into()
            }
        )
        .is_err()
    );
    assert!(
        authoring::patch(
            &mut after,
            &Edit::TypedLabel {
                id: 1,
                index: 0,
                text: "x".repeat(40)
            }
        )
        .is_err()
    );
}

#[test]
fn the_password_selector_the_tries_and_the_dialogue_are_conditions() {
    let mut files = fixture();
    for (field, value, at, width) in [
        (ConditionField::PasswordSelector, 3, 516 + 97, 1),
        (ConditionField::Attempts, 5, 516 + 152, 1),
        (ConditionField::Dialogue, 1234, 516 + 154, 2),
    ] {
        let edit = Edit::EncounterCondition {
            family: ScriptFamily::Typed,
            id: 1,
            field,
            index: 0,
            value,
        };
        conditions::patch(&mut files, &edit).unwrap();
        let stored = &files["Data ED2"][at..at + width];
        assert_eq!(
            i64::from(if width == 1 {
                i16::from(stored[0])
            } else {
                i16::from_be_bytes([stored[0], stored[1]])
            }),
            i64::from(value)
        );
    }
    let shown = conditions::projection(&files, ScriptFamily::Typed, 1).unwrap();
    assert!(
        shown["fields"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f["field"] == "dialogue" && f["value"] == 1234)
    );
}
