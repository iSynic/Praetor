use centurions_editor::vault;
use centurions_format::monsters::ROW;
use centurions_format::resource_fork::Fork;
use centurions_format::resources::hex;
use centurions_format::{Edit, Files};
use std::path::Path;

/// A scenario with two monsters (rows of 288 bytes whose names are "Alpha" and "Beta") and descriptions for them.
fn scenario(held: Option<(i16, &[u8])>) -> Files {
    let mut files = Files::new();
    let mut table = vec![0u8; ROW * 2];
    for (n, name) in ["Alpha", "Beta"].iter().enumerate() {
        let row = &mut table[n * ROW..(n + 1) * ROW];
        row[218] = name.len() as u8;
        row[219..219 + name.len()].copy_from_slice(name.as_bytes());
        row[0x50..0x52].copy_from_slice(&3017i16.to_be_bytes());
    }
    files.insert("Data MD".into(), table);
    let mut words = vec![0u8; 256 * 2];
    words[0] = 4;
    words[1..5].copy_from_slice(b"Evil");
    files.insert("Data DES".into(), words);
    if let Some((id, data)) = held {
        let mut fork = Fork::empty();
        fork.set(b"cicn", id, Some(data.to_vec()));
        let bytes = fork.write().unwrap();
        files.insert("Scenario.rsrc".into(), bytes);
    }
    files
}

#[test]
fn the_vault_keeps_monsters_once_and_a_copy_carries_the_icon_to_a_free_number() {
    let folder = tempfile::tempdir().unwrap();
    let dir = folder.path().join("vault");
    let source = scenario(Some((3017, b"picture of the icon")));
    // The scenario's own icon travels with the monster; adding again, or adding an empty row, adds nothing.
    let added = vault::add(&dir, &source, Path::new(""), &[0, 1, 0], "Source").unwrap();
    assert_eq!(
        (added["added"].as_u64(), added["skipped"].as_u64()),
        (Some(2), Some(1))
    );
    let listed = vault::list(&dir, &source, Path::new(""), folder.path()).unwrap();
    assert_eq!(listed["count"], 2);
    assert_eq!(listed["entries"][0]["name"], "Alpha");
    assert_eq!(listed["entries"][0]["source"], "Source · monster 0");
    assert_eq!(listed["entries"][0]["in_scenario"], true);
    assert_eq!(listed["entries"][0]["icon_travels"], true);
    let keys: Vec<String> = listed["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["key"].as_str().unwrap().to_string())
        .collect();
    let entries = vault::entries(&dir, &keys, Path::new("")).unwrap();

    // A scenario without the icon gets it at its own number.
    let bare = scenario(None);
    let edits = vault::copy_edits(&entries, 2, &bare, Path::new("")).unwrap();
    let pictures: Vec<_> = edits
        .iter()
        .filter(|e| matches!(e, Edit::ResourceChange { .. }))
        .collect();
    assert_eq!(
        pictures.len(),
        1,
        "both monsters carry the same icon, which is imported once"
    );
    assert!(matches!(pictures[0], Edit::ResourceChange { id: 3017, .. }));
    let imports: Vec<_> = edits
        .iter()
        .filter_map(|e| match e {
            Edit::MonsterImport { id, .. } => Some(*id),
            _ => None,
        })
        .collect();
    assert_eq!(imports, vec![2, 3]);

    // A scenario that holds the same picture imports nothing; one that holds another picture under the number
    // moves the icon to the next free number and the monster names it.
    let same = scenario(Some((3017, b"picture of the icon")));
    assert!(
        vault::copy_edits(&entries, 2, &same, Path::new(""))
            .unwrap()
            .iter()
            .all(|e| !matches!(e, Edit::ResourceChange { .. }))
    );
    let other = scenario(Some((3017, b"a different picture")));
    let moved = vault::copy_edits(&entries, 2, &other, Path::new("")).unwrap();
    assert!(
        moved
            .iter()
            .any(|e| matches!(e, Edit::ResourceChange { id: 3018, .. }))
    );
    let Edit::MonsterImport { record, .. } = &moved[1] else {
        panic!("the first monster follows its picture")
    };
    assert_eq!(&record[0x50 * 2..0x52 * 2], hex(&3018i16.to_be_bytes()));

    // Removing takes the entry out.
    assert_eq!(vault::remove(&dir, &keys[..1]).unwrap()["count"], 1);
}

#[test]
fn stock_monsters_come_from_the_installation_and_cannot_be_removed_or_added_twice() {
    let folder = tempfile::tempdir().unwrap();
    let installation = folder.path().join("game");
    let level = installation.join("Scenarios").join("The Game").join("0");
    std::fs::create_dir_all(&level).unwrap();
    let files = scenario(None);
    std::fs::write(level.join("Data MD"), &files["Data MD"]).unwrap();
    std::fs::write(level.join("Data DES"), &files["Data DES"]).unwrap();
    let dir = folder.path().join("vault");

    let stock = vault::stock(&installation).unwrap();
    assert_eq!(stock.len(), 2);
    assert!(stock.iter().all(|entry| entry.stock));
    assert_eq!(stock[1].source, "The Game · monster 1");

    // Both monsters are stock already, so adding them from a scenario keeps nothing; the list shows them as stock.
    let added = vault::add(&dir, &files, &installation, &[0, 1], "Mine").unwrap();
    assert_eq!(added["added"], 0);
    let cache = folder.path().join("cache");
    let listed = vault::list(&dir, &files, &installation, &cache).unwrap();
    assert_eq!(listed["count"], 2);
    assert_eq!(listed["entries"][0]["stock"], true);

    // A changed monster is the author's, and it can be removed; a stock one cannot.
    let mut changed = files.clone();
    changed.get_mut("Data MD").unwrap()[8] = 9;
    assert_eq!(
        vault::add(&dir, &changed, &installation, &[0], "Mine").unwrap()["added"],
        1
    );
    let listed = vault::list(&dir, &changed, &installation, &cache).unwrap();
    assert_eq!(listed["count"], 3);
    let key = |n: usize| listed["entries"][n]["key"].as_str().unwrap().to_string();
    assert_eq!(listed["entries"][2]["stock"], false);
    assert!(vault::remove(&dir, &[key(0)]).is_err());
    assert_eq!(vault::remove(&dir, &[key(2)]).unwrap()["count"], 0);
    // Stock monsters copy like any other.
    assert_eq!(
        vault::entries(&dir, &[key(1)], &installation).unwrap()[0].name,
        "Beta"
    );
}
