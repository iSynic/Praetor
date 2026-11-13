use centurions_format::{Edit, Files, MAP_BYTES, notes};

fn files() -> Files {
    let mut files = Files::new();
    // Two notes; the bytes the game does not read (words 72 and 74, and what follows the words) are marked.
    files.insert("Data MD2".into(), vec![0xee; notes::RECORD * 2]);
    files.insert("Data LD".into(), vec![0; MAP_BYTES * 2]);
    files
}

fn note(number: usize, icon_size: i16) -> Edit {
    let mut marks = [[0i16; 3]; 10];
    marks[0] = [137, 3, 4];
    Edit::MapNote {
        note: number,
        marks,
        start_x: 10,
        start_y: 20,
        level: 1,
        picture: 0,
        icon_size,
        show: 0,
        bottom: 0,
        right: 0,
        text: "A place".into(),
    }
}

#[test]
fn a_note_is_changed_or_added_and_keeps_the_bytes_the_game_does_not_read() {
    let mut files = files();
    notes::patch(&mut files, &note(1, 16)).unwrap();
    notes::patch(&mut files, &note(2, 32)).unwrap();
    let bytes = &files["Data MD2"];
    assert_eq!(
        bytes.len(),
        notes::RECORD * 3,
        "a note just past the last adds one"
    );
    let row = &bytes[notes::RECORD..notes::RECORD * 2];
    assert_eq!(&row[0..6], &[0, 137, 0, 3, 0, 4]);
    assert_eq!(&row[72..76], &[0xee; 4], "words 72 and 74 are kept");
    assert_eq!(row[84], 7);
    assert_eq!(&row[85..92], b"A place");
    assert_eq!(row[92], 0xee, "what follows the words is kept");
    let view = notes::view(&files).unwrap();
    assert_eq!(view["notes"][2]["icon_size"], 32);
    // A cell of 0 divides by zero in the game; a note past 18, a map that is not there and a cell off the map are refused.
    assert!(notes::patch(&mut files, &note(0, 0)).is_err());
    assert!(notes::patch(&mut files, &note(19, 16)).is_err());
    assert!(notes::patch(&mut files, &note(5, 16)).is_err());
    let mut elsewhere = note(0, 16);
    if let Edit::MapNote { level, .. } = &mut elsewhere {
        *level = 2;
    }
    assert!(notes::patch(&mut files, &elsewhere).is_err());
}
