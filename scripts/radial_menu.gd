class_name RadialMenu
extends Control
## Polytopia-style ring of round option buttons above a tapped building.
## Options come from a provider callable so costs and locks stay live:
## each option is {"id", "icon", "title", "note", "enabled", "ring"}; rings
## 1 and 2 sit on wider arcs outside ring 0.

signal chosen(id: String)
signal closed

const BUTTON_R := 44.0
const OUTLINE := Color("#2b2118")

var center: Vector2
var provider: Callable
var _art := {}


func _init(at: Vector2, options_provider: Callable) -> void:
	center = at
	provider = options_provider
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


## Each ring's buttons fan across arcs above the building. An arc holds only
## as many buttons as fit side by side on screen; the rest wrap onto the next,
## wider arc, so labels never overlap on a narrow phone.
const ARC_GAP := 150.0  # between arcs: a button plus its two label lines
const MIN_SPACING := 148.0  # between buttons on one arc: fits a label


func button_positions(options: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	result.resize(options.size())
	var radius := 0.0
	for ring in 3:
		var idxs := []
		for i in options.size():
			if options[i].get("ring", 0) == ring:
				idxs.append(i)
		var placed := 0
		while placed < idxs.size():
			radius = (130.0 if idxs.size() <= 2 else 215.0) if radius == 0.0 else radius + ARC_GAP
			# Angles from straight up (positive = right) that stay on screen.
			var margin := BUTTON_R + 30
			var right := asin(clampf((size.x - margin - center.x) / radius, -1, 1))
			var left := -asin(clampf((center.x - margin) / radius, -1, 1))
			var limit := deg_to_rad(80)
			left = maxf(left, -limit)
			right = minf(right, limit)
			var span := maxf(right - left, 0.0) * radius
			var fit := int(span / MIN_SPACING) + 1
			var n := mini(fit, idxs.size() - placed)
			var step := 0.0 if n == 1 else minf(span / (n - 1), MIN_SPACING * 1.2) / radius
			var mid := clampf(0.0, left + step * (n - 1) / 2, right - step * (n - 1) / 2)
			for k in n:
				var a := mid + (k - (n - 1) / 2.0) * step - PI / 2
				var p := center + Vector2.from_angle(a) * radius
				p.x = clampf(p.x, BUTTON_R + 8, size.x - BUTTON_R - 8)
				p.y = clampf(p.y, BUTTON_R + 8, size.y - BUTTON_R - 60)
				result[idxs[placed + k]] = p
			placed += n
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
		draw_line(center, p, Color(1, 1, 1, 0.12), 2)
		# Parchment disc with a wooden rim, gold-edged when it can be bought.
		draw_circle(p, BUTTON_R, OUTLINE)
		draw_circle(p, BUTTON_R - 2, Color("#8a5a33") if on else Color("#555049"))
		draw_circle(p, BUTTON_R - 7, Color("#f3e6c8") if on else Color("#9a958a"))
		if on:
			draw_arc(p, BUTTON_R - 1, 0, TAU, 48, Color("#f9ca24"), 3)
		if o.get("art", {}).is_empty():
			_draw_glyph(o.icon, p, 1.0 if on else 0.5)
		else:
			_draw_icon_art(o.art, p, on)
		if o.note in ["built", "done"]:
			# Already owned: a green check on the rim.
			var b := p + Vector2(BUTTON_R - 10, -BUTTON_R + 10)
			draw_circle(b, 12, OUTLINE)
			draw_circle(b, 10, Color("#27ae60"))
			draw_polyline(PackedVector2Array([b + Vector2(-5, 0), b + Vector2(-1, 4), b + Vector2(5, -4)]), Color.WHITE, 3)
		var label_color := Color.WHITE if on else Color(1, 1, 1, 0.55)
		_centered_text(font, o.title, p + Vector2(0, BUTTON_R + 20), 18, label_color)
		var lines: PackedStringArray = o.note.split("\n")
		for k in lines.size():
			_centered_text(font, lines[k], p + Vector2(0, BUTTON_R + 38 + k * 17), 15, Color("#f9ca24") if on else Color(1, 1, 1, 0.45))


func _centered_text(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	at.x = clampf(at.x, w / 2 + 6, size.x - w / 2 - 6)  # keep labels on screen
	# Dark backing so labels stay readable over the map.
	draw_rect(Rect2(at + Vector2(-w / 2 - 4, -font_size + 2), Vector2(w + 8, font_size + 4)), Color(0, 0, 0, 0.55))
	draw_string(font, at - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The option's building art, fitted inside the disc; greyed out when locked.
func _draw_icon_art(art: Dictionary, c: Vector2, on: bool) -> void:
	var box := Vector2(66, 56)
	var sz: Vector2 = art.size
	sz *= minf(box.x / sz.x, box.y / sz.y)
	var rect := Rect2(c - sz / 2 + Vector2(0, 2), sz)
	var shade := Color.WHITE if on else Color(0.55, 0.55, 0.55, 0.85)
	var tint: Color = art.tint
	for layer in art.layers:
		var base := _tex(layer)
		if base:
			draw_texture_rect(base, rect, false, shade)
		var t := _tex(layer + "_tint")
		if t:
			draw_texture_rect(t, rect, false, tint * shade)
	if art.has("sails"):
		# Windmill sails, still, in an X.
		var hub: Vector2 = rect.position + rect.size * art.sails
		var blade: float = art.blade * rect.size.x
		for k in 4:
			var a := PI / 4 + k * PI / 2
			var tip := hub + Vector2.from_angle(a) * blade
			draw_line(hub, tip, OUTLINE, 3)
			var side := Vector2.from_angle(a + PI / 2) * blade * 0.22
			var root := hub + Vector2.from_angle(a) * blade * 0.35
			draw_colored_polygon(PackedVector2Array([root, tip, tip + side, root + side]), Color("#f5f1e6") * shade)
		draw_circle(hub, 2.5, OUTLINE)


func _tex(name: String) -> Texture2D:
	if not _art.has(name):
		var path := "res://assets/art/%s.svg" % name
		_art[name] = load(path) if ResourceLoader.exists(path) else null
	return _art[name]


## Simple drawn icon for options without building art.
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
		"barracks":  # crossed sticks
			draw_line(c + Vector2(-12, 12), c + Vector2(12, -12), Color("#8b5a2b", alpha), 4)
			draw_line(c + Vector2(12, 12), c + Vector2(-12, -12), Color("#8b5a2b", alpha), 4)
		"archery_range":  # target
			draw_circle(c, 14, Color("#e8d27a", alpha))
			draw_circle(c, 9, Color(1, 1, 1, alpha))
			draw_circle(c, 4, Color("#c0392b", alpha))
		"stables":  # horse head
			draw_rect(Rect2(c + Vector2(-6, -12), Vector2(10, 24)), Color("#7a4a26", alpha))
			draw_rect(Rect2(c + Vector2(-14, -12), Vector2(12, 8)), Color("#7a4a26", alpha))
			draw_circle(c + Vector2(-10, -9), 1.5, Color(0, 0, 0, alpha))
		"upgrade":  # up arrow
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -18), c + Vector2(-14, -2), c + Vector2(14, -2)]), gold)
			draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 16)), gold)
