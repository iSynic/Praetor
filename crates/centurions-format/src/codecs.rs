//! Encoders for the resources the editor imports: color icons (`cicn`), pictures (`PICT`) and sounds (`snd `),
//! made from ordinary images and WAV audio. Each writes what the game's own resources look like, so the
//! decoders that read the game's resources read these back.
use crate::Result;
use crate::graphics::Image;
use std::collections::HashMap;

/// How an image is made to fit the size a resource wants.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fit {
    /// The whole image inside the size, centred, the rest transparent.
    Inside,
    /// The size filled, the overhang cropped.
    Fill,
    /// Stretched to the size.
    Stretch,
}

impl Fit {
    pub fn parse(name: &str) -> Result<Self> {
        match name {
            "inside" => Ok(Self::Inside),
            "fill" => Ok(Self::Fill),
            "stretch" => Ok(Self::Stretch),
            other => Err(format!("unknown fit {other:?}")),
        }
    }
}

/// The image drawn into a `width` by `height` frame. Enlarging keeps hard pixels; reducing averages the pixels
/// each new one covers, weighted by their alpha.
pub fn fit(image: &Image, width: usize, height: usize, mode: Fit) -> Image {
    let (sw, sh) = (usize::from(image.width), usize::from(image.height));
    let (dw, dh, ox, oy, crop_x, crop_y) = match mode {
        Fit::Stretch => (width, height, 0, 0, 0.0, 0.0),
        Fit::Inside => {
            let scale = (width as f64 / sw as f64).min(height as f64 / sh as f64);
            let dw = ((sw as f64 * scale).round() as usize).clamp(1, width);
            let dh = ((sh as f64 * scale).round() as usize).clamp(1, height);
            (dw, dh, (width - dw) / 2, (height - dh) / 2, 0.0, 0.0)
        }
        Fit::Fill => {
            let scale = (width as f64 / sw as f64).max(height as f64 / sh as f64);
            let covered_w = sw as f64 * scale;
            let covered_h = sh as f64 * scale;
            (
                width,
                height,
                0,
                0,
                (covered_w - width as f64) / 2.0 / scale,
                (covered_h - height as f64) / 2.0 / scale,
            )
        }
    };
    let span_x = match mode {
        Fit::Fill => sw as f64 - 2.0 * crop_x,
        _ => sw as f64,
    };
    let span_y = match mode {
        Fit::Fill => sh as f64 - 2.0 * crop_y,
        _ => sh as f64,
    };
    let mut out = vec![0u8; width * height * 4];
    for y in 0..dh {
        for x in 0..dw {
            let x0 = crop_x + span_x * x as f64 / dw as f64;
            let x1 = crop_x + span_x * (x + 1) as f64 / dw as f64;
            let y0 = crop_y + span_y * y as f64 / dh as f64;
            let y1 = crop_y + span_y * (y + 1) as f64 / dh as f64;
            let mut sum = [0.0f64; 4];
            let mut weight = 0.0;
            let upscaling = x1 - x0 <= 1.0 && y1 - y0 <= 1.0;
            let (xs, xe, ys, ye) = if upscaling {
                let cx = ((x0 + x1) / 2.0).floor().clamp(0.0, sw as f64 - 1.0) as usize;
                let cy = ((y0 + y1) / 2.0).floor().clamp(0.0, sh as f64 - 1.0) as usize;
                (cx, cx + 1, cy, cy + 1)
            } else {
                (
                    x0.floor().max(0.0) as usize,
                    (x1.ceil() as usize).min(sw),
                    y0.floor().max(0.0) as usize,
                    (y1.ceil() as usize).min(sh),
                )
            };
            for sy in ys..ye {
                for sx in xs..xe {
                    let w = if upscaling {
                        1.0
                    } else {
                        (x1.min(sx as f64 + 1.0) - x0.max(sx as f64)).max(0.0)
                            * (y1.min(sy as f64 + 1.0) - y0.max(sy as f64)).max(0.0)
                    };
                    let at = (sy * sw + sx) * 4;
                    let alpha = f64::from(image.rgba[at + 3]) / 255.0;
                    for (channel, total) in sum.iter_mut().take(3).enumerate() {
                        *total += f64::from(image.rgba[at + channel]) * alpha * w;
                    }
                    sum[3] += alpha * w;
                    weight += w;
                }
            }
            if weight > 0.0 && sum[3] > 0.0 {
                let at = ((oy + y) * width + ox + x) * 4;
                for channel in 0..3 {
                    out[at + channel] = (sum[channel] / sum[3]).round().clamp(0.0, 255.0) as u8;
                }
                out[at + 3] = (sum[3] / weight * 255.0).round().clamp(0.0, 255.0) as u8;
            }
        }
    }
    Image {
        width: width as u16,
        height: height as u16,
        rgba: out,
    }
}

