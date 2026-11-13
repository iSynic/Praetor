//! A connected mission recipe built entirely through the ordinary authoring boundary.
use crate::{
    BattleUnit, ConditionField, Edit, Files, Project, RecordFamily as R, Result, ScriptFamily as S,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct MissionSpec {
    pub name: String,
    pub completion_name: String,
    pub introduction: String,
    pub prompt: String,
    pub accept_label: String,
    pub decline_label: String,
    pub declined: String,
    pub victory: String,
    pub completion: String,
    pub monster_name: String,
    pub credits: i32,
    pub map: usize,
    pub x: usize,
    pub y: usize,
    pub floor: i16,
    pub monster_seed: usize,
    pub battle_seed: usize,
    pub choice_seed: usize,
}
impl Default for MissionSpec {
    fn default() -> Self {
        Self {
            name: "Micro Patrol".into(),
            completion_name: "Patrol Complete".into(),
            introduction: "A training drone blocks the patrol route.".into(),
            prompt: "Engage the drone and clear the route?".into(),
            accept_label: "Engage".into(),
            decline_label: "Not yet".into(),
            declined: "Return when the squad is ready.".into(),
            victory: "Route secure. Your patrol reward has been issued.".into(),
            completion: "Patrol complete. The squad has reached its destination.".into(),
            monster_name: "Training Drone".into(),
            credits: 25,
            map: 0,
            x: 2,
            y: 2,
            floor: 155,
            monster_seed: 1,
            battle_seed: 1,
            choice_seed: 0,
        }
    }
}

pub fn build(project: &Project, source: &Files, spec: &MissionSpec) -> Result<(Project, Value)> {
    if !matches!(project.origin, crate::Origin::MinimalTemplate { .. }) {
        return Err("connected authoring requires a template-derived mission; create one from an unchanged import first".into());
    }
    if !project.allocations.is_empty()
        || project.edits.iter().any(|edit| {
            !matches!(
                edit,
                Edit::DisableSchedule
                    | Edit::Opening { .. }
                    | Edit::QuietMap { .. }
                    | Edit::StageName { id: 0, .. }
                    | Edit::StageStart { id: 0, .. }
                    | Edit::DisableStage { .. }
                    | Edit::ClearStageScript { id: 0 }
            )
        })
    {
        return Err("connected recipe requires a fresh template-derived project; existing authored work will not be replaced".into());
    }
    if spec.map >= 20 || spec.x > 87 || spec.y >= 90 {
        return Err("Data Mission record 0 field start: this recipe requires x 0..87 and y 0..89 on an existing map".into());
    }
    let mut next = project.clone();
    let mut ids = serde_json::Map::new();
    for (key, family, seed) in [
        ("introduction", R::Message, 0),
        ("prompt", R::Message, 0),
        ("declined", R::Message, 0),
        ("victory", R::Message, 0),
        ("completion", R::Message, 0),
        ("choice", R::Choice, spec.choice_seed),
        ("completion_story", R::Story, 0),
        ("battle_extra", R::BattleExtra, 0),
        ("battle", R::Battle, spec.battle_seed),
        ("monster", R::Monster, spec.monster_seed),
        ("reward", R::Reward, 0),
    ] {
        let (allocated, id) = crate::authoring::allocate(&next, source, family, seed)?;
        next = allocated;
        ids.insert(key.into(), json!(id));
    }
    let id = |key: &str| ids[key].as_u64().unwrap() as usize;
    let word = |key: &str| id(key) as i16;
    let files = crate::apply(&next, source)?;
    let dd = files
        .get("Data DD")
        .ok_or("Data DD: missing walking table")?;
    let start = spec.map.checked_mul(4200).ok_or("map index overflow")?;
    let headers = dd
        .get(start..start + 4200)
        .ok_or("Data DD: missing 100-slot map table")?;
    let slot=(0..100).find(|slot| {
        let b=&headers[slot*42..(slot+1)*42];i32::from_be_bytes(b[..4].try_into().unwrap())<0&&b[8..40].iter().all(|v|*v==0)
    }).ok_or("Data DD: no unplaced empty program slot; no imported program will be cleared to make room")?;
    let trigger = spec.map * 100 + slot;
    let tx = spec.x + 1;
    let mut edits = vec![
        Edit::StageName {
            id: 0,
            name: spec.name.clone(),
        },
        Edit::StageStart {
            id: 0,
            map: spec.map as i16,
            x: spec.x as i16,
            y: spec.y as i16,
        },
        Edit::Opening {
            map: spec.map as i32,
            x: spec.x as i32,
            y: spec.y as i32,
        },
        Edit::WalkingLocation {
            map: spec.map,
            slot,
            x: tx,
            y: spec.y,
        },
        Edit::WalkingChance {
            id: trigger,
            chance: 100,
        },
        Edit::EventActivation {
            map: spec.map,
            x: tx,
            y: spec.y,
            enabled: true,
        },
        Edit::WalkingTarget {
            id: trigger,
            map: spec.map as i16,
            x: tx as i16,
            y: spec.y as i16,
            level: 0,
        },
        Edit::ChoicePrompt {
            id: id("choice"),
            message: word("prompt"),
        },
        Edit::ChoiceLabel {
            id: id("choice"),
            choice: 0,
            text: spec.accept_label.clone(),
        },
        Edit::ChoiceLabel {
            id: id("choice"),
            choice: 1,
            text: spec.decline_label.clone(),
        },
        Edit::EncounterCondition {
            family: S::Menu,
            id: id("choice"),
            field: ConditionField::ChoiceSelector,
            index: 0,
            value: 1,
        },
        Edit::EncounterCondition {
            family: S::Menu,
            id: id("choice"),
            field: ConditionField::ChoiceSelector,
            index: 1,
            value: 2,
        },
        Edit::BattleExtra {
            id: id("battle_extra"),
            minimum: word("battle"),
            maximum: 0,
            sound: 0,
            message: 0,
            cleanup_mode: 0,
        },
        Edit::BattlePopulation {
            id: id("battle"),
            units: vec![BattleUnit {
                x: 18,
                y: 13,
                monster: word("monster"),
            }],
        },
        Edit::MonsterStats {
            id: id("monster"),
            name: spec.monster_name.clone(),
            level: 1,
            stamina: 1,
            speed: 4,
            movement: 4,
        },
        Edit::MonsterNoDrops { id: id("monster") },
        Edit::Reward {
            id: id("reward"),
            credits: spec.credits,
            experience: 0,
        },
        Edit::StageName {
            id: 1,
            name: spec.completion_name.clone(),
        },
        Edit::StageStart {
            id: 1,
            map: spec.map as i16,
            x: (spec.x + 2) as i16,
            y: spec.y as i16,
        },
        Edit::StageScript {
            id: 1,
            story: word("completion_story"),
        },
    ];
    for (key, text) in [
        ("introduction", &spec.introduction),
        ("prompt", &spec.prompt),
        ("declined", &spec.declined),
        ("victory", &spec.victory),
        ("completion", &spec.completion),
    ] {
        edits.push(Edit::Message {
            id: id(key),
            text: text.clone(),
        });
    }
    for (family, owner, branch, program) in [
        (
            S::Walking,
            trigger,
            0,
            vec![(1, word("introduction")), (4, word("choice")), (24, 0)],
        ),
        (
            S::Menu,
            id("choice"),
            0,
            vec![
                (2, word("battle_extra")),
                (10, word("reward")),
                (1, word("victory")),
                (110, -2),
                (24, 0),
            ],
        ),
        (
            S::Menu,
            id("choice"),
            1,
            vec![(1, word("declined")), (24, 0)],
        ),
        (
            S::Story,
            id("completion_story"),
            0,
            vec![(1, word("completion")), (24, 0)],
        ),
    ] {
        for (slot, (opcode, operand)) in program.into_iter().enumerate() {
            edits.push(Edit::ScriptStep {
                family,
                id: owner,
                branch,
                slot: slot as u8,
                opcode,
                operand,
            });
        }
    }
    // An explicit small clearing supplies passable terrain; object/event bytes are retained.
    let ld = files.get("Data LD").ok_or("missing Data LD")?;
    for x in spec.x.saturating_sub(4)..(spec.x + 14).min(90) {
        for y in spec.y.saturating_sub(4)..(spec.y + 14).min(90) {
            let object = crate::word(ld, spec.map * crate::MAP_BYTES + 16200 + (x * 90 + y) * 2)?;
            if object != 0 {
                return Err(format!(
                    "Data LD map {} cell ({x},{y}) field object: recipe clearing overlaps an inherited object; choose another start",
                    spec.map
                ));
            }
            edits.push(Edit::Floor {
                map: spec.map,
                x,
                y,
                tile: spec.floor,
            });
        }
    }
    next = crate::update(&next, source, edits)?;
    ids.insert("walking".into(), json!(trigger));
    Ok((
        next,
        json!({"records":ids,"stage_transition":{"opcode":110,"operand":-2,"target_stage":1,"uses_extra":false},"template_derived":true,"source_free":false,"spec":spec}),
    ))
}
