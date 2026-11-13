//! Classic Macintosh resource forks: read one into its resources, change them, and write it back.
//!
//! A fork is a 256-byte header, the resources' data (each a length and its bytes), and a map of the
//! types, ids, names and attributes. Writing keeps the order of the data, the order of the types and of
//! the resources of each type, every name and attribute, and the header bytes the format does not use,
//! so a fork that only gains or loses a resource differs from the original only where it must.
use crate::Result;

const HEADER: usize = 256;
const MAP_HEAD: usize = 28;

/// One resource of a fork.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Resource {
    pub kind: [u8; 4],
    pub id: i16,
    pub attributes: u8,
    pub name: Option<Vec<u8>>,
    pub data: Vec<u8>,
    /// The four bytes of the reference that the format leaves to the system, kept as read.
    reserved: [u8; 4],
    /// Where its name lay in the name list it was read from; a name added since has `usize::MAX`.
    name_order: usize,
    /// Where its data lay in the fork it was read from; a resource added since has `usize::MAX`.
    order: usize,
}

/// The resources of a fork in the order of its map, with what the format keeps beside them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Fork {
    /// Header bytes 16 to 255: the system and application data areas.
    header_tail: Vec<u8>,
    /// Map bytes 16 to 27: the handle to the next map, the file reference and the map attributes.
    map_state: Vec<u8>,
    pub resources: Vec<Resource>,
}

fn word(bytes: &[u8], at: usize) -> Result<usize> {
    let slice = bytes.get(at..at + 2).ok_or("truncated resource fork")?;
    Ok(usize::from(u16::from_be_bytes([slice[0], slice[1]])))
}

fn long(bytes: &[u8], at: usize) -> Result<usize> {
    let slice = bytes.get(at..at + 4).ok_or("truncated resource fork")?;
    Ok(u32::from_be_bytes([slice[0], slice[1], slice[2], slice[3]]) as usize)
}

impl Fork {
    /// A fork with no resources.
    pub fn empty() -> Self {
        Self {
            header_tail: vec![0; HEADER - 16],
            map_state: vec![0; MAP_HEAD - 16],
            resources: vec![],
        }
    }

    /// Reads the resources of a fork.
    pub fn read(bytes: &[u8]) -> Result<Self> {
        if bytes.len() < HEADER {
            return Err("truncated resource fork".into());
        }
        let data_at = long(bytes, 0)?;
        let map_at = long(bytes, 4)?;
        let map_length = long(bytes, 12)?;
        let map = bytes
            .get(map_at..map_at + map_length)
            .ok_or("the resource map lies outside the fork")?;
        if map.len() < MAP_HEAD {
            return Err("truncated resource map".into());
        }
        let types_at = word(map, 24)?;
        let names_at = word(map, 26)?;
        let count = word(map, types_at)?;
        let mut resources = vec![];
        if count != 0xffff {
            for entry in 0..=count {
                let at = types_at + 2 + entry * 8;
                let kind: [u8; 4] = map
                    .get(at..at + 4)
                    .ok_or("truncated resource type list")?
                    .try_into()
                    .unwrap();
                let refs = types_at + word(map, at + 6)?;
                for item in 0..=word(map, at + 4)? {
                    let at = refs + item * 12;
                    let id = word(map, at)? as u16 as i16;
                    let name_offset = word(map, at + 2)?;
                    let attributes = *map.get(at + 4).ok_or("truncated resource reference")?;
                    let offset = map
                        .get(at + 5..at + 8)
                        .ok_or("truncated resource reference")?
                        .iter()
                        .fold(0usize, |a, b| a * 256 + usize::from(*b));
                    let name_order = if name_offset == 0xffff {
                        usize::MAX
                    } else {
                        name_offset
                    };
                    let name = if name_offset == 0xffff {
                        None
                    } else {
                        let at = names_at + name_offset;
                        let length = usize::from(*map.get(at).ok_or("truncated resource name")?);
                        Some(
                            map.get(at + 1..at + 1 + length)
                                .ok_or("truncated resource name")?
                                .to_vec(),
                        )
                    };
                    let reserved: [u8; 4] = map
                        .get(at + 8..at + 12)
                        .ok_or("truncated resource reference")?
                        .try_into()
                        .unwrap();
                    let start = data_at + offset;
                    let size = long(bytes, start)?;
                    let data = bytes
                        .get(start + 4..start + 4 + size)
                        .ok_or("resource data lies outside the fork")?
                        .to_vec();
                    resources.push(Resource {
                        kind,
                        id,
                        attributes,
                        name,
                        data,
                        reserved,
                        name_order,
                        order: offset,
                    });
                }
            }
        }
        Ok(Self {
            header_tail: bytes[16..HEADER].to_vec(),
            map_state: map[16..MAP_HEAD].to_vec(),
            resources,
        })
    }

