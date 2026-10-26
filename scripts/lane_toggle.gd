class_name LaneToggle
extends Control
## One lane's play/pause switch under a unit card: ▶ sends that unit's
## auto-trained units down this lane, ❚❚ pauses it. Several can be on at once.

signal toggled(on: bool)

var label: String
var on := true
var compact := false


func _init(lane_label: String, start_on: bool, small := false) -> void:
	label = lane_label
	on = start_on
	compact = small
	custom_minimum_size = Vector2(0, 40 if compact else 56)
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
	var k := 0.65 if compact else 1.0
	var c := Vector2(14 if compact else 30, size.y / 2)
	var fg := Color.WHITE if on else Color(1, 1, 1, 0.6)
	if on:  # play triangle
		draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -11) * k, c + Vector2(10, 0) * k, c + Vector2(-8, 11) * k]), fg)
	else:  # pause bars
		draw_rect(Rect2(c + Vector2(-9, -11) * k, Vector2(6, 22) * k), fg)
		draw_rect(Rect2(c + Vector2(3, -11) * k, Vector2(6, 22) * k), fg)
	var font := get_theme_default_font()
	var fs := 18 if compact else 22
	var x := 26.0 if compact else 52.0
	draw_string(font, Vector2(x, size.y / 2 + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 2, fs, fg)
