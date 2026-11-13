class_name UnitIcon
extends Control
## A troop's portrait for its card: head and shoulders with its helmet,
## weapon and gear, in the civ's color; horsemen with their horse's head.

var unit_id: String
var color: Color
## The troop's level (0-2): archers carry a crossbow at level 3.
var tier := 0
var _tex := {}


func _init(id: String, civ_color: Color) -> void:
	unit_id = id
	color = civ_color
	custom_minimum_size = Vector2(0, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers()


func set_tier(t: int) -> void:
	if t != tier:
		tier = t
		_layers()
		queue_redraw()


const VILLAGER_CLOTH := Color("#d9c8a0")


## The portrait's layers (assets/art/portrait2, made by
## tools/make_portraits.py), back to front: [texture, takes the civ color].
## Loaded here rather than in _draw (a first load while drawing shows blank
## on the web renderer).
func _layers() -> Array:
	var key := "%s_%d" % [unit_id, tier]
	if not _tex.has(key):
		var t := tier
		while t > 0 and not ResourceLoader.exists("res://assets/art/portrait2/%s_%d_0.svg" % [unit_id, t]):
			t -= 1
		var out := []
		for k in 16:
			var base := "res://assets/art/portrait2/%s_%d_%d" % [unit_id, t, k]
			if ResourceLoader.exists(base + ".svg"):
				out.append([load(base + ".svg"), false])
			elif ResourceLoader.exists(base + "_tint.svg"):
				out.append([load(base + "_tint.svg"), true])
			else:
				break
		_tex[key] = out
	return _tex[key]


## A head-and-shoulders portrait on a soft disc of the civ's color.
func _draw() -> void:
	var side := minf(size.x, size.y + 10)
	var box := Rect2(Vector2((size.x - side) / 2.0, size.y - side + 4), Vector2(side, side))
	draw_circle(box.get_center() + Vector2(0, 2), side * 0.42, Color(color, 0.18))
	for layer in _layers():
		var tint := Color.WHITE
		if layer[1]:
			tint = VILLAGER_CLOTH if unit_id == "villager" else color
		draw_texture_rect(layer[0], box, false, tint)
