//! Read-only navigation over the effective files: search, uses, flow and problems.
//! Nothing here changes a project; every answer is computed from the bytes.
use crate::{
    Files, MAP_BYTES, Project, Result, ScriptFamily as S, combat_view, inspect, references,
    scripts, word,
};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub(crate) const FAMILIES: [S; 4] = [S::Walking, S::Story, S::Menu, S::Typed];
const FLOW_NODES: usize = 40;
const USE_ROWS: usize = 500;

/// The name of a program family as a record kind.
fn kind_of(family: S) -> &'static str {
    match family {
        S::Walking => "walking",
        S::Story => "story",
        S::Menu => "choice",
        S::Typed => "typed",
    }
}

fn table_of(family: S) -> &'static str {
    match family {
        S::Walking => "Walking",
        S::Story => "Stories",
        S::Menu => "Choices",
        S::Typed => "Typed",
    }
}

fn maps(files: &Files) -> usize {
    files.get("Data LD").map_or(0, |b| b.len() / MAP_BYTES)
}

/// Rows a program table holds; walking rows past the maps are inspect-only.
fn rows(files: &Files, family: S) -> usize {
    files
        .get(family.path())
        .map_or(0, |b| b.len() / family.stride())
}

pub(crate) fn live_rows(files: &Files, family: S) -> usize {
    let count = rows(files, family);
    if family != S::Walking {
        return count;
    }
    let maps = maps(files);
    if (1..=20).contains(&maps) {
        count.min(maps * 100)
    } else {
        0
    }
}

pub(crate) struct Step {
    pub(crate) branch: u8,
    pub(crate) slot: u8,
    pub(crate) op: i16,
    pub(crate) operand: i16,
}

pub(crate) fn steps(files: &Files, family: S, id: usize) -> Vec<Step> {
    let Some(bytes) = files.get(family.path()) else {
        return vec![];
    };
    let branches = if matches!(family, S::Menu | S::Typed) {
        4
    } else {
        1
    };
    let mut out = vec![];
    for branch in 0..branches {
        for slot in 0..8u8 {
            let Ok((at, arg, width)) = scripts::offsets(family, id, branch, slot) else {
                continue;
            };
            let op = if width == 1 {
                bytes.get(at).map(|v| i16::from(*v as i8))
            } else {
                word(bytes, at).ok()
            };
            if let (Some(op), Some(operand)) = (op, word(bytes, arg).ok()) {
                out.push(Step {
                    branch,
                    slot,
                    op,
                    operand,
                });
            }
        }
    }
    out
}

/// What an operand names, when the operation's operand names a record.
fn target(op: i16, operand: i16) -> Option<(&'static str, i64)> {
    let value = i64::from(operand);
    match op {
        1 => Some(("message", value.abs())),
        2 | 48 if value >= 0 => Some(("battle_extra", value)),
        10 if value >= 0 => Some(("reward", value)),
        4 if value >= 0 => Some(("choice", value)),
        5 if value >= 0 => Some(("typed", value)),
        39 if value >= 0 => Some(("story", value)),
        110 if value != 0 => Some(("stage", value.abs() - 1)),
        9 => Some(("sound", value)),
        _ => None,
    }
}

