class_name LaneChip
extends Control
## One of the L / M / R chips under a troop card: lit (gold) when new troops
## of that type are recruited into that lane. Several can be lit; AUTO sends
## each new one to the next lit lane in turn.

signal toggled(on: bool)

var label: String
var on := false


func _init(lane_label: String, start_on: bool) -> void:
	label = lane_label
	on = start_on
	custom_minimum_size = Vector2(0, 34)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on = not on
		queue_redraw()
		toggled.emit(on)


func _draw() -> void:
	var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var bg := StyleBoxFlat.new()
	bg.set_corner_radius_all(8)
	bg.bg_color = Color("#f1c40f") if on else Color("#2b1d10")
	bg.border_color = Color("#2b1d10") if on else Color("#7a5a32")
	bg.set_border_width_all(2)
	draw_style_box(bg, r)
	var font := UiStyle.cinzel(800)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(font, Vector2((size.x - w) / 2, size.y / 2 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
		Color("#2b1d10") if on else Color(1, 1, 1, 0.45))
