use centurions_format::script_codes::{self, Kind, validate_extra_word};

#[test]
fn the_table_is_whole_and_every_authorable_code_says_what_its_values_are() {
    let codes = script_codes::codes();
    let mut seen = std::collections::BTreeSet::new();
    for code in codes {
        assert!(seen.insert(code.code), "code {} twice", code.code);
        assert!(
            code.ecodes.len() <= 5,
            "code {} lists more than five E-Codes",
            code.code
        );
        if !code.authorable {
            continue;
        }
        let id = code
            .id
            .as_ref()
            .unwrap_or_else(|| panic!("code {} has no ID kind", code.code));
        assert_eq!(
            matches!(id, Kind::Extra),
            code.id_class == "extra",
            "code {}: the ID kind and the manual disagree about Extra Codes",
            code.code
        );
        if let Some(extra) = &code.extra {
            for (index, kind) in extra.iter().enumerate() {
                let named = code.ecodes.get(index).is_some_and(Option::is_some);
                assert_eq!(
                    named,
                    !matches!(kind, Kind::Unused),
                    "code {}: Extra Code {} is named exactly when it is used",
                    code.code,
                    index + 1
                );
            }
        }
        assert_eq!(
            code.extra.as_ref().map_or(0, Vec::len),
            if matches!(id, Kind::Extra) { 5 } else { 0 },
            "code {}: an Extra Codes row has five words",
            code.code
        );
    }
    // The thirteen codes the editor wrote before the table are still written.
    for op in [0, 1, 2, 4, 5, 9, 10, 14, 24, 39, 48, 100, 110] {
        assert!(script_codes::authorable(op), "code {op}");
    }
    let none = centurions_format::Files::new();
    assert!(validate_extra_word(&none, 2, 4, 5).is_ok());
    assert!(validate_extra_word(&none, 2, 4, 3).is_err());
    assert!(validate_extra_word(&none, 2, 5, 0).is_err());
}

/// Every code the table lets the editor write is written, and read back, with the values its ID kind allows,
/// and refused with the ones it does not.
#[test]
fn every_authorable_code_is_written_with_its_values_and_refused_others() {
    use centurions_format::{Files, ScriptFamily, scripts};
    let mut files = Files::new();
    for (name, stride) in [
        ("Data ED3", 42),
        ("Data SD2", 256),
        ("Data ED", 426),
        ("Data ED2", 516),
        ("Data TD", 88),
        ("Data SD", 3002),
        ("Data MD2", 340),
        ("Data MD", 288),
        ("Data EDCD", 10),
        ("Data Mission", 464),
    ] {
        files.insert(name.into(), vec![0; stride * 3]);
    }
    files.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    let mut written = 0;
    for code in script_codes::codes().iter().filter(|c| c.authorable) {
        let (valid, invalid): (Vec<i16>, Vec<i16>) = match code.id.as_ref().unwrap() {
            Kind::Ignored | Kind::Sound | Kind::Number => (vec![0, 7], vec![]),
            // What the game does not handle is refused: the edges of a hard range, or the count of zero of code 14.
            Kind::Soft {
                hard: Some(hard), ..
            } => match hard.as_ref() {
                Kind::Range { min, max } => (vec![*min, *max, 0], vec![*min - 1, *max + 1]),
                _ => (vec![1, 9, -9], vec![0]),
            },
            Kind::Soft { .. } => (vec![1, 9, -1], vec![]),
            Kind::Record { sign, .. } => (
                vec![1],
                if sign == "magnitude" {
                    vec![9999]
                } else {
                    vec![-1, 9999]
                },
            ),
            Kind::Extra => (vec![1], vec![-1, 9999]),
            Kind::SignedCount { min, max } => (vec![*min, -*max], vec![*max + 1, -*max - 1]),
            Kind::Enum { values } => (
                values.clone(),
                (-3..9).filter(|v| !values.contains(v)).take(2).collect(),
            ),
            Kind::Range { min, max } => (
                vec![*min, *max],
                min.checked_sub(1)
                    .into_iter()
                    .chain(max.checked_add(1))
                    .collect(),
            ),
            Kind::Stage => (vec![1, -1], vec![0, 21]),
            _ => (vec![], vec![]),
        };
        for id in valid {
            let mut f = files.clone();
            scripts::patch(&mut f, ScriptFamily::Story, 1, 0, 0, code.code, id)
                .unwrap_or_else(|e| panic!("code {} id {id}: {e}", code.code));
            let at = 42 + 8;
            assert_eq!(
                &f["Data ED3"][at..at + 2],
                &code.code.to_be_bytes(),
                "code {}",
                code.code
            );
            assert_eq!(
                &f["Data ED3"][42 + 24..42 + 26],
                &id.to_be_bytes(),
                "code {}",
                code.code
            );
            written += 1;
        }
        for id in invalid {
            let mut f = files.clone();
            assert!(
                scripts::patch(&mut f, ScriptFamily::Story, 1, 0, 0, code.code, id).is_err(),
                "code {} id {id}",
                code.code
            );
            assert_eq!(f, files);
        }
    }
    assert!(written >= 45);
}