/// A palette of at most `limit` colours for the opaque pixels (alpha 128 or more), by median cut.
pub fn palette(image: &Image, limit: usize) -> Vec<[u8; 3]> {
    let mut counts: HashMap<[u8; 3], usize> = HashMap::new();
    for pixel in image.rgba.as_chunks::<4>().0 {
        if pixel[3] >= 128 {
            *counts.entry([pixel[0], pixel[1], pixel[2]]).or_default() += 1;
        }
    }
    let mut colours: Vec<([u8; 3], usize)> = counts.into_iter().collect();
    colours.sort();
    if colours.len() <= limit {
        return colours.into_iter().map(|(c, _)| c).collect();
    }
    let mut boxes = vec![colours];
    while boxes.len() < limit {
        // Split the box whose widest channel range is largest, at the weighted median of that channel.
        let mut pick: Option<(usize, usize, u8)> = None;
        for (index, members) in boxes.iter().enumerate() {
            if members.len() < 2 {
                continue;
            }
            for channel in 0..3 {
                let low = members.iter().map(|(p, _)| p[channel]).min().unwrap();
                let high = members.iter().map(|(p, _)| p[channel]).max().unwrap();
                if pick.is_none_or(|(_, _, range)| high - low > range) {
                    pick = Some((index, channel, high - low));
                }
            }
        }
        let Some((index, channel, _)) = pick else {
            break;
        };
        let mut part = boxes.swap_remove(index);
        part.sort_by_key(|(p, _)| (p[channel], *p));
        let total: usize = part.iter().map(|(_, n)| *n).sum();
        let mut seen = 0;
        let mut at = 0;
        for (i, (_, n)) in part.iter().enumerate() {
            seen += n;
            at = i + 1;
            if seen * 2 >= total {
                break;
            }
        }
        let at = at.clamp(1, part.len() - 1);
        let upper = part.split_off(at);
        boxes.push(part);
        boxes.push(upper);
    }
    let mut result: Vec<[u8; 3]> = boxes
        .iter()
        .map(|b| {
            let total: usize = b.iter().map(|(_, n)| *n).sum();
            let mean = |c: usize| {
                (b.iter().map(|(p, n)| usize::from(p[c]) * n).sum::<usize>() as f64 / total as f64)
                    .round() as u8
            };
            [mean(0), mean(1), mean(2)]
        })
        .collect();
    result.sort();
    result.dedup();
    result
}

fn nearest(palette: &[[u8; 3]], colour: [i32; 3]) -> usize {
    let mut best = 0;
    let mut least = i64::MAX;
    for (index, entry) in palette.iter().enumerate() {
        let d = |c: usize| i64::from(colour[c] - i32::from(entry[c]));
        // Green counts most to the eye.
        let distance = 2 * d(0) * d(0) + 4 * d(1) * d(1) + 3 * d(2) * d(2);
        if distance < least {
            least = distance;
            best = index;
        }
    }
    best
}

