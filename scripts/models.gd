class_name Models
extends RefCounted
## Low-poly 3D buildings, made from simple shapes: make(id, civ color)
## returns a model standing on the ground at its origin, its front facing +z
## (toward the camera). Sizes in world units (1 = 100 map pixels). Parts that
## turn (windmill sails, water wheels) are in the "spin" group, turning about
## their own z axis.

const WOOD := Color("#8a5a33")
const WOOD_DARK := Color("#5e3b1f")
const LOG := Color("#9b6a3c")
const THATCH := Color("#d1a54a")
const THATCH_DARK := Color("#a8822f")
const MUD := Color("#b98a5e")
const STONE := Color("#a7a69c")
const STONE_DARK := Color("#7f7e76")
const MARBLE := Color("#efe9dc")
const MARBLE_SHADE := Color("#d8d0bf")
const TERRACOTTA := Color("#c4623b")
const PLASTER := Color("#eadfc4")
const ROOF_BROWN := Color("#7a4a2a")
const DOOR := Color("#3b2614")
const GOLD := Color("#f1c40f")
const IRON := Color("#7f8c8d")
const HAY := Color("#e2c35a")
const RED := Color("#c0392b")


## `variant` varies houses (roof colors, chimney side) so a village isn't
## rows of the same box.
static func make(id: String, tint: Color, variant := 0) -> Node3D:
	var m := Node3D.new()
	match id:
		"fort_era0":
			_longhouse(m, tint)
		"fort_wood":
			_fort_wood(m, tint)
		"castle_stone":
			_castle(m, tint)
		"timber_hall":
			_timber_hall(m, tint)
		"marble_palace":
			_palace(m, tint)
		"tower_wood":
			_tower_wood(m, tint)
		"tower_stone":
			_tower_stone(m, tint)
		"tower_marble":
			_tower_marble(m, tint)
		"tower_ruin":
			_tower_ruin(m)
		"hut_era0":
			_round_hut(m, 0.11, variant)
		"hut_medieval":
			_timber_house(m, variant)
		"hut_classical":
			_villa(m, variant)
		"granary":
			_granary(m)
		"windmill", "grand_mill":
			_windmill(m, id == "grand_mill")
		"olive_press":
			_olive_press(m)
		"oil_workshop":
			_oil_workshop(m)
		"lean_to":
			_lean_to(m)
		"lumber_camp":
			_lumber_camp(m)
		"timber_yard":
			_timber_yard(m)
		"sawmill":
			_sawmill(m)
		"carpentry":
			_carpentry(m)
		"gold_mine", "gold_mine2", "stone_mine", "stone_mine2":
			_mine(m, id.begins_with("gold"), id.ends_with("2"))
		"campfire":
			_campfire(m)
		_:
			if id.begins_with("barracks_") or id.begins_with("archery_range_") or id.begins_with("stables_"):
				var parts := id.rsplit("_", true, 1)
				_military(m, parts[0], parts[1], tint)
			else:
				push_warning("no 3D model for " + id)
	return m


# --- Parts ----------------------------------------------------------------

