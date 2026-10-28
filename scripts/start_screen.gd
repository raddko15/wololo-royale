class_name StartScreen
extends Control
## The opening screen: a parchment sheet on dark wooden planks under a red
## title banner, wooden plaques to pick the opponent's strength, and one card
## per civilization with its heraldic emblem, bonus and unique unit.

signal chosen(civ_id: String, difficulty: String)

const INK := Color("#3b2614")
const PARCHMENT := Color("#e8d5a8")
const GOLD := Color("#f1c40f")

var difficulty := "normal"
var _title_font: FontVariation
var _bold_font: FontVariation
var _body: VBoxContainer


func _init(level := "normal") -> void:
	difficulty = level
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cinzel: FontFile = load("res://assets/fonts/Cinzel.ttf")
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_title_font = FontVariation.new()
	_title_font.base_font = cinzel
	_title_font.variation_opentype = {wght: 900}
	_bold_font = FontVariation.new()
	_bold_font.base_font = cinzel
	_bold_font.variation_opentype = {wght: 700}
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 190)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_body)
	var motto := _heading("Build · Advance · Conquer")
	motto.add_theme_font_size_override("font_size", 24)
	motto.add_theme_color_override("font_color", Color("#7a5230"))
	_body.add_child(motto)
	_body.add_child(_ornament())
	_body.add_child(_spacer(20))
	_body.add_child(_heading("Opponent"))
	_body.add_child(_difficulty_row())
	_body.add_child(_spacer(10))
	_body.add_child(_heading("Choose your civilization"))
	var civs: Dictionary = GameConfig.data().civs
	for id in civs:
		_body.add_child(_civ_card(id, civs[id]))


## A thin rule with a gold diamond in the middle.
func _ornament() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 24
	c.draw.connect(func():
		var mid := c.size / 2
		c.draw_line(Vector2(mid.x - 170, mid.y), Vector2(mid.x - 16, mid.y), Color("#8a6a3a"), 2)
		c.draw_line(Vector2(mid.x + 16, mid.y), Vector2(mid.x + 170, mid.y), Color("#8a6a3a"), 2)
		var d := PackedVector2Array([mid + Vector2(0, -9), mid + Vector2(9, 0), mid + Vector2(0, 9), mid + Vector2(-9, 0)])
		c.draw_colored_polygon(d, GOLD)
		c.draw_polyline(d + PackedVector2Array([d[0]]), Color("#2b1d10"), 1.5))
	return c


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _bold_font)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", INK)
	return l


## Easy / Normal / Hard computer opponents, or a Friend online, as wooden
## plaques; the chosen one has a gold rim.
func _difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for level in ["easy", "normal", "hard", "friend"]:
		var b := Button.new()
		b.text = level.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = level == difficulty
		b.custom_minimum_size = Vector2(142, 66)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", _bold_font)
		b.add_theme_font_size_override("font_size", 26)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, Color("#f5e6c0"))
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var on: bool = state.contains("pressed")
			var plank := StyleBoxFlat.new()
			plank.bg_color = Color("#7a5230") if on else Color("#5b3d22")
			plank.border_color = GOLD if on else Color("#2b1d10")
			plank.set_border_width_all(4)
			plank.set_corner_radius_all(8)
			plank.shadow_color = Color(0, 0, 0, 0.35)
			plank.shadow_size = 4
			plank.shadow_offset = Vector2(0, 3)
			b.add_theme_stylebox_override(state, plank)
		b.pressed.connect(func(): difficulty = level)
		row.add_child(b)
	return row


## A civilization card: its emblem, name, bonus, building style and unique unit.
func _civ_card(id: String, civ: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size.y = 150
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#f3e6c4")
	style.border_color = Color(civ.color).darkened(0.15)
	style.set_border_width_all(4)
	style.border_width_left = 10
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 16
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/art/civ_%s.svg" % id)
	icon.custom_minimum_size = Vector2(96, 112)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name := Label.new()
	name.text = civ.name
	name.add_theme_font_override("font", _title_font)
	name.add_theme_font_size_override("font_size", 36)
	name.add_theme_color_override("font_color", Color(civ.color).darkened(0.35))
	text.add_child(name)
	var unique := ""
	for u in GameConfig.data().units:
		if GameConfig.data().units[u].get("civ", "") == id:
			unique = GameConfig.data().units[u].name
	var look := "Classical: wood to marble" if civ.style == "classical" else "Medieval: forts and castles"
	var bonus: String = civ.bonus
	for line in [bonus.left(1).to_upper() + bonus.substr(1), look + (" · unique unit: " + unique if unique != "" else "")]:
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", INK)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(l)
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(id, difficulty))
	return card


func _draw() -> void:
	# Dark wooden planks with seams and nails.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#3b2a1c"))
	var plank_w := 90.0
	var x := 0.0
	var k := 0
	while x < size.x:
		var shade := Color("#45311f") if k % 2 == 0 else Color("#3f2c1c")
		draw_rect(Rect2(x, 0, plank_w, size.y), shade)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("#22170d"), 3)
		for y in [60.0, size.y - 60.0]:
			draw_circle(Vector2(x + 12, y), 3, Color("#1a110a"))
			draw_circle(Vector2(x + plank_w - 12, y), 3, Color("#1a110a"))
		x += plank_w
		k += 1
	# Parchment sheet behind the content, with a darker edge and inner rule.
	var sheet := Rect2(Vector2(24, 140), Vector2(size.x - 48, size.y - 180))
	draw_rect(sheet.grow(6), Color(0, 0, 0, 0.35))
	draw_rect(sheet, PARCHMENT)
	draw_rect(sheet, Color("#8a6a3a"), false, 4)
	draw_rect(sheet.grow(-12), Color("#b89a63"), false, 2)
	for corner in [sheet.position, Vector2(sheet.end.x, sheet.position.y), sheet.end, Vector2(sheet.position.x, sheet.end.y)]:
		draw_circle(corner, 9, Color("#8a6a3a"))
		draw_circle(corner, 5, GOLD)
	_draw_banner(Vector2(size.x / 2, 112))


## Red cloth banner with folded tails carrying the game's name.
func _draw_banner(c: Vector2) -> void:
	var w := size.x - 120
	var h := 84.0
	var top := c.y - h / 2
	var left := c.x - w / 2
	var right := c.x + w / 2
	for side in [-1.0, 1.0]:
		var edge := left if side < 0 else right
		var tail := PackedVector2Array([
			Vector2(edge - side * 10, top + 18), Vector2(edge + side * 44, top + 18),
			Vector2(edge + side * 30, top + h / 2 + 9), Vector2(edge + side * 44, top + h + 18),
			Vector2(edge - side * 10, top + h + 18)])
		draw_colored_polygon(tail, Color("#6e1f17"))
		draw_polyline(tail + PackedVector2Array([tail[0]]), Color("#2b1d10"), 3)
	var body := Rect2(Vector2(left, top), Vector2(w, h))
	draw_rect(body, Color("#a93226"))
	draw_rect(Rect2(body.position, Vector2(w, h * 0.45)), Color("#c0392b"))
	draw_rect(body, Color("#2b1d10"), false, 3)
	draw_line(Vector2(left + 8, top + 8), Vector2(right - 8, top + 8), GOLD, 2)
	draw_line(Vector2(left + 8, top + h - 8), Vector2(right - 8, top + h - 8), GOLD, 2)
	var title := "WOLOLO ROYALE"
	var fs := 50
	var tw := _title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(c.x - tw / 2, c.y + fs * 0.36)
	draw_string(_title_font, at + Vector2(2, 3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	draw_string(_title_font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f5e6c0"))
