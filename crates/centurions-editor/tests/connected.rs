use centurions_editor::{
    minimal,
    session::{Request, Session},
    store,
};
use centurions_format::{Edit, RecordFamily as R, Result, connected::MissionSpec};
use serde_json::{Value, json};
use std::{fs, path::Path};

#[test]
#[allow(clippy::single_range_in_vec_init)] // Entries are owned byte spans.
fn turn_story_selected_child_preserves_opaque_fields_and_validates_links() -> Result<()> {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("source");
    fixture(&source);
    let imported = temp.path().join("imported");
    store::import(&source, &imported)?;
    let (project, files) = store::open(&imported)?;
    let parent = centurions_format::update(
        &project,
        &files,
        vec![Edit::MonsterStats {
            id: 1,
            name: "Parent".into(),
            level: 1,
            stamina: 20,
            speed: 10,
            movement: 10,
        }],
    )?;
    let before = centurions_format::apply(&parent, &files)?;
    let edits = vec![
        Edit::MonsterTurnStory {
            id: 1,
            chance: -100,
            story: 1,
        },
        Edit::MonsterRetreatThreshold { id: 1, value: 101 },
        Edit::MonsterDeathStory { id: 1, story: 1 },
        Edit::SelectedBattleExtra {
            id: 1,
            minimum: 1,
            maximum: 0,
            sound: 611,
            message: 0,
            treasure: 0,
        },
        Edit::ScriptStep {
            family: centurions_format::ScriptFamily::Story,
            id: 1,
            branch: 0,
            slot: 0,
            opcode: 48,
            operand: 1,
        },
        Edit::ScriptStep {
            family: centurions_format::ScriptFamily::Story,
            id: 1,
            branch: 0,
            slot: 1,
            opcode: 9,
            operand: 612,
        },
    ];
    let next = centurions_format::update(&parent, &files, edits)?;
    let after = centurions_format::apply(&next, &files)?;
    for (name, bytes) in &after {
        let owned = match name.as_str() {
            "Data MD" => vec![288 + 0x44..288 + 0x46, 288 + 0x5c..288 + 0x62],
            "Data EDCD" => vec![10..20],
            "Data ED3" => vec![42 + 8..42 + 12, 42 + 24..42 + 28],
            _ => vec![],
        };
        assert_eq!(
            centurions_format::ownership::inspect(&before[name], bytes, &owned).unowned_changes,
            0,
            "{name}"
        );
    }
    assert_eq!(
        &after["Data MD"][288 + 0x5c..288 + 0x60],
        &[0xff, 0x9c, 0, 1]
    );
    assert_eq!(
        &after["Data MD"][288 + 0x44..288 + 0x46],
        &101i16.to_be_bytes()
    );
    assert_eq!(
        &after["Data MD"][288 + 0x46..288 + 0x48],
        &before["Data MD"][288 + 0x46..288 + 0x48]
    );
    assert_eq!(
        &after["Data MD"][288 + 0x60..288 + 0x62],
        &1i16.to_be_bytes()
    );
    for edit in [
        Edit::MonsterDeathStory { id: 1, story: 2 },
        Edit::MonsterDeathStory { id: 1, story: -1 },
        Edit::MonsterTurnStory {
            id: 1,
            chance: 101,
            story: 1,
        },
        Edit::MonsterTurnStory {
            id: 1,
            chance: 100,
            story: 2,
        },
        Edit::SelectedBattleExtra {
            id: 1,
            minimum: 1,
            maximum: 0,
            sound: 0,
            message: 0,
            treasure: 2,
        },
        Edit::SelectedBattleExtra {
            id: 1,
            minimum: -1,
            maximum: 0,
            sound: 0,
            message: 0,
            treasure: 0,
        },
        Edit::ScriptStep {
            family: centurions_format::ScriptFamily::Story,
            id: 1,
            branch: 0,
            slot: 0,
            opcode: 48,
            operand: -1,
        },
    ] {
        assert!(centurions_format::update(&next, &files, vec![edit]).is_err());
    }
    assert_eq!(centurions_format::apply(&next, &files)?, after);
    let mut inherited = after.clone();
    inherited.get_mut("Data ED3").unwrap()[42 + 24..42 + 26]
        .copy_from_slice(&(-1i16).to_be_bytes());
    let snapshot = inherited.clone();
    let program = centurions_format::scripts::program(
        &inherited,
        centurions_format::ScriptFamily::Story,
        1,
        0,
    )?;
    assert_eq!(program["steps"][0]["authorable"], false);
    assert!(
        centurions_format::scripts::patch(
            &mut inherited,
            centurions_format::ScriptFamily::Story,
            1,
            0,
            0,
            9,
            611,
        )
        .is_err()
    );
    assert_eq!(inherited, snapshot);
    let mut picks = after.clone();
    centurions_format::scripts::patch(
        &mut picks,
        centurions_format::ScriptFamily::Story,
        1,
        0,
        2,
        14,
        6,
    )?;
    assert_eq!(&picks["Data ED3"][42 + 12..42 + 14], &14i16.to_be_bytes());
    assert_eq!(&picks["Data ED3"][42 + 28..42 + 30], &6i16.to_be_bytes());
    {
        let operand = 0i16;
        assert!(
            centurions_format::scripts::patch(
                &mut picks,
                centurions_format::ScriptFamily::Story,
                1,
                0,
                2,
                14,
                operand,
            )
            .is_err()
        );
        let mut imported = picks.clone();
        imported.get_mut("Data ED3").unwrap()[42 + 28..42 + 30]
            .copy_from_slice(&operand.to_be_bytes());
        let before_imported = imported.clone();
        assert_eq!(
            centurions_format::scripts::program(
                &imported,
                centurions_format::ScriptFamily::Story,
                1,
                0,
            )?["steps"][2]["authorable"],
            false
        );
        assert!(
            centurions_format::scripts::patch(
                &mut imported,
                centurions_format::ScriptFamily::Story,
                1,
                0,
                2,
                9,
                611,
            )
            .is_err()
        );
        assert_eq!(imported, before_imported);
    }
    let mut signed = before.clone();
    signed.get_mut("Data EDCD").unwrap()[10..12].copy_from_slice(&(-1i16).to_be_bytes());
    for opcode in [2, 48] {
        let link = Edit::ScriptStep {
            family: centurions_format::ScriptFamily::Story,
            id: 1,
            branch: 0,
            slot: 0,
            opcode,
            operand: 1,
        };
        let linked = centurions_format::update(&parent, &signed, vec![link.clone()])?;
        let linked_files = centurions_format::apply(&linked, &signed)?;
        for (name, bytes) in &linked_files {
            let owned = if name == "Data ED3" {
                vec![42 + 8..42 + 10, 42 + 24..42 + 26]
            } else {
                vec![]
            };
            assert_eq!(
                centurions_format::ownership::inspect(&signed[name], bytes, &owned).unowned_changes,
                0,
                "{name}"
            );
        }
        assert_eq!(linked_files["Data EDCD"], signed["Data EDCD"]);
        for (low, high) in [(-2i16, 0i16), (i16::MIN, 0), (-1, -1), (-1, 1), (1, -1)] {
            let mut invalid = signed.clone();
            let extra = invalid.get_mut("Data EDCD").unwrap();
            extra[10..12].copy_from_slice(&low.to_be_bytes());
            extra[12..14].copy_from_slice(&high.to_be_bytes());
            assert!(centurions_format::update(&parent, &invalid, vec![link.clone()]).is_err());
        }
    }
    let slots = [0, 1101, 1707, 2101, 2302, 2402, 3101, 3707, 4101, 4707];
    let spells = centurions_format::update(
        &parent,
        &files,
        vec![Edit::MonsterSpellSlots { id: 1, slots }],
    )?;
    let spell_files = centurions_format::apply(&spells, &files)?;
    for (name, bytes) in &spell_files {
        let owned = if name == "Data MD" {
            vec![288 + 0x12..288 + 0x26]
        } else {
            vec![]
        };
        assert_eq!(
            centurions_format::ownership::inspect(&before[name], bytes, &owned).unowned_changes,
            0,
            "{name}"
        );
    }
    let expected: Vec<_> = slots.into_iter().flat_map(i16::to_be_bytes).collect();
    assert_eq!(&spell_files["Data MD"][288 + 0x12..288 + 0x26], expected);
    // The original takes a value of 1100 or less as an empty slot.
    for empty in [-1, 1100] {
        let mut empty_slots = slots;
        empty_slots[9] = empty;
        centurions_format::update(
            &spells,
            &files,
            vec![Edit::MonsterSpellSlots {
                id: 1,
                slots: empty_slots,
            }],
        )?;
    }
    for invalid in [1801, 2308, 5101] {
        let mut invalid_slots = slots;
        invalid_slots[9] = invalid;
        assert!(
            centurions_format::update(
                &spells,
                &files,
                vec![Edit::MonsterSpellSlots {
                    id: 1,
                    slots: invalid_slots,
                }],
            )
            .is_err()
        );
    }
    let saved = temp.path().join("spell-project");
    store::save_as(&spells, &files, &imported, &saved)?;
    let (reopened, reopened_files) = store::open(&saved)?;
    assert_eq!(
        centurions_format::apply(&reopened, &reopened_files)?,
        spell_files
    );
    let exported = temp.path().join("spell-export");
    store::export(&saved, &exported)?;
    for (name, bytes) in &spell_files {
        assert_eq!(fs::read(exported.join(name)).unwrap(), *bytes, "{name}");
    }
    Ok(())
}

