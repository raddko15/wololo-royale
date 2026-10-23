class_name Card
extends PanelContainer
## A Clash Royale style card: press to tap or start a drag. Greyed out when not affordable.

signal pressed

var _title := Label.new()
var _cost := Label.new()
var _style := StyleBoxFlat.new()


func _init(title: String) -> void:
	custom_minimum_size = Vector2(150, 130)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style.set_corner_radius_all(12)
	_style.set_border_width_all(4)
	add_theme_stylebox_override("panel", _style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	for l in [_title, _cost]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(l)
	_title.text = title
	_title.add_theme_font_size_override("font_size", 28)
	_cost.add_theme_font_size_override("font_size", 22)
	set_state("", true, false)


func set_state(cost_text: String, enabled: bool, selected: bool) -> void:
	_cost.text = cost_text
	modulate.a = 1.0 if enabled else 0.45
	_style.bg_color = Color("#5d4a2f") if enabled else Color("#2d2d2d")
	_style.border_color = Color("#f9ca24") if selected else Color("#1e1e1e")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
