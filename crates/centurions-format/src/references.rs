//! Diagnostics follow authored links only; preserved inherited programs are never normalized.
use crate::{Edit, Files, Project, Result, ScriptFamily as S, span, word};
use serde_json::{Value, json};

fn record<'a>(
    files: &'a Files,
    path: &str,
    id: usize,
    stride: usize,
    field: &str,
) -> Result<&'a [u8]> {
    let at = id.checked_mul(stride).ok_or("record index overflow")?;
    files
        .get(path)
        .and_then(|b| b.get(at..at.checked_add(stride)?))
        .ok_or_else(|| format!("{path} record {id} field {field}: dangling record reference"))
}
fn battle(files: &Files, id: usize) -> Result<()> {
    let b = record(files, "Data BD", id, 1372, "battle")?;
    let mut count = 0;
    for (cell, pair) in b[..1352].as_chunks::<2>().0.iter().enumerate() {
        let mid = i16::from_be_bytes(*pair);
        if mid == 0 {
            continue;
        }
        count += 1;
        let m = record(
            files,
            "Data MD",
            usize::from(mid.unsigned_abs()),
            288,
            "population",
        )?;
        if !(0..=127).contains(&word(m, 0)?) {
            return Err(format!(
                "Data BD record {id} field population ({},{}): Data MD record {} has unsupported level {}",
                cell / 26,
                cell % 26,
                mid.unsigned_abs(),
                word(m, 0)?
            ));
        }
    }
    if !(1..=100).contains(&count) {
        return Err(format!(
            "Data BD record {id} field population: ordinary battle requires 1..100 enabled actors, found {count}"
        ));
    }
    if !(0..26).contains(&word(b, 1356)?) || !(0..26).contains(&word(b, 1358)?) {
        return Err(format!(
            "Data BD record {id} field squad_start: outside native 26x26 layout"
        ));
    }
    Ok(())
}
fn battle_extra(files: &Files, id: usize, selected: bool) -> Result<()> {
    let b = record(files, "Data EDCD", id, 10, "battle_extra")?;
    let low = word(b, 0)?;
    let high = word(b, 2)?;
    if low < 0 && high == 0 {
        battle(files, usize::from(low.unsigned_abs()))?;
    } else {
        if low < 0 || high < 0 || (high != 0 && high < low) {
            return Err(format!(
                "Data EDCD record {id} field battle_range: unsupported ordinary battle bounds"
            ));
        }
        let high = if high == 0 { low } else { high };
        // Native battle IDs are i16; validate every possible selection, not just an endpoint.
        for battle_id in low..=high {
            battle(files, battle_id as usize)?;
        }
    }
    let mode = word(b, 8)?;
    if selected {
        if mode != 0 {
            record(
                files,
                "Data TD",
                usize::try_from(mode).map_err(|_| "negative selected-battle treasure")?,
                88,
                "selected_battle_treasure",
            )?;
        }
        return Ok(());
    }
    if !matches!(mode, 0 | 5) {
        return Err(format!(
            "Data EDCD record {id} field cleanup_mode: unsupported ordinary-battle cleanup mode {mode}; this field does not load a reward record"
        ));
    }
    Ok(())
}
pub(crate) fn monster_spell_slots(id: usize, slots: &[i16; 10]) -> Result<()> {
    for (slot, spell) in slots.iter().enumerate() {
        if *spell > 1100
            && (!(1..=4).contains(&(spell / 1000))
                || !(1..=7).contains(&(spell % 1000 / 100))
                || !(1..=7).contains(&(spell % 100)))
        {
            return Err(format!(
                "Data MD record {id} field spell_slot {slot}: invalid original spell reference {spell}"
            ));
        }
    }
    Ok(())
}

