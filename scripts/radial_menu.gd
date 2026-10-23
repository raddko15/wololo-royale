class_name RadialMenu
extends Control
## Polytopia-style ring of round option buttons above a tapped building.
## Options come from a provider callable so costs and locks stay live:
## each option is {"id", "icon", "title", "note", "enabled", "ring"}; ring 1
## options sit on a second, wider arc outside ring 0.

signal chosen(id: String)
signal closed

const BUTTON_R := 40.0

var center: Vector2
var provider: Callable


func _init(at: Vector2, options_provider: Callable) -> void:
	center = at
	provider = options_provider
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


## Each ring's buttons fan across the upper half-circle, kept inside the screen.
func button_positions(options: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	result.resize(options.size())
	for ring in 2:
		var idxs := []
		for i in options.size():
			if options[i].get("ring", 0) == ring:
				idxs.append(i)
		var count := idxs.size()
		var radius := (120.0 if count <= 2 else 185.0) + ring * 135.0  # wide enough that labels don't collide
		var edge := 0.2 + ring * 0.35  # outer arc is narrower so it stays on screen
		for n in count:
			var a := -PI / 2 if count == 1 else lerpf(PI + edge, TAU - edge, float(n) / (count - 1))
			var p := center + Vector2.from_angle(a) * radius
			p.x = clampf(p.x, BUTTON_R + 8, size.x - BUTTON_R - 8)
			p.y = clampf(p.y, BUTTON_R + 8, size.y - BUTTON_R - 60)
			result[idxs[n]] = p
	return result


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var options: Array = provider.call()
	var spots := button_positions(options)
	for i in options.size():
		if spots[i].distance_to(event.position) <= BUTTON_R:
			if options[i].enabled:
				chosen.emit(options[i].id)
			return
	closed.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	draw_arc(center, 50, 0, TAU, 40, Color("#f9ca24"), 3)
	var font := get_theme_default_font()
	var options: Array = provider.call()
	var spots := button_positions(options)
	for i in options.size():
		var o: Dictionary = options[i]
		var p := spots[i]
		var on: bool = o.enabled
		draw_line(center, p, Color(1, 1, 1, 0.25), 2)
		draw_circle(p, BUTTON_R, Color("#5d4a2f") if on else Color("#3a3a3a"))
		draw_arc(p, BUTTON_R, 0, TAU, 40, Color("#f9ca24") if on else Color("#1e1e1e"), 4)
		_draw_glyph(o.icon, p + Vector2(0, -6), 1.0 if on else 0.4)
		var label_color := Color.WHITE if on else Color(1, 1, 1, 0.55)
		_centered_text(font, o.title, p + Vector2(0, BUTTON_R + 20), 20, label_color)
		var lines: PackedStringArray = o.note.split("\n")
		for k in lines.size():
			_centered_text(font, lines[k], p + Vector2(0, BUTTON_R + 40 + k * 18), 16, Color("#f9ca24") if on else Color(1, 1, 1, 0.45))


func _centered_text(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	at.x = clampf(at.x, w / 2 + 6, size.x - w / 2 - 6)  # keep labels on screen
	# Dark backing so labels stay readable over the map.
	draw_rect(Rect2(at + Vector2(-w / 2 - 4, -font_size + 2), Vector2(w + 8, font_size + 4)), Color(0, 0, 0, 0.55))
	draw_string(font, at - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Simple drawn icon for each option.
func _draw_glyph(kind: String, c: Vector2, alpha: float) -> void:
	var gold := Color("#f9ca24", alpha)
	var wood := Color("#8b5a2b", alpha)
	var stone := Color("#bdc3c7", alpha)
	match kind:
		"era":  # star
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * (16.0 if k % 2 == 0 else 7.0))
			draw_colored_polygon(pts, gold)
		"hut":
			draw_rect(Rect2(c + Vector2(-12, -2), Vector2(24, 16)), wood)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -2), c + Vector2(0, -16), c + Vector2(16, -2)]), Color("#b39143", alpha))
		"towers":
			for x in [-10, 6]:
				draw_rect(Rect2(c + Vector2(x - 2, -2), Vector2(3, 16)), wood)
			draw_rect(Rect2(c + Vector2(-12, -12), Vector2(24, 10)), wood)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -12), c + Vector2(0, -22), c + Vector2(14, -12)]), Color("#c0392b", alpha))
		"gold":
			for p in [Vector2(-7, 4), Vector2(7, 5), Vector2(0, -6)]:
				draw_circle(c + p, 7, gold)
		"stone":
			draw_rect(Rect2(c + Vector2(-14, 0), Vector2(13, 11)), stone)
			draw_rect(Rect2(c + Vector2(1, 0), Vector2(13, 11)), stone.darkened(0.1))
			draw_rect(Rect2(c + Vector2(-7, -12), Vector2(14, 11)), stone.darkened(0.2))
		"worker":
			draw_circle(c, 12, Color("#f5f6fa", alpha))
			draw_arc(c, 12, 0, TAU, 16, Color(0, 0, 0, alpha), 2)
			draw_line(c + Vector2(14, -12), c + Vector2(14, 0), gold, 3)
			draw_line(c + Vector2(8, -6), c + Vector2(20, -6), gold, 3)
		"upgrade":  # up arrow
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(-14, -2), c + Vector2(14, -2)]), gold)
			draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 16)), gold)
