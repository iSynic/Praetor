//! The scenario's own items: 150-byte definitions in Data NI (item ids 800 and
//! up) and their 256-byte descriptions in Data NI Des. The offsets and meanings
//! are those of the reconstruction's `ItemDefinition`.
use crate::{Edit, Files, Result, ownership, span, text};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const ROW: usize = 150;
pub const DESCRIPTION: usize = 256;
pub const FIRST_ID: usize = 800;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ItemField {
    Icon,
    Class,
    Weight,
    Price,
    RequiredLevel,
    GeneratedRequiredLevel,
    ImmunityClass,
    Sound,
    ImpactSound,
    AttackCount,
    RoundsPerShot,
    MeleeDamage,
    MissileDamage,
    ElementalDamage,
    BaseAccuracy,
    BaseMeleeAccuracy,
    DamageEnhancement,
    RangeModifier,
    Range,
    SkipsHitRoll,
    Caliber,
    ReserveKind,
    MagazineCapacity,
    ChargeWeight,
    DiscardedWhenEmpty,
    Armor,
    ShieldChance,
    MissileDodge,
    MeleeDodge,
    BatteryCapacity,
    CapacityBonus,
    SuppliesShield,
    SuppliedQuantity,
    EffectSelector,
    Spell,
    ConditionSlot,
    ConditionThreshold,
    StoryScript,
    Strength,
    Quickness,
    MovementBonus,
    PsiResistanceBonus,
    MaximumPsiBonus,
    Hands,
    ShieldCost,
    ShieldCostModifier,
    EnergyRequirement,
    TargetMode,
    Animation,
    StartShieldChance,
    StartMissileDodge,
    StartMeleeDodge,
    StartArmor,
    EquipmentKind,
    ForbiddenTraits,
    ForbiddenSchools,
    RequiredRace,
    RequiredMos,
    RequiredTraits,
    RequiredSchools,
    Abilities,
}
use ItemField as F;

struct Place {
    at: usize,
    width: usize,
    signed: bool,
    low: i64,
    high: i64,
}

const fn place(at: usize, width: usize, signed: bool, low: i64, high: i64) -> Place {
    Place {
        at,
        width,
        signed,
        low,
        high,
    }
}

const ANY: (i64, i64) = (i16::MIN as i64, i16::MAX as i64);
/// Where the seven elemental damages lie, in the order of the spell info packet.
const ELEMENTS: [usize; 7] = [140, 64, 66, 68, 70, 72, 74];