pub fn diagnostics(project: &Project, files: &Files) -> Vec<Value> {
    let mut issues = Vec::new();
    let mut pending = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for edit in &project.edits {
        if let Edit::MonsterDeathStory { story, .. } = edit
            && *story != 0
        {
            pending.push((S::Story, *story as usize, 0, true));
        }
        if let Edit::MonsterTurnStory { chance, story, .. } = edit
            && *chance != 0
        {
            pending.push((S::Story, *story as usize, 0, true));
        }
        if let Edit::StageScript { story, .. } = edit
            && *story > 0
        {
            pending.push((S::Story, *story as usize, 0, true));
        }
        if let Edit::Region {
            scripts,
            script_chances,
            ..
        } = edit
        {
            for (story, chance) in scripts.iter().zip(script_chances) {
                if *story > 0 && *chance != 0 {
                    pending.push((S::Story, *story as usize, 0, true));
                }
            }
        }
        if let Edit::ScriptStep {
            family, id, branch, ..
        } = edit
        {
            pending.push((*family, *id, *branch, false));
        }
    }
    while let Some((family, id, branch, linked)) = pending.pop() {
        if !seen.insert((family.key(), id, branch, linked)) {
            continue;
        }
        let result = (|| -> Result<()> {
            let b = record(files, family.path(), id, family.stride(), "program")?;
            for slot in 0..8 {
                let allocated = project
                    .allocations
                    .iter()
                    .any(|a| a.family.path() == family.path() && a.id == id);
                let edited=project.edits.iter().any(|e|matches!(e,Edit::ScriptStep {family:f,id:i,branch:b,slot:s,..} if *f==family&&*i==id&&*b==branch&&usize::from(*s)==slot));
                if !allocated && !edited && !linked {
                    continue;
                }

                let (op, arg) = if matches!(family, S::Walking | S::Story) {
                    (word(b, 8 + slot * 2)?, word(b, 24 + slot * 2)?)
                } else {
                    (
                        i16::from(b[usize::from(branch) * 8 + slot] as i8),
                        word(b, 32 + usize::from(branch) * 16 + slot * 2)?,
                    )
                };
                let location = format!(
                    "{} record {id} branch {branch} step {}",
                    family.path(),
                    slot + 1
                );
                match op {
                    0 | 9 | 24 => {}
                    14 if (1..=6).contains(&arg) => {}
                    100 if arg == 0 => {}
                    1 => {
                        record(
                            files,
                            "Data SD2",
                            usize::from(arg.unsigned_abs()),
                            256,
                            "message",
                        )
                        .map_err(|e| format!("{location}: {e}"))?;
                    }
                    2 | 48 => {
                        battle_extra(
                            files,
                            usize::try_from(arg)
                                .map_err(|_| format!("{location}: negative battle EXTRA"))?,
                            op == 48,
                        )
                        .map_err(|e| format!("{location}: {e}"))?;
                    }
                    10 => {
                        record(
                            files,
                            "Data TD",
                            usize::try_from(arg)
                                .map_err(|_| format!("{location}: negative reward"))?,
                            88,
                            "reward",
                        )?;
                    }
                    4 => {
                        let target = usize::try_from(arg)
                            .map_err(|_| format!("{location}: negative choice"))?;
                        let choice = record(files, "Data ED", target, 426, "choice")?;
                        let mut enabled = 0;
                        for index in 0..4 {
                            let selector = choice[96 + index];
                            if selector == 0 {
                                continue;
                            }
                            if selector > 4 || choice[106 + index * 80] == 0 {
                                return Err(format!(
                                    "Data ED record {target} field choice {}: enabled choice needs a label and selector 1..4",
                                    index + 1
                                ));
                            }
                            enabled += 1;
                            pending.push((S::Menu, target, selector - 1, true));
                        }
                        if enabled == 0 {
                            return Err(format!(
                                "Data ED record {target} field choices: no enabled labelled choices"
                            ));
                        }
                    }
                    5 => {
                        record(
                            files,
                            "Data ED2",
                            usize::try_from(arg)
                                .map_err(|_| format!("{location}: negative typed encounter"))?,
                            516,
                            "typed",
                        )?;
                    }
                    39 => {
                        pending.push((
                            S::Story,
                            usize::try_from(arg)
                                .map_err(|_| format!("{location}: negative story"))?,
                            0,
                            true,
                        ));
                    }
                    110 => {
                        let stage =
                            usize::from(arg.unsigned_abs())
                                .checked_sub(1)
                                .ok_or_else(|| {
                                    format!("{location}: stage number must be signed one-based")
                                })?;
                        let m = record(files, "Data Mission", stage, 464, "transition")?;
                        if stage >= 20 || m[6] == 0 {
                            return Err(format!(
                                "Data Mission record {stage} field name: transition targets an inactive/unsupported stage"
                            ));
                        }
                        let story = word(m, 262)?;
                        if story != 0 {
                            pending.push((
                                S::Story,
                                usize::try_from(story).map_err(|_| "negative start script")?,
                                0,
                                true,
                            ));
                        }
                    }
                    _ => {
                        // An unrelated inherited step may be preserved beside an edited step.
                        // New linked choice/story programs must still remain inspectable.
                        issues.push(json!({"severity":"warning","file":family.path(),"record":id,"field":format!("branch {branch} step {}",slot+1),"message":format!("opcode {op} remains inherited and runtime-unverified")}));
                    }
                }
            }
            Ok(())
        })();
        if let Err(message) = result {
            issues.push(json!({"severity":"error","file":family.path(),"record":id,"field":"linked program","message":message}));
        }
    }
    for allocation in &project.allocations {
        if allocation.family == crate::RecordFamily::Monster {
            let description = files
                .get("Data DES")
                .and_then(|b| span(b, allocation.id * 256, 256).ok());
            if description.is_none() {
                issues.push(json!({"severity":"error","file":"Data MD","record":allocation.id,"field":"description","message":"New monster needs a retained matching Data DES description slot; no unknown companion bytes will be synthesized"}));
            }
        }
    }
    issues
}
pub fn validate(project: &Project, files: &Files) -> Result<()> {
    let errors = diagnostics(project, files)
        .into_iter()
        .filter(|d| d["severity"] == "error")
        .map(|d| d["message"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("\n"))
    }
}