    pub fn get(&self, kind: &[u8; 4], id: i16) -> Option<&Resource> {
        self.resources
            .iter()
            .find(|r| &r.kind == kind && r.id == id)
    }

    /// Sets the data of a resource, adding the resource when there is none, or removes it when `data` is `None`.
    pub fn set(&mut self, kind: &[u8; 4], id: i16, data: Option<Vec<u8>>) {
        let found = self
            .resources
            .iter()
            .position(|r| &r.kind == kind && r.id == id);
        match (found, data) {
            (Some(at), Some(data)) => self.resources[at].data = data,
            (Some(at), None) => {
                self.resources.remove(at);
            }
            (None, Some(data)) => {
                // A new resource joins the others of its type, or ends the map with a type of its own.
                let at = self
                    .resources
                    .iter()
                    .rposition(|r| &r.kind == kind)
                    .map_or(self.resources.len(), |last| last + 1);
                self.resources.insert(
                    at,
                    Resource {
                        kind: *kind,
                        id,
                        attributes: 0,
                        name: None,
                        data,
                        reserved: [0; 4],
                        name_order: usize::MAX,
                        order: usize::MAX,
                    },
                );
            }
            (None, None) => {}
        }
    }

    /// The ids of the resources of a type, in map order.
    pub fn ids(&self, kind: &[u8; 4]) -> Vec<i16> {
        self.resources
            .iter()
            .filter(|r| &r.kind == kind)
            .map(|r| r.id)
            .collect()
    }