fn fixture(root: &Path) {
    fs::create_dir(root).unwrap();
    let mut cs = vec![0xa7; 316];
    for (at, v) in [(8, 0i32), (12, 2), (16, 2)] {
        cs[at..at + 4].copy_from_slice(&v.to_be_bytes());
    }
    fs::write(root.join("Template"), &cs).unwrap();
    fs::write(root.join("Template.rsrc"), [4, 5, 6]).unwrap();
    fs::write(root.join("Data CS"), cs).unwrap();
    let mut ld = vec![0; 64800];
    for word in ld[32400..].as_chunks_mut::<4>().0 {
        word.copy_from_slice(&(-1i32).to_be_bytes());
    }
    fs::write(root.join("Data LD"), ld).unwrap();
    let mut dd = vec![0xa7; 4207];
    for row in dd[..4200].as_chunks_mut::<42>().0 {
        row[..4].copy_from_slice(&(-1i32).to_be_bytes());
        row[7..41].fill(0);
    }
    fs::write(root.join("Data DD"), dd).unwrap();
    let mut mission = vec![0xa7; 464 * 20 + 3];
    for row in mission[..464 * 20].as_chunks_mut::<464>().0 {
        row[..7].fill(0);
        row[262..264].fill(0);
    }
    fs::write(root.join("Data Mission"), mission).unwrap();
    fs::write(root.join("Data RD"), vec![0xa7; 647]).unwrap();
    fs::write(root.join("Data TD3"), vec![0; 80]).unwrap();
    fs::write(root.join("Data DES"), vec![0; 256 * 10]).unwrap();
    for family in [
        R::Message,
        R::Choice,
        R::Story,
        R::BattleExtra,
        R::Battle,
        R::Monster,
        R::Reward,
    ] {
        let stride = family.stride();
        let mut b = vec![0xa7; stride * 2 + if family == R::Choice { 24 } else { 3 }];
        for row in b[..stride * 2].chunks_exact_mut(stride) {
            match family {
                R::Message => row[0] = 0,
                R::Choice => {
                    row[..100].fill(0);
                    row[104..106].fill(0);
                    for i in 0..4 {
                        row[106 + i * 80] = 0;
                    }
                }
                R::Story => {
                    row[8..41].fill(0);
                }
                R::BattleExtra => {
                    row.fill(0);
                    row[1] = 1;
                }
                R::Battle => {
                    row[..1356].fill(0);
                    row[1] = 1;
                    row[1356..1360].copy_from_slice(&[0, 17, 0, 13]);
                }
                R::Monster => {
                    row[..8].copy_from_slice(&[0, 1, 0, 1, 0, 4, 0, 4]);
                    row[218] = 0;
                }
                R::Reward => row.fill(0),
            }
        }
        fs::write(root.join(family.path()), b).unwrap();
    }
    fs::write(root.join("opaque"), [0xff, 0x00, 0x81]).unwrap();
    fs::create_dir(root.join("empty")).unwrap();
}
fn call(session: &mut Session, operation: Value) -> Value {
    session.handle(
        serde_json::from_value::<Request>(json!({"protocol":1,"id":1,"operation":operation}))
            .unwrap(),
    )
}