static func _add(root: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = LowPoly.material(color)
	mi.position = pos
	mi.rotation.y = rot_y
	root.add_child(mi)
	return mi


static func _box(root: Node3D, size: Vector3, color: Color, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	return _add(root, LowPoly.box(size), color, pos + Vector3(0, size.y / 2.0, 0), rot_y)


static func _post(root: Node3D, r: float, h: float, color: Color, pos: Vector3, sides := 6) -> MeshInstance3D:
	return _add(root, LowPoly.prism(r, h, sides), color, pos + Vector3(0, h / 2.0, 0))


static func _flag(root: Node3D, pos: Vector3, h: float, tint: Color) -> void:
	_post(root, 0.008, h, WOOD_DARK, pos, 4)
	_box(root, Vector3(0.11, 0.065, 0.006), tint, pos + Vector3(0.055, h - 0.07, 0))


## Walls with a door and windows on the front, and a roof (gable or pyramid).
static func _hall(root: Node3D, size: Vector3, wall: Color, roof: Color, roof_h: float, at := Vector3.ZERO, pyramid := false, windows := 2) -> void:
	_box(root, size, wall, at)
	var front := at + Vector3(0, 0, size.z / 2.0 + 0.004)
	_box(root, Vector3(size.x * 0.18, size.y * 0.62, 0.012), DOOR, front)
	for i in windows:
		var x := (i - (windows - 1) / 2.0) * size.x * 0.55 if windows > 1 else size.x * 0.3
		if windows > 1:
			_box(root, Vector3(size.x * 0.1, size.y * 0.22, 0.012), DOOR, front + Vector3(x, size.y * 0.5, 0))
	var overhang := Vector3(size.x * 1.12, 0, size.z * 1.18)
	var mesh := LowPoly.pyramid(overhang.x, overhang.z, roof_h) if pyramid else LowPoly.gable(overhang.x, overhang.z, roof_h)
	_add(root, mesh, roof, at + Vector3(0, size.y, 0))


## Crenellations along a wall's top, from `a` to `b`.
static func _merlons(root: Node3D, a: Vector3, b: Vector3, color: Color, size := 0.045) -> void:
	var n := maxi(int(a.distance_to(b) / (size * 2.0)), 1)
	for i in n + 1:
		_box(root, Vector3(size, size, size), color, a.lerp(b, float(i) / n))


# --- Town centers -------------------------------------------------------------

## Era I: a long wooden hall under a big thatched roof, with a banner.
static func _longhouse(m: Node3D, tint: Color) -> void:
	_hall(m, Vector3(1.0, 0.28, 0.5), WOOD, THATCH, 0.36, Vector3(0, 0, -0.05))
	for x in [-0.42, 0.42]:
		_post(m, 0.03, 0.3, WOOD_DARK, Vector3(x, 0, 0.23))
	_flag(m, Vector3(0.58, 0, 0.1), 0.62, tint)
	# Fence posts across the front.
	for i in 9:
		var x := -0.62 + i * 0.155
		if absf(x) > 0.15:
			_post(m, 0.018, 0.12, LOG, Vector3(x, 0, 0.36), 5)


## Medieval Era II: a log palisade with corner towers around a keep.
static func _fort_wood(m: Node3D, tint: Color) -> void:
	_hall(m, Vector3(0.6, 0.42, 0.42), WOOD, tint.darkened(0.25), 0.3, Vector3(0, 0, -0.12))
	var w := 0.72
	var d := 0.42
	for i in 15:
		var t := float(i) / 14.0
		for z in [-d, d]:
			var x := -w + t * 2.0 * w
			if z > 0 and absf(x) < 0.14:
				continue  # the gate
			_post(m, 0.032, 0.3, LOG, Vector3(x, 0, z), 5)
	for i in 7:
		var z := -d + float(i) / 6.0 * 2.0 * d
		for x in [-w, w]:
			_post(m, 0.032, 0.3, LOG, Vector3(x, 0, z), 5)
	for corner in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d)]:
		_box(m, Vector3(0.18, 0.5, 0.18), WOOD, corner)
		_add(m, LowPoly.pyramid(0.24, 0.24, 0.18), tint, corner + Vector3(0, 0.5, 0))
	_box(m, Vector3(0.28, 0.06, 0.06), WOOD_DARK, Vector3(0, 0.3, d))
	_flag(m, Vector3(0.0, 0.72, -0.12), 0.3, tint)


## Medieval Era III: stone curtain walls, round towers and a tall keep.
static func _castle(m: Node3D, tint: Color) -> void:
	var w := 0.6
	var d := 0.38
	var wall_h := 0.32
	for z in [-d, d]:
		_box(m, Vector3(w * 2.0, wall_h, 0.1), STONE, Vector3(0, 0, z))
		_merlons(m, Vector3(-w, wall_h, z), Vector3(w, wall_h, z), STONE)
	for x in [-w, w]:
		_box(m, Vector3(0.1, wall_h, d * 2.0), STONE, Vector3(x, 0, 0))
	_box(m, Vector3(0.2, 0.22, 0.03), DOOR, Vector3(0, 0, d + 0.05))
	_box(m, Vector3(0.5, 0.78, 0.42), STONE_DARK.lightened(0.15), Vector3(0, 0, -0.08))
	_merlons(m, Vector3(-0.25, 0.78, 0.13), Vector3(0.25, 0.78, 0.13), STONE)
	_box(m, Vector3(0.06, 0.12, 0.01), DOOR, Vector3(0, 0.45, 0.135))
	for corner in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d)]:
		_post(m, 0.15, 0.58, STONE, corner, 8)
		_add(m, LowPoly.cone(0.19, 0.3, 8), tint, corner + Vector3(0, 0.58 + 0.15, 0))
	_flag(m, Vector3(0, 0.78, -0.08), 0.32, tint)