    /// The fork as bytes.
    pub fn write(&self) -> Result<Vec<u8>> {
        // The data follows the order it had; a resource added since comes last, in the order it was added.
        let mut by_data: Vec<usize> = (0..self.resources.len()).collect();
        by_data.sort_by_key(|&index| (self.resources[index].order, index));
        let mut data = vec![];
        let mut offsets = vec![0usize; self.resources.len()];
        for index in by_data {
            offsets[index] = data.len();
            data.extend_from_slice(&(self.resources[index].data.len() as u32).to_be_bytes());
            data.extend_from_slice(&self.resources[index].data);
        }
        if data.len() > 0xff_ffff {
            return Err("the resources are too large for one fork".into());
        }
        // Types in the order of first appearance, each with its resources in map order.
        let mut kinds: Vec<[u8; 4]> = vec![];
        for resource in &self.resources {
            if !kinds.contains(&resource.kind) {
                kinds.push(resource.kind);
            }
        }
        let mut names = vec![];
        let mut name_offsets: Vec<Option<usize>> = vec![None; self.resources.len()];
        let mut named: Vec<usize> = (0..self.resources.len())
            .filter(|&i| self.resources[i].name.is_some())
            .collect();
        named.sort_by_key(|&i| (self.resources[i].name_order, i));
        for index in named {
            let name = self.resources[index].name.as_ref().unwrap();
            name_offsets[index] = Some(names.len());
            names.push(name.len().min(255) as u8);
            names.extend_from_slice(&name[..name.len().min(255)]);
        }
        let offset = |value: usize, what: &str| {
            u16::try_from(value).map_err(|_| {
                format!("the resources are too many for one fork: {what} passes 65,535 bytes")
            })
        };
        let list_length = 2 + kinds.len() * 8;
        let mut types = vec![];
        let mut refs = vec![];
        if kinds.is_empty() {
            types.extend_from_slice(&0xffffu16.to_be_bytes());
        } else {
            types.extend_from_slice(&((kinds.len() - 1) as u16).to_be_bytes());
            for kind in &kinds {
                let members: Vec<usize> = (0..self.resources.len())
                    .filter(|&i| &self.resources[i].kind == kind)
                    .collect();
                types.extend_from_slice(kind);
                types.extend_from_slice(&((members.len() - 1) as u16).to_be_bytes());
                types.extend_from_slice(
                    &offset(list_length + refs.len(), "the list of references")?.to_be_bytes(),
                );
                for index in members {
                    let resource = &self.resources[index];
                    refs.extend_from_slice(&resource.id.to_be_bytes());
                    let name_at = match name_offsets[index] {
                        Some(at) => offset(at, "the list of names")?,
                        None => 0xffff,
                    };
                    refs.extend_from_slice(&name_at.to_be_bytes());
                    refs.push(resource.attributes);
                    refs.extend_from_slice(&(offsets[index] as u32).to_be_bytes()[1..]);
                    refs.extend_from_slice(&resource.reserved);
                }
            }
        }
        let names_at = MAP_HEAD + types.len() + refs.len();
        let map_length = names_at + names.len();
        // The head is a copy of the fork's header, then the handle, file reference and attributes, then the
        // offsets of the type list (right after the head) and of the name list (after the references).
        let mut map = vec![0u8; 16];
        map.extend_from_slice(&self.map_state[..8]);
        map.extend_from_slice(&(MAP_HEAD as u16).to_be_bytes());
        map.extend_from_slice(&offset(names_at, "the map")?.to_be_bytes());
        map.extend_from_slice(&types);
        map.extend_from_slice(&refs);
        map.extend_from_slice(&names);
        let map_at = HEADER + data.len();
        let mut fork = vec![0u8; HEADER];
        fork[..4].copy_from_slice(&(HEADER as u32).to_be_bytes());
        fork[4..8].copy_from_slice(&(map_at as u32).to_be_bytes());
        fork[8..12].copy_from_slice(&(data.len() as u32).to_be_bytes());
        fork[12..16].copy_from_slice(&(map_length as u32).to_be_bytes());
        fork[16..].copy_from_slice(&self.header_tail);
        // The map begins with a copy of the fork's header.
        map[..16].copy_from_slice(&fork[..16]);
        fork.extend_from_slice(&data);
        fork.extend_from_slice(&map);
        Ok(fork)
    }
}

/// The resource fork inside a file: the whole file for a raw fork, or the data of the AppleDouble entry
/// that holds it.
pub fn fork_of(file: &[u8]) -> Result<&[u8]> {
    match apple_double_fork(file)? {
        Some((at, length)) => file
            .get(at..at + length)
            .ok_or("truncated resource fork".into()),
        None => Ok(file),
    }
}

/// Where the resource fork lies in an AppleDouble file, or `None` when the file is not one.
fn apple_double_fork(file: &[u8]) -> Result<Option<(usize, usize)>> {
    if !(file.starts_with(&[0, 5, 0x16, 7]) || file.starts_with(&[0, 5, 0x16, 0])) {
        return Ok(None);
    }
    for entry in 0..word(file, 24)? {
        let at = 26 + entry * 12;
        if long(file, at)? == 2 {
            return Ok(Some((long(file, at + 4)?, long(file, at + 8)?)));
        }
    }
    Ok(Some((file.len(), 0)))
}

/// `file` with its resource fork replaced. The fork must be the last thing in an AppleDouble file.
pub fn with_fork(file: &[u8], fork: &[u8]) -> Result<Vec<u8>> {
    let Some((at, length)) = apple_double_fork(file)? else {
        return Ok(fork.to_vec());
    };
    if at + length != file.len() {
        return Err("the resource fork is not the last entry of its file".into());
    }
    let mut out = file[..at].to_vec();
    for entry in 0..word(file, 24)? {
        let place = 26 + entry * 12;
        if long(file, place)? == 2 {
            out[place + 8..place + 12].copy_from_slice(&(fork.len() as u32).to_be_bytes());
        }
    }
    out.extend_from_slice(fork);
    Ok(out)
}
