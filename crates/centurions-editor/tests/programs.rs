use centurions_editor::{
    session::{Request, Session},
    store,
};
use centurions_format::{Files, Result, ScriptFamily, scripts};
use serde_json::{Value, json};
use std::fs;

fn call(s: &mut Session, op: Value) -> Value {
    s.handle(
        serde_json::from_value::<Request>(json!({"protocol":1,"id":1,"operation":op})).unwrap(),
    )
}
fn fixture() -> Files {
    let mut f = Files::new();
    for (path, stride) in [
        ("Data DD", 4200),
        ("Data ED3", 42),
        ("Data ED", 426),
        ("Data ED2", 516),
        ("Data SD2", 256),
        ("Data LD", 64800),
        ("Data RD", 644),
    ] {
        f.insert(path.into(), vec![0; stride * 2 + 3]);
    }
    f.get_mut("Data DD").unwrap()[..4].copy_from_slice(&703i32.to_be_bytes());
    f.get_mut("Data DD").unwrap()[7] = 100;
    f.get_mut("Data DD").unwrap()[8..10].copy_from_slice(&9i16.to_be_bytes());
    f.get_mut("Data DD").unwrap()[10..12].copy_from_slice(&777i16.to_be_bytes());
    let rd = f.get_mut("Data RD").unwrap();
    for (offset, value) in [(0, 5i16), (2, 3), (4, 11), (6, 7)] {
        rd[offset..offset + 2].copy_from_slice(&value.to_be_bytes());
    }
    for name in ["Data ED", "Data ED2"] {
        f.get_mut(name).unwrap()[0] = 0xff;
    }
    f
}

#[test]
fn program_widths_strides_unknown_steps_and_fragments_are_preserved() -> Result<()> {
    let original = fixture();
    for family in [
        ScriptFamily::Walking,
        ScriptFamily::Story,
        ScriptFamily::Menu,
        ScriptFamily::Typed,
    ] {
        let mut f = original.clone();
        let path = family.path();
        let stride = family.stride();
        let branch = if stride > 42 { 3 } else { 0 };
        let slot = 6;
        scripts::patch(&mut f, family, 1, branch, slot, 9, 32767)?;
        let (op, arg, width) = if stride == 42 {
            (
                stride + 8 + slot as usize * 2,
                stride + 24 + slot as usize * 2,
                2,
            )
        } else {
            (
                stride + 24 + slot as usize,
                stride + 80 + slot as usize * 2,
                1,
            )
        };
        for (name, bytes) in &f {
            for (at, byte) in bytes.iter().enumerate() {
                if name != path || !(op..op + width).contains(&at) && !(arg..arg + 2).contains(&at)
                {
                    assert_eq!(*byte, original[name][at], "{name} byte {at}");
                }
            }
        }
        let p = scripts::program(&f, family, 1, branch)?;
        assert_eq!(p["steps"][6]["opcode"], 9);
        assert_eq!(p["steps"][6]["operand"], 32767);
        assert!(scripts::patch(&mut f, family, usize::MAX, 0, 0, 1, 0).is_err());
        assert!(scripts::patch(&mut f, family, 0, 0, 8, 1, 0).is_err());
    }
    let mut f = original.clone();
    for (family, slot) in [
        (ScriptFamily::Walking, 1),
        (ScriptFamily::Menu, 0),
        (ScriptFamily::Typed, 0),
    ] {
        // A step whose number names no code does nothing in the game; it can be written over.
        let mut written = original.clone();
        scripts::patch(&mut written, family, 0, 0, slot, 1, 0)?;
    }
    for (op, arg) in [(1, 2), (4, 2), (5, -1), (39, 2), (110, 0)] {
        assert!(scripts::patch(&mut f, ScriptFamily::Story, 0, 0, 0, op, arg).is_err());
    }
    assert_eq!(f, original);
    let map = scripts::map_triggers(&f, 0);
    assert_eq!(map["triggers"][0]["x"], 3);
    assert_eq!(map["triggers"][0]["y"], 7);
    assert_eq!(map["regions"][0]["first_x"], 3);
    assert_eq!(map["regions"][0]["last_y"], 11);
    Ok(())
}