#[test]
fn connected_author_export_reopen_preserves_owned_spans_and_atomic_history() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let source = t.path().join("source");
    fixture(&source);
    let template = t.path().join("template");
    store::import(&source, &template)?;
    let base = t.path().join("base");
    minimal::create(&template, &base, "Micro Patrol")?;
    let (base_project, raw) = store::open(&base)?;
    let baseline = centurions_format::apply(&base_project, &raw)?;
    let mut session = Session::new(t.path().join("cache"));
    assert_eq!(
        call(&mut session, json!({"op":"open","path":base}))["revision"],
        1
    );
    let result = call(
        &mut session,
        json!({"op":"author_connected_mission","expected_revision":1,"spec":MissionSpec::default()}),
    );
    assert_eq!(result["ok"], true, "{result}");
    let ids = &result["result"]["recipe"]["records"];
    let choice = ids["choice"].as_u64().unwrap() as usize;
    let walking = ids["walking"].as_u64().unwrap() as usize;
    assert_eq!(result["revision"], 2);
    assert_eq!(
        call(&mut session, json!({"op":"undo","expected_revision":2}))["revision"],
        3
    );
    assert!(
        call(&mut session, json!({"op":"inspect"}))["result"]["allocations"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        call(&mut session, json!({"op":"redo","expected_revision":3}))["revision"],
        4
    );
    let bad = call(
        &mut session,
        json!({"op":"apply","expected_revision":4,"edits":[{"kind":"choice_label","id":choice,"choice":0,"text":"Never published"},{"kind":"choice_prompt","id":choice,"message":32767}]}),
    );
    assert_eq!(bad["ok"], false);
    assert_eq!(bad["revision"], 4);
    assert!(
        bad["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Data ED record")
    );
    let saved = t.path().join("saved");
    assert_eq!(
        call(
            &mut session,
            json!({"op":"save_as","expected_revision":4,"destination":saved})
        )["ok"],
        true
    );
    let (p, f) = store::open(&saved)?;
    let effective = centurions_format::apply(&p, &f)?;
    assert_eq!(p.allocations.len(), 11);
    assert_eq!(f, raw);
    assert_eq!(effective["opaque"], raw["opaque"]);
    assert_eq!(
        &effective["Data ED"][choice * 426 + 100..choice * 426 + 104],
        &raw["Data ED"][100..104]
    );
    assert_eq!(
        &effective["Data ED"][effective["Data ED"].len() - 24..],
        &raw["Data ED"][raw["Data ED"].len() - 24..]
    );
    for allocation in &p.allocations {
        let family = allocation.family;
        let original = &raw[family.path()];
        assert_eq!(
            &effective[family.path()][..original.len() / family.stride() * family.stride()],
            &baseline[family.path()][..original.len() / family.stride() * family.stride()]
        );
        let new_row = &effective[family.path()]
            [allocation.id * family.stride()..(allocation.id + 1) * family.stride()];
        let seed_row =
            &original[allocation.seed * family.stride()..(allocation.seed + 1) * family.stride()];
        let owned = match family {
            R::Message => std::iter::once(0..1 + usize::from(new_row[0])).collect(),
            R::Choice => {
                let mut ranges = vec![0..100, 104..106];
                for choice in 0..2 {
                    let at = 106 + choice * 80;
                    ranges.push(at..at + 1 + usize::from(new_row[at]));
                }
                ranges
            }
            R::Story => std::iter::once(8..40).collect(),
            R::BattleExtra => std::iter::once(0..10).collect(),
            R::Battle => std::iter::once(0..1352).collect(),
            R::Monster => vec![
                0..8,
                0x26..0x32,
                0x3a..0x3c,
                218..219 + usize::from(new_row[218]),
            ],
            R::Reward => std::iter::once(0..88).collect(),
        };
        assert_eq!(
            centurions_format::ownership::inspect(seed_row, new_row, &owned).unowned_changes,
            0,
            "new {family:?} row changed bytes outside documented initialization/edit spans"
        );
    }
    assert!(centurions_format::connected::build(&p, &f, &MissionSpec::default()).is_err());
    assert_eq!(
        effective["Data DD"][walking * 42 + 41],
        raw["Data DD"][walking * 42 + 41]
    );
    assert_eq!(
        &effective["Data LD"][32400 + (3 * 90 + 2) * 4..32400 + (3 * 90 + 2) * 4 + 4],
        &203i32.to_be_bytes()
    );
    let export = t.path().join("export");
    store::export(&saved, &export)?;
    let reimport = t.path().join("reimport");
    store::import(&export, &reimport)?;
    let (rp, rf) = store::open(&reimport)?;
    assert_eq!(centurions_format::apply(&rp, &rf)?, effective);
    assert!(export.join("empty").is_dir());
    let removed = centurions_format::authoring::place_trigger(
        &p,
        &f,
        &centurions_format::authoring::TriggerPlacement {
            id: walking,
            x: 3,
            y: 2,
            chance: 0,
            remove: true,
            follow: false,
        },
    )?;
    let removed = centurions_format::apply(&removed, &f)?;
    assert_eq!(
        &removed["Data DD"][walking * 42..walking * 42 + 4],
        &(-1i32).to_be_bytes()
    );
    assert_eq!(
        &removed["Data LD"][32400 + (3 * 90 + 2) * 4..32400 + (3 * 90 + 2) * 4 + 4],
        &(-1i32).to_be_bytes()
    );
    assert!(
        centurions_format::update(
            &p,
            &f,
            vec![Edit::ChoiceLabel {
                id: choice,
                choice: 0,
                text: "x".repeat(80)
            }]
        )
        .is_err()
    );
    let mut capacity = f.clone();
    capacity.insert("Data SD2".into(), vec![0; 32768 * 256]);
    assert!(
        centurions_format::authoring::allocate(&base_project, &capacity, R::Message, 0)
            .unwrap_err()
            .contains("capacity")
    );
    Ok(())
}