## Classical Era II: a timber hall on a stone podium with a columned porch.
static func _timber_hall(m: Node3D, tint: Color) -> void:
	_box(m, Vector3(1.1, 0.08, 0.66), STONE, Vector3(0, 0, -0.02))
	_hall(m, Vector3(0.9, 0.38, 0.4), WOOD, TERRACOTTA, 0.24, Vector3(0, 0.08, -0.1), false, 2)
	for i in 6:
		_post(m, 0.026, 0.38, MARBLE, Vector3(-0.4 + i * 0.16, 0.08, 0.2), 6)
	_box(m, Vector3(0.95, 0.04, 0.12), tint, Vector3(0, 0.46, 0.2))
	_flag(m, Vector3(0.52, 0.08, 0.26), 0.55, tint)


## Classical Era III: a marble palace on steps, all round columns, a dome.
static func _palace(m: Node3D, tint: Color) -> void:
	for i in 3:
		var k := 1.0 - i * 0.06
		_box(m, Vector3(1.3 * k, 0.04, 0.8 * k), MARBLE_SHADE if i % 2 == 0 else MARBLE, Vector3(0, i * 0.04, 0))
	var base := 0.12
	_box(m, Vector3(0.9, 0.42, 0.46), MARBLE, Vector3(0, base, -0.04))
	for i in 8:
		var x := -0.52 + i * (1.04 / 7.0)
		_post(m, 0.03, 0.44, MARBLE, Vector3(x, base, 0.26), 8)
	_box(m, Vector3(1.12, 0.05, 0.62), MARBLE_SHADE, Vector3(0, base + 0.44, 0))
	_box(m, Vector3(1.12, 0.035, 0.03), tint, Vector3(0, base + 0.47, 0.31))
	_add(m, LowPoly.gable(1.16, 0.66, 0.2), TERRACOTTA, Vector3(0, base + 0.49, 0))
	_add(m, LowPoly.blob(0.22, 0.75, 10, 5), MARBLE, Vector3(0, base + 0.62, -0.14))
	_post(m, 0.02, 0.12, GOLD, Vector3(0, base + 0.78, -0.14), 6)
	_flag(m, Vector3(0.6, 0, 0.3), 0.6, tint)
	_flag(m, Vector3(-0.6, 0, 0.3), 0.6, tint)


# --- Towers -----------------------------------------------------------------

static func _tower_wood(m: Node3D, tint: Color) -> void:
	for p in [Vector3(-0.1, 0, -0.1), Vector3(0.1, 0, -0.1), Vector3(-0.1, 0, 0.1), Vector3(0.1, 0, 0.1)]:
		_post(m, 0.022, 0.42, LOG, p, 5)
	_box(m, Vector3(0.28, 0.03, 0.28), WOOD_DARK, Vector3(0, 0.2, 0))
	_box(m, Vector3(0.3, 0.12, 0.3), WOOD, Vector3(0, 0.42, 0))
	_box(m, Vector3(0.08, 0.035, 0.01), DOOR, Vector3(0, 0.47, 0.152))
	_add(m, LowPoly.pyramid(0.38, 0.38, 0.2), tint, Vector3(0, 0.54, 0))


static func _tower_stone(m: Node3D, tint: Color) -> void:
	_post(m, 0.15, 0.6, STONE, Vector3.ZERO, 8)
	_post(m, 0.17, 0.06, STONE_DARK, Vector3(0, 0.6, 0), 8)
	_box(m, Vector3(0.025, 0.09, 0.01), DOOR, Vector3(0, 0.38, 0.148))
	_add(m, LowPoly.cone(0.19, 0.3, 8), tint, Vector3(0, 0.66 + 0.15, 0))


