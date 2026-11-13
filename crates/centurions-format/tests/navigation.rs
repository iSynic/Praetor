use centurions_format::{Files, Project, ScriptFamily as S, navigation};
use serde_json::json;

fn put(files: &mut Files, file: &str, at: usize, value: i16) {
    files.get_mut(file).unwrap()[at..at + 2].copy_from_slice(&value.to_be_bytes());
}

fn story_step(files: &mut Files, id: usize, slot: usize, op: i16, operand: i16) {
    put(files, "Data ED3", id * 42 + 8 + slot * 2, op);
    put(files, "Data ED3", id * 42 + 24 + slot * 2, operand);
}

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data ED3".into(), vec![0; 42 * 3]);
    f.insert("Data SD2".into(), vec![0; 256 * 3]);
    f.insert("Data MD".into(), vec![0; 288 * 3]);
    story_step(&mut f, 0, 0, 1, 2);
    story_step(&mut f, 0, 1, 39, 1);
    story_step(&mut f, 1, 0, 10, 4);
    story_step(&mut f, 1, 1, 110, -2);
    story_step(&mut f, 1, 2, 9, -5);
    story_step(&mut f, 1, 3, 900, 0);
    let text = b"Hello pirate";
    let row = f.get_mut("Data SD2").unwrap();
    row[512] = text.len() as u8;
    row[513..513 + text.len()].copy_from_slice(text);
    let monster = f.get_mut("Data MD").unwrap();
    let name = b"Pirate Brawler";
    monster[288 + 218] = name.len() as u8;
    monster[288 + 219..288 + 219 + name.len()].copy_from_slice(name);
    f
}

fn project() -> Project {
    serde_json::from_value(json!({"kind":"project","version":1,"origin":{"kind":"imported","label":"t"},"files":{},"directories":[],"edits":[]})).unwrap()
}

#[test]
fn uses_name_every_step_and_field_that_points_at_a_record() {
    let files = fixture();
    let story = navigation::uses(&files, "story", 1).unwrap();
    assert_eq!(story["total"], 1);
    assert_eq!(story["rows"][0]["id"], 0);
    assert_eq!(story["rows"][0]["slot"], 1);
    assert_eq!(story["rows"][0]["before"], "Message 2");
    let sound = navigation::uses(&files, "sound", -5).unwrap();
    assert_eq!(sound["rows"][0]["id"], 1);
    assert_eq!(navigation::uses(&files, "message", 2).unwrap()["total"], 1);
    assert_eq!(navigation::uses(&files, "reward", 3).unwrap()["total"], 0);
}

#[test]
fn flow_follows_replacing_stories_and_stops_on_repeats() {
    let mut files = fixture();
    story_step(&mut files, 1, 4, 39, 0);
    let flow = navigation::flow(&files, S::Story, 0).unwrap();
    assert_eq!(flow["records"], 2);
    assert_eq!(flow["edges"].as_array().unwrap().len(), 2);
    assert!(navigation::flow(&files, S::Story, 9).is_err());
}

#[test]
fn search_finds_by_name_text_and_prefixed_id() {
    let files = fixture();
    let found = navigation::search(&files, "pirate", &[], 6).unwrap();
    let total = |family: &str| {
        found["groups"]
            .as_array()
            .unwrap()
            .iter()
            .find(|g| g["family"] == family)
            .unwrap()["total"]
            .as_u64()
            .unwrap()
    };
    assert_eq!((total("monsters"), total("messages")), (1, 1));
    let story = navigation::search(&files, "s1", &["stories".into()], 6).unwrap();
    assert_eq!(story["total"], 1);
}

#[test]
fn problems_count_what_the_editor_preserves_without_editing() {
    let files = fixture();
    let found = navigation::problems(&project(), &files).unwrap();
    assert_eq!(found["steps"]["preserved"], 0);
    assert_eq!(found["steps"]["used"], 6);
    let readonly: Vec<_> = found["findings"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|f| f["severity"] == "readonly")
        .collect();
    assert!(readonly.is_empty());
    let skipped: Vec<_> = found["findings"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|f| {
            f["message"]
                .as_str()
                .is_some_and(|m| m.contains("name no code"))
        })
        .collect();
    assert_eq!(skipped.len(), 1);
    assert_eq!(skipped[0]["count"], 1);
}

#[test]
fn a_search_finds_words_deep_in_a_scrolling_text_and_says_where() {
    use centurions_format::{Files, navigation, resource_fork::Fork};
    let mut fork = Fork::empty();
    let body = format!(
        "{}We would be washing dishes at a diner right now.",
        "Please register. ".repeat(20)
    );
    fork.set(b"TEXT", 2000, Some(body.into_bytes()));
    fork.set(b"TEXT", 2001, Some(b"Nothing of the kind.".to_vec()));
    let mut files = Files::new();
    files.insert("Scenario.rsrc".into(), fork.write().unwrap());
    let found = navigation::search(&files, "diner", &["texts".to_string()], 10).unwrap();
    let group = &found["groups"][0];
    assert_eq!(
        (group["family"].as_str(), group["total"].as_u64()),
        (Some("texts"), Some(1))
    );
    assert_eq!(group["rows"][0]["id"], 2000);
    assert!(
        group["rows"][0]["title"]
            .as_str()
            .unwrap()
            .contains("washing dishes at a diner")
    );
}
