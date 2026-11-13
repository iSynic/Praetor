use centurions_editor::media;
use centurions_format::{Files, Result};
use std::fs;

fn put(b: &mut [u8], at: usize, value: u16) {
    b[at..at + 2].copy_from_slice(&value.to_be_bytes());
}

fn pict(red: u16, green: u16) -> Vec<u8> {
    let mut p = vec![0; 14];
    put(&mut p, 6, 480);
    put(&mut p, 8, 640);
    p[10..14].copy_from_slice(&[0, 0x11, 2, 0xff]);
    p.extend_from_slice(&0x98u16.to_be_bytes());
    let start = p.len();
    p.resize(start + 46, 0);
    put(&mut p, start, 0x8000 | 640);
    put(&mut p, start + 6, 480);
    put(&mut p, start + 8, 640);
    put(&mut p, start + 28, 8);
    put(&mut p, start + 30, 1);
    put(&mut p, start + 32, 8);
    p.extend_from_slice(&[0, 0, 0, 0, 0x80, 0, 0, 0]);
    for component in [0, red, green, 0] {
        p.extend_from_slice(&component.to_be_bytes());
    }
    for _ in 0..2 {
        for value in [0u16, 0, 480, 640] {
            p.extend_from_slice(&value.to_be_bytes());
        }
    }
    p.extend_from_slice(&[0, 0]);
    for _ in 0..480 {
        p.extend_from_slice(&10u16.to_be_bytes());
        for _ in 0..5 {
            p.extend_from_slice(&[0x81, 0]);
        }
    }
    p.extend_from_slice(&[0, 0xff]);
    p
}

fn fork(payload: &[u8], duplicate: bool) -> Vec<u8> {
    let offset = 260 + payload.len();
    let mut b = vec![0; offset];
    b[..4].copy_from_slice(&256u32.to_be_bytes());
    b[4..8].copy_from_slice(&(offset as u32).to_be_bytes());
    b[8..12].copy_from_slice(&((payload.len() + 4) as u32).to_be_bytes());
    let size = if duplicate { 62u32 } else { 50 };
    b[12..16].copy_from_slice(&size.to_be_bytes());
    b[256..260].copy_from_slice(&(payload.len() as u32).to_be_bytes());
    b[260..].copy_from_slice(payload);
    let mut map = vec![0; size as usize];
    put(&mut map, 24, 28);
    put(&mut map, 28, 0);
    map[30..34].copy_from_slice(b"PICT");
    put(&mut map, 34, u16::from(duplicate));
    put(&mut map, 36, 10);
    put(&mut map, 38, 301);
    if duplicate {
        put(&mut map, 50, 301);
    }
    b.extend_from_slice(&map);
    b
}

#[test]
fn resource_identity_and_scenario_override_are_independent_of_stock_fallback() -> Result<()> {
    let t = tempfile::tempdir().unwrap();
    let installation = t.path().join("installation");
    fs::create_dir_all(installation.join("Data Files")).unwrap();
    fs::write(
        installation.join("Data Files/Cargo Pod.rsrc"),
        fork(&pict(0, 65535), false),
    )
    .unwrap();
    let mut files = Files::new();
    let mut rd = vec![0; 644];
    rd[520] = 2;
    files.insert("Data RD".into(), rd);
    files.insert("Data LD".into(), vec![0; 64800]);
    files.insert("Scenario.rsrc".into(), fork(&pict(65535, 0), false));
    let before = files.clone();
    let result = media::artwork(&files, 0, &installation, &t.path().join("cache"))?;
    assert_eq!(result["owner"], "Scenario.rsrc");
    assert_eq!(result["status"], "available");
    let decoder = png::Decoder::new(std::io::BufReader::new(
        fs::File::open(result["png"].as_str().unwrap()).unwrap(),
    ));
    let mut reader = decoder.read_info().unwrap();
    let mut pixels = vec![0; reader.output_buffer_size().unwrap()];
    reader.next_frame(&mut pixels).unwrap();
    assert!(
        pixels
            .as_chunks::<4>()
            .0
            .iter()
            .all(|p| p == &[255, 0, 0, 255])
    );
    files.insert("Scenario.rsrc".into(), fork(&[0], false));
    assert_eq!(
        media::artwork(&files, 0, &installation, &t.path().join("cache"))?["status"],
        "unresolved"
    );
    assert_eq!(before["Scenario.rsrc"], fork(&pict(65535, 0), false));
    Ok(())
}

