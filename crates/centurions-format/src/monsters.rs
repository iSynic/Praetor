//! The fields of a monster's definition in Data MD, one descriptor for each:
//! where it lies, how wide it is and what the engine accepts there. The
//! offsets and meanings are those of the reconstruction's `EnemyRecord`.
use crate::{Edit, Files, Result, ownership, span, text};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const ROW: usize = 288;
/// Bytes of a description in `Data DES`: a length and the words.
pub const DESCRIPTION: usize = 256;

/// The description of monster `id`: the words and how many bytes they take.
pub fn description(files: &Files, id: usize) -> (String, usize) {
    let Some(slot) = id.checked_mul(DESCRIPTION).and_then(|at| {
        files
            .get("Data DES")
            .and_then(|b| span(b, at, DESCRIPTION).ok())
    }) else {
        return (String::new(), 0);
    };
    let length = usize::from(slot[0]);
    (text::decode(&slot[1..1 + length]), length)
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MonsterField {
    Icon,
    Size,
    Faction,
    Flying,
    Capturable,
    Mechanical,
    SurvivorMarker,
    Armor,
    WeaponImmunity,
    MissileDodge,
    MissileAccuracy,
    DamagePlus,
    AttackCount,
    VictoryPoints,
    ShieldChance,
    PsiResistance,
    PsiPointsMax,
    MagicAttackCount,
    CastPercent,
    MissilePercent,
    SurrenderPercent,
    Ammunition,
    DeathSound,
    MovementSound,
    Item,
    CreditBound,
    Save,
    AttackMinimum,
    AttackMaximum,
    AttackSound,
    AttackCondition,
    Category,
    Weapon,
    ShieldPoints,
    Hidden,
    Condition,
}
use MonsterField as F;

/// Where a field lies: offset, width in bytes, whether it is signed, its lowest
/// and highest value.
struct Place {
    at: usize,
    width: usize,
    signed: bool,
    low: i16,
    high: i16,
}

const fn place(at: usize, width: usize, signed: bool, low: i16, high: i16) -> Place {
    Place {
        at,
        width,
        signed,
        low,
        high,
    }
}

fn descriptor(field: F, index: usize) -> Result<Place> {
    let one = |p: Place| {
        if index == 0 {
            Ok(p)
        } else {
            Err("this field has one value".to_string())
        }
    };
    let many = |count: usize, p: Place| {
        if index < count {
            Ok(Place {
                at: p.at + index * if p.width == 2 { 2 } else { 1 },
                ..p
            })
        } else {
            Err(format!("this field has {count} values"))
        }
    };
    let (any_low, any_high) = (i16::MIN, i16::MAX);
    match field {
        F::Icon => one(place(0x50, 2, true, 0, any_high)),
        F::Size => one(place(0x10, 2, true, -3, 3)),
        F::Faction => one(place(0x0e, 2, true, 0, any_high)),
        F::Flying => one(place(0x7f, 1, false, 0, 255)),
        F::Capturable => one(place(0xb1, 1, false, 0, 255)),
        F::Mechanical => one(place(0xb0, 1, false, 0, 1)),
        F::SurvivorMarker => one(place(0x5a, 2, true, -1, any_high)),
        F::Armor => one(place(0x08, 2, true, any_low, any_high)),
        F::WeaponImmunity => one(place(0x0c, 2, true, any_low, any_high)),
        F::MissileDodge => one(place(0x62, 2, true, any_low, any_high)),
        F::MissileAccuracy => one(place(0x66, 2, true, any_low, any_high)),
        F::DamagePlus => one(place(0x40, 2, true, any_low, any_high)),
        F::AttackCount => one(place(0x8a, 1, true, 0, 5)),
        F::VictoryPoints => one(place(0x54, 2, true, 0, any_high)),
        F::ShieldChance => one(place(0x56, 2, true, any_low, any_high)),
        F::PsiResistance => one(place(0x0a, 2, true, any_low, any_high)),
        F::PsiPointsMax => one(place(0x52, 2, true, any_low, any_high)),
        F::MagicAttackCount => one(place(0x7e, 1, true, 0, 10)),
        F::CastPercent => one(place(0x42, 2, true, any_low, any_high)),
        F::MissilePercent => one(place(0x48, 2, true, any_low, any_high)),
        F::SurrenderPercent => one(place(0x46, 2, true, 0, 100)),
        F::Ammunition => one(place(0x4c, 2, true, 0, any_high)),
        F::DeathSound => one(place(0x6a, 2, true, any_low, any_high)),
        F::MovementSound => one(place(0x6c, 2, true, any_low, any_high)),
        F::Item => many(6, place(0x26, 2, true, 0, 999)),
        F::CreditBound => one(place(0x3a, 2, true, 0, any_high)),
        F::Save => many(6, place(0x8b, 1, true, -128, 127)),
        F::AttackMinimum => attack(index, 0, true, -128, 127),
        F::AttackMaximum => attack(index, 1, true, -128, 127),
        F::AttackSound => attack(index, 2, true, -128, 127),
        F::AttackCondition => attack(index, 3, false, 0, 255),
        F::Category => many(8, place(0xa8, 1, false, 0, 255)),
        F::Weapon => one(place(0x4e, 2, true, -9, 999)),
        F::ShieldPoints => one(place(0x58, 2, true, any_low, any_high)),
        F::Hidden => one(place(0xa7, 1, false, 0, 255)),
        F::Condition => many(40, place(0xb2, 1, true, -128, 127)),
    }
}

fn attack(index: usize, part: usize, signed: bool, low: i16, high: i16) -> Result<Place> {
    if index >= 5 {
        return Err("a monster has five natural attacks".into());
    }
    Ok(place(0x93 + index * 4 + part, 1, signed, low, high))
}

fn read(row: &[u8], p: &Place) -> i16 {
    match (p.width, p.signed) {
        (2, _) => i16::from_be_bytes([row[p.at], row[p.at + 1]]),
        (_, true) => i16::from(row[p.at] as i8),
        _ => i16::from(row[p.at]),
    }
}

/// (field, count, label, group): what the monster page lists, in order.
const ROWS: &[(F, usize, &str, &str)] = &[
    (F::Icon, 1, "Icon", "Identity"),
    (
        F::Size,
        1,
        "Size (0 one cell, 1 to 3 larger; the original also reads -3 to -1)",
        "Identity",
    ),
    (
        F::Faction,
        1,
        "Side (0 the party's, anything else the monsters')",
        "Identity",
    ),
    (F::Flying, 1, "Flies (0 no, anything else yes)", "Identity"),
    (
        F::Capturable,
        1,
        "Can be captured (0 no, anything else yes)",
        "Identity",
    ),
    (F::Mechanical, 1, "Mechanical body (1 yes)", "Identity"),
    (
        F::SurvivorMarker,
        1,
        "Offered as an ally after the battle",
        "Identity",
    ),
    (F::Armor, 1, "Armor rating", "Body"),
    (F::WeaponImmunity, 1, "Weapon immunity (0 none)", "Body"),
    (F::MissileDodge, 1, "Missile dodge bonus", "Body"),
    (F::MissileAccuracy, 1, "Missile accuracy bonus", "Body"),
    (F::DamagePlus, 1, "Damage added to each attack", "Body"),
    (F::AttackCount, 1, "Attacks each round", "Body"),
    (F::ShieldChance, 1, "Power shield chance, percent", "Body"),
    (F::VictoryPoints, 1, "Victory points", "Body"),
    (F::MagicAttackCount, 1, "Scans cast each round", "Psi"),
    (F::CastPercent, 1, "Cast chance, percent", "Psi"),
    (F::PsiResistance, 1, "Resistance to scans", "Psi"),
    (F::PsiPointsMax, 1, "Psi points", "Psi"),
    (
        F::MissilePercent,
        1,
        "Missile fire chance, percent",
        "Behaviour",
    ),
    (
        F::SurrenderPercent,
        1,
        "Surrender chance, percent",
        "Behaviour",
    ),
    (F::Ammunition, 1, "Ammunition item (0 none)", "Behaviour"),
    (F::DeathSound, 1, "Death sound", "Sounds"),
    (F::MovementSound, 1, "Movement sound", "Sounds"),
    (
        F::Weapon,
        1,
        "Weapon (item id; -1 to -9 picks a random weapon table)",
        "Body",
    ),
    (F::ShieldPoints, 1, "Shield points", "Body"),
    (
        F::Hidden,
        1,
        "Left out of the bestiary menu (0 no)",
        "Identity",
    ),
    (
        F::Condition,
        40,
        "Condition counter at the start of a battle",
        "Conditions",
    ),
    (F::Save, 6, "Saving throw", "Saves"),
    (F::Category, 8, "Creature category flag", "Saves"),
    (F::AttackMinimum, 5, "Attack lowest damage", "Attacks"),
    (F::AttackMaximum, 5, "Attack highest damage", "Attacks"),
    (F::AttackSound, 5, "Attack impact sound", "Attacks"),
    (
        F::AttackCondition,
        5,
        "Attack condition (0 none)",
        "Attacks",
    ),
    (F::Item, 6, "Item carried", "Loot"),
    (F::CreditBound, 1, "Most credits dropped", "Loot"),
];

/// Every field of the definition with its value and what the engine accepts.
/// A value outside that range is shown but is read only.
pub fn projection(row: &[u8]) -> Value {
    let mut fields = Vec::new();
    for (field, count, label, group) in ROWS {
        for index in 0..*count {
            let Ok(p) = descriptor(*field, index) else {
                continue;
            };
            let value = read(row, &p);
            fields.push(json!({"field":field,"index":index,"offset":p.at,"width":p.width,"value":value,"minimum":p.low,"maximum":p.high,
                "label":if *count > 1 {format!("{label} {}", index + 1)} else {(*label).to_string()},
                "group":group,"authorable":(p.low..=p.high).contains(&value)}));
        }
    }
    json!(fields)
}

#[allow(clippy::single_range_in_vec_init)] // The element declares the owned byte span.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    if let Edit::MonsterImport {
        id,
        record,
        description: words,
    } = edit
    {
        let row = crate::resources::unhex(record)?;
        if row.len() != ROW {
            return Err(format!("a monster record is {ROW} bytes"));
        }
        let encoded = text::encode(words)?;
        if encoded.len() > DESCRIPTION - 1 {
            return Err(format!(
                "a description is at most {} bytes",
                DESCRIPTION - 1
            ));
        }
        let table = files.get_mut("Data MD").ok_or("missing Data MD")?;
        let at = id.checked_mul(ROW).ok_or("record index overflow")?;
        span(table, at, ROW).map_err(|_| format!("monster {id} is not in Data MD"))?;
        table[at..at + ROW].copy_from_slice(&row);
        let slot = files.get_mut("Data DES").ok_or("missing Data DES")?;
        let from = id * DESCRIPTION;
        span(slot, from, DESCRIPTION)
            .map_err(|_| format!("Data DES has no slot for monster {id}"))?;
        slot[from] = encoded.len() as u8;
        slot[from + 1..from + 1 + encoded.len()].copy_from_slice(&encoded);
        return Ok(());
    }
    if let Edit::MonsterDescription { id, text: words } = edit {
        let encoded = text::encode(words)?;
        if encoded.len() > DESCRIPTION - 1 {
            return Err(format!(
                "a description is at most {} bytes",
                DESCRIPTION - 1
            ));
        }
        if *id >= files.get("Data MD").map_or(0, |b| b.len() / ROW) {
            return Err(format!("monster {id} is not in Data MD"));
        }
        let bytes = files.get_mut("Data DES").ok_or("missing Data DES")?;
        let at = id * DESCRIPTION;
        span(bytes, at, DESCRIPTION)
            .map_err(|_| format!("Data DES has no slot for monster {id}"))?;
        bytes[at] = encoded.len() as u8;
        bytes[at + 1..at + 1 + encoded.len()].copy_from_slice(&encoded);
        return Ok(());
    }
    let Edit::MonsterField {
        id,
        field,
        index,
        value,
    } = edit
    else {
        return Err("not a monster field edit".into());
    };
    let p = descriptor(*field, *index)?;
    if !(p.low..=p.high).contains(value) {
        return Err(format!(
            "Data MD record {id} field {field:?}: value {value} is outside {}..{}",
            p.low, p.high
        ));
    }
    let bytes = files.get_mut("Data MD").ok_or("missing Data MD")?;
    let base = id.checked_mul(ROW).ok_or("record index overflow")?;
    span(bytes, base, ROW)?;
    let old = read(&bytes[base..base + ROW], &p);
    if !(p.low..=p.high).contains(&old) {
        return Err("an unresolved imported value is read only".into());
    }
    let before = bytes.clone();
    if p.width == 2 {
        bytes[base + p.at..base + p.at + 2].copy_from_slice(&value.to_be_bytes());
    } else {
        bytes[base + p.at] = *value as u8;
    }
    if ownership::inspect(&before, bytes, &[base + p.at..base + p.at + p.width]).unowned_changes
        != 0
    {
        return Err("unowned monster edit".into());
    }
    Ok(())
}