/// Everything a step points at: what its ID names, and what the words of its Extra Codes row hand the scene to.
fn step_targets(files: &Files, op: i16, operand: i16) -> Vec<(&'static str, i64)> {
    let mut found: Vec<(&'static str, i64)> = target(op, operand).into_iter().collect();
    if crate::script_codes::uses_extra(op) && operand >= 0 {
        found.push(("extra", i64::from(operand)));
        if crate::script_codes::has_companion(op) {
            found.push(("extra_second", i64::from(operand) + 1));
        }
    }
    if scripts::supported(op)
        && crate::script_codes::uses_extra(op)
        && operand >= 0
        && let Some(row) = files
            .get("Data EDCD")
            .and_then(|b| b.get(operand as usize * 10..operand as usize * 10 + 10))
    {
        let words: Vec<i16> = row
            .chunks(2)
            .map(|w| i16::from_be_bytes([w[0], w[1]]))
            .collect();
        for hit in crate::script_codes::row_targets(op, &words) {
            if !found.contains(&hit) {
                found.push(hit);
            }
        }
    }
    found
}

fn describe(op: i16, operand: i16) -> String {
    match op {
        0 => "Empty".into(),
        1 => format!("Message {}", operand.unsigned_abs()),
        2 => format!("Battle extra {operand}"),
        48 => format!("Selected battle {operand}"),
        4 => format!("Choice {operand}"),
        5 => format!("Typed {operand}"),
        9 => format!("Sound {operand}"),
        10 => format!("Reward {operand}"),
        39 => format!("Story {operand}"),
        110 => format!("Stage transition {operand}"),
        _ => format!("{} {operand}", scripts::label(op)),
    }
}

fn snippet(files: &Files, id: usize) -> Option<String> {
    let text = inspect::message(files, id).ok()?;
    let text = text["text"].as_str()?.replace('\n', " ");
    Some(text.chars().take(40).collect())
}

fn monster_name(files: &Files, id: usize) -> Option<String> {
    files
        .get("Data MD")
        .and_then(|b| b.get(id * 288..(id + 1) * 288))
        .map(combat_view::name)
}

fn battle_cells(files: &Files, id: usize) -> Vec<i16> {
    let Some(row) = files
        .get("Data BD")
        .and_then(|b| b.get(id * 1372..(id + 1) * 1372))
    else {
        return vec![];
    };
    row[..1352]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| i16::from_be_bytes(*pair))
        .filter(|value| *value != 0)
        .collect()
}

fn battle_title(files: &Files, id: usize) -> (String, usize) {
    let cells = battle_cells(files, id);
    let first = cells
        .first()
        .and_then(|value| monster_name(files, usize::from(value.unsigned_abs())))
        .unwrap_or_else(|| format!("Battle {id}"));
    let title = if cells.len() > 1 {
        format!("{first} +{}", cells.len() - 1)
    } else {
        first
    };
    (title, cells.len())
}

fn extra_range(files: &Files, id: usize) -> Option<(i64, i64)> {
    let b = files.get("Data EDCD")?.get(id * 10..id * 10 + 10)?;
    let (low, high) = (i64::from(word(b, 0).ok()?), i64::from(word(b, 2).ok()?));
    if low < 0 && high == 0 {
        Some((-low, -low))
    } else {
        Some((low, if high == 0 { low } else { high }))
    }
}

