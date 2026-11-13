//! A shop's stock in Data SD: a thousand signed item ids, a thousand byte
//! quantities and a price percent, in a 3002-byte record. A slot is stocked
//! when its quantity is not zero; the item id of an unstocked slot is never
//! read. The original's evidence is in docs/original-evidence/data-sd.md.
use crate::{Edit, Files, Result, ownership, span};
use serde_json::{Value, json};

pub const ROW: usize = 3002;
pub const SLOTS: usize = 1000;
const QUANTITIES: usize = SLOTS * 2;
const PRICE: usize = QUANTITIES + SLOTS;

fn row(files: &Files, shop: usize) -> Result<&[u8]> {
    let at = shop.checked_mul(ROW).ok_or("record index overflow")?;
    span(files.get("Data SD").ok_or("missing Data SD")?, at, ROW)
}

/// The shop as the editor shows it: its price percent and every slot that holds something.
pub fn view(files: &Files, shop: usize) -> Result<Value> {
    let b = row(files, shop)?;
    let stock: Vec<Value> = (0..SLOTS)
        .filter_map(|slot| {
            let item = i16::from_be_bytes([b[slot * 2], b[slot * 2 + 1]]);
            let quantity = b[QUANTITIES + slot];
            (quantity != 0).then(|| json!({"slot":slot,"item":item,"quantity":quantity}))
        })
        .collect();
    let count = files.get("Data SD").map_or(0, |b| b.len() / ROW);
    Ok(
        json!({"id":shop,"count":count,"slots":SLOTS,"price_percent":i16::from_be_bytes([b[PRICE],b[PRICE+1]]),"stock":stock}),
    )
}

/// The stocked scenario items whose price scaled by the shop's percent passes what the
/// game can hold (SANE turns the scaled cost into a long integer, 2,147,483,647 at most):
/// (shop, slot, item, price). Stock items below 800 keep their prices in the
/// installation, which this does not read.
pub fn price_overflows(files: &Files) -> Vec<(usize, usize, i16, i64)> {
    let shops = files.get("Data SD").map_or(0, |b| b.len() / ROW);
    let mut found = vec![];
    for shop in 0..shops {
        let Ok(b) = row(files, shop) else { continue };
        let percent = i64::from(i16::from_be_bytes([b[PRICE], b[PRICE + 1]]));
        for slot in 0..SLOTS {
            if b[QUANTITIES + slot] == 0 {
                continue;
            }
            let item = i16::from_be_bytes([b[slot * 2], b[slot * 2 + 1]]);
            let Some(price) = crate::items::price(files, item) else {
                continue;
            };
            if price.abs() * percent.abs() / 100 > i64::from(i32::MAX) {
                found.push((shop, slot, item, price));
            }
        }
    }
    found
}

#[allow(clippy::single_range_in_vec_init, clippy::type_complexity)] // Each element declares an owned byte span.
pub fn patch(files: &mut Files, edit: &Edit) -> Result<()> {
    let (shop, owned, writes): (usize, Vec<std::ops::Range<usize>>, Vec<(usize, Vec<u8>)>) =
        match edit {
            Edit::ShopStock {
                shop,
                slot,
                item,
                quantity,
            } => {
                if *slot >= SLOTS {
                    return Err("a shop holds slots 0..999".into());
                }
                if !(0..=255).contains(quantity) {
                    return Err("a shop slot holds 0..255 of an item".into());
                }
                if *quantity != 0 && !(1..1000).contains(item) {
                    return Err("a stocked item is one of the item ids 1..999".into());
                }
                // A slot that holds nothing keeps no item id, as when the game sells the last one.
                let item = if *quantity == 0 { &0 } else { item };
                (
                    *shop,
                    vec![
                        slot * 2..slot * 2 + 2,
                        QUANTITIES + slot..QUANTITIES + slot + 1,
                    ],
                    vec![
                        (slot * 2, item.to_be_bytes().to_vec()),
                        (QUANTITIES + slot, vec![*quantity as u8]),
                    ],
                )
            }
            Edit::ShopPrice { shop, percent } => (
                *shop,
                vec![PRICE..PRICE + 2],
                vec![(PRICE, percent.to_be_bytes().to_vec())],
            ),
            _ => return Err("not a shop edit".into()),
        };
    row(files, shop)?;
    let base = shop * ROW;
    let bytes = files.get_mut("Data SD").ok_or("missing Data SD")?;
    let before = bytes.clone();
    for (at, value) in writes {
        bytes[base + at..base + at + value.len()].copy_from_slice(&value);
    }
    let owned: Vec<_> = owned
        .into_iter()
        .map(|r| base + r.start..base + r.end)
        .collect();
    if ownership::inspect(&before, bytes, &owned).unowned_changes != 0 {
        return Err("unowned shop edit".into());
    }
    Ok(())
}
