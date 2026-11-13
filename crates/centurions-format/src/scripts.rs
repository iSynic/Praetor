//! Centurions newland programs. Native source pins are in script-support.md.
use crate::{Files, Result, ScriptFamily, ownership, span, word};
use serde_json::{Value, json};

pub fn supported(op: i16) -> bool {
    crate::script_codes::authorable(op) || crate::script_codes::is_noop(op)
}
pub fn label(op: i16) -> String {
    match op {
        0 => "Empty / continue",
        1 => "Show message",
        2 => "Battle (EXTRA)",
        3 => "Question (EXTRA)",
        4 => "Choice encounter",
        5 => "Typed encounter",
        9 => "Play sound",
        10 => "Reward / treasure",
        14 => "Pick party members",
        24 => "End script",
        25 => "Persist event",
        39 => "Replace with story",
        45 => "Travel (EXTRA)",
        48 => "Selected battle (EXTRA)",
        100 => "Combat cleanup",
        110 => "Stage transition",
        _ => {
            return crate::script_codes::code(op)
                .filter(|c| c.authorable)
                .and_then(|c| c.label.clone())
                .unwrap_or_else(|| {
                    if crate::script_codes::is_noop(op) {
                        format!("Does nothing · number {op}")
                    } else {
                        format!("Opcode {op} · preserved")
                    }
                });
        }
    }
    .into()
}
pub fn catalogue() -> Value {
    let mut offered: Vec<_> = crate::script_codes::codes()
        .iter()
        .filter(|c| c.authorable)
        .collect();
    offered.sort_by_key(|c| (c.order.unwrap_or(1000 + i32::from(c.code)), c.code));
    json!(
        offered
            .iter()
            .map(|c| json!({"opcode":c.code,"name":label(c.code)}))
            .collect::<Vec<_>>()
    )
}

pub(crate) fn offsets(
    family: ScriptFamily,
    id: usize,
    branch: u8,
    slot: u8,
) -> Result<(usize, usize, usize)> {
    if slot >= 8 {
        return Err("step slot must be 0..7".into());
    }
    let base = id
        .checked_mul(family.stride())
        .ok_or("program index overflow")?;
    let s = usize::from(slot);
    let branch = usize::from(branch);
    let (op, arg, width) = match family {
        ScriptFamily::Walking | ScriptFamily::Story => {
            if branch != 0 {
                return Err("story/walking programs have one branch".into());
            }
            (8 + s * 2, 24 + s * 2, 2)
        }
        _ => {
            if branch >= 4 {
                return Err("encounter branch must be 0..3".into());
            }
            (branch * 8 + s, 32 + branch * 16 + s * 2, 1)
        }
    };
    Ok((
        base.checked_add(op).ok_or("step offset overflow")?,
        base.checked_add(arg).ok_or("step offset overflow")?,
        width,
    ))
}

pub fn program(files: &Files, family: ScriptFamily, id: usize, branch: u8) -> Result<Value> {
    let bytes = files.get(family.path()).ok_or("missing program table")?;
    let row = span(
        bytes,
        id.checked_mul(family.stride())
            .ok_or("program index overflow")?,
        family.stride(),
    )?;
    let walking_in_map = family != ScriptFamily::Walking
        || files.get("Data LD").is_some_and(|b| {
            let maps = b.len() / crate::MAP_BYTES;
            (1..=20).contains(&maps) && id < maps * 100
        });
    let mut steps = Vec::new();
    for slot in 0..8 {
        let (at, arg, width) = offsets(family, id, branch, slot)?;
        let op = if width == 1 {
            i16::from(bytes[at] as i8)
        } else {
            word(bytes, at)?
        };
        let operand = word(bytes, arg)?;
        steps.push(json!({"slot":slot,"opcode":op,"operand":operand,"name":label(op),"authorable":supported(op)&&walking_in_map&&crate::script_codes::id_shape_ok(op,operand)}));
    }
    let mut v = json!({"family":family,"id":id,"branch":branch,"steps":steps,"catalogue":catalogue(),"count":bytes.len()/family.stride(),"branches":if matches!(family,ScriptFamily::Menu|ScriptFamily::Typed){4}else{1}});
    v["conditions"] = crate::conditions::projection(files, family, id)?;
    match family {
        ScriptFamily::Walking | ScriptFamily::Story => {
            v["destination"] = json!({"map":row[4] as i8,"x":row[5] as i8,"y":row[6] as i8,"level":row[40],"stamp":row[41]});
            v["location_key"] = json!(i32::from_be_bytes(row[..4].try_into().unwrap()));
            v["chance"] = json!(row[7] as i8);
        }
        ScriptFamily::Menu => {
            v["dialogue"] = json!(word(row, 104)?);
            let at = 106 + usize::from(branch) * 80;
            v["label"] = json!(crate::text::decode(span(
                row,
                at + 1,
                usize::from(row[at]).min(79)
            )?));
            v["selector"] = json!(row[96 + usize::from(branch)] as i8);
        }
        ScriptFamily::Typed => {
            v["dialogue"] = json!(word(row, 154)?);
            v["labels"] = json!(
                (0..9)
                    .map(|n| {
                        let at = 156 + n * 40;
                        crate::text::decode(&row[at + 1..at + 1 + usize::from(row[at]).min(39)])
                    })
                    .collect::<Vec<_>>()
            );
            v["selectors"] = json!({"physical":row[96] as i8,"password":row[97] as i8,"attempts":row[152] as i8});
        }
    }
    Ok(v)
}