/// Every step, record and field that names a target.
pub fn uses(files: &Files, kind: &str, id: i64) -> Result<Value> {
    let mut found: Vec<Value> = vec![];
    for family in FAMILIES {
        for record in 0..live_rows(files, family) {
            let all = steps(files, family, record);
            for step in &all {
                if !step_targets(files, step.op, step.operand).contains(&(kind_target(kind), id)) {
                    continue;
                }
                let before = all
                    .iter()
                    .find(|other| {
                        other.branch == step.branch && step.slot > 0 && other.slot == step.slot - 1
                    })
                    .map(|other| describe(other.op, other.operand));
                let mut row = json!({"table":table_of(family),"kind":kind_of(family),"id":record,"branch":step.branch,"slot":step.slot,"opcode":step.op,"operand":step.operand,"name":describe(step.op,step.operand),"before":before});
                if family == S::Walking {
                    row["map"] = json!(record / 100);
                }
                found.push(row);
            }
        }
    }
    let stage_rows = files.get("Data Mission").map_or(0, |b| b.len() / 464);
    if kind == "story" {
        for stage in 0..stage_rows {
            let b = &files["Data Mission"][stage * 464..(stage + 1) * 464];
            if b[6] != 0 && i64::from(word(b, 262)?) == id {
                found.push(json!({"table":"Stages","kind":"stage","id":stage,"field":"start script","name":"Start script"}));
            }
        }
        for monster in 0..files.get("Data MD").map_or(0, |b| b.len() / 288) {
            let b = &files["Data MD"][monster * 288..(monster + 1) * 288];
            if i64::from(word(b, 96)?) == id {
                found.push(json!({"table":"Monsters","kind":"monster","id":monster,"field":"death script","name":"Death script"}));
            }
        }
    }
    if kind == "walking"
        && let Some(row) = files
            .get("Data DD")
            .and_then(|b| b.get(id as usize * 42..id as usize * 42 + 42))
        && (id as usize) < live_rows(files, S::Walking)
    {
        let key = i32::from_be_bytes(row[..4].try_into().unwrap());
        if key >= 0 {
            found.push(json!({"table":"Map cells","kind":"cell","id":id,"map":id/100,"x":key%100,"y":key/100,"name":format!("Placed at {}, {}", key%100, key/100)}));
        }
    }
    if kind == "message" {
        for (family, at) in [(S::Menu, 104), (S::Typed, 154)] {
            for record in 0..rows(files, family) {
                let b = &files[family.path()][record * family.stride()..];
                if i64::from(word(b, at)?).abs() == id {
                    found.push(json!({"table":table_of(family),"kind":kind_of(family),"id":record,"field":"prompt","name":"Prompt message"}));
                }
            }
        }
    }
    if kind == "battle" {
        for extra in 0..files.get("Data EDCD").map_or(0, |b| b.len() / 10) {
            if let Some((low, high)) = extra_range(files, extra)
                && (low..=high).contains(&id)
            {
                found.push(json!({"table":"Battle extras","kind":"battle_extra","id":extra,"field":"battle","name":format!("Battles {low} to {high}")}));
            }
        }
    }
    if kind == "monster" {
        for battle in 0..files.get("Data BD").map_or(0, |b| b.len() / 1372) {
            let count = battle_cells(files, battle)
                .iter()
                .filter(|value| i64::from(value.unsigned_abs()) == id)
                .count();
            if count > 0 {
                found.push(json!({"table":"Battles","kind":"battle","id":battle,"field":"population","name":format!("{count} in the population")}));
            }
        }
    }
    if kind == "item" {
        for shop in 0..files.get("Data SD").map_or(0, |b| b.len() / 3002) {
            let b = &files["Data SD"][shop * 3002..(shop + 1) * 3002];
            let held: u32 = (0..1000)
                .filter(|slot| {
                    b[2000 + slot] != 0
                        && i64::from(i16::from_be_bytes([b[slot * 2], b[slot * 2 + 1]])) == id
                })
                .map(|slot| u32::from(b[2000 + slot]))
                .sum();
            if held > 0 {
                found.push(json!({"table":"Shops","kind":"shop","id":shop,"field":"stock","name":format!("Stocks {held}")}));
            }
        }
        for monster in 0..files.get("Data MD").map_or(0, |b| b.len() / 288) {
            let b = &files["Data MD"][monster * 288..(monster + 1) * 288];
            if (0..6).any(|slot| i64::from(word(b, 0x26 + slot * 2).unwrap_or(0)) == id) {
                found.push(json!({"table":"Monsters","kind":"monster","id":monster,"field":"loot","name":"Carries it"}));
            }
        }
        for record in 0..rows(files, S::Typed) {
            let b = &files["Data ED2"][record * 516..(record + 1) * 516];
            for index in 0..5 {
                if i64::from(word(b, 136 + index * 2).unwrap_or(0)) == id {
                    found.push(json!({"table":"Typed","kind":"typed","id":record,"field":"item criterion","name":format!("Item criterion {}", index + 1)}));
                }
            }
        }
    }
    let records: BTreeSet<String> = found
        .iter()
        .map(|row| format!("{}:{}", row["kind"], row["id"]))
        .collect();
    let tables: BTreeSet<String> = found
        .iter()
        .map(|row| row["table"].as_str().unwrap_or("").to_string())
        .collect();
    let total = found.len();
    found.truncate(USE_ROWS);
    Ok(
        json!({"kind":kind,"id":id,"total":total,"records":records.len(),"tables":tables.len(),"truncated":total>USE_ROWS,"rows":found}),
    )
}

fn kind_target(kind: &str) -> &'static str {
    match kind {
        "message" => "message",
        "battle_extra" => "battle_extra",
        "reward" => "reward",
        "choice" => "choice",
        "typed" => "typed",
        "story" => "story",
        "stage" => "stage",
        "sound" => "sound",
        "item" => "item",
        "extra" => "extra",
        // Kinds a step cannot name never match a step.
        _ => "",
    }
}

fn key(kind: &str, id: usize) -> String {
    format!("{kind}:{id}")
}