/// The index of the palette entry nearest each pixel, with the share of opaque pixels that moved far from their
/// colour. With `dither` the error of each pixel is spread to its neighbours (Floyd-Steinberg).
pub fn indices(image: &Image, palette: &[[u8; 3]], dither: bool) -> (Vec<u8>, f64) {
    let (w, h) = (usize::from(image.width), usize::from(image.height));
    let mut work: Vec<[f32; 3]> = image
        .rgba
        .as_chunks::<4>()
        .0
        .iter()
        .map(|p| [f32::from(p[0]), f32::from(p[1]), f32::from(p[2])])
        .collect();
    let mut out = vec![0u8; w * h];
    let mut cache: HashMap<[i32; 3], usize> = HashMap::new();
    let (mut far, mut opaque) = (0usize, 0usize);
    for y in 0..h {
        for x in 0..w {
            let at = y * w + x;
            if image.rgba[at * 4 + 3] < 128 {
                continue;
            }
            let wanted = work[at];
            let key = [
                wanted[0].round().clamp(0.0, 255.0) as i32,
                wanted[1].round().clamp(0.0, 255.0) as i32,
                wanted[2].round().clamp(0.0, 255.0) as i32,
            ];
            let choice = *cache.entry(key).or_insert_with(|| nearest(palette, key));
            out[at] = choice as u8;
            let got = palette[choice];
            let original = &image.rgba[at * 4..at * 4 + 3];
            opaque += 1;
            if (0..3).any(|c| (i32::from(original[c]) - i32::from(got[c])).abs() > 24) {
                far += 1;
            }
            if dither {
                let error: Vec<f32> = (0..3).map(|c| wanted[c] - f32::from(got[c])).collect();
                for (dx, dy, share) in
                    [(1i32, 0i32, 7.0f32), (-1, 1, 3.0), (0, 1, 5.0), (1, 1, 1.0)]
                {
                    let (nx, ny) = (x as i32 + dx, y as i32 + dy);
                    if nx >= 0 && (nx as usize) < w && (ny as usize) < h {
                        let target = &mut work[ny as usize * w + nx as usize];
                        for c in 0..3 {
                            target[c] += error[c] * share / 16.0;
                        }
                    }
                }
            }
        }
    }
    (
        out,
        if opaque == 0 {
            0.0
        } else {
            far as f64 / opaque as f64
        },
    )
}

fn put16(out: &mut Vec<u8>, value: usize) {
    out.extend_from_slice(&(value as u16).to_be_bytes());
}

fn color_table(out: &mut Vec<u8>, palette: &[[u8; 3]]) {
    out.extend_from_slice(&[0; 4]);
    put16(out, 0);
    put16(out, palette.len() - 1);
    for (index, colour) in palette.iter().enumerate() {
        put16(out, index);
        for channel in colour {
            out.extend_from_slice(&(u16::from(*channel) * 257).to_be_bytes());
        }
    }
}

/// What importing an image costs: how many colours it keeps and how far the rest moved.
#[derive(Clone, Debug, PartialEq)]
pub struct Cost {
    pub colours: usize,
    pub far: f64,
}

/// A color icon: the pixels as an 8-bit palette image and a 1-bit mask of the pixels with alpha 128 or more.
pub fn encode_cicn(image: &Image, dither: bool) -> Result<(Vec<u8>, Cost)> {
    let (w, h) = (usize::from(image.width), usize::from(image.height));
    if !(1..=256).contains(&w) || !(1..=256).contains(&h) {
        return Err("an icon is 1 to 256 pixels each way".into());
    }
    let mut colours = palette(image, 255);
    if colours.is_empty() {
        colours.push([0, 0, 0]);
    }
    let (pixels, far) = indices(image, &colours, dither);
    let row = w;
    let mask_row = w.div_ceil(8).next_multiple_of(2);
    let mut out = vec![];
    out.extend_from_slice(&[0; 4]);
    put16(&mut out, 0x8000 | row);
    for value in [0, 0, h, w, 0, 0, 0, 0] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&0x0048_0000u32.to_be_bytes());
    out.extend_from_slice(&0x0048_0000u32.to_be_bytes());
    for value in [0, 8, 1, 8] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&[0; 12]);
    out.extend_from_slice(&[0; 4]);
    put16(&mut out, mask_row);
    for value in [0, 0, h, w] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&[0; 4]);
    put16(&mut out, 0);
    for value in [0, 0, h, w] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&[0; 4]);
    debug_assert_eq!(out.len(), 82);
    for y in 0..h {
        let mut bits = vec![0u8; mask_row];
        for x in 0..w {
            if image.rgba[(y * w + x) * 4 + 3] >= 128 {
                bits[x / 8] |= 0x80 >> (x % 8);
            }
        }
        out.extend_from_slice(&bits);
    }
    color_table(&mut out, &colours);
    out.extend_from_slice(&pixels);
    Ok((
        out,
        Cost {
            colours: colours.len(),
            far,
        },
    ))
}