/// A program row as bytes, with what each span of it means. Only fields the
/// editor reads are named; every other byte is "Copied as recorded".
pub fn program_bytes(files: &Files, family: ScriptFamily, id: usize) -> Result<Value> {
    let bytes = files.get(family.path()).ok_or("missing program table")?;
    let stride = family.stride();
    let offset = id.checked_mul(stride).ok_or("program index overflow")?;
    let row = span(bytes, offset, stride)?;
    let mut spans: Vec<(usize, usize, &str, String)> = Vec::new();
    match family {
        ScriptFamily::Walking | ScriptFamily::Story => {
            let key = i32::from_be_bytes(row[..4].try_into().unwrap());
            spans.push((
                0,
                3,
                "key",
                format!(
                    "Key {key} · map {}, y {}, x {} (i32)",
                    key / 10000,
                    (key / 100) % 100,
                    key % 100
                ),
            ));
            spans.push((
                4,
                6,
                "placement",
                format!(
                    "Return map {}, x {}, y {}",
                    row[4] as i8, row[5] as i8, row[6] as i8
                ),
            ));
            spans.push((7, 7, "chance", format!("Chance {}", row[7] as i8)));
            spans.push((8, 23, "opcodes", "Eight opcodes (i16)".into()));
            spans.push((24, 39, "operands", "Eight operands (i16)".into()));
            spans.push((
                40,
                41,
                "preserved",
                "Level and stamp, copied as recorded".into(),
            ));
        }
        ScriptFamily::Menu | ScriptFamily::Typed => {
            spans.push((
                0,
                31,
                "opcodes",
                "Four branches of eight opcodes (i8)".into(),
            ));
            spans.push((
                32,
                95,
                "operands",
                "Four branches of eight operands (i16)".into(),
            ));
            if family == ScriptFamily::Menu {
                spans.push((96, 99, "selector", "Branch selectors (i8)".into()));
                spans.push((100, 103, "preserved", "Copied as recorded".into()));
                spans.push((
                    104,
                    105,
                    "dialogue",
                    format!("Prompt message {} (i16)", word(row, 104)?),
                ));
                spans.push((
                    106,
                    425,
                    "text",
                    "Four choice labels (80-byte Pascal strings)".into(),
                ));
            } else {
                spans.push((
                    96,
                    97,
                    "selector",
                    "Physical and password selectors (i8)".into(),
                ));
                spans.push((98, 151, "preserved", "Copied as recorded".into()));
                spans.push((152, 152, "selector", format!("Attempts {}", row[152] as i8)));
                spans.push((153, 153, "preserved", "Copied as recorded".into()));
                spans.push((
                    154,
                    155,
                    "dialogue",
                    format!("Prompt message {} (i16)", word(row, 154)?),
                ));
                spans.push((156, 515, "preserved", "Copied as recorded".into()));
            }
        }
    }
    Ok(
        json!({"family":family,"id":id,"path":family.path(),"offset":offset,"stride":stride,
        "bytes":row,"spans":spans.iter().map(|(from,to,kind,label)|json!({"from":from,"to":to,"kind":kind,"label":label})).collect::<Vec<_>>()}),
    )
}