/// The calls a program makes: choice branches, replacing stories and typed encounters.
pub fn flow(files: &Files, family: S, id: usize) -> Result<Value> {
    if id >= rows(files, family) {
        return Err(format!("{} {id} is past the table", kind_of(family)));
    }
    let mut queue = VecDeque::from([(family, id)]);
    let mut seen = BTreeSet::from([key(kind_of(family), id)]);
    let mut nodes = vec![];
    let mut edges = vec![];
    let mut truncated = false;
    while let Some((family, id)) = queue.pop_front() {
        let from = key(kind_of(family), id);
        let mut branches = vec![];
        let program = files.get(family.path()).and_then(|b| {
            let at = id * family.stride();
            b.get(at..at + family.stride())
        });
        let all = steps(files, family, id);
        let count = if matches!(family, S::Menu | S::Typed) {
            4
        } else {
            1
        };
        for branch in 0..count {
            let (enabled, label) = match (family, program) {
                (S::Menu, Some(row)) => {
                    let at = 106 + usize::from(branch) * 80;
                    let length = usize::from(row[at]).min(79);
                    (
                        row[96 + usize::from(branch)] != 0,
                        crate::text::decode(&row[at + 1..at + 1 + length]),
                    )
                }
                _ => (true, String::new()),
            };
            if !enabled {
                continue;
            }
            let mut listed = vec![];
            for step in all.iter().filter(|s| s.branch == branch && s.op != 0) {
                let mut item = json!({"slot":step.slot,"opcode":step.op,"operand":step.operand,"name":describe(step.op,step.operand),"authorable":scripts::supported(step.op)});
                if step.op == 1 {
                    item["text"] = json!(snippet(files, usize::from(step.operand.unsigned_abs())));
                }
                for (kind, target_id) in step_targets(files, step.op, step.operand)
                    .into_iter()
                    .filter(|(kind, _)| matches!(*kind, "story" | "choice" | "typed"))
                {
                    let to = key(kind, target_id as usize);
                    let child = match kind {
                        "story" => S::Story,
                        "choice" => S::Menu,
                        _ => S::Typed,
                    };
                    if (target_id as usize) < rows(files, child) {
                        if seen.contains(&to) || seen.len() < FLOW_NODES {
                            if seen.insert(to.clone()) {
                                queue.push_back((child, target_id as usize));
                            }
                            edges.push(
                                json!({"from":from,"branch":branch,"slot":step.slot,"to":to}),
                            );
                            item["target"] = json!(to);
                        } else {
                            truncated = true;
                        }
                    }
                }
                listed.push(item);
            }
            branches.push(json!({"branch":branch,"label":label,"steps":listed}));
        }
        nodes.push(
            json!({"key":from,"kind":kind_of(family),"id":id,"branches":branches,"title":format!("{} {id}", table_title(family))}),
        );
    }
    let ends = nodes
        .iter()
        .filter(|node| !edges.iter().any(|edge| edge["from"] == node["key"]))
        .count();
    Ok(
        json!({"root":key(kind_of(family),id),"nodes":nodes,"edges":edges,"records":nodes.len(),"ends":ends,"truncated":truncated}),
    )
}

fn table_title(family: S) -> &'static str {
    match family {
        S::Walking => "Walking trigger",
        S::Story => "Story",
        S::Menu => "Choice",
        S::Typed => "Typed encounter",
    }
}

/// The words around the first place `needle` (lower case) occurs in `text`, on one line.
fn words_around(text: &str, needle: &str) -> String {
    let lower = text.to_lowercase();
    let at = lower
        .find(needle)
        .map_or(0, |at| lower[..at].chars().count());
    let flat: String = text
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    let start = at.saturating_sub(40);
    let words: String = flat.chars().skip(start).take(120).collect();
    format!("{}{}", if start > 0 { "… " } else { "" }, words.trim())
}