#[test]
fn malformed_and_ambiguous_forks_refuse_without_panicking() {
    let valid = fork(&[1, 2, 3], false);
    assert_eq!(media::picture(&valid, 301).unwrap(), Some(vec![1, 2, 3]));
    assert_eq!(media::picture(&[], 301).unwrap(), None);
    for end in 1..valid.len() {
        assert!(media::picture(&valid[..end], 301).is_err());
    }
    assert!(media::picture(&fork(&[1, 2, 3], true), 301).is_err());
    let mut metadata = vec![0; 70];
    metadata[..4].copy_from_slice(&[0, 5, 0x16, 7]);
    put(&mut metadata, 24, 1);
    metadata[26..30].copy_from_slice(&9u32.to_be_bytes());
    metadata[30..34].copy_from_slice(&38u32.to_be_bytes());
    metadata[34..38].copy_from_slice(&32u32.to_be_bytes());
    assert_eq!(media::picture(&metadata, 301).unwrap(), None);
}

#[test]
fn signed_color_icon_identity_and_asymmetric_mask_survive_decoding() {
    let mut p = vec![0; 82];
    for (at, value) in [
        (4, 0x8002),
        (10, 1),
        (12, 2),
        (32, 8),
        (54, 1),
        (60, 1),
        (62, 2),
    ] {
        put(&mut p, at, value);
    }
    p.push(0x80); // The left pixel is opaque, the right transparent.
    p.extend_from_slice(&[0, 0, 0, 0, 0x80, 0, 0, 1]);
    for component in [0u16, 65535, 0, 0, 1, 0, 65535, 0] {
        p.extend_from_slice(&component.to_be_bytes());
    }
    p.extend_from_slice(&[0, 1]);
    let mut b = fork(&p, false);
    let map = u32::from_be_bytes(b[4..8].try_into().unwrap()) as usize;
    b[map + 30..map + 34].copy_from_slice(b"cicn");
    put(&mut b, map + 38, (-2i16) as u16);
    assert!(media::picture(&b, -2).unwrap().is_none());
    let payload = media::resource(&b, b"cicn", -2).unwrap().unwrap();
    assert_eq!(payload, p);
    let image = centurions_format::graphics::decode_cicn(&payload).unwrap();
    assert_eq!((image.width, image.height), (2, 1));
    assert_eq!(image.rgba, [255, 0, 0, 255, 0, 255, 0, 0]);
    for end in 0..p.len() {
        assert!(centurions_format::graphics::decode_cicn(&p[..end]).is_err());
    }
}

/// A fork read from the bytes of a resource file.
fn fork_of(bytes: &[u8]) -> centurions_format::resource_fork::Fork {
    centurions_format::resource_fork::Fork::read(bytes).unwrap()
}

/// A resource fork holding one resource of each given kind.
fn resources(items: &[(&[u8; 4], i16, &[u8])]) -> Vec<u8> {
    let mut data = vec![];
    let mut offsets = vec![];
    for (_, _, payload) in items {
        offsets.push(data.len());
        data.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        data.extend_from_slice(payload);
    }
    let count = items.len();
    let mut map = vec![0; 28];
    put(&mut map, 24, 28);
    map.extend_from_slice(&((count - 1) as u16).to_be_bytes());
    for (index, (kind, _, _)) in items.iter().enumerate() {
        map.extend_from_slice(*kind);
        map.extend_from_slice(&0u16.to_be_bytes());
        map.extend_from_slice(&((2 + 8 * count + 12 * index) as u16).to_be_bytes());
    }
    for (index, (_, id, _)) in items.iter().enumerate() {
        map.extend_from_slice(&id.to_be_bytes());
        map.extend_from_slice(&0xffffu16.to_be_bytes());
        map.push(0);
        map.extend_from_slice(&(offsets[index] as u32).to_be_bytes()[1..]);
        map.extend_from_slice(&[0; 4]);
    }
    let mut fork = vec![0; 256];
    fork[..4].copy_from_slice(&256u32.to_be_bytes());
    fork[4..8].copy_from_slice(&((256 + data.len()) as u32).to_be_bytes());
    fork[8..12].copy_from_slice(&(data.len() as u32).to_be_bytes());
    fork[12..16].copy_from_slice(&(map.len() as u32).to_be_bytes());
    fork.extend_from_slice(&data);
    fork.extend_from_slice(&map);
    fork
}

