//! Adapted from Providence owned_byte_diff.rs; see docs/provenance.json.
use serde::Serialize;
use std::ops::Range;

#[derive(Debug, Serialize)]
pub struct ByteDiff {
    pub exact: bool,
    pub changed_bytes: usize,
    pub unowned_changes: usize,
    pub unowned_sample: Vec<usize>,
}

/// Every byte outside explicit spans stays opaque, including record/file tails.
pub fn inspect(before: &[u8], after: &[u8], owned: &[Range<usize>]) -> ByteDiff {
    let mut report = ByteDiff {
        exact: before == after,
        changed_bytes: 0,
        unowned_changes: 0,
        unowned_sample: Vec::new(),
    };
    for at in 0..before.len().max(after.len()) {
        if before.get(at) == after.get(at) {
            continue;
        }
        report.changed_bytes += 1;
        if at >= before.len().min(after.len()) || !owned.iter().any(|r| r.contains(&at)) {
            report.unowned_changes += 1;
            if report.unowned_sample.len() < 16 {
                report.unowned_sample.push(at);
            }
        }
    }
    report
}
