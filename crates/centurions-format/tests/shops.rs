use centurions_format::{Edit, Files, shops};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data SD".into(), vec![0; 3002 * 2 + 5]);
    f
}

fn stock(shop: usize, slot: usize, item: i16, quantity: i16) -> Edit {
    Edit::ShopStock {
        shop,
        slot,
        item,
        quantity,
    }
}

#[test]
fn a_shop_edit_owns_only_its_slot_or_its_price_and_reads_back() {
    let before = fixture();
    let mut after = before.clone();
    shops::patch(&mut after, &stock(1, 7, 812, 3)).unwrap();
    shops::patch(
        &mut after,
        &Edit::ShopPrice {
            shop: 1,
            percent: 120,
        },
    )
    .unwrap();
    let base = 3002;
    for at in 0..before["Data SD"].len() {
        let owned = [base + 14, base + 15, base + 2007, base + 3000, base + 3001].contains(&at);
        assert!(
            before["Data SD"][at] == after["Data SD"][at] || owned,
            "byte {at} changed outside the slot"
        );
    }
    let view = shops::view(&after, 1).unwrap();
    assert_eq!(view["price_percent"], 120);
    assert_eq!(view["stock"][0]["item"], 812);
    assert_eq!(view["stock"][0]["quantity"], 3);
    assert_eq!(
        shops::view(&after, 0).unwrap()["stock"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
}

#[test]
fn a_slot_is_stocked_by_its_quantity_and_the_edit_stays_inside_the_record() {
    let mut files = fixture();
    shops::patch(&mut files, &stock(0, 4, 77, 1)).unwrap();
    shops::patch(&mut files, &stock(0, 4, 77, 0)).unwrap();
    assert_eq!(
        &files["Data SD"][8..10],
        &[0, 0],
        "an emptied slot keeps no item id"
    );
    assert!(shops::patch(&mut files, &stock(0, 0, 0, 1)).is_err());
    assert!(shops::patch(&mut files, &stock(0, 0, -5, 1)).is_err());
    assert_eq!(
        shops::view(&files, 0).unwrap()["stock"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
    assert!(shops::patch(&mut files, &stock(0, 1000, 1, 1)).is_err());
    assert!(shops::patch(&mut files, &stock(0, 0, 1, 256)).is_err());
    assert!(shops::patch(&mut files, &stock(0, 0, 1000, 1)).is_err());
    assert!(shops::patch(&mut files, &stock(2, 0, 1, 1)).is_err());
    shops::patch(
        &mut files,
        &Edit::ShopPrice {
            shop: 0,
            percent: -1,
        },
    )
    .unwrap();
    assert_eq!(shops::view(&files, 0).unwrap()["price_percent"], -1);
}

#[test]
fn a_price_the_percent_scales_past_a_long_integer_is_reported() {
    let mut files = fixture();
    let mut items = vec![0u8; 150];
    items[142..146].copy_from_slice(&900_000_000i32.to_be_bytes());
    files.insert("Data NI".into(), items);
    shops::patch(&mut files, &stock(0, 3, 800, 1)).unwrap();
    assert!(shops::price_overflows(&files).is_empty());
    shops::patch(
        &mut files,
        &Edit::ShopPrice {
            shop: 0,
            percent: 300,
        },
    )
    .unwrap();
    assert_eq!(
        shops::price_overflows(&files),
        vec![(0, 3, 800, 900_000_000)]
    );
}
