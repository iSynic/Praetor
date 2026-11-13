use centurions_format::{Edit, Files, monsters, monsters::MonsterField};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data MD".into(), vec![0; 288 * 2 + 3]);
    f
}

fn field(id: usize, field: MonsterField, index: usize, value: i16) -> Edit {
    Edit::MonsterField {
        id,
        field,
        index,
        value,
    }
}

#[test]
fn a_monster_field_edit_owns_only_its_own_bytes_and_reads_back() {
    let before = fixture();
    let mut after = before.clone();
    monsters::patch(&mut after, &field(1, MonsterField::Armor, 0, -7)).unwrap();
    monsters::patch(&mut after, &field(1, MonsterField::Save, 3, -20)).unwrap();
    monsters::patch(&mut after, &field(1, MonsterField::AttackMaximum, 2, 9)).unwrap();
    monsters::patch(&mut after, &field(1, MonsterField::Item, 5, 812)).unwrap();
    let base = 288;
    let owned = [
        base + 8,
        base + 9,
        base + 0x8b + 3,
        base + 0x93 + 2 * 4 + 1,
        base + 0x26 + 10,
        base + 0x26 + 11,
    ];
    for at in 0..before["Data MD"].len() {
        assert!(
            before["Data MD"][at] == after["Data MD"][at] || owned.contains(&at),
            "byte {at} changed outside the fields"
        );
    }
    let shown = monsters::projection(&after["Data MD"][base..base + 288]);
    let find = |name: &str, index: u64| {
        shown
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["field"] == name && row["index"] == index)
            .unwrap()["value"]
            .as_i64()
            .unwrap()
    };
    assert_eq!(
        (
            find("armor", 0),
            find("save", 3),
            find("attack_maximum", 2),
            find("item", 5)
        ),
        (-7, -20, 9, 812)
    );
}

#[test]
fn a_value_the_engine_does_not_accept_is_refused() {
    let mut files = fixture();
    assert!(monsters::patch(&mut files, &field(0, MonsterField::Size, 0, 4)).is_err());
    assert!(monsters::patch(&mut files, &field(0, MonsterField::AttackCount, 0, 6)).is_err());
    assert!(monsters::patch(&mut files, &field(0, MonsterField::Save, 6, 0)).is_err());
    assert!(monsters::patch(&mut files, &field(2, MonsterField::Armor, 0, 1)).is_err());
    // An imported value outside what the engine accepts is kept as it is.
    files.get_mut("Data MD").unwrap()[0x10 + 1] = 9;
    assert!(monsters::patch(&mut files, &field(0, MonsterField::Size, 0, 1)).is_err());
}

#[test]
fn a_description_is_a_pascal_string_in_its_own_slot_and_a_new_monster_takes_a_copy() {
    use centurions_format::{KIND, Origin, Project, RecordFamily, VERSION, authoring, update};
    let mut files = fixture();
    // Two monsters, and a Data DES whose slots hold a description and, past the monsters, leftover bytes.
    let mut descriptions = vec![0xeeu8; 256 * 4];
    descriptions[0] = 5;
    descriptions[1..6].copy_from_slice(b"Zevon");
    files.insert("Data DES".into(), descriptions);
    let project = Project {
        kind: KIND.into(),
        version: VERSION,
        origin: Origin::Imported {
            label: "test".into(),
        },
        files: Default::default(),
        directories: Default::default(),
        edits: vec![],
        allocations: vec![],
        native: None,
    };
    let (project, id) = authoring::allocate(&project, &files, RecordFamily::Monster, 0).unwrap();
    assert_eq!(id, 2, "the table's complete rows decide the new id");
    let edits = vec![Edit::MonsterDescription {
        id: 0,
        text: "A hostile race".into(),
    }];
    let built =
        centurions_format::apply(&update(&project, &files, edits).unwrap(), &files).unwrap();
    assert_eq!(
        monsters::description(&built, 0),
        ("A hostile race".to_string(), 14)
    );
    // The copy is of the imported seed, as the row's other fields are: a description edit of the seed does not reach it.
    assert_eq!(monsters::description(&built, id), ("Zevon".to_string(), 5));
    // Bytes after the words are not read, and are not touched.
    assert_eq!(built["Data DES"][256 * 3..], files["Data DES"][256 * 3..]);
    let mut long = files.clone();
    assert!(
        monsters::patch(
            &mut long,
            &Edit::MonsterDescription {
                id: 0,
                text: "x".repeat(256)
            }
        )
        .is_err()
    );
    assert!(
        monsters::patch(
            &mut long,
            &Edit::MonsterDescription {
                id: 9,
                text: "x".into()
            }
        )
        .is_err()
    );
}

#[test]
fn an_imported_monster_replaces_its_whole_row_and_replays_before_the_authors_edits() {
    use centurions_format::{
        KIND, Origin, Project, RecordFamily, VERSION, authoring, resources::hex, update,
    };
    let mut files = fixture();
    files.insert("Data DES".into(), vec![0; 256 * 3]);
    let project = Project {
        kind: KIND.into(),
        version: VERSION,
        origin: Origin::Imported {
            label: "test".into(),
        },
        files: Default::default(),
        directories: Default::default(),
        edits: vec![],
        allocations: vec![],
        native: None,
    };
    let (project, id) = authoring::allocate(&project, &files, RecordFamily::Monster, 0).unwrap();
    let mut row = vec![0x11u8; 288];
    row[218] = 3;
    row[219..222].copy_from_slice(b"Imp");
    let edits = vec![
        Edit::MonsterImport {
            id,
            record: hex(&row),
            description: "From the vault".into(),
        },
        field(id, MonsterField::Armor, 0, -7),
    ];
    let built =
        centurions_format::apply(&update(&project, &files, edits).unwrap(), &files).unwrap();
    let at = id * 288;
    assert_eq!(
        &built["Data MD"][at + 218..at + 222],
        &[3, b'I', b'm', b'p']
    );
    assert_eq!(
        built["Data MD"][at + 8..at + 10],
        (-7i16).to_be_bytes(),
        "the author's edit follows the import"
    );
    assert_eq!(
        monsters::description(&built, id),
        ("From the vault".to_string(), 14)
    );
    assert!(
        monsters::patch(
            &mut files,
            &Edit::MonsterImport {
                id: 0,
                record: "00".into(),
                description: String::new()
            }
        )
        .is_err()
    );
}