#[test]
fn program_batches_revision_undo_save_and_v2_reopen() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let source = t.path().join("source");
    fs::create_dir(&source).unwrap();
    for (name, b) in fixture() {
        fs::write(source.join(name), b).unwrap();
    }
    let checkpoint = t.path().join("import");
    store::import(&source, &checkpoint)?;
    let manifest = checkpoint.join("project.json");
    let mut v: Value = serde_json::from_slice(&fs::read(&manifest).unwrap()).unwrap();
    v["version"] = json!(2);
    fs::write(&manifest, serde_json::to_vec(&v).unwrap()).unwrap();
    let original = fs::read(&manifest).unwrap();
    let mut s = Session::new(t.path().join("cache"));
    assert_eq!(
        call(&mut s, json!({"op":"open","path":checkpoint}))["ok"],
        true
    );
    let edit = json!({"kind":"script_step","family":"typed","id":1,"branch":3,"slot":6,"opcode":9,"operand":5});
    let r = call(
        &mut s,
        json!({"op":"apply","expected_revision":1,"edits":[edit,{"kind":"script_step","family":"walking","id":0,"branch":0,"slot":1,"opcode":14,"operand":0}]}),
    );
    assert_eq!(r["ok"], false);
    assert_eq!(r["revision"], 1);
    assert_eq!(
        call(
            &mut s,
            json!({"op":"apply","expected_revision":1,"edits":[edit]})
        )["revision"],
        2
    );
    assert_eq!(
        call(
            &mut s,
            json!({"op":"apply","expected_revision":1,"edits":[edit]})
        )["ok"],
        false
    );
    assert_eq!(
        call(&mut s, json!({"op":"undo","expected_revision":2}))["revision"],
        3
    );
    assert_eq!(
        call(
            &mut s,
            json!({"op":"program","family":"typed","id":1,"branch":3})
        )["result"]["steps"][6]["opcode"],
        0
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
    let (p, f) = store::open(&saved)?;
    assert_eq!(p.version, centurions_format::VERSION);
    let f = centurions_format::apply(&p, &f)?;
    assert_eq!(f["Data ED2"][516 + 24 + 6], 9);
    assert_eq!(fs::read(manifest).unwrap(), original);
    Ok(())
}