static func _tower_marble(m: Node3D, tint: Color) -> void:
	_box(m, Vector3(0.28, 0.46, 0.28), MARBLE, Vector3.ZERO)
	_box(m, Vector3(0.32, 0.04, 0.32), MARBLE_SHADE, Vector3(0, 0.46, 0))
	for p in [Vector3(-0.12, 0.5, -0.12), Vector3(0.12, 0.5, -0.12), Vector3(-0.12, 0.5, 0.12), Vector3(0.12, 0.5, 0.12)]:
		_post(m, 0.022, 0.14, MARBLE, p, 6)
	_box(m, Vector3(0.025, 0.09, 0.01), DOOR, Vector3(0, 0.3, 0.142))
	_box(m, Vector3(0.34, 0.03, 0.34), tint, Vector3(0, 0.64, 0))
	_add(m, LowPoly.pyramid(0.36, 0.36, 0.16), TERRACOTTA, Vector3(0, 0.67, 0))


static func _tower_ruin(m: Node3D) -> void:
	_post(m, 0.022, 0.16, LOG, Vector3(-0.1, 0, -0.1), 5)
	_post(m, 0.022, 0.09, LOG, Vector3(0.1, 0, 0.08), 5)
	var fallen := _add(m, LowPoly.prism(0.022, 0.36, 5), LOG, Vector3(0.02, 0.025, 0.02), 0.7)
	fallen.rotation.z = PI / 2
	_add(m, LowPoly.blob(0.06, 0.7, 5, 3), STONE_DARK, Vector3(-0.05, 0.02, 0.12))


# --- Houses -------------------------------------------------------------------

## Era I: a round mud-walled hut under a straw cone, with a door frame,
## a smoke hole, and a woodpile or a pot by the wall.
static func _round_hut(m: Node3D, r: float, variant := 0) -> void:
	var straw: Color = [THATCH, Color("#c8963c"), Color("#dcb35a")][variant % 3]
	_post(m, r * 1.06, 0.025, STONE_DARK, Vector3.ZERO, 7)
	_post(m, r, r * 0.9, MUD, Vector3(0, 0.02, 0), 7)
	_add(m, LowPoly.cone(r * 1.45, r * 1.5, 7), straw, Vector3(0, 0.02 + r * 0.9 + r * 0.75, 0))
	_add(m, LowPoly.cone(r * 1.05, r * 0.6, 7), straw.darkened(0.18), Vector3(0, 0.02 + r * 0.9 + r * 1.2, 0))
	_post(m, r * 0.18, r * 0.25, WOOD_DARK, Vector3(0, 0.02 + r * 2.35, 0), 5)
	_box(m, Vector3(r * 0.6, r * 0.7, 0.012), WOOD_DARK, Vector3(0, 0.02, r * 0.97))
	_box(m, Vector3(r * 0.42, r * 0.58, 0.014), DOOR, Vector3(0, 0.02, r * 0.98))
	if variant % 2 == 0:
		_log_pile(m, Vector3(r * 1.4, 0, r * 0.3), 3)
	else:
		_add(m, LowPoly.blob(r * 0.3, 0.9, 6, 3), Color("#a0522d"), Vector3(-r * 1.25, r * 0.25, r * 0.4))