fn descriptor(field: F, index: usize) -> Result<Place> {
    let tables = match field {
        F::ForbiddenTraits | F::RequiredTraits | F::RequiredSchools => 2,
        F::Abilities => 8,
        _ => 1,
    };
    if index != 0 && field != F::ElementalDamage && index >= tables {
        return Err("this field has one value".into());
    }
    let word = |at: usize, low: i64, high: i64| place(at, 2, true, low, high);
    let byte = |at: usize| place(at, 1, true, -128, 127);
    Ok(match field {
        F::Icon => word(10, ANY.0, ANY.1),
        F::Class => word(26, -255, 255),
        F::Weight => word(16, ANY.0, ANY.1),
        F::Price => place(142, 4, true, -i64::from(i32::MAX), i64::from(i32::MAX)),
        F::RequiredLevel => word(138, ANY.0, ANY.1),
        F::GeneratedRequiredLevel => byte(139),
        F::ImmunityClass => word(100, ANY.0, ANY.1),
        F::Sound => word(12, ANY.0, ANY.1),
        F::ImpactSound => word(14, ANY.0, ANY.1),
        F::AttackCount => word(76, ANY.0, ANY.1),
        F::RoundsPerShot => word(22, ANY.0, ANY.1),
        F::MeleeDamage => word(40, ANY.0, ANY.1),
        F::MissileDamage => word(62, ANY.0, ANY.1),
        F::ElementalDamage => {
            let at = *ELEMENTS
                .get(index)
                .ok_or("an item has seven elemental damages")?;
            word(at, ANY.0, ANY.1)
        }
        F::BaseAccuracy => byte(81),
        F::BaseMeleeAccuracy => byte(82),
        F::DamageEnhancement => byte(85),
        F::RangeModifier => byte(79),
        F::Range => word(60, ANY.0, ANY.1),
        F::SkipsHitRoll => word(136, ANY.0, ANY.1),
        F::Caliber => word(32, ANY.0, ANY.1),
        F::ReserveKind => word(34, ANY.0, ANY.1),
        F::MagazineCapacity => word(24, ANY.0, ANY.1),
        F::ChargeWeight => word(36, ANY.0, ANY.1),
        F::DiscardedWhenEmpty => word(38, ANY.0, ANY.1),
        F::Armor => word(94, ANY.0, ANY.1),
        F::ShieldChance => word(88, ANY.0, ANY.1),
        F::MissileDodge => byte(3),
        F::MeleeDodge => byte(4),
        F::BatteryCapacity => word(90, ANY.0, ANY.1),
        F::CapacityBonus => word(148, ANY.0, ANY.1),
        F::SuppliesShield => word(18, ANY.0, ANY.1),
        F::SuppliedQuantity => word(20, ANY.0, ANY.1),
        F::EffectSelector => word(42, ANY.0, ANY.1),
        F::Spell => word(44, ANY.0, ANY.1),
        F::ConditionSlot => word(46, ANY.0, ANY.1),
        F::ConditionThreshold => word(48, ANY.0, ANY.1),
        F::StoryScript => word(50, ANY.0, ANY.1),
        F::Strength => byte(0),
        F::Quickness => byte(2),
        F::MovementBonus => byte(5),
        F::PsiResistanceBonus => byte(6),
        F::MaximumPsiBonus => byte(7),
        F::Hands => byte(8),
        F::ShieldCost => word(92, ANY.0, ANY.1),
        F::ShieldCostModifier => byte(80),
        F::EnergyRequirement => word(146, ANY.0, ANY.1),
        F::TargetMode => word(56, ANY.0, ANY.1),
        F::Animation => word(58, ANY.0, ANY.1),
        F::StartShieldChance => byte(78),
        F::StartMissileDodge => byte(83),
        F::StartMeleeDodge => byte(84),
        F::StartArmor => byte(86),
        F::EquipmentKind => byte(87),
        F::ForbiddenTraits => place(104 + index, 1, false, 0, 255),
        F::ForbiddenSchools => place(106 + index, 1, false, 0, 255),
        F::RequiredRace => word(108, ANY.0, ANY.1),
        F::RequiredMos => word(110, ANY.0, ANY.1),
        F::RequiredTraits => place(112 + index, 1, false, 0, 255),
        F::RequiredSchools => place(114 + index, 1, false, 0, 255),
        F::Abilities => place(128 + index, 1, false, 0, 255),
    })
}

fn read(row: &[u8], p: &Place) -> i64 {
    match (p.width, p.signed) {
        (4, _) => i64::from(i32::from_be_bytes(row[p.at..p.at + 4].try_into().unwrap())),
        (2, _) => i64::from(i16::from_be_bytes([row[p.at], row[p.at + 1]])),
        (_, true) => i64::from(row[p.at] as i8),
        _ => i64::from(row[p.at]),
    }
}

