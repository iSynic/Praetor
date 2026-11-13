//! Importing pictures, icons and sounds from ordinary files into the scenario's resources, listing the
//! resources of each kind, and exporting one to a file.
//!
//! An import is prepared first: the file is converted, and the reply shows what the game would hold (a preview,
//! how many colours were kept, whether the number is free) together with the resource's bytes. Nothing is written
//! until the editor applies a `resource_change` edit with those bytes.
use crate::media;
use centurions_format::resource_fork::Fork;
use centurions_format::{Files, Result, codecs, graphics};
use serde_json::{Value, json};
use std::path::Path;
use std::sync::Arc;

/// The kinds the editor imports, with the resource type each becomes.
fn resource_type(kind: &str) -> Result<&'static [u8; 4]> {
    match kind {
        "icon" => Ok(b"cicn"),
        "picture" => Ok(b"PICT"),
        "sound" => Ok(b"snd "),
        other => Err(format!("the editor does not import {other:?}")),
    }
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes
        .iter()
        .fold(String::with_capacity(bytes.len() * 2), |mut out, b| {
            let _ = write!(out, "{b:02x}");
            out
        })
}

/// Decodes a PNG file to RGBA.
fn decode_png(bytes: &[u8]) -> Result<graphics::Image> {
    let mut decoder = png::Decoder::new(std::io::Cursor::new(bytes));
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|e| e.to_string())?;
    let mut buffer = vec![
        0;
        reader
            .output_buffer_size()
            .ok_or("the picture is too large")?
    ];
    let info = reader.next_frame(&mut buffer).map_err(|e| e.to_string())?;
    let data = &buffer[..info.buffer_size()];
    let (width, height) = (info.width as usize, info.height as usize);
    if width == 0 || height == 0 || width > 4096 || height > 4096 {
        return Err("the picture must be 1 to 4096 pixels each way".into());
    }
    let rgba: Vec<u8> = match info.color_type {
        png::ColorType::Rgba => data.to_vec(),
        png::ColorType::Rgb => data
            .as_chunks::<3>()
            .0
            .iter()
            .flat_map(|p| [p[0], p[1], p[2], 255])
            .collect(),
        png::ColorType::GrayscaleAlpha => data
            .as_chunks::<2>()
            .0
            .iter()
            .flat_map(|p| [p[0], p[0], p[0], p[1]])
            .collect(),
        png::ColorType::Grayscale => data.iter().flat_map(|g| [*g, *g, *g, 255]).collect(),
        png::ColorType::Indexed => return Err("an indexed picture was not expanded".into()),
    };
    Ok(graphics::Image {
        width: width as u16,
        height: height as u16,
        rgba,
    })
}

fn scenario_fork(files: &Files) -> Option<Arc<Fork>> {
    crate::installation::scenario(files)
}

/// What the scenario and the game hold of each kind, by resource number.
pub fn list(files: &Files, installation: &Path) -> Result<Value> {
    let forks = crate::installation::named(installation)?;
    let mine = scenario_fork(files);
    let mut result = serde_json::Map::new();
    for (kind, name) in [
        ("icon", "icons"),
        ("picture", "pictures"),
        ("sound", "sounds"),
    ] {
        let rtype = resource_type(kind)?;
        let mut scenario = mine.as_ref().map(|f| f.ids(rtype)).unwrap_or_default();
        scenario.sort_unstable();
        let mut game: Vec<i16> = forks.iter().flat_map(|(_, f)| f.ids(rtype)).collect();
        game.sort_unstable();
        game.dedup();
        result.insert(name.into(), json!({"scenario":scenario,"game":game}));
    }
    Ok(Value::Object(result))
}

