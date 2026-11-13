use crate::{Files, MAP_BYTES, long, span, text, word};
use serde_json::{Value, json};

pub fn project(files: &Files) -> Value {
    let mut warnings = vec![
        "Runtime evidence is separate from format validation; match a receipt to the exact export."
            .to_string(),
    ];
    let mut tables = Vec::new();
    for (name, stride) in [
        ("Data LD", MAP_BYTES),
        ("Data DD", 4200),
        ("Data RD", 644),
        ("Data Mission", 464),
        ("Data ED3", 42),
        ("Data SD2", 256),
        ("Data ED", 426),
        ("Data ED2", 516),
        ("Data EDCD", 10),
        ("Data TD3", 40),
        ("Data BD", 1372),
        ("Data MD", 288),
        ("Data TD", 88),
        ("Data SD", 3002),
        ("Data NI", 150),
    ] {
        if let Some(bytes) = files.get(name) {
            let tail = bytes.len() % stride;
            if tail != 0 {
                warnings.push(format!("{name}: {tail} trailing bytes retained"));
            }
            tables.push(json!({"file":name,"stride":stride,"complete_records":bytes.len()/stride,"trailing_bytes":tail}));
        } else {
            warnings.push(format!(
                "{name}: absent; unchanged export remains available"
            ));
        }
    }
    let maps = files.get("Data LD").map_or(0, |b| b.len() / MAP_BYTES);
    if !(1..=20).contains(&maps) {
        warnings.push("Data LD: native loader requires 1..20 complete maps".into());
    }
    for (name, stride) in [("Data DD", 4200), ("Data RD", 644)] {
        if files.get(name).is_some_and(|b| b.len() < maps * stride) {
            warnings.push(format!("{name}: fewer rows than Data LD maps"));
        }
    }
    let stages = files
        .get("Data Mission")
        .map(|bytes| {
            bytes
                .as_chunks::<464>().0.iter()
                .enumerate()
                .filter(|(_, row)| row[6] > 0)
                .map(|(id, row)| {
                    json!({
            "id":id,"name":pascal(&row[6..262]),"x":word(row,0).ok(),
            "y":word(row,2).ok(),"map":word(row,4).ok(),"start_script":word(row,262).ok()
        })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let opening = files.get("Data CS").map(|bytes| {
        json!({
            "map":long(bytes,8).ok(),"x":long(bytes,12).ok(),"y":long(bytes,16).ok()
        })
    });
    let sizes: serde_json::Map<String, Value> = ["Data NI", "Data NI Des", "Data NID", "Data SD"]
        .iter()
        .filter_map(|name| {
            files
                .get(*name)
                .map(|b| ((*name).to_string(), json!(b.len())))
        })
        .collect();
    json!({"tables":tables,"maps":maps,"stages":stages,"opening":opening,"preserved_sizes":sizes,
        "warnings":warnings,"authorable":crate::AUTHORABLE,
        "unresolved":"Unlisted fields and unsupported opcode steps are inspection/preservation only"})
}

pub fn message(files: &Files, id: usize) -> crate::Result<Value> {
    let bytes = files.get("Data SD2").ok_or("missing Data SD2")?;
    let at = id.checked_mul(256).ok_or("record index overflow")?;
    let row = span(bytes, at, 256)?;
    Ok(json!({"id":id,"text":pascal(row),"status":"authorable"}))
}

pub fn story(files: &Files, id: usize) -> crate::Result<Value> {
    let bytes = files.get("Data ED3").ok_or("missing Data ED3")?;
    let at = id.checked_mul(42).ok_or("record index overflow")?;
    let row = span(bytes, at, 42)?;
    let actions = (0..8)
        .map(|slot| {
            json!({
                "slot":slot,"opcode":word(row,8+slot*2).ok(),"operand":word(row,24+slot*2).ok(),
                "semantics":"unresolved in editor"
            })
        })
        .collect::<Vec<_>>();
    Ok(json!({"id":id,"actions":actions,"status":"inspect_only","dispatch_stamp":row[41]}))
}

/// Bytes of the floor, and of the object layer after it.
const CELLS_BYTES: usize = crate::CELLS * 2;

pub fn map(files: &Files, id: usize) -> crate::Result<Value> {
    let bytes = files.get("Data LD").ok_or("missing Data LD")?;
    let at = id.checked_mul(MAP_BYTES).ok_or("map index overflow")?;
    let row = span(bytes, at, MAP_BYTES)?;
    let floor = row[..16200]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|v| i16::from_be_bytes(*v))
        .collect::<Vec<_>>();
    let objects = row[CELLS_BYTES..CELLS_BYTES * 2]
        .as_chunks::<2>()
        .0
        .iter()
        .map(|v| i16::from_be_bytes(*v))
        .collect::<Vec<_>>();
    let mut result = crate::scripts::map_triggers(files, id);
    result["objects"] = json!(objects);
    result["id"] = json!(id);
    result["side"] = json!(90);
    result["indexing"] = json!("x*90+y");
    result["floor"] = json!(floor);
    result["object_and_event_layers"] = json!(
        "the object layer is authored; only bounded walking activation cells of the event layer are"
    );
    Ok(result)
}

fn pascal(row: &[u8]) -> String {
    let len = row.first().copied().unwrap_or(0) as usize;
    text::decode(row.get(1..(len + 1).min(row.len())).unwrap_or_default())
}
