use centurions_editor::{
    session::{Request, Session},
    store,
};
use centurions_format::{
    ConditionField as F, Edit, Files, Result, ScriptFamily as S, combat_view, conditions,
};
use serde_json::{Value, json};
use std::fs;

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data LD".into(), vec![0x63; 64800]);
    let mut dd = vec![0x47; 4200 + 19];
    for i in 0..100 {
        dd[i * 42..i * 42 + 4].copy_from_slice(&(-1i32).to_be_bytes());
    }
    dd[7..11].copy_from_slice(&[100, 0, 1, 0]);
    dd[..4].copy_from_slice(&703i32.to_be_bytes());
    dd[42..46].copy_from_slice(&703i32.to_be_bytes());
    dd[49] = 100;
    dd[7] = 0;
    f.insert("Data DD".into(), dd);
    for (path, stride) in [("Data ED", 426), ("Data ED2", 516)] {
        let mut b = vec![0x5e; stride * 2 + 7];
        b[stride + 96..stride + 151].fill(0);
        f.insert(path.into(), b);
    }
    f
}
fn unchanged_except(before: &Files, after: &Files, path: &str, owned: std::ops::Range<usize>) {
    for (name, b) in before {
        assert_eq!(b.len(), after[name].len());
        for (at, byte) in b.iter().enumerate() {
            if name != path || !owned.contains(&at) {
                assert_eq!(*byte, after[name][at], "{name}:{at}");
            }
        }
    }
}
#[test]
fn location_chance_conditions_own_only_proven_bytes() -> Result<()> {
    let before = fixture();
    let mut after = before.clone();
    conditions::patch(
        &mut after,
        &Edit::WalkingLocation {
            map: 0,
            slot: 13,
            x: 17,
            y: 29,
        },
    )?;
    unchanged_except(&before, &after, "Data DD", 13 * 42..13 * 42 + 4);
    assert_eq!(&after["Data DD"][546..550], &2917i32.to_be_bytes());
    assert_eq!(before["Data LD"], after["Data LD"]);
    let stable = after.clone();
    assert!(
        conditions::patch(
            &mut after,
            &Edit::WalkingLocation {
                map: 0,
                slot: 13,
                x: 3,
                y: 7
            }
        )
        .is_err()
    );
    assert_eq!(stable, after);
    for edit in [
        Edit::WalkingChance {
            id: 100,
            chance: 10,
        },
        Edit::WalkingChance { id: 13, chance: -1 },
        Edit::WalkingLocation {
            map: usize::MAX,
            slot: 0,
            x: 0,
            y: 0,
        },
        Edit::WalkingLocation {
            map: 0,
            slot: 100,
            x: 0,
            y: 0,
        },
    ] {
        assert!(conditions::patch(&mut after, &edit).is_err());
        assert_eq!(stable, after);
    }
    for (family, field, index, offset, width, value) in [
        (S::Menu, F::ChoiceSelector, 3, 99, 1, 2),
        (S::Typed, F::PhysicalSelector, 0, 96, 1, 3),
        (S::Typed, F::RequiredAction, 7, 105, 1, 1),
        (S::Typed, F::SpellCriterion, 9, 124, 2, 123),
        (S::Typed, F::SpellSelector, 9, 135, 1, 4),
        (S::Typed, F::ItemCriterion, 4, 144, 2, 456),
        (S::Typed, F::ItemSelector, 4, 150, 1, 1),
    ] {
        let mut next = before.clone();
        conditions::patch(
            &mut next,
            &Edit::EncounterCondition {
                family,
                id: 1,
                field,
                index,
                value,
            },
        )?;
        let at = family.stride() + offset;
        unchanged_except(&before, &next, family.path(), at..at + width);
        if width == 2 {
            assert_eq!(&next[family.path()][at..at + 2], &value.to_be_bytes());
        } else {
            assert_eq!(next[family.path()][at], value as u8);
        }
    }
    let mut invalid = before.clone();
    assert!(
        conditions::patch(
            &mut invalid,
            &Edit::EncounterCondition {
                family: S::Typed,
                id: 0,
                field: F::SpellSelector,
                index: 0,
                value: 1
            }
        )
        .is_err()
    );
    assert_eq!(invalid, before);
    let m = centurions_format::scripts::map_triggers(&before, 0);
    assert_eq!(m["triggers"][0]["active"], false);
    assert_eq!(m["triggers"][1]["shadowed"], true);
    assert_eq!(m["triggers"][1]["active"], false);
    Ok(())
}
fn call(s: &mut Session, op: Value) -> Value {
    s.handle(
        serde_json::from_value::<Request>(json!({"protocol":1,"id":1,"operation":op})).unwrap(),
    )
}
#[test]
fn atomic_placement_history_and_condition_reopen() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let source = t.path().join("source");
    fs::create_dir(&source).unwrap();
    for (n, b) in fixture() {
        fs::write(source.join(n), b).unwrap();
    }
    let imported = t.path().join("imported");
    store::import(&source, &imported)?;
    let mut s = Session::new(t.path().join("cache"));
    assert_eq!(
        call(&mut s, json!({"op":"open","path":imported}))["ok"],
        true
    );
    let edits = json!([{"kind":"walking_location","map":0,"slot":13,"x":17,"y":29},{"kind":"walking_chance","id":13,"chance":75},{"kind":"encounter_condition","family":"typed","id":1,"field":"physical_selector","index":0,"value":2}]);
    assert_eq!(
        call(
            &mut s,
            json!({"op":"apply","expected_revision":1,"edits":edits})
        )["revision"],
        2
    );
    assert_eq!(
        call(&mut s, json!({"op":"undo","expected_revision":2}))["revision"],
        3
    );
    assert_eq!(
        call(&mut s, json!({"op":"redo","expected_revision":3}))["revision"],
        4
    );
    let saved = t.path().join("saved");
    assert_eq!(
        call(
            &mut s,
            json!({"op":"save_as","expected_revision":4,"destination":saved})
        )["ok"],
        true
    );
    assert_eq!(call(&mut s, json!({"op":"open","path":saved}))["ok"], true);
    let r = call(
        &mut s,
        json!({"op":"program","family":"walking","id":13,"branch":0}),
    );
    assert_eq!(r["result"]["location_key"], 2917);
    assert_eq!(r["result"]["chance"], 75);
    Ok(())
}
#[test]
fn combat_view_uses_native_signed_population_axis_and_retains_all_bytes() -> Result<()> {
    let mut f = Files::new();
    let mut bd = vec![0x5a; 1372 + 3];
    bd[..1352].fill(0);
    bd[(3 * 26 + 7) * 2..(3 * 26 + 7) * 2 + 2].copy_from_slice(&(-1i16).to_be_bytes());
    f.insert("Data BD".into(), bd);
    let mut md = vec![0; 288 * 2 + 7];
    md[288 + 218] = 4;
    md[288 + 219..288 + 223].copy_from_slice(b"Test");
    f.insert("Data MD".into(), md);
    let before = f.clone();
    let b = combat_view::record(&f, false, 0)?;
    assert_eq!(b["actors"][0]["x"], 3);
    assert_eq!(b["actors"][0]["y"], 7);
    assert_eq!(b["actors"][0]["monster"], -1);
    assert_eq!(b["actors"][0]["name"], "Test");
    assert_eq!(combat_view::catalogue(&f, true, 0, "test")?["total"], 1);
    assert!(combat_view::record(&f, true, usize::MAX).is_err());
    assert_eq!(f, before);
    Ok(())
}