## Medieval house: whitewashed walls in a dark timber frame on a stone
## footing, a steep roof (shingles, thatch or slate), a chimney, shuttered
## windows and a door.
static func _timber_house(m: Node3D, variant := 0) -> void:
	var w := 0.22
	var d := 0.16
	var h := 0.14
	var roof: Color = [ROOF_BROWN, Color("#c9a24a"), Color("#5d6470"), Color("#8a3b28")][variant % 4]
	_box(m, Vector3(w + 0.02, 0.025, d + 0.02), STONE, Vector3.ZERO)
	_box(m, Vector3(w, h, d), Color("#f1e8d4"), Vector3(0, 0.025, 0))
	# Timber frame on the front: corner posts, a middle beam, cross braces.
	var front := d / 2.0 + 0.004
	for x in [-w / 2.0, w / 2.0]:
		_box(m, Vector3(0.016, h, 0.012), WOOD_DARK, Vector3(x, 0.025, front))
	_box(m, Vector3(w, 0.014, 0.012), WOOD_DARK, Vector3(0, 0.025 + h * 0.55, front))
	_box(m, Vector3(w, 0.014, 0.012), WOOD_DARK, Vector3(0, 0.025 + h - 0.007, front))
	for x in [-0.065, 0.065]:
		var brace := _box(m, Vector3(0.012, h * 0.62, 0.01), WOOD_DARK, Vector3(x, 0.025 + h * 0.18, front + 0.002))
		brace.rotation.z = 0.6 if x < 0 else -0.6
	# Door, windows with shutters.
	_box(m, Vector3(0.045, 0.07, 0.014), DOOR, Vector3(0.02 if variant % 2 == 0 else -0.02, 0.025, front))
	var win_x := -0.065 if variant % 2 == 0 else 0.065
	_box(m, Vector3(0.03, 0.03, 0.014), Color("#2c3e50"), Vector3(win_x, 0.025 + h * 0.62, front))
	for s in [-1, 1]:
		_box(m, Vector3(0.012, 0.032, 0.016), Color("#2e6b3f"), Vector3(win_x + s * 0.022, 0.025 + h * 0.62, front))
	# A steep roof with a little overhang, so the walls show; ridge beam.
	_add(m, LowPoly.gable(w * 1.12, d * 1.22, 0.13), roof, Vector3(0, 0.025 + h, 0))
	_box(m, Vector3(w * 1.14, 0.014, 0.014), roof.darkened(0.3), Vector3(0, 0.025 + h + 0.125, 0))
	var cx := 0.06 if variant % 2 == 0 else -0.06
	_box(m, Vector3(0.035, 0.12, 0.035), STONE, Vector3(cx, 0.025 + h + 0.03, -0.03))
	_box(m, Vector3(0.04, 0.012, 0.04), STONE_DARK, Vector3(cx, 0.025 + h + 0.15, -0.03))
	if variant % 3 == 0:
		_post(m, 0.022, 0.05, WOOD, Vector3(w / 2.0 + 0.03, 0, front - 0.02), 7)  # a barrel


## Classical house: white walls and a low terracotta roof, a small porch on
## two columns, a window, and a potted plant.
static func _villa(m: Node3D, variant := 0) -> void:
	var w := 0.22
	var d := 0.16
	var h := 0.12
	var roof: Color = [TERRACOTTA, Color("#b5522f"), Color("#d47a4a")][variant % 3]
	_box(m, Vector3(w + 0.02, 0.02, d + 0.06), MARBLE_SHADE, Vector3(0, 0, 0.02))
	_box(m, Vector3(w, h, d), Color("#f6f1e6"), Vector3(0, 0.02, 0))
	var front := d / 2.0 + 0.004
	_box(m, Vector3(0.04, 0.07, 0.014), DOOR, Vector3(0, 0.02, front))
	_box(m, Vector3(0.028, 0.028, 0.014), Color("#2c3e50"), Vector3(0.065 if variant % 2 == 0 else -0.065, 0.02 + h * 0.55, front))
	_box(m, Vector3(w + 0.01, 0.012, 0.012), roof.darkened(0.15), Vector3(0, 0.02 + h - 0.012, front))
	_add(m, LowPoly.gable(w * 1.12, d * 1.2, 0.07), roof, Vector3(0, 0.02 + h, 0))
	for x in [-0.045, 0.045]:
		_post(m, 0.009, h, MARBLE, Vector3(x, 0.02, front + 0.03), 6)
	_box(m, Vector3(0.12, 0.012, 0.045), roof, Vector3(0, 0.02 + h, front + 0.02))
	var px := -w / 2.0 - 0.02 if variant % 2 == 0 else w / 2.0 + 0.02
	_post(m, 0.016, 0.025, TERRACOTTA, Vector3(px, 0, front), 6)
	_add(m, LowPoly.blob(0.022, 0.9, 6, 3), Color("#4f8f37"), Vector3(px, 0.04, front))


# --- Food and wood --------------------------------------------------------------

static func _granary(m: Node3D) -> void:
	_round_hut(m, 0.14)
	_post(m, 0.07, 0.04, STONE, Vector3(0.24, 0, 0.12), 8)
	_post(m, 0.05, 0.05, Color("#c9a35c"), Vector3(-0.22, 0, 0.14), 7)
	_add(m, LowPoly.blob(0.045, 0.6, 6, 3), HAY, Vector3(-0.22, 0.06, 0.14))


