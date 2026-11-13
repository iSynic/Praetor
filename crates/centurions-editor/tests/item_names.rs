use centurions_editor::media;
use centurions_format::Files;
use std::path::Path;

fn put(b: &mut [u8], at: usize, value: u16) {
    b[at..at + 2].copy_from_slice(&value.to_be_bytes());
}

/// A resource fork holding one resource of `kind` and `id`.
fn fork(kind: &[u8; 4], id: u16, payload: &[u8]) -> Vec<u8> {
    let offset = 260 + payload.len();
    let mut b = vec![0; offset];
    b[..4].copy_from_slice(&256u32.to_be_bytes());
    b[4..8].copy_from_slice(&(offset as u32).to_be_bytes());
    b[8..12].copy_from_slice(&((payload.len() + 4) as u32).to_be_bytes());
    b[12..16].copy_from_slice(&50u32.to_be_bytes());
    b[256..260].copy_from_slice(&(payload.len() as u32).to_be_bytes());
    b[260..].copy_from_slice(payload);
    let mut map = vec![0; 50];
    put(&mut map, 24, 28);
    put(&mut map, 26, 0);
    map[30..34].copy_from_slice(kind);
    put(&mut map, 36, 10);
    put(&mut map, 38, id);
    put(&mut map, 40, 0xffff);
    b.extend_from_slice(&map);
    b
}

fn strings(names: &[&str]) -> Vec<u8> {
    let mut p = (names.len() as u16).to_be_bytes().to_vec();
    for name in names {
        p.push(name.len() as u8);
        p.extend_from_slice(name.as_bytes());
    }
    p
}

#[test]
fn the_scenarios_items_are_named_from_its_str_801() {
    let mut files = Files::new();
    files.insert(
        "Scenario.rsrc".into(),
        fork(b"STR#", 801, &strings(&["Rations", "Cargo Pod"])),
    );
    let found = media::item_names(&files, Path::new("")).unwrap();
    let names = found["names"].as_array().unwrap();
    assert_eq!(names.len(), 1000);
    assert_eq!(
        (names[800].as_str(), names[801].as_str()),
        (Some("Rations"), Some("Cargo Pod"))
    );
    assert!(names[802].is_null() && names[0].is_null());
    assert_eq!(
        (found["scenario"].as_bool(), found["stock"].as_bool()),
        (Some(true), Some(false))
    );
}

#[test]
fn a_scenario_without_the_resource_has_no_names() {
    let mut files = Files::new();
    files.insert(
        "Scenario.rsrc".into(),
        fork(b"STR#", 802, &strings(&["Mission"])),
    );
    let found = media::item_names(&files, Path::new("")).unwrap();
    assert_eq!(found["scenario"].as_bool(), Some(false));
    assert!(found["names"][800].is_null());
}
