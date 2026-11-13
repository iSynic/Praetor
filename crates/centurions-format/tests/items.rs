use centurions_format::{Edit, Files, items, items::ItemField};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data NI".into(), vec![0; 150 * 3]);
    f.insert("Data NI Des".into(), vec![0; 256 * 3]);
    f
}

fn field(index: usize, field: ItemField, slot: usize, value: i32) -> Edit {
    Edit::ItemField {
        index,
        field,
        slot,
        value,
    }
}

#[test]
fn an_item_field_owns_only_its_own_bytes_and_reads_back() {
    let before = fixture();
    let mut after = before.clone();
    items::patch(&mut after, &field(1, ItemField::Price, 0, 123456)).unwrap();
    items::patch(&mut after, &field(1, ItemField::Armor, 0, -4)).unwrap();
    items::patch(&mut after, &field(1, ItemField::BaseAccuracy, 0, 9)).unwrap();
    items::patch(&mut after, &field(1, ItemField::ElementalDamage, 3, 12)).unwrap();
    let base = 150;
    let owned: Vec<usize> = (142..146)
        .chain(94..96)
        .chain([81])
        .chain(68..70)
        .map(|at| base + at)
        .collect();
    for at in 0..before["Data NI"].len() {
        assert!(
            before["Data NI"][at] == after["Data NI"][at] || owned.contains(&at),
            "byte {at} changed outside the fields"
        );
    }
    let shown = items::view(&after, 1).unwrap();
    let find = |name: &str, slot: u64| {
        shown["fields"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["field"] == name && f["index"] == slot)
            .unwrap()["value"]
            .as_i64()
            .unwrap()
    };
    assert_eq!(
        (
            find("price", 0),
            find("armor", 0),
            find("base_accuracy", 0),
            find("elemental_damage", 3)
        ),
        (123456, -4, 9, 12)
    );
    assert_eq!(shown["id"], 801);
}

#[test]
fn a_description_keeps_its_unused_tail_and_a_bad_value_is_refused() {
    let mut files = fixture();
    items::patch(
        &mut files,
        &Edit::ItemDescription {
            index: 2,
            text: "Mmm! Meal.".into(),
        },
    )
    .unwrap();
    assert_eq!(items::view(&files, 2).unwrap()["description"], "Mmm! Meal.");
    assert!(
        items::patch(
            &mut files,
            &Edit::ItemDescription {
                index: 0,
                text: "x".repeat(256)
            }
        )
        .is_err()
    );
    assert!(items::patch(&mut files, &field(0, ItemField::ShieldChance, 0, 40000)).is_err());
    assert!(items::patch(&mut files, &field(0, ItemField::ElementalDamage, 7, 1)).is_err());
    assert!(items::patch(&mut files, &field(3, ItemField::Armor, 0, 1)).is_err());
    assert_eq!(items::catalogue(&files).as_array().unwrap().len(), 3);
}