static func _windmill(m: Node3D, grand: bool) -> void:
	var h := 0.62 if grand else 0.46
	var wall := STONE if grand else WOOD
	_add(m, LowPoly.prism(0.16, h, 8, 0.11), wall, Vector3(0, h / 2.0, 0))
	_add(m, LowPoly.cone(0.15, 0.2, 8), ROOF_BROWN, Vector3(0, h + 0.1, 0))
	_box(m, Vector3(0.07, 0.12, 0.01), DOOR, Vector3(0, 0, 0.15))
	var hub := Node3D.new()
	hub.position = Vector3(0, h * 0.85, 0.16)
	hub.add_to_group("spin")
	m.add_child(hub)
	var blade := 0.34 if grand else 0.28
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = k * PI / 2.0
		hub.add_child(arm)
		_box(arm, Vector3(0.02, blade, 0.012), WOOD_DARK, Vector3(0, 0, 0))
		_box(arm, Vector3(0.07, blade * 0.7, 0.006), Color("#f2ead2"), Vector3(0.045, blade * 0.28, 0.008))
	_add(m, LowPoly.prism(0.025, 0.03, 6), WOOD_DARK, Vector3(0, h * 0.85, 0.17)).rotation.x = PI / 2


static func _olive_press(m: Node3D) -> void:
	_hall(m, Vector3(0.36, 0.2, 0.26), PLASTER, TERRACOTTA, 0.1, Vector3(0, 0, -0.04), false, 0)
	_post(m, 0.09, 0.07, STONE, Vector3(0.24, 0, 0.12), 8)
	_post(m, 0.015, 0.16, WOOD_DARK, Vector3(0.24, 0.07, 0.12), 5)
	for i in 2:
		_amphora(m, Vector3(-0.22 + i * 0.07, 0, 0.16))


static func _oil_workshop(m: Node3D) -> void:
	_box(m, Vector3(0.5, 0.04, 0.38), STONE, Vector3(0, 0, 0))
	_hall(m, Vector3(0.42, 0.24, 0.24), MARBLE, TERRACOTTA, 0.12, Vector3(0, 0.04, -0.05), false, 0)
	for i in 4:
		_post(m, 0.015, 0.24, MARBLE, Vector3(-0.18 + i * 0.12, 0.04, 0.1), 6)
	for i in 4:
		_amphora(m, Vector3(-0.2 + i * 0.07, 0.04, 0.17))


static func _amphora(m: Node3D, at: Vector3) -> void:
	_add(m, LowPoly.blob(0.028, 1.5, 6, 4), TERRACOTTA, at + Vector3(0, 0.04, 0))
	_post(m, 0.01, 0.02, TERRACOTTA, at + Vector3(0, 0.08, 0), 5)


static func _log_pile(m: Node3D, at: Vector3, n := 3) -> void:
	for i in n:
		var row := 0 if i < 2 else 1
		var lg := _add(m, LowPoly.prism(0.022, 0.2, 6), LOG, at + Vector3(0, 0.022 + row * 0.036, (i % 2) * 0.045 - 0.022 + row * 0.022))
		lg.rotation.z = PI / 2


static func _lean_to(m: Node3D) -> void:
	for x in [-0.15, 0.15]:
		_post(m, 0.015, 0.2, LOG, Vector3(x, 0, 0.08), 5)
	_add(m, LowPoly.shed(0.38, 0.26, 0.22, 0.02), Color("#7a5a3a"), Vector3(0, 0, -0.02))
	_post(m, 0.05, 0.06, WOOD, Vector3(0.22, 0, 0.14), 7)
	_log_pile(m, Vector3(-0.2, 0, 0.14))


static func _lumber_camp(m: Node3D) -> void:
	_hall(m, Vector3(0.36, 0.18, 0.24), WOOD, ROOF_BROWN, 0.11, Vector3(0, 0, -0.05), false, 0)
	_log_pile(m, Vector3(0.24, 0, 0.12), 5)
	_post(m, 0.05, 0.06, WOOD, Vector3(-0.22, 0, 0.14), 7)