/// (field, count, label, group): what the item page lists, in order.
const ROWS: &[(F, usize, &str, &str)] = &[
    (F::Icon, 1, "Icon", "Identity"),
    (
        F::Class,
        1,
        "Class (an entry of the item class names)",
        "Identity",
    ),
    (F::Weight, 1, "Weight", "Identity"),
    (
        F::Price,
        1,
        "Price (shops use its absolute value)",
        "Identity",
    ),
    (F::RequiredLevel, 1, "Level a warrior needs", "Identity"),
    (
        F::GeneratedRequiredLevel,
        1,
        "Level a generated copy starts with",
        "Identity",
    ),
    (F::ImmunityClass, 1, "Immunity class", "Identity"),
    (F::Sound, 1, "Sound", "Sounds"),
    (F::ImpactSound, 1, "Impact sound", "Sounds"),
    (F::AttackCount, 1, "Attacks", "Attack"),
    (F::RoundsPerShot, 1, "Rounds a shot uses", "Attack"),
    (F::MeleeDamage, 1, "Melee damage", "Attack"),
    (F::MissileDamage, 1, "Missile damage", "Attack"),
    (F::ElementalDamage, 7, "Elemental damage", "Attack"),
    (F::BaseAccuracy, 1, "Accuracy", "Attack"),
    (F::BaseMeleeAccuracy, 1, "Melee accuracy", "Attack"),
    (F::DamageEnhancement, 1, "Damage added", "Attack"),
    (F::Range, 1, "Range", "Attack"),
    (F::RangeModifier, 1, "Range added", "Attack"),
    (
        F::SkipsHitRoll,
        1,
        "Skips the hit roll (0 no, anything else yes)",
        "Attack",
    ),
    (F::Caliber, 1, "Ammunition caliber", "Ammunition"),
    (F::ReserveKind, 1, "Reserve ammunition kind", "Ammunition"),
    (F::MagazineCapacity, 1, "Magazine capacity", "Ammunition"),
    (F::ChargeWeight, 1, "Weight of each charge", "Ammunition"),
    (
        F::DiscardedWhenEmpty,
        1,
        "Thrown away when empty (0 no)",
        "Ammunition",
    ),
    (F::Armor, 1, "Armor added", "Defence"),
    (F::ShieldChance, 1, "Shield chance, percent", "Defence"),
    (F::MissileDodge, 1, "Missile dodge added", "Defence"),
    (F::MeleeDodge, 1, "Melee dodge added", "Defence"),
    (F::BatteryCapacity, 1, "Battery capacity", "Charge"),
    (
        F::CapacityBonus,
        1,
        "Capacity added to a fresh battery",
        "Charge",
    ),
    (
        F::SuppliesShield,
        1,
        "Recharges a power shield (0 no)",
        "Charge",
    ),
    (
        F::SuppliedQuantity,
        1,
        "Charges a fresh item starts with",
        "Charge",
    ),
    (F::EffectSelector, 1, "Effect when used", "Effect"),
    (
        F::Spell,
        1,
        "Spell descriptor (over 1100 names a scan); with effect -10, the condition: 1 saving throw, 2 chance, else always",
        "Effect",
    ),
    (
        F::ConditionSlot,
        1,
        "First attribute changed when worn; with effect -10 on a melee weapon, the condition slot plus 20",
        "Effect",
    ),
    (
        F::ConditionThreshold,
        1,
        "Second attribute changed when worn; with effect -10, the condition's saving throw or percent chance",
        "Effect",
    ),
    (F::Strength, 1, "Strength added when worn", "Worn"),
    (F::Quickness, 1, "Quickness added when worn", "Worn"),
    (F::MovementBonus, 1, "Movement added when worn", "Worn"),
    (
        F::PsiResistanceBonus,
        1,
        "Psi resistance added when worn",
        "Worn",
    ),
    (F::MaximumPsiBonus, 1, "Psi points added when worn", "Worn"),
    (F::Hands, 1, "Hands it takes", "Worn"),
    (
        F::ShieldCost,
        1,
        "Shield charge spent for each point of damage stopped",
        "Defence",
    ),
    (F::ShieldCostModifier, 1, "Shield cost added", "Defence"),
    (
        F::EnergyRequirement,
        1,
        "Charge a weapon needs to fire",
        "Charge",
    ),
    (F::TargetMode, 1, "Picks targets when used (0 no)", "Effect"),
    (F::Animation, 1, "Animation shown (0 none)", "Effect"),
    (
        F::StartShieldChance,
        1,
        "Shield chance a new copy starts with",
        "New copy",
    ),
    (
        F::StartMissileDodge,
        1,
        "Missile dodge a new copy starts with",
        "New copy",
    ),
    (
        F::StartMeleeDodge,
        1,
        "Melee dodge a new copy starts with",
        "New copy",
    ),
    (F::StartArmor, 1, "Armor a new copy starts with", "New copy"),
    (
        F::EquipmentKind,
        1,
        "Kind of equipment an upgrade must match",
        "New copy",
    ),
    (
        F::ForbiddenTraits,
        2,
        "Races with these traits cannot use it, byte (first trait is the high bit)",
        "Who may use it",
    ),
    (
        F::ForbiddenSchools,
        1,
        "Psi schools that cannot use it, bits (first school is the high bit)",
        "Who may use it",
    ),
    (
        F::RequiredRace,
        1,
        "The one race that may use it (0 any)",
        "Who may use it",
    ),
    (
        F::RequiredMos,
        1,
        "The one MOS that may use it (0 any)",
        "Who may use it",
    ),
    (
        F::RequiredTraits,
        2,
        "Only races with these traits may use it, byte (0 any)",
        "Who may use it",
    ),
    (
        F::RequiredSchools,
        2,
        "Only these Psi schools may use it, byte (0 any)",
        "Who may use it",
    ),
    (
        F::Abilities,
        8,
        "Ability the item gives, byte (first ability is the high bit)",
        "Who may use it",
    ),
    (
        F::StoryScript,
        1,
        "Amount the attributes change by when worn (negative lowers); the continuation story of a class 23 item; the condition's amount with effect -10",
        "Effect",
    ),
];