/// Converts a file to the resource of `kind` that would be saved as number `id`.
#[allow(clippy::too_many_arguments)]
pub fn prepare(
    files: &Files,
    installation: &Path,
    cache: &Path,
    kind: &str,
    path: &Path,
    id: i16,
    options: &Value,
) -> Result<Value> {
    let rtype = resource_type(kind)?;
    let path = crate::paths::checked_existing(path)?;
    let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
    if bytes.len() > 64 * 1024 * 1024 {
        return Err("the file is larger than 64 MB".into());
    }
    let mine = scenario_fork(files);
    let replaces = mine.as_ref().is_some_and(|f| f.get(rtype, id).is_some());
    let in_game = crate::installation::named(installation)?
        .iter()
        .any(|(_, f)| f.get(rtype, id).is_some());
    let mut warnings: Vec<String> = vec![];
    let mut reply = json!({"status":"ready","kind":kind,"resource_type":String::from_utf8_lossy(rtype),"id":id,
        "replaces":replaces,"in_game":in_game});
    let fit = codecs::Fit::parse(options["fit"].as_str().unwrap_or("inside"))?;
    let dither = options["dither"].as_bool();
    let data = match kind {
        "icon" | "picture" => {
            let source = decode_png(&bytes)?;
            reply["source_width"] = json!(source.width);
            reply["source_height"] = json!(source.height);
            let (image, converted, cost) = if kind == "icon" {
                let size = options["size"].as_u64().unwrap_or(32).clamp(8, 256) as usize;
                let image = codecs::fit(&source, size, size, fit);
                let (converted, cost) = codecs::encode_cicn(&image, dither.unwrap_or(false))?;
                (image, converted, cost)
            } else {
                let longest = usize::from(source.width.max(source.height));
                let image = if longest > 1024 {
                    let scale = 1024.0 / longest as f64;
                    codecs::fit(
                        &source,
                        (f64::from(source.width) * scale).round() as usize,
                        (f64::from(source.height) * scale).round() as usize,
                        codecs::Fit::Stretch,
                    )
                } else {
                    source.clone()
                };
                if longest > 1024 {
                    warnings.push("The picture is larger than 1024 pixels and was reduced.".into());
                }
                let (converted, cost) = codecs::encode_pict(&image, dither.unwrap_or(true))?;
                (image, converted, cost)
            };
            let back = if kind == "icon" {
                graphics::decode_cicn(&converted)
            } else {
                graphics::decode_pict(&converted)
            }
            .map_err(|e| e.to_string())?;
            reply["width"] = json!(image.width);
            reply["height"] = json!(image.height);
            reply["colours"] = json!(cost.colours);
            reply["far_percent"] = json!((cost.far * 1000.0).round() / 10.0);
            reply["preview"] = json!(media::cache_image(cache, &converted, &back)?);
            if cost.far > 0.01 {
                warnings.push(format!(
                    "{:.1}% of the pixels moved more than a small step when the colours were reduced to {}.",
                    cost.far * 100.0,
                    cost.colours
                ));
            }
            converted
        }
        _ => {
            let pcm = codecs::read_wav(&bytes)?;
            let wanted = options["rate"].as_u64().map(|r| r as u32);
            let (converted, rate, seconds) = codecs::encode_snd(&pcm, wanted)?;
            if pcm.rate > 65535 && wanted.is_none() {
                warnings
                    .push("The rate was lowered to fit the game's 65,535 samples a second.".into());
            }
            let (wav, _, _) = media::snd_to_wav(&converted)?;
            reply["rate"] = json!(rate);
            reply["seconds"] = json!(seconds);
            reply["source_rate"] = json!(pcm.rate);
            reply["source_channels"] = json!(pcm.channels);
            reply["preview"] = json!(media::cache_bytes(cache, &converted, "wav", &wav)?);
            if pcm.channels > 1 {
                warnings.push("The channels were averaged into one.".into());
            }
            warnings.push("The samples are written as 8 bits, as the game's own are.".into());
            converted
        }
    };
    reply["bytes"] = json!(data.len());
    reply["data"] = json!(hex(&data));
    reply["warnings"] = json!(warnings);
    Ok(reply)
}

/// Writes the picture, icon or sound with this number to a new file: a PNG for the first two, a WAV for a sound.
pub fn export(
    files: &Files,
    installation: &Path,
    kind: &str,
    id: i16,
    destination: &Path,
) -> Result<Value> {
    let rtype = resource_type(kind)?;
    let mut found = scenario_fork(files).and_then(|f| f.get(rtype, id).map(|r| r.data.clone()));
    if found.is_none() {
        found = crate::installation::named(installation)?
            .iter()
            .find_map(|(_, f)| f.get(rtype, id).map(|r| r.data.clone()));
    }
    let payload = found.ok_or_else(|| format!("no {kind} has the number {id}"))?;
    let out = match kind {
        "sound" => media::snd_to_wav(&payload)?.0,
        _ => {
            let image = if kind == "icon" {
                graphics::decode_cicn(&payload)
            } else {
                graphics::decode_pict(&payload)
            }
            .map_err(|e| e.to_string())?;
            let mut png = Vec::new();
            {
                let mut encoder =
                    png::Encoder::new(&mut png, u32::from(image.width), u32::from(image.height));
                encoder.set_color(png::ColorType::Rgba);
                encoder.set_depth(png::BitDepth::Eight);
                encoder
                    .write_header()
                    .map_err(|e| e.to_string())?
                    .write_image_data(&image.rgba)
                    .map_err(|e| e.to_string())?;
            }
            png
        }
    };
    let target = crate::paths::new_destination(destination, &[])?;
    std::fs::write(&target, out).map_err(|e| e.to_string())?;
    Ok(json!({"path":target}))
}
