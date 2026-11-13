extends Control
## A line icon drawn on a 24-unit grid, so the editor ships no icon files.
const Tokens = preload("res://theme/editor_tokens.gd")

@export var glyph := "":
	set(value): glyph = value; queue_redraw()
@export var color := Tokens.MUTED:
	set(value): color = value; queue_redraw()
@export var extent := 16.0:
	set(value): extent = value; custom_minimum_size = Vector2(value, value); queue_redraw()

# Open strokes, closed strokes, arcs [cx, cy, r, from, to] and filled dots [cx, cy, r].
const SHAPES := {
	"maps": {"closed": [[4, 4, 20, 4, 20, 20, 4, 20]], "open": [[9.3, 4, 9.3, 20], [14.7, 4, 14.7, 20], [4, 9.3, 20, 9.3], [4, 14.7, 20, 14.7]]},
	"stages": {"open": [[5, 3, 5, 21]], "closed": [[5, 4, 19, 4, 16, 8.5, 19, 13, 5, 13]]},
	"triggers": {"closed": [[13, 2, 4, 14, 12, 14, 11, 22, 20, 10, 12, 10]]},
	"stories": {"open": [[12, 7, 8, 4, 3, 4, 3, 18, 8, 18, 12, 21, 16, 18, 21, 18, 21, 4, 16, 4, 12, 7, 12, 21]]},
	"encounters": {"open": [[6, 7.5, 6, 10, 12, 13, 18, 10, 18, 7.5], [12, 13, 12, 16.5]], "arcs": [[6, 5, 2.5, 0, 6.3], [18, 5, 2.5, 0, 6.3], [12, 19, 2.5, 0, 6.3]]},
	"messages": {"closed": [[4, 4, 20, 4, 20, 16, 9, 16, 4, 20]]},
	"battles": {"open": [[4, 3, 17, 16], [20, 3, 7, 16], [14, 19, 20, 13], [4, 13, 10, 19], [17, 16, 20.5, 19.5], [7, 16, 3.5, 19.5]]},
	"monsters": {"arcs": [[12, 11, 8, 2.6, 6.83], [9, 10.5, 1.4, 0, 6.3], [15, 10.5, 1.4, 0, 6.3]], "open": [[5.2, 15.2, 8, 17.5, 8, 21, 16, 21, 16, 17.5, 18.8, 15.2]]},
	"rewards": {"closed": [[6, 3, 18, 3, 22, 9, 12, 21, 2, 9]], "open": [[2, 9, 22, 9], [9, 3, 8, 9, 12, 21, 16, 9, 15, 3]]},
	"items": {"closed": [[12, 2, 21, 7, 21, 17, 12, 22, 3, 17, 3, 7]], "open": [[3, 7, 12, 12, 21, 7], [12, 12, 12, 22]]},
	"shops": {"closed": [[4, 10, 20, 10, 20, 21, 4, 21]], "open": [[4, 10, 3, 7, 5, 3, 19, 3, 21, 7, 20, 10], [9, 21, 9, 15, 15, 15, 15, 21]]},
	"problems": {"closed": [[12, 3, 22, 20, 2, 20]], "open": [[12, 9, 12, 14]], "dots": [[12, 17, 1.1]]},
	"export": {"open": [[12, 15, 12, 3], [7, 8, 12, 3, 17, 8], [4, 15, 4, 20, 20, 20, 20, 15]]},
	"import": {"open": [[12, 3, 12, 15], [7, 10, 12, 15, 17, 10], [4, 15, 4, 20, 20, 20, 20, 15]]},
	"folder": {"closed": [[3, 6, 9, 6, 11, 8, 21, 8, 21, 19, 3, 19]]},
	"calendar": {"closed": [[4, 6, 20, 6, 20, 21, 4, 21]], "open": [[4, 11, 20, 11], [8, 3, 8, 8], [16, 3, 16, 8]]},
	"search": {"arcs": [[11, 11, 7, 0, 6.3]], "open": [[16.2, 16.2, 21, 21]]},
	"lock": {"closed": [[5, 11, 19, 11, 19, 21, 5, 21]], "open": [[8, 11, 8, 7], [16, 7, 16, 11]], "arcs": [[12, 7, 4, 3.14, 6.28]]},
	"close": {"open": [[6, 6, 18, 18], [18, 6, 6, 18]]},
	"plus": {"open": [[12, 5, 12, 19], [5, 12, 19, 12]]},
	"undo": {"open": [[9, 14, 4, 9, 9, 4], [4, 9, 14.5, 9], [14.5, 20, 11, 20]], "arcs": [[14.5, 14.5, 5.5, -1.57, 1.57]]},
	"redo": {"open": [[15, 14, 20, 9, 15, 4], [20, 9, 9.5, 9], [9.5, 20, 13, 20]], "arcs": [[9.5, 14.5, 5.5, 1.57, 4.71]]},
	"play": {"closed": [[7, 4, 20, 12, 7, 20]]},
	"back": {"open": [[19, 12, 5, 12], [11, 6, 5, 12, 11, 18]]},
	"forward": {"open": [[5, 12, 19, 12], [13, 6, 19, 12, 13, 18]]},
	"chevron_down": {"open": [[6, 9, 12, 15, 18, 9]]},
	"chevron_up": {"open": [[6, 15, 12, 9, 18, 15]]},
	"chevron_right": {"open": [[9, 6, 15, 12, 9, 18]]},
	"columns": {"closed": [[3, 4, 21, 4, 21, 20, 3, 20]], "open": [[12, 4, 12, 20]]},
	"dot": {"dots": [[12, 12, 7]]},
}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(extent, extent)


func _draw() -> void:
	var side := minf(extent, minf(size.x, size.y))
	paint(self, glyph, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), color)


## Draws `glyph` inside `rect` on any canvas item.
static func paint(item: CanvasItem, glyph: String, rect: Rect2, color: Color) -> void:
	var shape: Dictionary = SHAPES.get(glyph, {})
	var unit := rect.size.x / 24.0
	var width := maxf(1.25, 1.9 * unit)
	for closed in [false, true]:
		for stroke in shape.get("closed" if closed else "open", []):
			var points := PackedVector2Array()
			for index in range(0, stroke.size(), 2): points.append(rect.position + Vector2(stroke[index], stroke[index + 1]) * unit)
			if closed: points.append(points[0])
			item.draw_polyline(points, color, width, true)
	for arc in shape.get("arcs", []):
		item.draw_arc(rect.position + Vector2(arc[0], arc[1]) * unit, arc[2] * unit, arc[3], arc[4], 24, color, width, true)
	for dot in shape.get("dots", []):
		item.draw_circle(rect.position + Vector2(dot[0], dot[1]) * unit, dot[2] * unit, color, true, -1.0, true)


## A filled dot as a texture, for buttons that carry a mark beside their text.
static func dot_texture(color: Color, diameter := 8) -> ImageTexture:
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var centre := (diameter - 1) / 2.0
	for x in range(diameter):
		for y in range(diameter):
			var reach := Vector2(x - centre, y - centre).length()
			image.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(diameter / 2.0 - reach, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
