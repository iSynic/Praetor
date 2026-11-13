extends RefCounted
## The design tokens of the editor. tools/build_theme.gd turns them into
## editor_theme.tres; custom drawing reads them here.

const INK := Color("0a0f15")
const BAR := Color("0e141b")
const PANEL := Color("111922")
const PANEL2 := Color("16202b")
const RAISED := Color("1b2633")
const FIELD := Color("0b121a")
const LINE := Color("222e3b")
const LINE2 := Color("2d3b4c")
const TEXT := Color("e2e7ec")
const MUTED := Color("93a0ae")
const DIM := Color("5e6c7b")
const ACCENT := Color("3ccfab")
const ACCENT_INK := Color("04211a")
const ACCENT_SOFT := Color("3ccfab22")
const WARN := Color("e5a53c")
const ERR := Color("ef6662")
const ERR_INK := Color("2a0d0c")
const INFO := Color("6fb3e8")
const GOOD := Color("73c47b")
const SCRIM := Color("04070bb8")
const SHADOW := Color("00000099")

# Map overlays.
const TRIGGER := Color("5cc8f0")
const REGION := Color("e5bd62")
const START := Color("c793f3")
const SELECTED := Color("ffffff")

# One colour per record family.
const FAMILY := {
	"message": Color("6fb3e8"),
	"encounter": Color("b28df2"),
	"combat": Color("ef8159"),
	"flow": Color("7fc0b4"),
	"media": Color("d9b85c"),
	"reward": Color("79c77f"),
	"party": Color("e08fb0"),
	"world": Color("8fa8e0"),
	"shop": Color("e0c28f"),
	"ally": Color("a6d98f"),
	"preserved": Color("5e6c7b"),
}

## What a step does, finer than its family: the colour of the bar on a step and of its name in the picker.
const KIND := {
	"message": Color("6fb3e8"),
	"encounter": Color("b28df2"),
	"combat": Color("ef8159"),
	"test": Color("f2d24b"),
	"jump": Color("3fb0a4"),
	"pick": Color("f09ad0"),
	"vitals": Color("e5545f"),
	"gear": Color("b08a62"),
	"map": Color("7f9bf0"),
	"clock": Color("8ee0c8"),
	"mission": Color("c3b3f5"),
	"shop": Color("e8a23c"),
	"media": Color("38c3e6"),
	"reward": Color("4fbf6b"),
	"ally": Color("a6d14a"),
	"preserved": Color("5e6c7b"),
}

const RADIUS_KEY := 3
const RADIUS_BADGE := 4
const RADIUS_INPUT := 5
const RADIUS_BUTTON := 6
const RADIUS_CARD := 7
const RADIUS_MODAL := 10
const RADIUS_CHIP := 13

const TEXT_SIZE := 13
const SMALL_SIZE := 12
const CAPTION_SIZE := 11
const KEY_SIZE := 10
const HEADING_SIZE := 16

const CONTROL_HEIGHT := 30
const CHIP_HEIGHT := 26
const HEADER_HEIGHT := 48
const RAIL_WIDTH := 64
const STATUS_HEIGHT := 28

# Installed families are used until the OFL font files ship with the editor.
const SANS := ["Inter", "Segoe UI Variable Text", "Segoe UI", "Arial"]
const MONO := ["JetBrains Mono", "IBM Plex Mono", "Cascadia Mono", "Consolas", "Courier New"]


static func tint(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
