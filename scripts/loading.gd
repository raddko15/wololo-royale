class_name Loading
extends CanvasLayer
## A "Loading…" screen over everything: dark planks, the game's gold ring
## spinning and a line of text. Shown at once when a game is chosen, so the
## tap answers before the (slow) building of the match and its 3D world.

var text := "Loading…"
var _screen := Control.new()
var _turn := 0.0


func _init(what := "Loading…") -> void:
	text = what
	layer = 100
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.draw.connect(_paint)
	add_child(_screen)


func _process(dt: float) -> void:
	_turn += dt * 5.0
	_screen.queue_redraw()


## Fade out, then go.
func finish() -> void:
	var t := create_tween()
	t.tween_property(_screen, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)


func _paint() -> void:
	var s := _screen.size
	_screen.draw_rect(Rect2(Vector2.ZERO, s), UiStyle.WOOD)
	var c := s / 2.0
	_screen.draw_arc(c, 46, 0, TAU, 48, Color(0, 0, 0, 0.35), 10)
	_screen.draw_arc(c, 46, _turn, _turn + TAU * 0.3, 24, UiStyle.GOLD, 10, true)
	var font := UiStyle.cinzel(700)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 34).x
	_screen.draw_string(font, Vector2(c.x - w / 2.0, c.y + 110), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiStyle.CREAM)
