class_name LaneToggle
extends Control
## One lane's play/pause switch above the cards: ▶ sends auto-trained units
## down this lane, ❚❚ pauses it. Several lanes can be on at once.

signal toggled(on: bool)

var label: String
var on := true


func _init(lane_label: String, start_on: bool) -> void:
	label = lane_label
	on = start_on
	custom_minimum_size = Vector2(0, 56)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on = not on
		queue_redraw()
		toggled.emit(on)


func _draw() -> void:
	var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var bg := StyleBoxFlat.new()
	bg.set_corner_radius_all(10)
	bg.bg_color = Color("#2f5d34") if on else Color("#3a3a3a")
	bg.border_color = Color("#44bd32") if on else Color("#1e1e1e")
	bg.set_border_width_all(3)
	draw_style_box(bg, r)
	var c := Vector2(30, size.y / 2)
	var fg := Color.WHITE if on else Color(1, 1, 1, 0.6)
	if on:  # play triangle
		draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -11), c + Vector2(10, 0), c + Vector2(-8, 11)]), fg)
	else:  # pause bars
		draw_rect(Rect2(c + Vector2(-9, -11), Vector2(6, 22)), fg)
		draw_rect(Rect2(c + Vector2(3, -11), Vector2(6, 22)), fg)
	var font := get_theme_default_font()
	draw_string(font, Vector2(52, size.y / 2 + 8), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 56, 22, fg)
