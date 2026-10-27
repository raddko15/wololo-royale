class_name UiStyle
extends RefCounted
## Shared look for the game's UI, matching the start screen: dark wood with a
## gold trim, parchment cards, wooden plaque buttons and Cinzel lettering.

const INK := Color("#3b2614")
const PARCHMENT := Color("#f3e6c4")
const CREAM := Color("#f5e6c0")
const GOLD := Color("#d4a017")
const WOOD := Color("#3b2a1c")

static var _fonts := {}


## Cinzel at a weight (400 regular … 900 black), cached.
static func cinzel(weight := 700) -> FontVariation:
	if not _fonts.has(weight):
		var f := FontVariation.new()
		f.base_font = load("res://assets/fonts/Cinzel.ttf")
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = f
	return _fonts[weight]


## Dark wooden bar with a gold rule on the edge facing the map (`top_edge`:
## the rule is along its top, for the card bar; otherwise along its bottom).
static func wood_bar(top_edge := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = WOOD
	s.border_color = GOLD
	if top_edge:
		s.border_width_top = 3
	else:
		s.border_width_bottom = 3
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## A small wooden plaque button (header buttons).
static func plaque(b: Button, font_size := 15) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", cinzel(700))
	b.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var on: bool = state.contains("pressed")
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#7a5230") if on else Color("#5b3d22")
		s.border_color = Color("#f1c40f") if on else Color("#2b1d10")
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 2
		s.content_margin_bottom = 2
		b.add_theme_stylebox_override(state, s)