static func _timber_yard(m: Node3D) -> void:
	for p in [Vector3(-0.17, 0, -0.1), Vector3(0.17, 0, -0.1), Vector3(-0.17, 0, 0.1), Vector3(0.17, 0, 0.1)]:
		_post(m, 0.018, 0.2, MARBLE, p, 6)
	_add(m, LowPoly.gable(0.44, 0.3, 0.1), TERRACOTTA, Vector3(0, 0.2, 0))
	_log_pile(m, Vector3(0, 0, 0.0), 5)


static func _sawmill(m: Node3D) -> void:
	_hall(m, Vector3(0.36, 0.22, 0.26), WOOD, ROOF_BROWN, 0.12, Vector3(0.04, 0, -0.04), false, 0)
	var wheel := Node3D.new()
	wheel.position = Vector3(-0.2, 0.12, 0.1)
	wheel.add_to_group("spin")
	m.add_child(wheel)
	var rim := _add(wheel, LowPoly.prism(0.12, 0.03, 10), WOOD_DARK, Vector3.ZERO)
	rim.rotation.x = PI / 2
	for k in 4:
		var spoke := Node3D.new()
		spoke.rotation.z = k * PI / 4.0
		wheel.add_child(spoke)
		_box(spoke, Vector3(0.26, 0.025, 0.04), LOG, Vector3(0, -0.0125, 0))
	_log_pile(m, Vector3(0.25, 0, 0.14), 3)


static func _carpentry(m: Node3D) -> void:
	_box(m, Vector3(0.46, 0.03, 0.32), STONE, Vector3.ZERO)
	_hall(m, Vector3(0.38, 0.2, 0.22), PLASTER, TERRACOTTA, 0.1, Vector3(0, 0.03, -0.04), false, 0)
	for i in 3:
		_post(m, 0.014, 0.2, MARBLE, Vector3(-0.15 + i * 0.15, 0.03, 0.09), 6)
	for i in 3:
		_box(m, Vector3(0.22, 0.012, 0.05), Color("#c99a62"), Vector3(0.0, 0.03 + i * 0.013, 0.16))


# --- Mines and camp ---------------------------------------------------------------

static func _mine(m: Node3D, gold: bool, upgraded: bool) -> void:
	_add(m, LowPoly.blob(0.22, 0.55, 7, 4), STONE_DARK, Vector3(0, 0.04, -0.04))
	_add(m, LowPoly.blob(0.14, 0.7, 6, 3), STONE, Vector3(0.14, 0.03, 0.04))
	_box(m, Vector3(0.09, 0.08, 0.02), DOOR, Vector3(-0.04, 0, 0.14))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 if gold else 5
	for i in 6:
		var p := Vector3(rng.randf_range(-0.18, 0.2), 0.0, rng.randf_range(0.02, 0.18))
		if gold:
			_add(m, LowPoly.blob(0.025, 0.8, 5, 3), GOLD, p + Vector3(0, 0.02, 0))
		else:
			_box(m, Vector3(0.05, 0.035, 0.04), Color("#e5e1d6"), p, rng.randf())
	if upgraded:
		if gold:
			# A wooden headframe over the shaft, and a cart.
			for x in [-0.1, 0.02]:
				var leg := _post(m, 0.012, 0.3, WOOD_DARK, Vector3(x, 0, 0.12), 4)
				leg.rotation.z = 0.2 if x < 0 else -0.2
			_box(m, Vector3(0.18, 0.02, 0.03), WOOD_DARK, Vector3(-0.04, 0.27, 0.12))
			_box(m, Vector3(0.08, 0.05, 0.06), IRON, Vector3(0.2, 0.02, 0.18))
		else:
			_box(m, Vector3(0.3, 0.06, 0.1), Color("#d9d4c7"), Vector3(0.05, 0, -0.18))
			_box(m, Vector3(0.07, 0.07, 0.07), Color("#e5e1d6"), Vector3(-0.22, 0, 0.12))
			_box(m, Vector3(0.07, 0.07, 0.07), Color("#e5e1d6"), Vector3(-0.22, 0.07, 0.12))


