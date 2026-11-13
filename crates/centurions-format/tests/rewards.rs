use centurions_format::{Edit, Files, authoring};

fn fixture() -> Files {
    let mut f = Files::new();
    f.insert("Data TD".into(), vec![0; 88 * 2]);
    f
}

#[test]
fn a_reward_item_owns_its_item_and_level_words_and_a_negative_award_is_a_random_one() {
    let before = fixture();
    let mut after = before.clone();
    authoring::patch(
        &mut after,
        &Edit::RewardItem {
            id: 1,
            slot: 3,
            item: 812,
            level: 2,
        },
    )
    .unwrap();
    for at in 0..before["Data TD"].len() {
        let owned = [88 + 6, 88 + 7, 88 + 46, 88 + 47].contains(&at);
        assert!(
            before["Data TD"][at] == after["Data TD"][at] || owned,
            "byte {at}"
        );
    }
    authoring::patch(
        &mut after,
        &Edit::Reward {
            id: 1,
            credits: -500,
            experience: 40_000,
        },
    )
    .unwrap();
    assert_eq!(
        &after["Data TD"][88 + 84..88 + 88],
        &(-500i32).to_be_bytes()
    );
    for refused in [
        Edit::RewardItem {
            id: 1,
            slot: 20,
            item: 1,
            level: 0,
        },
        Edit::RewardItem {
            id: 1,
            slot: 0,
            item: 1000,
            level: 0,
        },
        Edit::Reward {
            id: 1,
            credits: -32768,
            experience: 0,
        },
    ] {
        assert!(authoring::patch(&mut after, &refused).is_err());
    }
}