fn pack_bits(row: &[u8]) -> Vec<u8> {
    let mut out = vec![];
    let mut at = 0;
    while at < row.len() {
        let run = row[at..]
            .iter()
            .take(128)
            .take_while(|b| **b == row[at])
            .count();
        if run >= 3 {
            out.push((1i16 - run as i16) as i8 as u8);
            out.push(row[at]);
            at += run;
        } else {
            let mut end = at + 1;
            while end < row.len() && end - at < 128 {
                let ahead = row[end..]
                    .iter()
                    .take(3)
                    .take_while(|b| **b == row[end])
                    .count();
                if ahead >= 3 {
                    break;
                }
                end += 1;
            }
            out.push((end - at - 1) as u8);
            out.extend_from_slice(&row[at..end]);
            at = end;
        }
    }
    out
}

/// A picture: an 8-bit palette image in a version 2 PICT. Transparent pixels are drawn black.
pub fn encode_pict(image: &Image, dither: bool) -> Result<(Vec<u8>, Cost)> {
    let (w, h) = (usize::from(image.width), usize::from(image.height));
    if !(1..=1024).contains(&w) || !(1..=1024).contains(&h) {
        return Err("a picture is 1 to 1024 pixels each way".into());
    }
    let mut flat = image.clone();
    for pixel in flat.rgba.as_chunks_mut::<4>().0 {
        let alpha = u32::from(pixel[3]);
        for channel in pixel.iter_mut().take(3) {
            *channel = (u32::from(*channel) * alpha / 255) as u8;
        }
        pixel[3] = 255;
    }
    let colours = palette(&flat, 256);
    let (pixels, far) = indices(&flat, &colours, dither);
    let row = w.next_multiple_of(2);
    let mut out = vec![0u8; 2];
    for value in [0, 0, h, w] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&[0x00, 0x11, 0x02, 0xff]);
    out.extend_from_slice(&[0x0c, 0x00]);
    out.extend_from_slice(&0xffff_ffffu32.to_be_bytes());
    for value in [0u32, 0, (h as u32) << 16, (w as u32) << 16] {
        out.extend_from_slice(&value.to_be_bytes());
    }
    out.extend_from_slice(&[0; 4]);
    out.extend_from_slice(&[0x00, 0x1e]);
    out.extend_from_slice(&[0x00, 0x01, 0x00, 0x0a]);
    for value in [0, 0, h, w] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&[0x00, 0x98]);
    put16(&mut out, 0x8000 | row);
    for value in [0, 0, h, w, 0, 0, 0, 0] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&0x0048_0000u32.to_be_bytes());
    out.extend_from_slice(&0x0048_0000u32.to_be_bytes());
    for value in [0, 8, 1, 8] {
        put16(&mut out, value);
    }
    out.extend_from_slice(&[0; 12]);
    color_table(&mut out, &colours);
    for _ in 0..2 {
        for value in [0, 0, h, w] {
            put16(&mut out, value);
        }
    }
    put16(&mut out, 0);
    for y in 0..h {
        let mut line = pixels[y * w..(y + 1) * w].to_vec();
        line.resize(row, 0);
        let packed = pack_bits(&line);
        if row > 250 {
            put16(&mut out, packed.len());
        } else {
            out.push(packed.len() as u8);
        }
        out.extend_from_slice(&packed);
    }
    if out.len() % 2 == 1 {
        out.push(0);
    }
    out.extend_from_slice(&[0x00, 0xff]);
    let size = out.len();
    out[..2].copy_from_slice(&(size as u16).to_be_bytes());
    Ok((
        out,
        Cost {
            colours: colours.len(),
            far,
        },
    ))
}

/// Sound read from a WAV file: interleaved samples between -1 and 1.
#[derive(Clone, Debug)]
pub struct Pcm {
    pub rate: u32,
    pub channels: usize,
    pub samples: Vec<f32>,
}

fn le16(b: &[u8], at: usize) -> Result<usize> {
    Ok(usize::from(u16::from_le_bytes(
        b.get(at..at + 2)
            .ok_or("truncated WAV file")?
            .try_into()
            .unwrap(),
    )))
}

fn le32(b: &[u8], at: usize) -> Result<usize> {
    Ok(u32::from_le_bytes(
        b.get(at..at + 4)
            .ok_or("truncated WAV file")?
            .try_into()
            .unwrap(),
    ) as usize)
}

