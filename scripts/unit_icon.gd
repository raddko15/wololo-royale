class_name UnitIcon
extends Control
## A small portrait of a troop for its card, drawn from the same art as on the
## map: foot soldiers face the viewer with their weapon and gear, horsemen and
## chariots are seen from above, pointing up.

var unit_id: String
var color: Color
## The troop's level (0-2): archers carry a crossbow at level 3.
var tier := 0
var _tex := {}


func _init(id: String, civ_color: Color) -> void:
	unit_id = id
	color = civ_color
	custom_minimum_size = Vector2(0, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_tier(t: int) -> void:
	if t != tier:
		tier = t
		queue_redraw()


func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := "res://assets/art/%s.svg" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _layer(name: String, r: Rect2, tint := Color.WHITE) -> void:
	var t := _t(name)
	if t:
		draw_texture_rect(t, r, false, tint)


func _draw() -> void:
	var c := size / 2
	match unit_id:
		"cavalry", "knight":
			_mounted(c)
		"chariot":
			_chariot(c)
		_:
			_foot(c)


## Standing figure (32x40 art) scaled to the icon, plus its gear and weapon.
func _foot(c: Vector2) -> void:
	var k := size.y / 40.0
	var box := Rect2(c - Vector2(16, 21) * k, Vector2(32, 40) * k)
	var gear: Array = {"fighter": ["helmet_1"], "archer": ["helmet_1"] if tier >= 2 else ["hood"], "phalanx": ["cuirass", "hoplite_helm"], "villager": []}.get(unit_id, [])
	var tunic: Color = Color("#d9c8a0") if unit_id == "villager" else color
	if unit_id == "archer":
		_layer("quiver", box)
	for leg in [-1, 1]:
		draw_rect(Rect2(box.position + Vector2(16 + leg * 3.5 - 2, 31) * k, Vector2(4, 6) * k), Color("#5a3d24"))
	_layer("unit", box)
	_layer("unit_tint", box, tunic)
	_layer("head", box)
	for g in gear:
		_layer(g, box)
	var hand := box.position + Vector2(26, 27) * k
	match unit_id:
		"fighter":
			_weapon("club", Vector2(10, 30), Vector2(5, 27), hand, -PI / 2 + 0.45, k)
			_shield(box.position + Vector2(6, 26) * k, k)
		"archer":
			if tier >= 2:  # crossbow held across the chest
				_weapon("crossbow", Vector2(18, 30), Vector2(9, 22), hand, -PI / 2 - 0.55, k)
			else:  # bow upright in the hand, its back facing out
				_weapon("bow", Vector2(16, 30), Vector2(5, 15), hand + Vector2(1, -2) * k, -PI / 2, k)
		"phalanx":
			_weapon("spear", Vector2(6, 70), Vector2(3, 50), hand, -PI / 2 + 0.55, k * 0.5)
			var sh := Rect2(box.position + Vector2(-1, 17) * k, Vector2(22, 22) * k)
			_layer("aspis", sh)
			_layer("aspis_tint", sh, color)
		"villager":
			draw_line(hand, hand + Vector2(4, -12) * k, Color("#8a5a33"), 2.0 * k)


func _weapon(name: String, tex_size: Vector2, pivot: Vector2, at: Vector2, angle: float, k: float) -> void:
	var t := _t(name)
	if t == null:
		return
	draw_set_transform(at, angle + PI / 2, Vector2(k, k))
	draw_texture_rect(t, Rect2(-pivot, tex_size), false)
	draw_set_transform(Vector2.ZERO)


func _shield(at: Vector2, k: float) -> void:
	var r := Rect2(at - Vector2(8, 8) * k, Vector2(16, 16) * k)
	_layer("shield", r)
	_layer("shield_tint", r, color)


## Horse and rider from above (30x56 art), pointing up.
func _mounted(c: Vector2) -> void:
	var k := size.y / 48.0
	var box := Rect2(c - Vector2(15, 30) * k, Vector2(30, 56) * k)
	_layer("cav_horse", box)
	if unit_id == "knight":
		_layer("knight_barding_tint", box, color)
		_layer("knight_barding", box)
		_layer("knight_rider_tint", box, color)
		_layer("knight_rider", box)
		_layer("knight_helm", box)
	else:
		_layer("cav_rider", box)
		_layer("cav_rider_tint", box, color)
		_layer("cav_head", box)
	var grip := box.position + Vector2(21, 30) * k
	var lance := Rect2(grip - Vector2(4, 44) * 0.85 * k, Vector2(8, 56) * 0.85 * k)
	_layer("lance", lance)
	if unit_id == "knight":
		_layer("pennant_tint", lance, color)


## Two horses ahead of the car with its two archers, from above.
func _chariot(c: Vector2) -> void:
	var k := size.y / 58.0
	for side in [-1.0, 1.0]:
		_layer("cav_horse", Rect2(c + Vector2(side * 7.5 - 12, -31) * k, Vector2(24, 45) * k))
	var car := Rect2(c + Vector2(-20, 3) * k, Vector2(40, 28) * k)
	_layer("chariot_car", car)
	_layer("chariot_car_tint", car, color)
	_layer("chariot_crew_tint", car, color)
	_layer("chariot_crew", car)
