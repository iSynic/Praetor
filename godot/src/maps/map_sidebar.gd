extends VBoxContainer
## The left of the Maps workspace: the maps, the floors to paint with, and the
## layers the canvas shows.
signal map_requested(id: int)
signal tile_chosen(tile: int, alt: bool)
signal layer_toggled(layer: String, on: bool)
signal add_map_requested
signal folder_requested
## What the palette paints: the floor (its icons too) or the object layer.
signal target_changed(target: String)
const RecordList = preload("res://src/widgets/record_list.gd")
const TilePalette = preload("res://src/tile_palette.gd")
const Tokens = preload("res://theme/editor_tokens.gd")

var maps := RecordList.new()
var palette := TilePalette.new()
var _tabs := ButtonGroup.new()
var _tile_name := Label.new()
var _tile_info := Label.new()
var _toggles: Dictionary = {}
var _names: Dictionary = {}
var _icons_tab: Button
var _no_artwork := VBoxContainer.new()
var _no_artwork_text := Label.new()
var _no_artwork_button := Button.new()


func _init() -> void:
	add_theme_constant_override("separation", 14)
	maps.title = "Maps"
	maps.filter_placeholder = "Filter maps"
	maps.custom_minimum_size.y = 230
	maps.set_columns([{"title": "", "width": 0}, {"title": "", "width": 72, "mono": true}, {"title": "", "width": 48, "mono": true, "right": true}])
	maps.row_selected.connect(func(id): if id != null: map_requested.emit(int(id)))
	maps.can_add = true
	maps.add_requested.connect(func(): add_map_requested.emit())
	add_child(maps)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.theme_type_variation = &"CaptionMuted"
	title.text = "PALETTE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for entry in [["Floor", "floor"], ["Icons", "icons"], ["Objects", "objects"]]:
		var chip := Button.new()
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.button_group = _tabs
		chip.text = entry[0]
		chip.button_pressed = entry[1] == "floor"
		chip.pressed.connect(func():
			# Objects are buildings and icons, chosen with the buttons of the tool bar, so the floor's palette is hidden.
			palette.mode = "icons" if entry[1] == "icons" else "floor"
			palette.visible = entry[1] != "objects"
			target_changed.emit("object" if entry[1] == "objects" else "floor"))
		if entry[1] == "icons": _icons_tab = chip
		head.add_child(chip)
	add_child(head)
	palette.chosen.connect(func(tile, alt): tile_chosen.emit(tile, alt))
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(palette)
	# Without the game's artwork the map shows numbers; this says why and, in a development run, where to point it.
	_no_artwork.add_theme_constant_override("separation", 6)
	_no_artwork_text.theme_type_variation = &"Muted"
	_no_artwork_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_artwork.add_child(_no_artwork_text)
	_no_artwork_button.text = "Choose the New Centurions folder…"
	_no_artwork_button.pressed.connect(func(): folder_requested.emit())
	_no_artwork.add_child(_no_artwork_button)
	_no_artwork.visible = false
	add_child(_no_artwork)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	_tile_name.theme_type_variation = &"Strong"
	foot.add_child(_tile_name)
	_tile_info.theme_type_variation = &"Dim"
	_tile_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_info.clip_text = true
	foot.add_child(_tile_info)
	var alt := Label.new()
	alt.theme_type_variation = &"Dim"
	alt.text = "Alt-click picks"
	foot.add_child(alt)
	add_child(foot)
	var layers := Label.new()
	layers.theme_type_variation = &"CaptionMuted"
	layers.text = "LAYERS"
	add_child(layers)
	for entry in [["floor", "Floor"], ["objects", "Objects"], ["triggers", "Walking triggers"], ["regions", "Regions"], ["starts", "Stage starts"], ["secrets", "Secret cells"]]:
		add_child(_layer_row(entry[0], entry[1]))


func _layer_row(layer: String, text: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = true
	toggle.toggled.connect(func(on): layer_toggled.emit(layer, on))
	row.add_child(toggle)
	_toggles[layer] = toggle
	_names[layer] = [label, text]
	return row


## The map rows: `counts` and `terrains` hold what is known of each map.
func show_maps(count: int, counts: Dictionary, terrains: Dictionary, current: int) -> void:
	var rows: Array = []
	for id in range(count):
		rows.append({"id": id, "cells": ["Map %d" % id, ("terrain %d" % int(terrains[id])) if terrains.has(id) else "", ("%d W" % int(counts[id])) if counts.has(id) else ""]})
	maps.set_rows(rows)
	maps.set_count(count)
	maps.select(current)


## Counts beside the layer names.
func show_counts(triggers: int, regions: int, starts: int) -> void:
	for entry in [["triggers", triggers], ["regions", regions], ["starts", starts]]:
		_names[entry[0]][0].text = "%s · %d" % [_names[entry[0]][1], entry[1]]


func set_layer(layer: String, on: bool) -> void:
	if _toggles.has(layer): _toggles[layer].set_pressed_no_signal(on)


## The footer under the palette: the tile in use and where it comes from.
func show_tile(tile: int, info: String) -> void:
	palette.current = tile
	_tile_name.text = "Tile %d" % tile
	_tile_info.text = info


## Says why the map has no artwork. `folder_missing` is true when no installation was found at all.
func show_artwork(available: bool, folder_missing: bool, can_choose: bool) -> void:
	_no_artwork.visible = not available and folder_missing
	_no_artwork_text.text = "The floor needs the game's artwork, and no New Centurions folder was found." + ("" if can_choose else " Place the editor in that folder.")
	_no_artwork_button.visible = can_choose


func show_icons_available(any: bool) -> void:
	_icons_tab.disabled = not any
