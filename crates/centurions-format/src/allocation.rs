//! Append complete template-derived rows before retained table tails.
use crate::authoring::{error, row};
use crate::{Allocation, Files, Project, RecordFamily as R, Result};
pub fn materialize(project: &Project, source: &Files) -> Result<Files> {
    let mut files = source.clone();
    for allocation in &project.allocations {
        let f = allocation.family;
        let stride = f.stride();
        let mut seed = row(source, f, allocation.seed)?.to_vec();
        match f {
            R::Choice => {
                seed[..100].fill(0);
            }
            R::Story => {
                seed[8..40].fill(0);
            }
            R::Reward => {
                seed[..80].fill(0);
            }
            _ => {}
        }
        let bytes = files.get_mut(f.path()).ok_or("missing allocation table")?;
        let count = bytes.len() / stride;
        if count >= f.limit() || allocation.id != count {
            return Err(error(
                f.path(),
                allocation.id,
                "allocation",
                "nonsequential ID or supported record capacity exhausted",
            ));
        }
        bytes.splice(count * stride..count * stride, seed);
        if f == R::Monster {
            // The new monster takes its own copy of the seed's description, in a slot that follows the others.
            use crate::monsters::DESCRIPTION;
            let words = files.entry("Data DES".into()).or_default();
            let from = allocation.seed * DESCRIPTION;
            let copy = words
                .get(from..from + DESCRIPTION)
                .map_or(vec![0; DESCRIPTION], <[u8]>::to_vec);
            if words.len() < (count + 1) * DESCRIPTION {
                words.resize((count + 1) * DESCRIPTION, 0);
            }
            words[count * DESCRIPTION..(count + 1) * DESCRIPTION].copy_from_slice(&copy);
        }
    }
    Ok(files)
}
pub fn allocate(
    project: &Project,
    source: &Files,
    family: R,
    seed: usize,
) -> Result<(Project, usize)> {
    let effective = crate::apply(project, source)?;
    row(source, family, seed)?;
    let id = effective
        .get(family.path())
        .ok_or("missing allocation table")?
        .len()
        / family.stride();
    if id >= family.limit() {
        return Err(error(
            family.path(),
            id,
            "allocation",
            "supported record capacity exhausted",
        ));
    }
    let mut next = project.clone();
    next.version = crate::VERSION;
    next.allocations.push(Allocation { family, seed, id });
    crate::apply(&next, source)?;
    Ok((next, id))
}