/// Reads a WAV file of 8, 16, 24 or 32-bit integer samples or 32-bit float samples.
pub fn read_wav(bytes: &[u8]) -> Result<Pcm> {
    if bytes.get(..4) != Some(b"RIFF") || bytes.get(8..12) != Some(b"WAVE") {
        return Err("not a WAV file".into());
    }
    let (mut format, mut data) = (None, None);
    let mut at = 12;
    while at + 8 <= bytes.len() {
        let length = le32(bytes, at + 4)?;
        let body = at + 8;
        match &bytes[at..at + 4] {
            b"fmt " => {
                // An extensible file (tag 0xfffe) names its real format in the first two bytes of the sub-format.
                let mut tag = le16(bytes, body)?;
                if tag == 0xfffe && length >= 40 {
                    tag = le16(bytes, body + 24)?;
                }
                format = Some((
                    tag,
                    le16(bytes, body + 2)?,
                    le32(bytes, body + 4)?,
                    le16(bytes, body + 14)?,
                ))
            }
            b"data" => data = bytes.get(body..(body + length).min(bytes.len())),
            _ => {}
        }
        at = body + length + (length & 1);
    }
    let (tag, channels, rate, bits) = format.ok_or("the WAV file has no format")?;
    let data = data.ok_or("the WAV file has no samples")?;
    if channels == 0 || rate == 0 {
        return Err("the WAV file has no channels or no rate".into());
    }
    let samples: Vec<f32> = match (tag, bits) {
        (1, 8) => data
            .iter()
            .map(|b| (f32::from(*b) - 128.0) / 128.0)
            .collect(),
        (1, 16) => data
            .as_chunks::<2>()
            .0
            .iter()
            .map(|c| f32::from(i16::from_le_bytes(*c)) / 32768.0)
            .collect(),
        (1, 24) => data
            .as_chunks::<3>()
            .0
            .iter()
            .map(|c| (i32::from_le_bytes([0, c[0], c[1], c[2]]) >> 8) as f32 / 8_388_608.0)
            .collect(),
        (1, 32) => data
            .as_chunks::<4>()
            .0
            .iter()
            .map(|c| i32::from_le_bytes(*c) as f32 / 2_147_483_648.0)
            .collect(),
        (3, 32) => data
            .as_chunks::<4>()
            .0
            .iter()
            .map(|c| f32::from_le_bytes(*c))
            .collect(),
        _ => {
            return Err(format!(
                "WAV format {tag} with {bits}-bit samples is not supported"
            ));
        }
    };
    Ok(Pcm {
        rate: rate as u32,
        channels,
        samples,
    })
}

/// A sound resource (format 1, one sampled-sound synthesizer, a buffer command) of 8-bit mono samples at `rate`
/// (the sound's own rate when absent; at most 65,535 samples a second). Channels are averaged.
pub fn encode_snd(pcm: &Pcm, rate: Option<u32>) -> Result<(Vec<u8>, u32, f64)> {
    let target = rate.unwrap_or(pcm.rate).clamp(1000, 65535);
    let mono: Vec<f32> = pcm
        .samples
        .chunks_exact(pcm.channels)
        .map(|frame| frame.iter().sum::<f32>() / pcm.channels as f32)
        .collect();
    if mono.is_empty() {
        return Err("the sound holds no samples".into());
    }
    let count = ((mono.len() as f64) * f64::from(target) / f64::from(pcm.rate))
        .round()
        .max(1.0) as usize;
    let mut samples = Vec::with_capacity(count);
    for n in 0..count {
        let position = n as f64 * f64::from(pcm.rate) / f64::from(target);
        let low = (position.floor() as usize).min(mono.len() - 1);
        let high = (low + 1).min(mono.len() - 1);
        let t = (position - low as f64) as f32;
        let value = mono[low] * (1.0 - t) + mono[high] * t;
        samples.push((value.clamp(-1.0, 1.0) * 127.0 + 128.0).round() as u8);
    }
    if samples.len() > 8 * 1024 * 1024 {
        return Err("the sound is longer than the editor writes".into());
    }
    let mut out = vec![
        0, 1, 0, 1, 0, 5, 0, 0, 0, 0x80, 0, 1, 0x80, 0x51, 0, 0, 0, 0, 0, 20,
    ];
    out.extend_from_slice(&[0; 4]);
    out.extend_from_slice(&(samples.len() as u32).to_be_bytes());
    out.extend_from_slice(&(target << 16).to_be_bytes());
    out.extend_from_slice(&[0; 8]);
    out.extend_from_slice(&[0, 60]);
    out.extend_from_slice(&samples);
    let seconds = samples.len() as f64 / f64::from(target);
    Ok((out, target, seconds))
}
