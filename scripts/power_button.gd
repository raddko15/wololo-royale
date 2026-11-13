class_name PowerButton
extends Control
## A round power button over the battlefield's right edge: the power's
## emblem, a gold ring filling with the faith gathered toward its cost, and
## the cost under it. Grey until it can be used; while the god walks, the
## ring shows the time it has left.

signal pressed

var emblem: Texture2D
var cost := 1000.0
## 0..1: how full the ring is; usable: lit and tappable.
var fill := 0.0
var usable := false
var active := false
var caption := ""


func _init(art: String, power_cost: float, tip: String) -> void:
	emblem = load("res://assets/art/emblem/%s.svg" % art)
	cost = power_cost
	caption = tip
	custom_minimum_size = Vector2(92, 112)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_state(faith: float, god_life := -1.0, lifetime := 60.0) -> void:
	active = god_life >= 0.0
	fill = clampf(god_life / lifetime, 0.0, 1.0) if active else clampf(faith / cost, 0.0, 1.0)
	usable = not active and faith >= cost
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, 44)
	var r := 36.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0) if usable else 0.0
	if usable:
		draw_circle(c, r + 8 + pulse * 3, Color(1.0, 0.85, 0.3, 0.35))
	draw_circle(c, r + 3, Color("#2b1d10"))
	draw_circle(c, r, Color("#3b2a1c") if not usable else Color("#5a3d1f"))
	draw_arc(c, r - 2, -PI / 2, -PI / 2 + TAU * fill, 48, Color("#f4c542") if not active else Color("#9be3ff"), 5, true)
	if emblem:
		var tint := Color.WHITE if usable or active else Color(0.55, 0.55, 0.55)
		draw_texture_rect(emblem, Rect2(c - Vector2(26, 26), Vector2(52, 52)), false, tint)
	var font := UiStyle.cinzel(700)
	var text := caption if active else "%d" % cost
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(c.x - w / 2.0 + 1, c.y + r + 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)
	draw_string(font, Vector2(c.x - w / 2.0, c.y + r + 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiStyle.CREAM)


func _process(_dt: float) -> void:
	if usable:
		queue_redraw()
