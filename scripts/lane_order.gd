class_name LaneOrder
extends Control
## One lane's order button under a troop card: ■ stop (halt where they are;
## new ones wait by the tower), ▶ march, ◀ retreat to the tower. Tapping
## cycles stop → march → retreat. Shows how many of that troop are in the lane.

signal changed(state: String)

const NEXT := {"stop": "march", "march": "retreat", "retreat": "stop"}
const LOOK := {
	"march": [Color("#2f5d34"), Color("#44bd32")],
	"stop": [Color("#5a4a24"), Color("#d4a017")],
	"retreat": [Color("#24435a"), Color("#3498db")],
}

var label: String
var state := "stop"
## Returns how many of this troop are in the lane (drawn as a small number).
var count: Callable


func _init(lane_label: String, start: String, counter: Callable) -> void:
	label = lane_label
	state = start
	count = counter
	custom_minimum_size = Vector2(0, 40)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _process(_delta: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		state = NEXT[state]
		queue_redraw()
		changed.emit(state)


func _draw() -> void:
	var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var bg := StyleBoxFlat.new()
	bg.set_corner_radius_all(10)
	bg.bg_color = LOOK[state][0]
	bg.border_color = LOOK[state][1]
	bg.set_border_width_all(3)
	draw_style_box(bg, r)
	var c := Vector2(14, size.y / 2)
	var k := 0.65
	match state:
		"march":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -11) * k, c + Vector2(10, 0) * k, c + Vector2(-8, 11) * k]), Color.WHITE)
		"stop":
			draw_rect(Rect2(c + Vector2(-9, -9) * k, Vector2(18, 18) * k), Color.WHITE)
		"retreat":
			draw_colored_polygon(PackedVector2Array([c + Vector2(8, -11) * k, c + Vector2(-10, 0) * k, c + Vector2(8, 11) * k]), Color.WHITE)
	var font := get_theme_default_font()
	draw_string(font, Vector2(26, size.y / 2 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var n: int = count.call() if count.is_valid() else 0
	if n > 0:
		# Small gold badge on the top-right corner.
		var text := str(n)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var c2 := Vector2(size.x - 7, 7)
		var rr := maxf(8.0, w / 2 + 3)
		draw_circle(c2, rr + 1.5, Color("#2b1d10"))
		draw_circle(c2, rr, Color("#f9ca24"))
		draw_string(font, c2 + Vector2(-w / 2, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#2b1d10"))