static func _campfire(m: Node3D) -> void:
	for a in [0.4, -0.4, PI / 2]:
		var lg := _add(m, LowPoly.prism(0.012, 0.13, 5), WOOD, Vector3(0, 0.012, 0), a)
		lg.rotation.z = PI / 2
	var flame := _add(m, LowPoly.cone(0.035, 0.1, 5), Color("#f39c12"), Vector3(0, 0.06, 0))
	flame.name = "Flame"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#f39c12")
	mat.emission_enabled = true
	mat.emission = Color("#f5b041")
	mat.emission_energy_multiplier = 1.5
	flame.material_override = mat


# --- Military -------------------------------------------------------------------

## Barracks, archery range or stables, in their look: "era0" (rough wood and
## straw), "medieval" (timber frame, civ shields) or "classical" (plaster,
## columns, terracotta).
static func _military(m: Node3D, id: String, look: String, tint: Color) -> void:
	var wall: Color = {"era0": WOOD, "medieval": PLASTER, "classical": Color("#f4efe4")}[look]
	var roof: Color = {"era0": THATCH, "medieval": ROOF_BROWN, "classical": TERRACOTTA}[look]
	match id:
		"barracks":
			_hall(m, Vector3(0.5, 0.24, 0.3), wall, roof, 0.18, Vector3(0, 0, -0.06), false, 2)
			# Training dummy and a weapon rack.
			_post(m, 0.012, 0.18, WOOD_DARK, Vector3(0.3, 0, 0.16), 4)
			_box(m, Vector3(0.09, 0.015, 0.015), WOOD_DARK, Vector3(0.3, 0.13, 0.16))
			_add(m, LowPoly.blob(0.025, 1.0, 5, 3), HAY, Vector3(0.3, 0.2, 0.16))
			_box(m, Vector3(0.14, 0.12, 0.02), WOOD_DARK, Vector3(-0.3, 0, 0.14))
		"archery_range":
			_hall(m, Vector3(0.36, 0.2, 0.26), wall, roof, 0.14, Vector3(-0.08, 0, -0.08), false, 0)
			for i in 2:
				var tgt := Node3D.new()
				tgt.position = Vector3(0.18 + i * 0.13, 0.0, 0.12 - i * 0.04)
				m.add_child(tgt)
				var face := _add(tgt, LowPoly.prism(0.05, 0.02, 10), Color("#f5f0e6"), Vector3(0, 0.11, 0))
				face.rotation.x = PI / 2
				var eye := _add(tgt, LowPoly.prism(0.022, 0.024, 10), RED, Vector3(0, 0.11, 0.001))
				eye.rotation.x = PI / 2
				_post(tgt, 0.008, 0.08, WOOD_DARK, Vector3(0, 0, -0.012), 4)
		"stables":
			_hall(m, Vector3(0.56, 0.18, 0.26), wall, roof, 0.14, Vector3(0, 0, -0.08), false, 0)
			for i in 3:
				_box(m, Vector3(0.1, 0.12, 0.012), DOOR, Vector3(-0.17 + i * 0.17, 0, 0.055))
			# Fence and a hay bale.
			for i in 5:
				_post(m, 0.01, 0.08, LOG, Vector3(-0.28 + i * 0.14, 0, 0.2), 4)
			_box(m, Vector3(0.58, 0.012, 0.012), LOG, Vector3(0, 0.06, 0.2))
			_box(m, Vector3(0.09, 0.06, 0.06), HAY, Vector3(0.36, 0, 0.06))
	if look == "medieval":
		for x in [-0.12, 0.12]:
			_add(m, LowPoly.prism(0.035, 0.012, 6), tint, Vector3(x, 0.16, 0.11)).rotation.x = PI / 2
	elif look == "classical":
		for x in [-0.16, 0.0, 0.16]:
			_post(m, 0.014, 0.2, MARBLE, Vector3(x, 0, 0.12), 6)


## A second upgrade: a stone base and pennants (added over any military model).
static func military_tier2(m: Node3D, tint: Color) -> void:
	_box(m, Vector3(0.62, 0.04, 0.42), STONE, Vector3(0, -0.001, -0.04))
	for x in [-0.28, 0.28]:
		_flag(m, Vector3(x, 0, -0.2), 0.42, tint)
