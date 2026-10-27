class_name Card
extends PanelContainer
## A Clash Royale style card: press to tap or start a drag. Greyed out when not
## affordable; a green border and "AUTO" tag when it is training on repeat.

signal pressed
## The red ✕ in the corner was tapped: cancel the newest queued one.
signal cancel_pressed
## The skull in the bottom corner was tapped (villager card: delete one).
signal delete_pressed

const CANCEL_R := 17.0

var _title := Label.new()
var _cost := Label.new()
var _style := StyleBoxFlat.new()
var _queued := 0
var _deletable := false


func _init(title: String, icon: Control = null) -> void:
	custom_minimum_size = Vector2(110, 140)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style.set_corner_radius_all(10)
	_style.set_border_width_all(3)
	_style.content_margin_top = 4
	_style.content_margin_bottom = 4
	_style.shadow_color = Color(0, 0, 0, 0.35)
	_style.shadow_size = 3
	_style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", _style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	if icon:
		box.add_child(icon)
	for l in [_title, _cost]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.add_theme_color_override("font_color", UiStyle.INK)
		box.add_child(l)
	_title.text = title
	_title.add_theme_font_override("font", UiStyle.cinzel(800))
	_title.add_theme_font_size_override("font_size", 19)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_cost.add_theme_font_size_override("font_size", 16)
	# Fixed text space so a longer note (e.g. "2 queued") never makes the card
	# taller and shifts the map above it.
	_title.max_lines_visible = 1
	_cost.max_lines_visible = 2
	_cost.custom_minimum_size.y = 40
	set_state("", true, false)


func set_state(cost_text: String, enabled: bool, selected: bool, auto := false) -> void:
	_cost.text = ("AUTO · " if auto else "") + cost_text
	# Three-resource costs use a smaller font so they still fit on two lines.
	_cost.add_theme_font_size_override("font_size", 16 if _cost.text.length() <= 26 else 14)
	_cost.add_theme_color_override("font_color", Color("#1e7a34") if auto else UiStyle.INK)
	# A parchment card; faded when it cannot be afforded (an auto card stays bright).
	modulate.a = 1.0 if enabled or auto else 0.6
	_style.bg_color = UiStyle.PARCHMENT if enabled or auto else Color("#b9ab8c")
	if auto:
		_style.border_color = Color("#2ecc40")
	else:
		_style.border_color = Color("#f1c40f") if selected else Color("#8a6a3a")


## Shows the cancel ✕ while anything of this card is queued.
func set_queued(count: int) -> void:
	if count != _queued:
		_queued = count
		queue_redraw()


## Shows the delete skull in the bottom-left corner.
func set_deletable(on: bool) -> void:
	if on != _deletable:
		_deletable = on
		queue_redraw()


func _cancel_center() -> Vector2:
	return Vector2(size.x - CANCEL_R - 4, CANCEL_R + 4)


func _delete_center() -> Vector2:
	return Vector2(CANCEL_R + 4, size.y - CANCEL_R - 4)


func _draw() -> void:
	if _deletable:
		# Skull: round cranium, jaw, dark eyes.
		var d := _delete_center()
		draw_circle(d, CANCEL_R, Color("#1e1e1e"))
		draw_circle(d + Vector2(0, -2), 9, Color("#ece4cf"))
		draw_rect(Rect2(d + Vector2(-5, 4), Vector2(10, 6)), Color("#ece4cf"))
		draw_circle(d + Vector2(-3.5, -2), 2.6, Color("#1e1e1e"))
		draw_circle(d + Vector2(3.5, -2), 2.6, Color("#1e1e1e"))
		for x in [-2.5, 0.0, 2.5]:
			draw_line(d + Vector2(x, 6), d + Vector2(x, 10), Color("#1e1e1e"), 1)
	if _queued <= 0:
		return
	var c := _cancel_center()
	draw_circle(c, CANCEL_R, Color("#1e1e1e"))
	draw_circle(c, CANCEL_R - 2, Color("#c0392b"))
	for d in [Vector2(6, 6), Vector2(6, -6)]:
		draw_line(c - d, c + d, Color.WHITE, 3)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# A generous finger-sized area around the ✕.
		if _queued > 0 and event.position.distance_to(_cancel_center()) < CANCEL_R + 12:
			cancel_pressed.emit()
			accept_event()
			return
		if _deletable and event.position.distance_to(_delete_center()) < CANCEL_R + 12:
			delete_pressed.emit()
			accept_event()
			return
		pressed.emit()
