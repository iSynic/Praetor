use centurions_format::{Edit, Files, regions};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    f.insert("Data RD".into(), vec![0x5a; 644 + 9]);
    f
}

fn edit(slot: usize, last_x: i16) -> Edit {
    Edit::Region {
        map: 0,
        slot,
        first_y: 1,
        first_x: 2,
        last_y: 9,
        last_x,
        encounter_chance: 400,
        battle_min: 3,
        battle_max: 5,
        scripts: [28, 0, 7],
        script_chances: [100, 0, -50],
        exclusive: true,
        avoid_chance: 25,
        avoid_sound: 82,
        avoid_dialogue: -12,
    }
}

#[test]
fn a_region_edit_owns_only_its_own_bytes_and_reads_back() {
    let before = fixture();
    let mut after = before.clone();
    regions::patch(&mut after, &edit(4, 10)).unwrap();
    let (a, b) = (&before["Data RD"], &after["Data RD"]);
    let owned = |at: usize| {
        let slot = 4;
        (slot * 8..slot * 8 + 8).contains(&at)
            || (160 + slot * 2..162 + slot * 2).contains(&at)
            || (200 + slot * 4..204 + slot * 4).contains(&at)
            || (280 + slot * 6..286 + slot * 6).contains(&at)
            || (400 + slot * 6..406 + slot * 6).contains(&at)
            || at == 524 + slot
            || at == 544 + slot
            || (564 + slot * 2..566 + slot * 2).contains(&at)
            || (604 + slot * 2..606 + slot * 2).contains(&at)
    };
    for at in 0..a.len() {
        assert!(
            a[at] == b[at] || owned(at),
            "byte {at} changed outside the region"
        );
    }
    let map = centurions_format::scripts::map_triggers(&after, 0);
    let region = map["regions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["slot"] == 4)
        .unwrap();
    assert_eq!(
        (region["slot"].as_u64(), region["last_x"].as_i64()),
        (Some(4), Some(10))
    );
    assert_eq!(region["scripts"], json_array([28, 0, 7]));
    assert_eq!(region["script_chances"], json_array([100, 0, -50]));
    assert_eq!(
        (
            region["exclusive"].as_bool(),
            region["avoid_chance"].as_i64()
        ),
        (Some(true), Some(25))
    );
    assert_eq!(region["avoid_dialogue"].as_i64(), Some(-12));
}

fn json_array(values: [i64; 3]) -> serde_json::Value {
    serde_json::json!(values)
}

#[test]
fn a_region_outside_the_map_is_refused_and_an_empty_one_clears_the_slot() {
    let mut files = fixture();
    assert!(regions::patch(&mut files, &edit(0, 90)).is_err());
    assert!(regions::patch(&mut files, &edit(20, 10)).is_err());
    regions::patch(&mut files, &edit(2, 10)).unwrap();
    let Edit::Region { .. } = edit(2, 10) else {
        unreachable!()
    };
    let cleared = Edit::Region {
        map: 0,
        slot: 2,
        first_y: 0,
        first_x: 0,
        last_y: 0,
        last_x: 0,
        encounter_chance: 9,
        battle_min: 9,
        battle_max: 9,
        scripts: [9, 9, 9],
        script_chances: [9, 9, 9],
        exclusive: true,
        avoid_chance: 9,
        avoid_sound: 9,
        avoid_dialogue: 9,
    };
    regions::patch(&mut files, &cleared).unwrap();
    let rd = &files["Data RD"];
    assert!(
        rd[16..24].iter().all(|b| *b == 0) && rd[160 + 4..162 + 4] == [0, 0] && rd[524 + 2] == 0
    );
}

#[test]
fn a_map_look_owns_its_tile_set_and_sight_bytes_and_refuses_a_set_that_quits_the_game() {
    let before = fixture();
    let mut after = before.clone();
    let look = |terrain| Edit::MapLook {
        map: 0,
        terrain,
        limits_sight: true,
        light: 3,
    };
    regions::patch(&mut after, &look(7)).unwrap();
    for at in 0..before["Data RD"].len() {
        assert!(
            before["Data RD"][at] == after["Data RD"][at] || (520..524).contains(&at) && at != 521,
            "byte {at}"
        );
    }
    assert_eq!(&after["Data RD"][520..524], &[7, 0x5a, 3, 1]);
    assert!(
        regions::patch(
            &mut after,
            &Edit::MapLook {
                map: 0,
                terrain: 7,
                limits_sight: false,
                light: 256,
            }
        )
        .is_err()
    );
    for refused in [0, 10, 14, 20] {
        assert!(regions::patch(&mut after, &look(refused)).is_err());
    }
}
