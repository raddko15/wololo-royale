class_name LaneOrder
extends Control
## A lane's order button, one of three in a row above the cards. It shows the
## lane, a big icon and what the troops there do: HOLD (■: stop where they
## are; new ones wait by the tower and defend), GO (▶: march out and attack,
## together) or BACK (◀: return to the tower). Tapping cycles HOLD → GO →
## BACK. A badge shows how many troops are in the lane.

signal changed(state: String)

const NEXT := {"stop": "march", "march": "retreat", "retreat": "stop"}
const WORD := {"stop": "HOLD", "march": "GO", "retreat": "BACK"}
const HELP := {"stop": "wait & defend", "march": "attack!", "retreat": "to the tower"}
const LOOK := {
	"march": [Color("#2f5d34"), Color("#44bd32")],
	"stop": [Color("#5a4a24"), Color("#d4a017")],
	"retreat": [Color("#24435a"), Color("#3498db")],
}

var label: String
var state := "stop"
## Returns how many troops are in the lane (drawn as a badge).
var count: Callable


func _init(lane_label: String, start: String, counter: Callable) -> void:
	label = lane_label
	state = start
	count = counter
	custom_minimum_size = Vector2(0, 58)
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
	# Big icon on the left.
	var c := Vector2(26, size.y / 2)
	match state:
		"march":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -12), c + Vector2(11, 0), c + Vector2(-8, 12)]), Color.WHITE)
		"stop":
			draw_rect(Rect2(c + Vector2(-10, -10), Vector2(20, 20)), Color.WHITE)
		"retreat":
			draw_colored_polygon(PackedVector2Array([c + Vector2(8, -12), c + Vector2(-11, 0), c + Vector2(8, 12)]), Color.WHITE)
	# Lane name, the order in big letters, and a few words on what it means.
	var font := get_theme_default_font()
	var bold := UiStyle.cinzel(800)
	draw_string(font, Vector2(46, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))
	draw_string(bold, Vector2(46, 38), WORD[state], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, Vector2(46, 52), HELP[state], HORIZONTAL_ALIGNMENT_LEFT, size.x - 50, 12, Color(1, 1, 1, 0.8))
	var n: int = count.call() if count.is_valid() else 0
	if n > 0:
		# Gold badge on the top-right corner.
		var text := str(n)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var c2 := Vector2(size.x - 14, 15)
		var rr := maxf(10.0, w / 2 + 4)
		draw_circle(c2, rr + 1.5, Color("#2b1d10"))
		draw_circle(c2, rr, Color("#f9ca24"))
		draw_string(font, c2 + Vector2(-w / 2, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#2b1d10"))
