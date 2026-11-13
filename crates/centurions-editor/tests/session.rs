use centurions_editor::{
    session::{Request, Session},
    store,
};
use centurions_format::{Edit, Result};
use serde_json::{Value, json};
use std::{fs, path::Path};

fn call(s: &mut Session, operation: Value) -> Value {
    let request: Request =
        serde_json::from_value(json!({"protocol":1,"id":1,"operation":operation})).unwrap();
    s.handle(request)
}

fn fixture(root: &Path) -> Result<()> {
    fs::create_dir(root).unwrap();
    let mut cs = vec![0u8; 316];
    cs[12..16].copy_from_slice(&2i32.to_be_bytes());
    cs[16..20].copy_from_slice(&3i32.to_be_bytes());
    for (n, b) in [
        ("Data CS", cs),
        ("Data LD", vec![0x82; 64800]),
        ("Data SD2", vec![0x44; 515]),
        ("Data Mission", vec![0x43; 929]),
        ("Data ED3", vec![0x42; 85]),
        ("unknown", vec![0xff; 19]),
    ] {
        fs::write(root.join(n), b).unwrap();
    }
    fs::create_dir(root.join("empty")).unwrap();
    Ok(())
}

#[test]
fn revisions_history_checkpoints_and_rejections_preserve_bytes() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let source = t.path().join("source");
    fixture(&source)?;
    let project = t.path().join("project");
    store::import(&source, &project)?;
    let manifest = fs::read(project.join("project.json")).unwrap();
    let mut s = Session::new(t.path().join("cache"));
    assert_eq!(
        call(&mut s, json!({"op":"open","path":project}))["revision"],
        1
    );
    let edits = json!([{"kind":"message","id":0,"text":"Café\nPatrol"},
        {"kind":"floor","map":0,"x":3,"y":7,"tile":17},
        {"kind":"floor","map":0,"x":4,"y":7,"tile":18}]);
    let r = call(
        &mut s,
        json!({"op":"apply","expected_revision":1,"edits":edits}),
    );
    assert_eq!(r["ok"], true, "{r}");
    assert_eq!(r["revision"], 2);
    assert_eq!(r["result"]["dirty"], true);
    for operation in [
        json!({"op":"apply","expected_revision":1,"edits":[]}),
        json!({"op":"apply","expected_revision":2,"edits":[{"kind":"floor","map":0,"x":90,"y":7,"tile":1}]}),
        json!({"op":"apply","expected_revision":2,"edits":[{"kind":"message","id":0,"text":"😀"}]}),
        json!({"op":"apply","expected_revision":2,"edits":[{"kind":"disable_schedule"}]}),
    ] {
        let r = call(&mut s, operation);
        assert_eq!(r["ok"], false);
        assert_eq!(r["revision"], 2);
    }
    let r = call(&mut s, json!({"op":"undo","expected_revision":2}));
    assert_eq!(r["revision"], 3);
    assert_eq!(r["result"]["dirty"], false);
    let m = call(&mut s, json!({"op":"map","id":0}));
    assert_eq!(m["result"]["floor"][3 * 90 + 7], -32126);
    assert_eq!(
        call(&mut s, json!({"op":"redo","expected_revision":3}))["revision"],
        4
    );
    let checkpoint = t.path().join("checkpoint");
    assert_eq!(
        call(
            &mut s,
            json!({"op":"save_as","expected_revision":4,"destination":checkpoint})
        )["revision"],
        5
    );
    let failed = call(
        &mut s,
        json!({"op":"save_as","expected_revision":5,"destination":checkpoint}),
    );
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["revision"], 5);
    let output = t.path().join("export");
    assert_eq!(
        call(
            &mut s,
            json!({"op":"export","expected_revision":5,"destination":output})
        )["ok"],
        true
    );
    let (p, f) = store::open(&project)?;
    let expected = centurions_format::apply(
        &centurions_format::update(&p, &f, serde_json::from_value::<Vec<Edit>>(edits).unwrap())?,
        &f,
    )?;
    for (n, b) in expected {
        assert_eq!(fs::read(output.join(n)).unwrap(), b);
    }
    assert!(output.join("empty").is_dir());
    assert_eq!(fs::read(project.join("project.json")).unwrap(), manifest);
    assert_eq!(
        call(&mut s, json!({"op":"open","path":checkpoint}))["result"]["dirty"],
        false
    );
    assert_eq!(
        call(&mut s, json!({"op":"message","id":0}))["result"]["text"],
        "Café\nPatrol"
    );
    Ok(())
}

#[test]
fn protocol_rejects_unknown_fields_and_bad_pages() {
    assert!(serde_json::from_value::<Request>(json!({"protocol":1,"id":1,"operation":{"op":"apply","expected_revision":0,"edits":[],"raw":"00"}})).is_err());
    let mut s = Session::new("unused".into());
    assert_eq!(
        call(
            &mut s,
            json!({"op":"messages","offset":0,"limit":1000000,"query":""})
        )["ok"],
        false
    );
    assert_eq!(
        call(&mut s, json!({"op":"text_check","text":"😀"}))["result"]["valid"],
        false
    );
}

#[test]
fn opened_and_saved_projects_are_remembered_with_what_the_project_page_shows() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let source = t.path().join("source");
    fixture(&source)?;
    let project = t.path().join("project");
    store::import(&source, &project)?;
    let settings = t.path().join("settings.json");
    let mut s = Session::with_preferences(t.path().join("cache"), settings.clone());
    let opened = call(&mut s, json!({"op":"open","path":project}));
    assert_eq!(opened["result"]["contents"]["maps"], 1);
    assert_eq!(opened["result"]["contents"]["messages"], 2);
    assert_eq!(opened["result"]["edits"], 0);
    let edits = json!([{"kind":"message","id":0,"text":"Patrol"}]);
    call(
        &mut s,
        json!({"op":"apply","expected_revision":1,"edits":edits}),
    );
    let saved = t.path().join("saved");
    let reply = call(
        &mut s,
        json!({"op":"save_as","expected_revision":2,"destination":saved}),
    );
    assert_eq!(reply["result"]["edit_kinds"]["message"], 1, "{reply}");
    let described = call(&mut s, json!({"op":"describe"}));
    let recent = described["result"]["preferences"]["recent"]
        .as_array()
        .unwrap();
    let order: Vec<_> = recent
        .iter()
        .map(|entry| {
            (
                entry["path"].as_str().unwrap().ends_with("saved"),
                entry["edits"].as_u64().unwrap(),
            )
        })
        .collect();
    assert_eq!(order, [(true, 1), (false, 0)]);
    assert!(
        !recent[0]["path"].as_str().unwrap().starts_with(r"\?\"),
        "the recent list names folders the way the author does"
    );
    assert_eq!(recent[0]["contents"]["messages"], 2);
    Ok(())
}