/// Every word of every Extra Codes row a code reads takes the values its kind allows and refuses the rest.
#[test]
fn every_extra_code_word_takes_its_values_and_refuses_others() {
    use centurions_format::{Files, ScriptFamily, extras, scripts};
    let mut files = Files::new();
    for (name, stride) in [
        ("Data ED3", 42),
        ("Data ED", 426),
        ("Data TD", 88),
        ("Data SD", 3002),
        ("Data MD", 288),
        ("Data BD", 1372),
        ("Data TD3", 40),
        ("Data EDCD", 10),
    ] {
        files.insert(name.into(), vec![0; stride * 3]);
    }
    files.insert("Data LD".into(), vec![0; centurions_format::MAP_BYTES]);
    let mut checked = 0;
    for code in script_codes::codes()
        .iter()
        .filter(|c| c.authorable && c.extra.is_some())
    {
        let mut f = files.clone();
        scripts::patch(&mut f, ScriptFamily::Story, 1, 0, 0, code.code, 1)
            .unwrap_or_else(|e| panic!("code {}: {e}", code.code));
        for (index, kind) in code.extra.as_ref().unwrap().iter().enumerate() {
            let (valid, invalid): (Vec<i16>, Vec<i16>) = match kind {
                Kind::Range { min, max } => (
                    vec![*min, *max],
                    min.checked_sub(1)
                        .into_iter()
                        .chain(max.checked_add(1))
                        .collect(),
                ),
                Kind::SignedCount { min, max } => (vec![*min, -*max], vec![*max + 1]),
                Kind::Enum { values } => (
                    values.clone(),
                    (-3..20).filter(|v| !values.contains(v)).take(2).collect(),
                ),
                Kind::Map { keep_negative } => {
                    (if *keep_negative { vec![0, -1] } else { vec![0] }, vec![5])
                }
                Kind::Record { sign, .. } => match sign.as_str() {
                    "magnitude" => (vec![1, -1], vec![]),
                    "negative_ok" => (vec![1, -5], vec![9999]),
                    "minus_one_ok" => (vec![1, -1], vec![-2, 9999]),
                    _ => (vec![1], vec![-1, 9999]),
                },
                Kind::TreasureOrShop => (vec![1, 0, -1], vec![9999, -9999]),
                Kind::Spell => (vec![1101, 4707], vec![0, 1109, 1801, 5101, -1101]),
                Kind::Soft { hard: Some(_), .. } => (vec![1], vec![]),
                Kind::Soft { .. } => (vec![0, 3, 22, -7], vec![]),
                _ => (vec![0, 7, -7], vec![]),
            };
            for value in valid {
                extras::set_word(&mut f, 1, index, value).unwrap_or_else(|e| {
                    panic!("code {} E{} value {value}: {e}", code.code, index + 1)
                });
                let at = 10 + index * 2;
                assert_eq!(&f["Data EDCD"][at..at + 2], &value.to_be_bytes());
                checked += 1;
            }
            for value in invalid {
                let before = f.clone();
                assert!(
                    extras::set_word(&mut f, 1, index, value).is_err(),
                    "code {} E{} value {value}",
                    code.code,
                    index + 1
                );
                assert_eq!(f, before);
            }
        }
    }
    assert!(checked > 200);
}
