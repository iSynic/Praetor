//! Read-only native battle population and monster definitions, never a runtime preview.
use crate::{Files, Result, span, text, word};
use serde_json::{Value, json};
pub fn path(monsters: bool) -> (&'static str, usize) {
    if monsters {
        ("Data MD", 288)
    } else {
        ("Data BD", 1372)
    }
}
pub fn name(row: &[u8]) -> String {
    text::decode(&row[219..219 + usize::from(row[218]).min(29)])
}
pub fn catalogue(files: &Files, monsters: bool, offset: usize, query: &str) -> Result<Value> {
    let (path, stride) = path(monsters);
    let b = files.get(path).ok_or("missing combat table")?;
    let query = query.to_lowercase();
    let rows = b
        .chunks_exact(stride)
        .enumerate()
        .map(|(id, row)| {
            if monsters {
                json!({"id":id,"name":name(row),"icon":i16::from_be_bytes([row[80], row[81]])})
            } else {
                json!({"id":id,"name":format!("Battle {id}")})
            }
        })
        .filter(|v| {
            format!("{} {}", v["id"], v["name"])
                .to_lowercase()
                .contains(&query)
        })
        .collect::<Vec<_>>();
    Ok(
        json!({"total":rows.len(),"offset":offset,"rows":rows.into_iter().skip(offset).take(128).collect::<Vec<_>>(),"trailing_bytes":b.len()%stride}),
    )
}
pub fn record(files: &Files, monsters: bool, id: usize) -> Result<Value> {
    let (path, stride) = path(monsters);
    let b = files.get(path).ok_or("missing combat table")?;
    let row = span(
        b,
        id.checked_mul(stride).ok_or("record index overflow")?,
        stride,
    )?;
    let mut fields = serde_json::Map::new();
    let layout: &[(&str, usize)] = if monsters {
        &[
            ("Level", 0),
            ("Base stamina", 2),
            ("Speed", 4),
            ("Movement / round", 6),
            ("Faction", 14),
            ("Death script", 96),
        ]
    } else {
        &[
            ("Before message", 1352),
            ("After message", 1354),
            ("Squad start X", 1356),
            ("Squad start Y", 1358),
        ]
    };
    for (label, at) in layout {
        fields.insert((*label).into(), json!(word(row, *at)?));
    }
    if monsters {
        fields.insert("Name".into(), json!(name(row)));
    } else {
        fields.insert("Distance".into(), json!(row[1370] as i8));
    }
    let mut result = json!({"id":id,"file":path,"status":"read_only","fields":fields,"raw_hex":row.iter().map(|b|format!("{b:02x}")).collect::<String>()});
    if !monsters {
        let word_at = |at: usize| i64::from(i16::from_be_bytes([row[at], row[at + 1]]));
        let mut settings = vec![
            json!({"field":"before_message","index":0,"label":"Opening message (0 none)","value":word_at(1352),"minimum":0,"maximum":32767}),
            json!({"field":"after_message","index":0,"label":"Win message (0 none)","value":word_at(1354),"minimum":0,"maximum":32767}),
            json!({"field":"squad_x","index":0,"label":"Squad column","value":word_at(1356),"minimum":0,"maximum":25}),
            json!({"field":"squad_y","index":0,"label":"Squad row","value":word_at(1358),"minimum":0,"maximum":25}),
        ];
        for slot in 0..5 {
            settings.push(json!({"field":"round_script","index":slot,"label":format!("Round story {} (0 none)", slot + 1),"value":word_at(1360 + slot * 2),"minimum":0,"maximum":32767}));
        }
        settings.push(json!({"field":"distance","index":0,"label":"Starting distance","value":i64::from(row[1370] as i8),"minimum":-128,"maximum":127}));
        result["settings"] = json!(settings);
        let mut cells = Vec::new();
        let mut actors = Vec::new();
        for x in 0..26 {
            for y in 0..26 {
                let value = word(row, (x * 26 + y) * 2)?;
                cells.push(value);
                if value != 0 {
                    let mid = usize::from(value.unsigned_abs());
                    let label = files
                        .get("Data MD")
                        .and_then(|b| b.get(mid * 288..(mid + 1) * 288))
                        .map(name);
                    actors.push(json!({"x":x,"y":y,"monster":value,"name":label}));
                }
            }
        }
        result["cells"] = json!(cells);
        result["actors"] = json!(actors);
        result["note"] = json!(
            "26×26 native population layout, x*26+y; signed monster IDs retained. Actual tactical terrain and randomized placement require the original runtime."
        );
    }
    Ok(result)
}