/// Records matching a query by id, name or text, grouped by kind.
pub fn search(files: &Files, query: &str, families: &[String], limit: usize) -> Result<Value> {
    let needle = query.trim().to_lowercase();
    let number = needle
        .trim_start_matches(|c: char| c.is_ascii_alphabetic())
        .parse::<usize>()
        .ok();
    let wanted = |name: &str| families.is_empty() || families.iter().any(|f| f == name);
    let mut groups = vec![];
    let mut group = |name: &str, matches: Vec<Value>| {
        groups.push(
            json!({"family":name,"total":matches.len(),"rows":matches.into_iter().take(limit).collect::<Vec<_>>()}),
        );
    };
    if wanted("monsters") {
        let count = files.get("Data MD").map_or(0, |b| b.len() / 288);
        let matches = (0..count)
            .filter_map(|id| {
                let name = monster_name(files, id)?;
                let hit = !needle.is_empty() && name.to_lowercase().contains(&needle)
                    || needle.parse::<usize>() == Ok(id);
                hit.then(|| json!({"id":id,"title":name}))
            })
            .collect();
        group("monsters", matches);
    }
    if wanted("battles") {
        let count = files.get("Data BD").map_or(0, |b| b.len() / 1372);
        let matches = (0..count)
            .filter_map(|id| {
                let (title, actors) = battle_title(files, id);
                let named = !needle.is_empty()
                    && battle_cells(files, id).iter().any(|value| {
                        monster_name(files, usize::from(value.unsigned_abs()))
                            .is_some_and(|name| name.to_lowercase().contains(&needle))
                    });
                let by_id = needle.starts_with('b') && number == Some(id)
                    || needle.parse::<usize>() == Ok(id);
                (named || by_id)
                    .then(|| json!({"id":id,"title":title,"detail":format!("{actors} monsters")}))
            })
            .collect();
        group("battles", matches);
    }
    if wanted("messages") {
        let count = files.get("Data SD2").map_or(0, |b| b.len() / 256);
        let matches = (0..count)
            .filter_map(|id| {
                let text = inspect::message(files, id).ok()?["text"]
                    .as_str()?
                    .to_string();
                let hit = !needle.is_empty() && text.to_lowercase().contains(&needle)
                    || needle.parse::<usize>() == Ok(id)
                    || needle.starts_with('m') && number == Some(id);
                hit.then(|| json!({"id":id,"title":text.replace('\n'," ").chars().take(120).collect::<String>()}))
            })
            .collect();
        group("messages", matches);
    }
    if wanted("texts") {
        let matches = crate::resources::scroll_text_words(files)
            .unwrap_or_default()
            .into_iter()
            .filter_map(|(id, words)| {
                let hit = !needle.is_empty() && words.to_lowercase().contains(&needle)
                    || needle.parse::<i16>() == Ok(id);
                hit.then(
                    || json!({"id":id,"title":words_around(&words, &needle),"detail":"Scrolling text"}),
                )
            })
            .collect();
        group("texts", matches);
    }
    if wanted("triggers") {
        let matches = if let Some(number) = number.filter(|_| needle.starts_with('w')) {
            (number < live_rows(files, S::Walking))
                .then(|| json!({"id":number,"title":format!("W{number}"),"detail":format!("Map {}", number / 100)}))
                .into_iter()
                .collect()
        } else {
            vec![]
        };
        group("triggers", matches);
    }
    if wanted("stories") {
        let matches = if let Some(number) =
            number.filter(|_| needle.starts_with('s') || needle.parse::<usize>().is_ok())
        {
            (number < rows(files, S::Story))
                .then(|| {
                    let used = steps(files, S::Story, number).iter().filter(|s| s.op != 0).count();
                    json!({"id":number,"title":format!("Story {number}"),"detail":format!("{used} steps")})
                })
                .into_iter()
                .collect()
        } else {
            vec![]
        };
        group("stories", matches);
    }
    let total: u64 = groups
        .iter()
        .map(|g| g["total"].as_u64().unwrap_or(0))
        .sum();
    Ok(json!({"query":query,"total":total,"groups":groups}))
}

/// Every step that uses the code, as (program, record, step, ID).
pub fn steps_of(files: &Files, op: i16) -> Vec<(S, usize, u8, i16)> {
    let mut found = vec![];
    for family in FAMILIES {
        for record in 0..live_rows(files, family) {
            for step in steps(files, family, record) {
                if step.op == op {
                    found.push((family, record, step.slot, step.operand));
                }
            }
        }
    }
    found
}

/// The name of a program as Problems and the lists write it.
pub fn program_label(family: S, record: usize, slot: u8) -> String {
    format!("{} {record} : {}", table_title(family), slot + 1)
}

