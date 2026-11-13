//! Bounded authoring projections, independent of UI and storage.
use crate::authoring::row;
use crate::{Files, Project, RecordFamily as R, Result, text, word};
use serde_json::{Value, json};
pub fn inspect(files: &Files, family: R, id: usize) -> Result<Value> {
    let b = row(files, family, id)?;
    let mut v = json!({"family":family,"id":id,"template_derived":true});
    match family {
        R::Message => {
            let length = usize::from(b[0]);
            v["text"] = json!(text::decode(&b[1..1 + length]));
        }
        R::Choice => {
            v["prompt"] = json!(word(b, 104)?);
            v["labels"] = json!(
                (0..4)
                    .map(|i| {
                        let at = 106 + i * 80;
                        text::decode(&b[at + 1..at + 1 + usize::from(b[at]).min(79)])
                    })
                    .collect::<Vec<_>>()
            );
            v["selectors"] = json!(&b[96..100]);
            v["retained_header_hex"] = json!(
                b[100..104]
                    .iter()
                    .map(|v| format!("{v:02x}"))
                    .collect::<String>()
            );
        }
        R::BattleExtra => {
            for (name, at) in [
                ("minimum", 0),
                ("maximum", 2),
                ("sound", 4),
                ("message", 6),
                ("cleanup_mode", 8),
            ] {
                v[name] = json!(word(b, at)?);
            }
        }
        R::Reward => {
            v["experience"] = json!(i32::from_be_bytes(b[80..84].try_into().unwrap()));
            v["credits"] = json!(i32::from_be_bytes(b[84..88].try_into().unwrap()));
            v["items"] = json!(
                (0..20)
                    .map(|slot| json!({"slot":slot,"item":word(b, slot * 2).unwrap(),"level":word(b, 40 + slot * 2).unwrap()}))
                    .collect::<Vec<_>>()
            );
        }
        R::Monster => {
            v["name"] = json!(crate::combat_view::name(b));
            v["loot_items"] = json!(
                (0..6)
                    .map(|i| word(b, 0x26 + i * 2).unwrap())
                    .collect::<Vec<_>>()
            );
            v["cash_drop_bound"] = json!(word(b, 0x3a)?);
            let (words, bytes) = crate::monsters::description(files, id);
            v["description"] = json!(words);
            v["description_bytes"] = json!(bytes);
            v["fields"] = crate::monsters::projection(b);
            v["behaviour"] = json!({"run_percent":word(b, 0x44)?,"turn_chance":word(b, 0x5c)?,"turn_story":word(b, 0x5e)?,"death_story":word(b, 0x60)?});
            v["spells"] = json!(
                (0..10)
                    .map(|i| word(b, 0x12 + i * 2).unwrap())
                    .collect::<Vec<_>>()
            );
            for (name, at) in [("level", 0), ("stamina", 2), ("speed", 4), ("movement", 6)] {
                v[name] = json!(word(b, at)?);
            }
        }
        R::Battle => {
            v["units"] = json!(
                (0..26)
                    .flat_map(|x| (0..26).map(move |y| (x, y)))
                    .filter_map(|(x, y)| {
                        let monster = word(b, (x * 26 + y) * 2).ok()?;
                        if monster == 0 {
                            None
                        } else {
                            Some(json!({"x":x,"y":y,"monster":monster}))
                        }
                    })
                    .collect::<Vec<_>>()
            );
        }
        R::Story => {
            v["program"] = crate::scripts::program(files, crate::ScriptFamily::Story, id, 0)?;
        }
    }
    Ok(v)
}
pub fn catalogue(project: &Project, source: &Files) -> Result<Value> {
    let files = crate::apply(project, source)?;
    let families=[R::Message,R::Choice,R::Story,R::BattleExtra,R::Battle,R::Monster,R::Reward].map(|family|json!({"family":family,"file":family.path(),"count":files.get(family.path()).map_or(0,|b|b.len()/family.stride()),"imported_count":source.get(family.path()).map_or(0,|b|b.len()/family.stride()),"supported_limit":family.limit(),"trailing_bytes":files.get(family.path()).map_or(0,|b|b.len()%family.stride())}));
    Ok(json!({"families":families,"allocations":project.allocations}))
}

/// What each reward row pays and gives: experience and credits (a negative figure is a random one up to its
/// size) and the items that are set, each with its level.
pub fn rewards(files: &Files) -> Result<Value> {
    let bytes = files.get("Data TD").ok_or("missing Data TD")?;
    let word = |row: &[u8], at: usize| i64::from(i16::from_be_bytes([row[at], row[at + 1]]));
    let long = |row: &[u8], at: usize| {
        i64::from(i32::from_be_bytes([
            row[at],
            row[at + 1],
            row[at + 2],
            row[at + 3],
        ]))
    };
    let rows = bytes
        .as_chunks::<88>()
        .0
        .iter()
        .enumerate()
        .map(|(id, row)| {
            let items: Vec<Value> = (0..20)
                .filter(|slot| word(row, slot * 2) > 0)
                .map(|slot| json!({"slot":slot,"item":word(row, slot * 2),"level":word(row, 40 + slot * 2)}))
                .collect();
            json!({"id":id,"experience":long(row, 80),"credits":long(row, 84),"items":items})
        })
        .collect::<Vec<_>>();
    Ok(json!({"rows":rows}))
}