/// The price of a scenario item (ids from 800), or `None` for any other id.
pub fn price(files: &Files, item: i16) -> Option<i64> {
    let index = usize::try_from(item).ok()?.checked_sub(FIRST_ID)?;
    let row = definition(files, index).ok()?;
    Some(read(row, &place(142, 4, true, 0, 0)))
}

fn definition(files: &Files, index: usize) -> Result<&[u8]> {
    let at = index.checked_mul(ROW).ok_or("record index overflow")?;
    span(files.get("Data NI").ok_or("missing Data NI")?, at, ROW)
}

fn description(files: &Files, index: usize) -> Result<&[u8]> {
    let at = index
        .checked_mul(DESCRIPTION)
        .ok_or("record index overflow")?;
    span(
        files.get("Data NI Des").ok_or("missing Data NI Des")?,
        at,
        DESCRIPTION,
    )
}

/// How many items the scenario's own table holds.
pub fn count(files: &Files) -> usize {
    files.get("Data NI").map_or(0, |b| b.len() / ROW)
}

fn describe(files: &Files, index: usize) -> String {
    description(files, index).map_or(String::new(), |row| {
        text::decode(&row[1..1 + usize::from(row[0])])
    })
}

/// One line of each item for a list: its id and the start of its description.
pub fn catalogue(files: &Files) -> Value {
    json!((0..count(files).min(200))
        .map(|index| json!({"index":index,"id":FIRST_ID+index,"text":describe(files, index).replace('\n'," ").chars().take(60).collect::<String>()}))
        .collect::<Vec<_>>())
}

/// The item's fields with what the engine accepts there, and its description.
pub fn view(files: &Files, index: usize) -> Result<Value> {
    let row = definition(files, index)?;
    let mut fields = Vec::new();
    for (field, rows, label, group) in ROWS {
        for at in 0..*rows {
            let Ok(p) = descriptor(*field, at) else {
                continue;
            };
            let value = read(row, &p);
            fields.push(
                json!({"field":field,"index":at,"offset":p.at,"width":p.width,"value":value,"minimum":p.low,"maximum":p.high,
                "label":if *rows > 1 {format!("{label} {}", at + 1)} else {(*label).to_string()},
                "group":group,"authorable":(p.low..=p.high).contains(&value)}),
            );
        }
    }
    Ok(
        json!({"index":index,"id":FIRST_ID+index,"count":count(files),"fields":fields,
        "description":describe(files, index),"description_bytes":description(files, index)?[0]}),
    )
}

#[allow(clippy::single_range_in_vec_init)] // Each element declares an owned byte span.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    match edit {
        Edit::ItemField {
            index,
            field,
            slot,
            value,
        } => {
            let p = descriptor(*field, *slot)?;
            if !(p.low..=p.high).contains(&i64::from(*value)) {
                return Err(format!(
                    "Data NI record {index} field {field:?}: value {value} is outside {}..{}",
                    p.low, p.high
                ));
            }
            definition(files, *index)?;
            let bytes = files.get_mut("Data NI").ok_or("missing Data NI")?;
            let base = index * ROW;
            if !(p.low..=p.high).contains(&read(&bytes[base..base + ROW], &p)) {
                return Err("an unresolved imported value is read only".into());
            }
            let before = bytes.clone();
            let encoded = value.to_be_bytes();
            let width = p.width;
            bytes[base + p.at..base + p.at + width].copy_from_slice(&encoded[4 - width..]);
            if ownership::inspect(&before, bytes, &[base + p.at..base + p.at + width])
                .unowned_changes
                != 0
            {
                return Err("unowned item edit".into());
            }
            Ok(())
        }
        Edit::ItemDescription { index, text: value } => {
            description(files, *index)?;
            let encoded = text::encode(value)?;
            if encoded.len() > DESCRIPTION - 1 {
                return Err(format!("text exceeds {} Mac Roman bytes", DESCRIPTION - 1));
            }
            let bytes = files.get_mut("Data NI Des").ok_or("missing Data NI Des")?;
            let at = index * DESCRIPTION;
            bytes[at] = encoded.len() as u8;
            bytes[at + 1..at + 1 + encoded.len()].copy_from_slice(&encoded);
            Ok(())
        }
        _ => Err("not an item edit".into()),
    }
}
