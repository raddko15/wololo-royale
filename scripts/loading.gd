class_name Loading
extends CanvasLayer
## A loading screen over everything, shown at once when a game is chosen so
## the tap answers before the (slow) building of the match and its 3D world:
## dark wooden planks like the start screen, and a hammer forging a glowing
## blade on an anvil, sparks flying at every blow.

## Seconds per hammer blow.
const BLOW := 0.9

var text := "Forging the battle"
var _screen := Control.new()
var _time := 0.0


func _init(what := "Forging the battle") -> void:
	text = what
	layer = 100
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.draw.connect(_paint)
	add_child(_screen)


func _process(dt: float) -> void:
	_time += minf(dt, 0.1)  # after a long frame, carry on rather than jump
	_screen.queue_redraw()


## Fade out, then go.
func finish() -> void:
	var t := create_tween()
	t.tween_property(_screen, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)


func _paint() -> void:
	var s := _screen.size
	var c := _screen
	# Planks.
	c.draw_rect(Rect2(Vector2.ZERO, s), UiStyle.WOOD)
	var x := 0.0
	var k := 0
	while x < s.x:
		c.draw_rect(Rect2(x, 0, 90, s.y), Color("#45311f") if k % 2 == 0 else Color("#3f2c1c"))
		c.draw_line(Vector2(x, 0), Vector2(x, s.y), Color("#22170d"), 3)
		x += 90.0
		k += 1
	var mid := Vector2(s.x / 2.0, s.y / 2.0)
	# Forge glow behind the anvil.
	var t := fmod(_time, BLOW) / BLOW  # 0 = the blow lands
	var flash := 1.0 - t
	for r in [190.0, 140.0, 95.0]:
		c.draw_circle(mid + Vector2(0, 10), r, Color(1.0, 0.45, 0.1, 0.05 + 0.05 * flash))
	# Anvil: horn to the left, flat face, waist, wide foot.
	var ink := Color("#1d1d22")
	var iron := Color("#3c3f47")
	var top := mid.y
	var anvil := PackedVector2Array([
		Vector2(mid.x - 150, top), Vector2(mid.x - 70, top - 4), Vector2(mid.x + 95, top - 4),
		Vector2(mid.x + 95, top + 28), Vector2(mid.x + 40, top + 40), Vector2(mid.x + 34, top + 78),
		Vector2(mid.x + 80, top + 100), Vector2(mid.x - 80, top + 100), Vector2(mid.x - 34, top + 78),
		Vector2(mid.x - 40, top + 40), Vector2(mid.x - 75, top + 30)])
	c.draw_colored_polygon(anvil, iron)
	c.draw_polyline(anvil + PackedVector2Array([anvil[0]]), ink, 4)
	c.draw_line(Vector2(mid.x - 70, top), Vector2(mid.x + 93, top), Color("#6b707c"), 4)
	# The glowing blade on the anvil, cooling between blows.
	var hot := Color("#ffd27a").lerp(Color("#d9531e"), t)
	c.draw_rect(Rect2(mid.x - 60, top - 16, 110, 12), hot)
	c.draw_colored_polygon(PackedVector2Array([Vector2(mid.x + 50, top - 16), Vector2(mid.x + 72, top - 10), Vector2(mid.x + 50, top - 4)]), hot)
	c.draw_rect(Rect2(mid.x - 82, top - 18, 22, 16), Color("#5b3a1e"))
	# Hammer: swings from raised (back) down onto the blade, fast down, slow up.
	var pivot := Vector2(mid.x + 150, top - 30)
	var down := PI + 0.12
	var up := PI + 1.25
	var a := lerpf(up, down, ease(clampf((t - 0.75) / 0.25, 0.0, 1.0), 2.5)) if t > 0.75 else lerpf(down, up, ease(t / 0.75, 0.5))
	if t < 0.05:
		a = down
	var dir := Vector2.from_angle(a)
	var head := pivot + dir * 150
	c.draw_line(pivot, head, Color("#7a4b26"), 12)
	c.draw_line(pivot, head, ink, 2)
	var across := dir.orthogonal()
	var face := PackedVector2Array([head + across * 30 - dir * 18, head + across * 30 + dir * 18,
		head - across * 30 + dir * 18, head - across * 30 - dir * 18])
	c.draw_colored_polygon(face, Color("#55585f"))
	c.draw_polyline(face + PackedVector2Array([face[0]]), ink, 3)
	# Sparks after each blow.
	if t < 0.55:
		var blow := int(_time / BLOW)
		var rng := RandomNumberGenerator.new()
		rng.seed = blow
		var age := t * BLOW
		for i in 18:
			var v := Vector2.from_angle(rng.randf_range(-PI + 0.25, -0.25)) * rng.randf_range(160, 420)
			var p := Vector2(mid.x + rng.randf_range(-30, 30), top - 14) + v * age + Vector2(0, 600) * age * age
			var fade := 1.0 - t / 0.55
			c.draw_line(p, p - v * 0.03, Color(1.0, 0.8, 0.3, fade), 3)
	# Words, with dots counting up.
	var font := UiStyle.cinzel(700)
	var line := text + ".".repeat(int(_time * 2.0) % 4)
	var w := font.get_string_size(text + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	c.draw_string(font, Vector2(mid.x - w / 2.0, top + 190), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiStyle.CREAM)