/// The steps whose ID or Extra Codes row holds what the code cannot take, or names a row that is not there.
pub fn script_findings(files: &Files) -> Vec<Value> {
    let mut found = vec![];
    for family in FAMILIES {
        for record in 0..live_rows(files, family) {
            for step in steps(files, family, record) {
                if step.op == 0 || !crate::script_codes::authorable(step.op) {
                    continue;
                }
                let mut problem =
                    crate::script_codes::validate_id(files, step.op, step.operand).err();
                if problem.is_none()
                    && crate::script_codes::uses_extra(step.op)
                    && step.operand >= 0
                    && let Some(row) = files.get("Data EDCD").and_then(|b| {
                        b.get(step.operand as usize * 10..step.operand as usize * 10 + 10)
                    })
                {
                    let words: Vec<i16> = row
                        .chunks(2)
                        .map(|w| i16::from_be_bytes([w[0], w[1]]))
                        .collect();
                    if words.iter().any(|w| *w != 0) {
                        problem = crate::script_codes::validate_row(files, step.op, &words).err();
                    }
                }
                if let Some(message) = problem {
                    found.push((family, record, step.slot, step.op, message));
                } else {
                    let words: Option<Vec<i16>> = (crate::script_codes::uses_extra(step.op)
                        && step.operand >= 0)
                        .then(|| {
                            files
                                .get("Data EDCD")?
                                .get(step.operand as usize * 10..step.operand as usize * 10 + 10)
                        })
                        .flatten()
                        .map(|row| {
                            row.chunks(2)
                                .map(|w| i16::from_be_bytes([w[0], w[1]]))
                                .collect()
                        });
                    for message in crate::script_codes::soft_problems(
                        files,
                        step.op,
                        step.operand,
                        words.as_deref(),
                    ) {
                        found.push((
                            family,
                            record,
                            step.slot,
                            step.op,
                            format!(
                                "{message} (the game handles it, but the manual advises against it)"
                            ),
                        ));
                    }
                }
            }
        }
    }
    found
        .into_iter()
        .map(|(family, record, slot, op, message)| {
            json!({"severity":"warning","message":format!("{} {record} : {} · {message}", table_title(family), slot + 1),"count":null,"unit":null,
                "where":{"kind":kind_of(family),"id":record,"slot":slot,"label":format!("{} {record} : {}", table_title(family), slot + 1)},"code":op})
        })
        .collect()
}

