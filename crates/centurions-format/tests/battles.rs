use centurions_format::{BattleSettingField as B, Edit, Files, authoring};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data BD".into(), vec![0; 1372 * 2]);
    f.insert("Data SD2".into(), vec![0; 256 * 3]);
    f.insert("Data ED3".into(), vec![0; 42 * 3]);
    f
}

fn set(field: B, index: usize, value: i16) -> Edit {
    Edit::BattleSetting {
        id: 1,
        field,
        index,
        value,
    }
}

#[test]
fn a_battle_setting_owns_only_its_own_bytes_and_a_dangling_or_out_of_grid_value_is_refused() {
    let before = fixture();
    let mut after = before.clone();
    authoring::patch(&mut after, &set(B::BeforeMessage, 0, 2)).unwrap();
    authoring::patch(&mut after, &set(B::RoundScript, 4, 1)).unwrap();
    authoring::patch(&mut after, &set(B::SquadY, 0, 25)).unwrap();
    authoring::patch(&mut after, &set(B::Distance, 0, -3)).unwrap();
    let base = 1372;
    for at in 0..before["Data BD"].len() {
        let owned = [
            base + 1352,
            base + 1353,
            base + 1358,
            base + 1359,
            base + 1368,
            base + 1369,
            base + 1370,
        ]
        .contains(&at);
        assert!(
            before["Data BD"][at] == after["Data BD"][at] || owned,
            "byte {at}"
        );
    }
    assert_eq!(after["Data BD"][base + 1370], 0xfd);
    for refused in [
        set(B::BeforeMessage, 0, 3),
        set(B::RoundScript, 0, 3),
        set(B::RoundScript, 5, 0),
        set(B::SquadX, 0, 26),
    ] {
        assert!(authoring::patch(&mut after, &refused).is_err());
    }
}