#[allow(clippy::too_many_arguments)]
pub fn patch(
    files: &mut Files,
    family: ScriptFamily,
    id: usize,
    branch: u8,
    slot: u8,
    op: i16,
    arg: i16,
) -> Result<()> {
    let before_program = program(files, family, id, branch)?;
    let old = before_program["steps"][usize::from(slot.min(7))]["opcode"]
        .as_i64()
        .ok_or("missing slot")? as i16;
    if !before_program["steps"][usize::from(slot.min(7))]["authorable"]
        .as_bool()
        .unwrap_or(false)
        || !supported(old)
        || !supported(op)
    {
        return Err("unsupported operations are preserved and read-only".into());
    }
    crate::script_codes::validate_id(files, op, arg)?;
    let old_operand = before_program["steps"][usize::from(slot.min(7))]["operand"]
        .as_i64()
        .unwrap_or(0);
    if crate::script_codes::uses_extra(op) && (op != old || i64::from(arg) != old_operand) {
        // A step that takes a row must find words in it that its code reads.
        let at = usize::from(arg.unsigned_abs()) * 10;
        let row = span(files.get("Data EDCD").ok_or("missing Data EDCD")?, at, 10)?;
        let words: Vec<i16> = row
            .chunks(2)
            .map(|w| i16::from_be_bytes([w[0], w[1]]))
            .collect();
        // A row of zeros is a fresh one, filled in after the step names it.
        if words.iter().any(|w| *w != 0) {
            crate::script_codes::validate_row(files, op, &words)?;
        }
    }
    let (at, operand, width) = offsets(family, id, branch, slot)?;
    let bytes = files
        .get_mut(family.path())
        .ok_or("missing program table")?;
    let before = bytes.clone();
    if width == 1 {
        bytes[at] = i8::try_from(op).map_err(|_| "encounter opcode exceeds signed byte")? as u8;
    } else {
        bytes[at..at + 2].copy_from_slice(&op.to_be_bytes());
    }
    bytes[operand..operand + 2].copy_from_slice(&arg.to_be_bytes());
    if ownership::inspect(&before, bytes, &[at..at + width, operand..operand + 2]).unowned_changes
        != 0
    {
        return Err("unowned program edit".into());
    }
    Ok(())
}

pub fn map_triggers(files: &Files, map: usize) -> Value {
    let mut triggers = Vec::new();
    let mut regions = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    if map >= 20 {
        return json!({"triggers":triggers,"regions":regions});
    }
    if let Some(b) = files
        .get("Data DD")
        .and_then(|b| b.get(map * 4200..(map + 1) * 4200))
    {
        for (slot, row) in b.as_chunks::<42>().0.iter().enumerate() {
            let key = i32::from_be_bytes(row[..4].try_into().unwrap());
            if key >= 0 {
                let x = key % 100;
                let y = (key / 100) % 100;
                if x < 90 && y < 90 && key / 10000 == map as i32 {
                    let at = map * crate::MAP_BYTES + 32400 + (x as usize * 90 + y as usize) * 4;
                    let cell_flag = files.get("Data LD").and_then(|b| crate::long(b, at).ok());
                    let first = seen.insert(key);
                    triggers.push(json!({"family":"walking","id":map*100+slot,"slot":slot,"x":x,"y":y,"chance":row[7] as i8,"cell_flag":cell_flag,"shadowed":!first,"lookup_eligible":first&&(row[7] as i8)>0,"active":first&&(row[7] as i8)>0&&cell_flag.is_some_and(|v|v>0)}));
                }
            }
        }
    }
    if let Some(b) = files
        .get("Data RD")
        .and_then(|b| b.get(map * 644..(map + 1) * 644))
    {
        for slot in 0..20 {
            let values = (0..4)
                .map(|n| word(b, slot * 8 + n * 2).unwrap())
                .collect::<Vec<_>>();
            if values.iter().any(|v| *v != 0) {
                regions.push(json!({"slot":slot,"first_y":values[0],"first_x":values[1],"last_y":values[2],"last_x":values[3],"encounter_chance":word(b,160+slot*2).ok(),"battle_min":word(b,200+slot*4).ok(),"battle_max":word(b,202+slot*4).ok(),"scripts":(0..3).map(|n|word(b,280+slot*6+n*2).unwrap()).collect::<Vec<_>>(),"script_chances":(0..3).map(|n|word(b,400+slot*6+n*2).unwrap()).collect::<Vec<_>>(),"exclusive":b[524+slot]!=0,"avoid_chance":b[544+slot] as i8,"avoid_sound":word(b,564+slot*2).ok(),"avoid_dialogue":word(b,604+slot*2).ok()}));
            }
        }
    }
    let land = files
        .get("Data RD")
        .and_then(|b| b.get(map * 644..(map + 1) * 644))
        .map(|b| json!({"terrain":b[520],"light":b[522],"limits_sight":b[523]!=0}));
    json!({"triggers":triggers,"regions":regions,"land":land})
}
