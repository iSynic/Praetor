//! Mac Roman conversion adapted from Providence; see docs/provenance.json.
use crate::Result;

pub fn decode(bytes: &[u8]) -> String {
    decode_mac_roman_name(bytes).replace('\r', "\n")
}

pub fn encode(text: &str) -> Result<Vec<u8>> {
    if text.contains('\0') {
        return Err("NUL is not authorable text".into());
    }
    encode_mac_roman_name(&text.replace('\n', "\r"))
        .ok_or_else(|| "text contains characters outside Mac Roman".into())
}

fn decode_mac_roman_name(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|byte| match *byte {
            0x80..=0xff => MAC_ROMAN_HIGH[usize::from(*byte - 0x80)],
            _ => char::from(*byte),
        })
        .collect()
}

fn encode_mac_roman_name(value: &str) -> Option<Vec<u8>> {
    value
        .chars()
        .map(|character| {
            if character.is_ascii() {
                Some(character as u8)
            } else {
                MAC_ROMAN_HIGH
                    .iter()
                    .position(|candidate| *candidate == character)
                    .map(|index| index as u8 + 0x80)
            }
        })
        .collect()
}

const MAC_ROMAN_HIGH: [char; 128] = [
    'Ä', 'Å', 'Ç', 'É', 'Ñ', 'Ö', 'Ü', 'á', 'à', 'â', 'ä', 'ã', 'å', 'ç', 'é', 'è', 'ê', 'ë', 'í',
    'ì', 'î', 'ï', 'ñ', 'ó', 'ò', 'ô', 'ö', 'õ', 'ú', 'ù', 'û', 'ü', '†', '°', '¢', '£', '§', '•',
    '¶', 'ß', '®', '©', '™', '´', '¨', '≠', 'Æ', 'Ø', '∞', '±', '≤', '≥', '¥', 'µ', '∂', '∑', '∏',
    'π', '∫', 'ª', 'º', 'Ω', 'æ', 'ø', '¿', '¡', '¬', '√', 'ƒ', '≈', '∆', '«', '»', '…',
    '\u{00a0}', 'À', 'Ã', 'Õ', 'Œ', 'œ', '–', '—', '“', '”', '‘', '’', '÷', '◊', 'ÿ', 'Ÿ', '⁄',
    '€', '‹', '›', 'ﬁ', 'ﬂ', '‡', '·', '‚', '„', '‰', 'Â', 'Ê', 'Á', 'Ë', 'È', 'Í', 'Î', 'Ï', 'Ì',
    'Ó', 'Ô', '\u{f8ff}', 'Ò', 'Ú', 'Û', 'Ù', 'ı', 'ˆ', '˜', '¯', '˘', '˙', '˚', '¸', '˝', '˛',
    'ˇ',
];