#[test]
fn cleanup_story_export_reimport_preserves_unknown_pairs_and_rejected_batches() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let source = t.path().join("source");
    fs::create_dir(&source).unwrap();
    let mut original = fixture();
    let stories = original.get_mut("Data ED3").unwrap();
    stories[..8].fill(0xa7);
    stories[12..14].copy_from_slice(&900i16.to_be_bytes());
    stories[28..30].copy_from_slice(&35i16.to_be_bytes());
    stories[50..52].copy_from_slice(&100i16.to_be_bytes());
    stories[66..68].copy_from_slice(&1i16.to_be_bytes());
    stories[84..].copy_from_slice(&[0x91, 0x92, 0x93]);
    original.insert("Data ED3.rsrc".into(), vec![0xff, 0x81, 0]);
    for (name, bytes) in &original {
        fs::write(source.join(name), bytes).unwrap();
    }
    let checkpoint = t.path().join("imported");
    store::import(&source, &checkpoint)?;
    let manifest = fs::read(checkpoint.join("project.json")).unwrap();
    let mut s = Session::new(t.path().join("cache"));
    assert_eq!(
        call(&mut s, json!({"op":"open","path":checkpoint}))["revision"],
        1
    );
    let allocation = call(
        &mut s,
        json!({"op":"allocate_record","expected_revision":1,"family":"story","seed":0}),
    );
    assert_eq!(allocation["ok"], true, "{allocation}");
    assert_eq!(allocation["result"]["id"], 2);
    let before = call(
        &mut s,
        json!({"op":"program","family":"story","id":2,"branch":0}),
    )["result"]
        .clone();
    let cleanup = json!({"kind":"script_step","family":"story","id":2,"branch":0,"slot":0,"opcode":100,"operand":0});
    for operand in [i16::MIN, -1, 2, i16::MAX] {
        let rejected = call(
            &mut s,
            json!({"op":"apply","expected_revision":2,"edits":[cleanup,{"kind":"script_step","family":"story","id":2,"branch":0,"slot":1,"opcode":100,"operand":operand}]}),
        );
        assert_eq!(rejected["ok"], false);
        assert_eq!(rejected["revision"], 2);
        assert!(
            rejected["error"]["message"]
                .as_str()
                .unwrap()
                .contains("one of")
        );
        assert_eq!(
            call(
                &mut s,
                json!({"op":"program","family":"story","id":2,"branch":0})
            )["result"],
            before
        );
    }
    // End combat with kind 1 is a code the editor writes; kind 2 is not one the game handles.
    let kind_one = call(
        &mut s,
        json!({"op":"program","family":"story","id":1,"branch":0}),
    );
    assert_eq!(kind_one["result"]["steps"][0]["authorable"], true);
    {
        let (id, slot) = (0, 2);
        let program = call(
            &mut s,
            json!({"op":"program","family":"story","id":id,"branch":0}),
        );
        // The number 900 names no code: the game skips it, and the editor keeps it and may write over it.
        assert_eq!(program["result"]["steps"][slot]["authorable"], true);
        assert_eq!(program["result"]["steps"][slot]["opcode"], 900);
        let rejected = call(
            &mut s,
            json!({"op":"apply","expected_revision":2,"edits":[{"kind":"script_step","family":"story","id":id,"branch":0,"slot":slot,"opcode":100,"operand":2}]}),
        );
        assert_eq!(rejected["ok"], false);
        assert_eq!(rejected["revision"], 2);
    }
    let applied = call(
        &mut s,
        json!({"op":"apply","expected_revision":2,"edits":[cleanup,{"kind":"script_step","family":"story","id":2,"branch":0,"slot":1,"opcode":24,"operand":0}]}),
    );
    assert_eq!(applied["ok"], true, "{applied}");
    assert_eq!(applied["revision"], 3);
    assert_eq!(applied["result"]["diagnostics"], json!([]));
    let saved = t.path().join("saved");
    assert_eq!(
        call(
            &mut s,
            json!({"op":"save_as","expected_revision":3,"destination":saved})
        )["revision"],
        4
    );
    let exported = t.path().join("exported");
    let result = call(
        &mut s,
        json!({"op":"export","expected_revision":4,"destination":exported}),
    );
    assert_eq!(result["ok"], true, "{result}");
    let reimported = t.path().join("reimported");
    store::import(&exported, &reimported)?;
    let (project, files) = store::open(&reimported)?;
    let actual = centurions_format::apply(&project, &files)?;
    let mut expected = original.clone();
    let mut row = original["Data ED3"][..42].to_vec();
    row[8..40].fill(0);
    row[8..10].copy_from_slice(&100i16.to_be_bytes());
    row[10..12].copy_from_slice(&24i16.to_be_bytes());
    expected.get_mut("Data ED3").unwrap().splice(84..84, row);
    assert_eq!(actual, expected);
    assert_eq!(fs::read(checkpoint.join("project.json")).unwrap(), manifest);
    assert_eq!(store::open(&checkpoint)?.1, original);
    Ok(())
}

#[test]
fn program_bytes_name_every_byte_of_the_row_once() -> Result<()> {
    let files = fixture();
    for (family, stride) in [
        (ScriptFamily::Walking, 42),
        (ScriptFamily::Story, 42),
        (ScriptFamily::Menu, 426),
        (ScriptFamily::Typed, 516),
    ] {
        let row = scripts::program_bytes(&files, family, 1)?;
        assert_eq!(row["offset"], stride);
        assert_eq!(row["bytes"].as_array().unwrap().len(), stride);
        let mut next = 0;
        for span in row["spans"].as_array().unwrap() {
            assert_eq!(
                span["from"], next,
                "{family:?} spans must follow each other"
            );
            next = span["to"].as_u64().unwrap() + 1;
        }
        assert_eq!(
            next as usize, stride,
            "{family:?} spans must end with the row"
        );
    }
    assert!(scripts::program_bytes(&files, ScriptFamily::Story, 5).is_err());
    let key = scripts::program_bytes(&files, ScriptFamily::Walking, 0)?;
    assert_eq!(key["spans"][0]["label"], "Key 703 · map 0, y 7, x 3 (i32)");
    Ok(())
}