#[test]
fn a_step_that_names_a_resource_nobody_holds_is_a_finding() {
    use centurions_format::{ScriptFamily, extras, scripts};
    let mut files = Files::new();
    for (name, stride, rows) in [
        ("Data ED3", 42, 3),
        ("Data ED", 426, 3),
        ("Data ED2", 516, 3),
        ("Data EDCD", 10, 6),
    ] {
        files.insert(name.into(), vec![0; stride * rows]);
    }
    files.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    // A picture, a text and an animation whose first word is 3: icons 12024 to 12031.
    scripts::patch(&mut files, ScriptFamily::Story, 1, 0, 0, 27, 5).unwrap();
    scripts::patch(&mut files, ScriptFamily::Story, 1, 0, 1, 62, 7).unwrap();
    scripts::patch(&mut files, ScriptFamily::Story, 1, 0, 2, 128, 2).unwrap();
    extras::set_row(&mut files, 2, [3, 0, 0, 64, 2]).unwrap();
    let game = resources(&[(b"cicn", 12027, &[1])]);
    let scenario = resources(&[(b"PICT", 5, &[1]), (b"TEXT", 7, &[1])]);
    let found = media::missing_in(&files, &[fork_of(&scenario), fork_of(&game)]).unwrap();
    assert_eq!(found.len(), 1, "only the text lacks its styl: {found:?}");
    assert!(found[0]["message"].as_str().unwrap().contains("text 7"));
    let scenario = resources(&[(b"TEXT", 7, &[1]), (b"styl", 7, &[1])]);
    let found = media::missing_in(
        &files,
        &[
            fork_of(&scenario),
            fork_of(&resources(&[(b"cicn", 99, &[1])])),
        ],
    )
    .unwrap();
    assert_eq!(
        found.len(),
        2,
        "the picture and the animation are missing: {found:?}"
    );
    assert!(
        found[1]["message"]
            .as_str()
            .unwrap()
            .contains("animation 3")
    );
}

#[test]
fn a_format_one_sound_becomes_a_wav_with_its_samples_and_rate() {
    // Format 1, one synthesizer, one buffer command pointing at a standard header with four 8-bit samples.
    let mut snd = vec![
        0, 1, 0, 1, 0, 5, 0, 0, 0, 0x80, 0, 1, 0x80, 0x51, 0, 0, 0, 0, 0, 20,
    ];
    snd.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 4]);
    snd.extend_from_slice(&(11127u32 << 16).to_be_bytes());
    snd.extend_from_slice(&[0; 8]);
    snd.extend_from_slice(&[0, 60, 10, 20, 30, 40]);
    let (wav, rate, seconds) = media::snd_to_wav(&snd).unwrap();
    assert_eq!(rate, 11127);
    assert!((seconds - 4.0 / 11127.0).abs() < 1e-9);
    assert_eq!(&wav[..4], b"RIFF");
    assert_eq!(&wav[24..28], &11127u32.to_le_bytes());
    assert_eq!(&wav[44..], &[10, 20, 30, 40]);
    // A compressed sound is refused rather than played as noise.
    let mut compressed = snd.clone();
    compressed[40] = 0xfe;
    assert!(media::snd_to_wav(&compressed).is_err());
}