/// The project's findings, each with where to go, and the steps by operation.
pub fn problems(project: &Project, files: &Files) -> Result<Value> {
    let mut findings = vec![];
    let summary = inspect::project(files);
    for warning in summary["warnings"].as_array().into_iter().flatten() {
        let text = warning.as_str().unwrap_or_default();
        let (file, bytes) = match text.split_once(": ") {
            Some((file, rest)) if rest.ends_with("trailing bytes retained") => (
                file.to_string(),
                rest.split(' ').next().and_then(|n| n.parse::<u64>().ok()),
            ),
            Some((file, _)) if file.starts_with("Data ") => (file.to_string(), None),
            _ => ("Project".to_string(), None),
        };
        findings.push(json!({"severity":"warning","message":text,"count":bytes,"unit":bytes.map(|_| "bytes"),"where":{"kind":"file","label":file}}));
    }
    for issue in references::diagnostics(project, files) {
        let severity = if issue["severity"] == "error" {
            "error"
        } else {
            "warning"
        };
        findings.push(json!({"severity":severity,"message":format!("{}: {}", issue["field"].as_str().unwrap_or(""), issue["message"].as_str().unwrap_or("")),"count":null,"unit":null,"where":{"kind":"record","label":format!("{} · {}", issue["file"].as_str().unwrap_or(""), issue["record"]),"file":issue["file"],"id":issue["record"]}}));
    }
    let mut script = script_findings(files);
    if script.len() > 100 {
        let more = script.len() - 100;
        script.truncate(100);
        script.push(json!({"severity":"warning","message":format!("{more} more steps hold values their code does not take"),"count":more,"unit":"steps","where":{"kind":"file","label":"Programs"}}));
    }
    findings.extend(script);
    // Regions that run past the map or whose battles cannot be drawn.
    let battles = files.get("Data BD").map_or(0, |b| b.len() / 1372);
    for map in 0..files
        .get("Data RD")
        .map_or(0, |b| b.len() / 644)
        .min(maps(files))
    {
        let region_row = &files["Data RD"][map * 644..(map + 1) * 644];
        for slot in 0..20 {
            let value = |n: usize| word(region_row, n).unwrap_or(0);
            let (fy, fx, ly, lx) = (
                value(slot * 8),
                value(slot * 8 + 2),
                value(slot * 8 + 4),
                value(slot * 8 + 6),
            );
            if [fy, fx, ly, lx].iter().all(|v| *v == 0) {
                continue;
            }
            let (min, max) = (value(200 + slot * 4), value(202 + slot * 4));
            let message = if lx >= 90 || ly >= 90 || fx < 0 || fy < 0 {
                Some(format!(
                    "Region R{slot} runs past the map edge (last column {lx}, last row {ly})"
                ))
            } else if fx > lx || fy > ly {
                Some(format!("Region R{slot} ends before it begins"))
            } else if min != 0 && (max < min || usize::try_from(max).is_ok_and(|m| m >= battles)) {
                Some(format!(
                    "Region R{slot} draws battles {min} to {max}, past what the scenario holds"
                ))
            } else {
                None
            };
            if let Some(message) = message {
                findings.push(json!({"severity":"warning","message":message,"count":null,"unit":null,"where":{"kind":"region","map":map,"slot":slot,"label":format!("Map {map} · R{slot}")}}));
            }
        }
    }
    findings.extend(crate::maps::findings(files));
    findings.extend(crate::calendar::findings(files));
    findings.extend(crate::notes::findings(files));
    for (shop, slot, item, price) in crate::shops::price_overflows(files) {
        findings.push(json!({"severity":"warning","message":format!("Shop {shop} slot {slot}: item {item} costs {price} and the shop's percent scales it past what the game can hold"),"count":null,"unit":null,"where":{"kind":"record","label":format!("Data SD · shop {shop}"),"file":"Data SD","id":shop}}));
    }
    // What the editor reads but does not edit.
    let mut by_opcode: BTreeMap<i16, (u64, BTreeSet<String>)> = BTreeMap::new();
    let mut preserved_steps = 0u64;
    let mut noop_steps = 0u64;
    let mut noop_first: Option<(S, usize, u8)> = None;
    let mut preserved_records = BTreeSet::new();
    let mut used_steps = 0u64;
    let mut walking_past: BTreeMap<usize, u64> = BTreeMap::new();
    let live = live_rows(files, S::Walking);
    for family in FAMILIES {
        for record in 0..rows(files, family) {
            for step in steps(files, family, record) {
                if step.op == 0 {
                    continue;
                }
                used_steps += 1;
                let entry = by_opcode.entry(step.op).or_default();
                entry.0 += 1;
                entry.1.insert(key(kind_of(family), record));
                if family == S::Walking && record >= live {
                    *walking_past.entry(record / 100).or_default() += 1;
                    preserved_steps += 1;
                    preserved_records.insert(key("walking", record));
                    continue;
                }
                if !scripts::supported(step.op) {
                    preserved_steps += 1;
                    preserved_records.insert(key(kind_of(family), record));
                } else if crate::script_codes::is_noop(step.op) {
                    noop_steps += 1;
                    noop_first.get_or_insert((family, record, step.slot));
                }
            }
        }
    }
    let readonly = |message: String, count: u64, unit: &str, place: Value| json!({"severity":"readonly","message":message,"count":count,"unit":unit,"where":place});
    if preserved_steps > 0 {
        findings.push(readonly(
            "Steps use operations the editor preserves without editing".into(),
            preserved_steps,
            "steps",
            json!({"kind":"records","label":format!("{} records", preserved_records.len())}),
        ));
    }
    if let Some((family, record, slot)) = noop_first {
        findings.push(json!({"severity":"warning","message":"Steps use numbers that name no code; the game skips them and goes on","count":noop_steps,"unit":"steps",
            "where":{"kind":kind_of(family),"id":record,"slot":slot,"label":format!("{} {record} : {}", table_title(family), slot + 1)}}));
    }
    for (table, count) in &walking_past {
        findings.push(readonly(
            format!(
                "Walking table {table} is past the {} maps in Data LD; its rows are inspect-only",
                maps(files)
            ),
            *count,
            "steps",
            json!({"kind":"file","label":format!("Data DD · table {table}")}),
        ));
    }
    let count = |severity: &str| {
        findings
            .iter()
            .filter(|f| f["severity"] == severity)
            .count()
    };
    let counts =
        json!({"errors":count("error"),"warnings":count("warning"),"readonly":count("readonly")});
    let operations: Vec<Value> = by_opcode
        .iter()
        .map(|(op, (steps, records))| json!({"opcode":op,"steps":steps,"records":records.len()}))
        .collect();
    let preserved_ops = by_opcode
        .keys()
        .filter(|op| !scripts::supported(**op))
        .count();
    Ok(json!({
        "findings":findings,"counts":counts,"operations":operations,
        "steps":{"used":used_steps,"editable":used_steps-preserved_steps,"preserved":preserved_steps,"preserved_operations":preserved_ops},
        "checked":"Findings come from the preservation notices, the reference diagnostics and the steps the editor preserves; they are not runtime evidence."
    }))
}
