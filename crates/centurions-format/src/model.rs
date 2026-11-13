use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

pub const KIND: &str = "new-centurions-scenario-project";
pub const VERSION: u32 = 13;
pub const AUTHORABLE: &[&str] = &[
    "message",
    "stage_name",
    "stage_start",
    "stage_script",
    "opening",
    "floor",
    "script_step",
    "walking_location",
    "walking_chance",
    "walking_target",
    "event_activation",
    "encounter_condition",
    "choice_label",
    "choice_prompt",
    "battle_extra",
    "extra_word",
    "extra_row",
    "extra_independent",
    "battle_population",
    "battle_setting",
    "monster_stats",
    "monster_turn_story",
    "monster_retreat_threshold",
    "monster_death_story",
    "monster_spell_slots",
    "selected_battle_extra",
    "monster_no_drops",
    "reward",
    "reward_item",
    "record_allocation",
    "region",
    "map_look",
    "shop_stock",
    "shop_price",
    "monster_field",
    "monster_description",
    "monster_import",
    "typed_label",
    "item_field",
    "item_description",
    "resource_change",
    "scroll_text",
    "scroll_text_remove",
    "item_name",
    "calendar_entry",
    "map_object",
    "add_map",
    "note_label",
    "remove_map",
    "map_note",
];
pub const SIDE: usize = 90;
pub const CELLS: usize = SIDE * SIDE;
pub const MAP_BYTES: usize = CELLS * 8;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SourceFile {
    pub sha256: String,
    pub size: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Project {
    pub kind: String,
    pub version: u32,
    pub origin: Origin,
    pub files: BTreeMap<String, SourceFile>,
    pub directories: BTreeSet<String>,
    pub edits: Vec<Edit>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub allocations: Vec<Allocation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub native: Option<NativeScenario>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NativeScenario {
    pub name: String,
    pub startup_header_source: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Origin {
    Imported {
        label: String,
    },
    MinimalTemplate {
        label: String,
        unchanged_gate: String,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Edit {
    MonsterNoDrops {
        id: usize,
    },
    EventActivation {
        map: usize,
        x: usize,
        y: usize,
        enabled: bool,
    },
    ItemField {
        index: usize,
        field: crate::items::ItemField,
        slot: usize,
        value: i32,
    },
    ItemDescription {
        index: usize,
        text: String,
    },
    TypedLabel {
        id: usize,
        index: usize,
        text: String,
    },
    ChoiceLabel {
        id: usize,
        choice: usize,
        text: String,
    },
    ChoicePrompt {
        id: usize,
        message: i16,
    },
    StageScript {
        id: usize,
        story: i16,
    },
    WalkingTarget {
        id: usize,
        map: i16,
        x: i16,
        y: i16,
        level: u8,
    },
    WalkingRemove {
        id: usize,
    },
    BattleExtra {
        id: usize,
        minimum: i16,
        maximum: i16,
        sound: i16,
        message: i16,
        cleanup_mode: i16,
    },
    BattlePopulation {
        id: usize,
        units: Vec<BattleUnit>,
    },
    ExtraWord {
        record: usize,
        index: usize,
        value: i16,
    },
    ExtraRow {
        record: usize,
        words: [i16; 5],
    },
    ExtraIndependent {
        family: ScriptFamily,
        id: usize,
        branch: u8,
        slot: u8,
    },
    BattleSetting {
        id: usize,
        field: BattleSettingField,
        index: usize,
        value: i16,
    },
    SelectedBattleExtra {
        id: usize,
        minimum: i16,
        maximum: i16,
        sound: i16,
        message: i16,
        treasure: i16,
    },
    MonsterTurnStory {
        id: usize,
        chance: i16,
        story: i16,
    },
    MonsterRetreatThreshold {
        id: usize,
        value: i16,
    },
    MonsterDeathStory {
        id: usize,
        story: i16,
    },
    MonsterSpellSlots {
        id: usize,
        slots: [i16; 10],
    },
    MonsterStats {
        id: usize,
        name: String,
        level: i16,
        stamina: i16,
        speed: i16,
        movement: i16,
    },
    RewardItem {
        id: usize,
        slot: usize,
        item: i16,
        level: i16,
    },
    Reward {
        id: usize,
        credits: i32,
        experience: i32,
    },
    WalkingLocation {
        map: usize,
        slot: usize,
        x: usize,
        y: usize,
    },
    WalkingChance {
        id: usize,
        chance: i16,
    },
    /// The words the Archives show for a monster: its slot of `Data DES`, a Pascal string of at most 255 bytes.
    MonsterDescription {
        id: usize,
        text: String,
    },
    /// A whole monster, as the vault holds it: the 288 bytes of its `Data MD` row (hex) and its description. It is
    /// made by the vault's copy, after the row's allocation, and replays before the author's other edits of the row.
    MonsterImport {
        id: usize,
        record: String,
        description: String,
    },
    MonsterField {
        id: usize,
        field: crate::monsters::MonsterField,
        index: usize,
        value: i16,
    },
    ShopStock {
        shop: usize,
        slot: usize,
        item: i16,
        quantity: i16,
    },
    ShopPrice {
        shop: usize,
        percent: i16,
    },
    Region {
        map: usize,
        slot: usize,
        first_y: i16,
        first_x: i16,
        last_y: i16,
        last_x: i16,
        encounter_chance: i16,
        battle_min: i16,
        battle_max: i16,
        scripts: [i16; 3],
        script_chances: [i16; 3],
        exclusive: bool,
        avoid_chance: i16,
        avoid_sound: i16,
        avoid_dialogue: i16,
    },
    MapLook {
        map: usize,
        terrain: i16,
        limits_sight: bool,
        light: i16,
    },
    EncounterCondition {
        family: ScriptFamily,
        id: usize,
        field: ConditionField,
        index: usize,
        value: i16,
    },
    ScriptStep {
        family: ScriptFamily,
        id: usize,
        branch: u8,
        slot: u8,
        opcode: i16,
        operand: i16,
    },
    Message {
        id: usize,
        text: String,
    },
    StageName {
        id: usize,
        name: String,
    },
    StageStart {
        id: usize,
        map: i16,
        x: i16,
        y: i16,
    },
    Opening {
        map: i32,
        x: i32,
        y: i32,
    },
    Floor {
        map: usize,
        x: usize,
        y: usize,
        tile: i16,
    },
    QuietMap {
        map: usize,
    },
    DisableStage {
        id: usize,
    },
    ClearStageScript {
        id: usize,
    },
    DisableSchedule,
    /// Sets one resource of the scenario's resource file, or removes it when `data` is absent. `data` is hex.
    ResourceChange {
        resource_type: String,
        id: i16,
        data: Option<String>,
    },
    /// A scrolling text: its `TEXT` and the `styl` that sets its fonts. Without `runs` the text keeps the styles
    /// it has, cut to the new length.
    ScrollText {
        id: i16,
        text: String,
        runs: Option<Vec<StyleRun>>,
    },
    /// Removes a scrolling text's `TEXT` and `styl`.
    ScrollTextRemove {
        id: i16,
    },
    /// The name of scenario item `index` (item 800 + `index`): that place in the scenario's `STR#` 801.
    ItemName {
        index: usize,
        name: String,
    },
    /// Adds the next map with the records it is made of, as hex: its cells (`Data LD`), walking triggers
    /// (`Data DD`) and regions (`Data RD`). The adapter makes them from a blank map or a copy of another as the
    /// project stands, so the edit does not depend on what later edits do to the map it copies.
    AddMap {
        map: usize,
        cells: String,
        walking: String,
        regions: String,
    },
    /// What the object layer holds at a cell: 0 for nothing, a building number (the picture 23000 plus it), or
    /// minus an icon number.
    MapObject {
        map: usize,
        x: usize,
        y: usize,
        value: i16,
    },
    /// Removes the last map, when nothing refers to it. It is applied after every other edit, so the edits of the
    /// map and of what refers to it are in place before the check.
    RemoveMap {
        map: usize,
    },
    /// One map note of `Data MD2` (numbers 0 to 18; a number just past the last adds a note): its ten marks of (icon,
    /// column, row), the section's start, land and cell size, a picture or a text number, a picture's size, and its words.
    MapNote {
        note: usize,
        marks: [[i16; 3]; 10],
        start_x: i16,
        start_y: i16,
        level: i16,
        picture: i16,
        icon_size: i16,
        show: i16,
        bottom: i16,
        right: i16,
        text: String,
    },
    /// The label the Maps and Notes menu shows for note `note` (1 to 19): the one before the party has the note
    /// (`STR#` -101), or the one after (`STR#` -102).
    NoteLabel {
        note: usize,
        identified: bool,
        text: String,
    },
    /// One entry of the calendar in `Data TD3`; a slot just past the last adds an entry.
    CalendarEntry {
        slot: usize,
        day: i16,
        interval: i16,
        chance: i16,
        story: i16,
        map: i16,
        region: i16,
        x: i16,
        y: i16,
        item: i16,
        flag: i16,
        place: i16,
    },
}

/// One style run of a scrolling text: from character `start` on, text is drawn in this font.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct StyleRun {
    pub start: u32,
    pub height: i16,
    pub ascent: i16,
    pub font: i16,
    pub face: u8,
    pub size: i16,
    pub color: [u16; 3],
}

impl Edit {
    pub fn identity(&self) -> String {
        match self {
            Self::MonsterNoDrops { id } => format!("monster-drops:{id:08}"),
            Self::EventActivation { map, x, y, .. } => {
                format!("event-activation:{map:02}:{x:02}:{y:02}")
            }
            Self::ChoiceLabel { id, choice, .. } => format!("choice-label:{id:08}:{choice}"),
            Self::TypedLabel { id, index, .. } => format!("typed-label:{id:08}:{index}"),
            Self::ItemField {
                index, field, slot, ..
            } => format!("item-field:{index:04}:{field:?}:{slot:02}"),
            Self::ItemDescription { index, .. } => format!("item-description:{index:04}"),
            Self::ChoicePrompt { id, .. } => format!("choice-prompt:{id:08}"),
            Self::StageScript { id, .. } => format!("stage-script:{id:08}"),
            Self::WalkingTarget { id, .. } => format!("walking-target:{id:08}"),
            Self::WalkingRemove { id } => {
                format!("walking-location:{:02}:{:02}", id / 100, id % 100)
            }
            Self::BattleExtra { id, .. } => format!("battle-extra:{id:08}"),
            Self::BattlePopulation { id, .. } => format!("battle-population:{id:08}"),
            Self::BattleSetting {
                id, field, index, ..
            } => format!("battle-setting:{id:08}:{field:?}:{index:02}"),
            Self::SelectedBattleExtra { id, .. } => format!("battle-extra:{id:08}"),
            Self::MonsterTurnStory { id, .. } => format!("monster-turn-story:{id:08}"),
            Self::MonsterRetreatThreshold { id, .. } => {
                format!("monster-retreat-threshold:{id:08}")
            }
            Self::MonsterDeathStory { id, .. } => format!("monster-death-story:{id:08}"),
            Self::MonsterSpellSlots { id, .. } => format!("monster-spell-slots:{id:08}"),
            Self::MonsterStats { id, .. } => format!("monster-stats:{id:08}"),
            Self::Reward { id, .. } => format!("reward:{id:08}"),
            Self::ExtraWord { record, index, .. } => format!("step~word:{record:05}:{index}"),
            Self::ExtraRow { record, .. } => format!("step~row:{record:05}"),
            Self::ExtraIndependent {
                family,
                id,
                branch,
                slot,
            } => format!("step~independent:{}:{id:08}:{branch}:{slot}", family.key()),
            Self::RewardItem { id, slot, .. } => format!("reward-item:{id:08}:{slot:02}"),
            Self::WalkingLocation { map, slot, .. } => {
                format!("walking-location:{map:02}:{slot:02}")
            }
            Self::WalkingChance { id, .. } => format!("walking-chance:{id:08}"),
            Self::Region { map, slot, .. } => format!("region:{map:02}:{slot:02}"),
            Self::MapLook { map, .. } => format!("map-look:{map:02}"),
            Self::ShopStock { shop, slot, .. } => format!("shop-stock:{shop:02}:{slot:04}"),
            Self::ShopPrice { shop, .. } => format!("shop-price:{shop:02}"),
            Self::MonsterDescription { id, .. } => format!("monster-description:{id:08}"),
            Self::MonsterImport { id, .. } => format!("monster-0-import:{id:08}"),
            Self::MonsterField {
                id, field, index, ..
            } => format!("monster-field:{id:08}:{field:?}:{index:02}"),
            Self::EncounterCondition {
                family,
                id,
                field,
                index,
                ..
            } => format!("condition:{}:{id:08}:{field:?}:{index:02}", family.key()),
            Self::ScriptStep {
                family,
                id,
                branch,
                slot,
                ..
            } => format!("step:{}:{id:08}:{branch}:{slot}", family.key()),
            Self::Message { id, .. } => format!("message:{id:08}"),
            Self::StageName { id, .. } => format!("stage-name:{id:08}"),
            Self::StageStart { id, .. } => format!("stage-start:{id:08}"),
            Self::Opening { .. } => "opening".into(),
            Self::Floor { map, x, y, .. } => format!("floor:{map:02}:{x:02}:{y:02}"),
            Self::QuietMap { map } => format!("quiet-map:{map:02}"),
            Self::DisableStage { id } => format!("stage-name:{id:08}"),
            Self::ClearStageScript { id } => format!("stage-script:{id:08}"),
            // Named to be applied before the calendar entries, so that an entry the author writes replaces the template's switch-off.
            Self::DisableSchedule => "calendar-disable".into(),
            Self::ResourceChange {
                resource_type, id, ..
            } => {
                format!("resource:{resource_type}:{id}")
            }
            Self::ScrollText { id, .. } | Self::ScrollTextRemove { id } => {
                format!("scroll-text:{id}")
            }
            Self::ItemName { index, .. } => format!("item-name:{index:04}"),
            Self::CalendarEntry { slot, .. } => format!("calendar-entry:{slot:04}"),
            Self::MapObject { map, x, y, .. } => format!("object:{map:02}:{x:02}:{y:02}"),
            Self::AddMap { map, .. } => format!("add-map:{map:02}"),
            // A tilde sorts after every letter, so the removal is the last edit applied.
            Self::RemoveMap { map } => format!("~remove-map:{map:02}"),
            Self::MapNote { note, .. } => format!("map-note:{note:02}"),
            Self::NoteLabel {
                note, identified, ..
            } => format!("note-label:{note:02}:{}", u8::from(*identified)),
        }
    }

    pub fn path(&self) -> &'static str {
        match self {
            Self::MonsterNoDrops { .. } => "Data MD",
            Self::EventActivation { .. } => "Data LD",
            Self::ChoiceLabel { .. } | Self::ChoicePrompt { .. } => "Data ED",
            Self::TypedLabel { .. } => "Data ED2",
            Self::ItemField { .. } => "Data NI",
            Self::ItemDescription { .. } => "Data NI Des",
            Self::StageScript { .. } => "Data Mission",
            Self::WalkingTarget { .. } | Self::WalkingRemove { .. } => "Data DD",
            Self::BattleExtra { .. } | Self::SelectedBattleExtra { .. } => "Data EDCD",
            Self::BattlePopulation { .. } | Self::BattleSetting { .. } => "Data BD",
            Self::MonsterStats { .. }
            | Self::MonsterTurnStory { .. }
            | Self::MonsterRetreatThreshold { .. }
            | Self::MonsterDeathStory { .. }
            | Self::MonsterSpellSlots { .. } => "Data MD",
            Self::Reward { .. } | Self::RewardItem { .. } => "Data TD",
            Self::ExtraWord { .. } | Self::ExtraRow { .. } => "Data EDCD",
            Self::ExtraIndependent { family, .. } => family.path(),
            Self::WalkingLocation { .. } | Self::WalkingChance { .. } => "Data DD",
            Self::Region { .. } | Self::MapLook { .. } => "Data RD",
            Self::ShopStock { .. } | Self::ShopPrice { .. } => "Data SD",
            Self::MonsterField { .. } | Self::MonsterImport { .. } => "Data MD",
            Self::MonsterDescription { .. } => "Data DES",
            Self::EncounterCondition { family, .. } => family.path(),
            Self::ScriptStep { family, .. } => family.path(),
            Self::Message { .. } => "Data SD2",
            Self::StageName { .. }
            | Self::StageStart { .. }
            | Self::DisableStage { .. }
            | Self::ClearStageScript { .. } => "Data Mission",
            Self::Opening { .. } => "Data CS",
            Self::Floor { .. }
            | Self::MapObject { .. }
            | Self::AddMap { .. }
            | Self::RemoveMap { .. } => "Data LD",
            Self::QuietMap { .. } => "Data DD",
            Self::DisableSchedule | Self::CalendarEntry { .. } => "Data TD3",
            Self::MapNote { .. } => "Data MD2",
            Self::ResourceChange { .. }
            | Self::ScrollText { .. }
            | Self::ScrollTextRemove { .. }
            | Self::NoteLabel { .. }
            | Self::ItemName { .. } => "Scenario.rsrc",
        }
    }
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ScriptFamily {
    Walking,
    Story,
    Menu,
    Typed,
}
impl ScriptFamily {
    pub fn key(self) -> &'static str {
        match self {
            Self::Walking => "walking",
            Self::Story => "story",
            Self::Menu => "menu",
            Self::Typed => "typed",
        }
    }
    pub fn path(self) -> &'static str {
        match self {
            Self::Walking => "Data DD",
            Self::Story => "Data ED3",
            Self::Menu => "Data ED",
            Self::Typed => "Data ED2",
        }
    }
    pub fn stride(self) -> usize {
        match self {
            Self::Walking | Self::Story => 42,
            Self::Menu => 426,
            Self::Typed => 516,
        }
    }
}

pub type Files = BTreeMap<String, Vec<u8>>;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RecordFamily {
    Message,
    Choice,
    Story,
    BattleExtra,
    Battle,
    Monster,
    Reward,
}
impl RecordFamily {
    pub fn path(self) -> &'static str {
        match self {
            Self::Message => "Data SD2",
            Self::Choice => "Data ED",
            Self::Story => "Data ED3",
            Self::BattleExtra => "Data EDCD",
            Self::Battle => "Data BD",
            Self::Monster => "Data MD",
            Self::Reward => "Data TD",
        }
    }
    pub fn stride(self) -> usize {
        match self {
            Self::Message => 256,
            Self::Choice => 426,
            Self::Story => 42,
            Self::BattleExtra => 10,
            Self::Battle => 1372,
            Self::Monster => 288,
            Self::Reward => 88,
        }
    }
    pub fn limit(self) -> usize {
        if self == Self::Monster { 256 } else { 32768 }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Allocation {
    pub family: RecordFamily,
    pub seed: usize,
    pub id: usize,
}

/// The fields of a battle record after its grid.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BattleSettingField {
    BeforeMessage,
    AfterMessage,
    SquadX,
    SquadY,
    RoundScript,
    Distance,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BattleUnit {
    pub x: usize,
    pub y: usize,
    pub monster: i16,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConditionField {
    ChoiceSelector,
    PhysicalSelector,
    RequiredAction,
    SpellCriterion,
    SpellSelector,
    ItemCriterion,
    ItemSelector,
    PasswordSelector,
    Attempts,
    Dialogue,
    CanBackOut,
}
