use centurions_editor::media;
use centurions_format::codecs::{self, Fit, Pcm};
use centurions_format::graphics::{self, Image};

fn image(width: usize, height: usize, pixel: impl Fn(usize, usize) -> [u8; 4]) -> Image {
    let mut rgba = Vec::with_capacity(width * height * 4);
    for y in 0..height {
        for x in 0..width {
            rgba.extend_from_slice(&pixel(x, y));
        }
    }
    Image {
        width: width as u16,
        height: height as u16,
        rgba,
    }
}

#[test]
fn an_icon_reads_back_with_its_colours_and_its_mask() {
    let icon = image(32, 32, |x, y| match (x < 4 && y < 4, x % 2) {
        (true, _) => [0, 0, 0, 0],
        (false, 0) => [200, 30, 30, 255],
        _ => [30, 30, 200, 255],
    });
    let (bytes, cost) = codecs::encode_cicn(&icon, false).unwrap();
    assert_eq!(cost.colours, 2);
    let back = graphics::decode_cicn(&bytes).unwrap();
    assert_eq!((back.width, back.height), (32, 32));
    assert_eq!(back.rgba[3], 0, "the corner stays transparent");
    let at = (10 * 32 + 10) * 4;
    assert_eq!(&back.rgba[at..at + 4], &[200, 30, 30, 255]);
    assert_eq!(&back.rgba[at + 4..at + 8], &[30, 30, 200, 255]);
}

#[test]
fn a_picture_with_many_colours_keeps_its_size_and_stays_close() {
    let picture = image(130, 70, |x, y| {
        [(x * 2) as u8, (y * 3) as u8, ((x + y) % 256) as u8, 255]
    });
    let (bytes, cost) = codecs::encode_pict(&picture, true).unwrap();
    assert!(cost.colours <= 256);
    let back = graphics::decode_pict(&bytes).unwrap();
    assert_eq!((back.width, back.height), (130, 70));
    let total: u64 = back
        .rgba
        .as_chunks::<4>()
        .0
        .iter()
        .zip(picture.rgba.as_chunks::<4>().0)
        .map(|(a, b)| (0..3).map(|c| u64::from(a[c].abs_diff(b[c]))).sum::<u64>())
        .sum();
    assert!(
        total / (130 * 70 * 3) < 12,
        "the colours moved too far: {}",
        total / (130 * 70 * 3)
    );
    // A picture of 256 colours or fewer comes back exactly.
    let flat = image(16, 16, |x, y| [(x * 16) as u8, (y * 16) as u8, 90, 255]);
    let (bytes, _) = codecs::encode_pict(&flat, false).unwrap();
    assert_eq!(graphics::decode_pict(&bytes).unwrap().rgba, flat.rgba);
}

#[test]
fn a_wav_becomes_a_sound_of_eight_bit_mono_that_reads_back_at_its_rate() {
    let rate = 22050usize;
    let samples: Vec<f32> = (0..rate / 10)
        .flat_map(|n| {
            let v = (n as f32 / 20.0).sin() * 0.5;
            [v, v]
        })
        .collect();
    let mut wav = b"RIFF".to_vec();
    let data: Vec<u8> = samples
        .iter()
        .flat_map(|s| ((s * 32767.0) as i16).to_le_bytes())
        .collect();
    wav.extend_from_slice(&((36 + data.len()) as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    for value in [
        16u32,
        0x0002_0001,
        rate as u32,
        rate as u32 * 4,
        0x0010_0004,
    ] {
        wav.extend_from_slice(&value.to_le_bytes());
    }
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&(data.len() as u32).to_le_bytes());
    wav.extend_from_slice(&data);
    let pcm: Pcm = codecs::read_wav(&wav).unwrap();
    assert_eq!(
        (pcm.rate, pcm.channels, pcm.samples.len()),
        (22050, 2, samples.len())
    );
    let (snd, rate, seconds) = codecs::encode_snd(&pcm, Some(11025)).unwrap();
    assert_eq!(rate, 11025);
    assert!((seconds - 0.1).abs() < 0.001);
    let (back, back_rate, _) = media::snd_to_wav(&snd).unwrap();
    assert_eq!(back_rate, 11025);
    assert_eq!(&back[44..48].len(), &4);
    assert_eq!((back.len() - 44) as f64, (seconds * 11025.0).round());
}

#[test]
fn an_image_is_fitted_inside_filled_or_stretched() {
    let wide = image(64, 32, |_, _| [255, 0, 0, 255]);
    let inside = codecs::fit(&wide, 32, 32, Fit::Inside);
    assert_eq!(inside.rgba[3], 0, "the top row is padding");
    assert_eq!(inside.rgba[(16 * 32 + 16) * 4 + 3], 255);
    let filled = codecs::fit(&wide, 32, 32, Fit::Fill);
    assert!(filled.rgba.as_chunks::<4>().0.iter().all(|p| p[3] == 255));
    let stretched = codecs::fit(&wide, 32, 32, Fit::Stretch);
    assert!(
        stretched
            .rgba
            .as_chunks::<4>()
            .0
            .iter()
            .all(|p| p[3] == 255)
    );
}

#[test]
fn an_extensible_wav_is_read_by_its_sub_format() {
    // WAVE_FORMAT_EXTENSIBLE (0xfffe) holding 16-bit PCM: the format is named in the sub-format at byte 24.
    let mut wav = b"RIFF".to_vec();
    wav.extend_from_slice(&(4 + 8 + 40 + 8 + 4u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&40u32.to_le_bytes());
    wav.extend_from_slice(&0xfffeu16.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&22050u32.to_le_bytes());
    wav.extend_from_slice(&44100u32.to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(&22u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(&4u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&[0; 14]);
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&4u32.to_le_bytes());
    wav.extend_from_slice(&[0, 64, 0, 192]);
    let pcm = codecs::read_wav(&wav).unwrap();
    assert_eq!((pcm.rate, pcm.channels, pcm.samples.len()), (22050, 1, 2));
    assert!((pcm.samples[0] - 0.5).abs() < 0.001 && (pcm.samples[1] + 0.5).abs() < 0.001);
}
