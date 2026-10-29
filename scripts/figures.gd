class_name Figures
extends RefCounted
## Low-poly 3D troops and villagers. make_*() build a figure facing +z with
## its feet at the origin; animate() poses it each frame (walking legs,
## swinging arms, galloping horses). Sizes in world units: a foot soldier is
## about 0.3 tall.

const SKIN := Color("#e8b98a")
const LEG := Color("#4a2f1a")
const HAIR := Color("#6b4426")
const HAIR_LONG := Color("#7a4a26")
const IRON := Color("#9aa3a6")
const BRONZE := Color("#c9a04a")
const WOOD := Color("#8a5a33")
const WOOD_DARK := Color("#5e3b1f")
const HORSE := Color("#8b5a2b")
const HORSE_DARK := Color("#5e3b1f")
const VILLAGER_TUNIC := Color("#d9c8a0")
const VILLAGER_DRESS := Color("#a0674b")
const APRON := Color("#efe4c8")

static var _meshes := {}


## A mesh built once and shared (figures are many; their shapes are few).
static func _m(key: String, build: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = build.call()
	return _meshes[key]


## A part: an empty node carrying its mesh and color. Figures draw nothing
## themselves; WorldView draws every part of every figure in batches, one
## per mesh (see compact()).
static func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, name := "") -> Node3D:
	var part := Node3D.new()
	part.set_meta("mesh", mesh)
	part.set_meta("color", color)
	part.position = pos
	if name != "":
		part.name = name
	parent.add_child(part)
	return part


static func _pivot(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


static func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, name := "") -> Node3D:
	var key := "box%s" % size
	return _part(parent, _m(key, func(): return LowPoly.box(size)), color, pos, name)


# --- People -----------------------------------------------------------------

## A person: legs, a tunic (or a long dress), arms on shoulder pivots
## ("ArmL", "ArmR", each with a "Hand" at its end), a head with hair.
## look: {"dress": bool, "long_hair": bool, "seated": bool (no legs: astride)}.
static func person(tunic: Color, look := {}) -> Node3D:
	var root := Node3D.new()
	var body := _pivot(root, "Body", Vector3.ZERO)
	var seated: bool = look.get("seated", false)
	if not seated:
		for side in [-1, 1]:
			var leg := _pivot(root, "LegL" if side < 0 else "LegR", Vector3(side * 0.027, 0.1, 0))
			_box(leg, Vector3(0.034, 0.1, 0.04), LEG, Vector3(0, -0.05, 0))
	if look.get("dress", false):
		_part(body, _m("dress", func(): return LowPoly.prism(0.07, 0.2, 7, 0.045)), tunic, Vector3(0, 0.12, 0))
		_part(body, _m("apron", func(): return LowPoly.box(Vector3(0.06, 0.09, 0.01))), APRON, Vector3(0, 0.1, 0.066))
	else:
		_part(body, _m("tunic", func(): return LowPoly.prism(0.06, 0.13, 6, 0.045)), tunic, Vector3(0, 0.165, 0))
		_part(body, _m("belt", func(): return LowPoly.prism(0.062, 0.016, 6)), WOOD_DARK, Vector3(0, 0.145, 0))
	var head := _pivot(body, "Head", Vector3(0, 0.265, 0))
	_part(head, _m("head", func(): return LowPoly.blob(0.045, 1.0, 7, 4)), SKIN, Vector3.ZERO)
	_part(head, _m("hair", func(): return LowPoly.blob(0.047, 0.65, 7, 3)), HAIR, Vector3(0, 0.02, -0.008), "Hair")
	if look.get("long_hair", false):
		_part(head, _m("hair_long", func(): return LowPoly.box(Vector3(0.075, 0.1, 0.03))), HAIR_LONG, Vector3(0, -0.035, -0.03))
	for side in [-1, 1]:
		var arm := _pivot(body, "ArmL" if side < 0 else "ArmR", Vector3(side * 0.068, 0.215, 0))
		_box(arm, Vector3(0.028, 0.095, 0.03), tunic, Vector3(0, -0.045, 0))
		var hand := _pivot(arm, "Hand", Vector3(0, -0.1, 0))
		_part(hand, _m("hand", func(): return LowPoly.blob(0.017, 1.0, 5, 3)), SKIN, Vector3.ZERO)
	return root


## A villager: a man in a tunic with short hair, or a woman in a long dress
## with long hair (`woman`). Smaller than soldiers.
static func villager(woman: bool) -> Node3D:
	var v := person(VILLAGER_DRESS if woman else VILLAGER_TUNIC, {"dress": woman, "long_hair": woman})
	v.scale = Vector3.ONE * 0.75
	var tool := _pivot(v.get_node("Body/ArmR/Hand"), "Tool", Vector3.ZERO)
	tool.visible = false
	_box(tool, Vector3(0.012, 0.012, 0.13), WOOD, Vector3(0, 0, 0.06))
	_box(tool, Vector3(0.04, 0.025, 0.02), IRON, Vector3(0, -0.01, 0.12), "Head")
	var load := _pivot(v.get_node("Body"), "Load", Vector3(0, 0.33, 0))
	load.visible = false
	_box(load, Vector3(0.07, 0.045, 0.06), HAIR, Vector3.ZERO, "Box")
	return v


## Foot soldiers: "fighter", "archer" (crossbowman at tier 2) and "phalanx"
## (a hoplite), in the civ's color, geared by tier.
static func soldier(type: String, tier: int, color: Color) -> Node3D:
	var p := person(color)
	var head: Node3D = p.get_node("Body/Head")
	var hand_r: Node3D = p.get_node("Body/ArmR/Hand")
	var hand_l: Node3D = p.get_node("Body/ArmL/Hand")
	match type:
		"fighter":
			if tier >= 1:
				_helmet(head, tier >= 2)
				var shield := _pivot(hand_l, "Shield", Vector3(0, 0.01, 0.02))
				var disc := _part(shield, _m("shield", func(): return LowPoly.prism(0.05, 0.014, 8)), color.darkened(0.15), Vector3.ZERO)
				disc.rotation.x = PI / 2
				_part(shield, _m("boss", func(): return LowPoly.blob(0.015, 0.8, 5, 3)), IRON, Vector3(0, 0, 0.01))
			if tier >= 2:
				for side in [-1, 1]:
					_box(p.get_node("Body"), Vector3(0.05, 0.03, 0.08), IRON, Vector3(side * 0.05, 0.21, 0))
				var w := _pivot(hand_r, "Weapon", Vector3.ZERO)
				_box(w, Vector3(0.018, 0.16, 0.008), Color("#dfe6e9"), Vector3(0, -0.09, 0))
				_box(w, Vector3(0.06, 0.012, 0.014), WOOD_DARK, Vector3(0, -0.012, 0))
			else:
				var w := _pivot(hand_r, "Weapon", Vector3.ZERO)
				_part(w, _m("club", func(): return LowPoly.prism(0.013, 0.14, 5, 0.024)), WOOD, Vector3(0, -0.07, 0)).rotation.x = PI
		"archer":
			if tier == 1:
				_part(head, _m("hood", func(): return LowPoly.blob(0.054, 1.0, 7, 4)), Color("#2f8a4c"), Vector3(0, 0.008, -0.012))
			if tier >= 2:
				_helmet(head, false)
			if tier >= 1:
				_box(p.get_node("Body"), Vector3(0.035, 0.12, 0.03), WOOD, Vector3(0.03, 0.2, -0.06), "Quiver")
			if tier >= 2:
				var xb := _pivot(hand_l, "Crossbow", Vector3(0, 0, 0.0))
				_box(xb, Vector3(0.02, 0.02, 0.14), WOOD, Vector3(0, 0, 0.0))
				_box(xb, Vector3(0.13, 0.015, 0.015), IRON, Vector3(0, 0, 0.06))
			else:
				var bow := _pivot(hand_l, "Bow", Vector3.ZERO)
				for s in [-1, 1]:
					var limb := _box(bow, Vector3(0.012, 0.1, 0.012), WOOD_DARK, Vector3(0, s * 0.045, -0.012))
					limb.rotation.x = s * 0.35
				_box(bow, Vector3(0.003, 0.17, 0.003), Color("#ecf0f1"), Vector3(0, 0, -0.04), "String")
		"phalanx":
			# Bronze armor, crested helmet, a big round shield and a long spear.
			var body: Node3D = p.get_node("Body")
			_part(body, _m("cuirass", func(): return LowPoly.prism(0.064, 0.08, 6, 0.05)), BRONZE, Vector3(0, 0.19, 0))
			_part(head, _m("hoplite_helm", func(): return LowPoly.blob(0.052, 1.0, 7, 4)), BRONZE, Vector3(0, 0.006, -0.004))
			_box(head, Vector3(0.014, 0.05, 0.09), color, Vector3(0, 0.06, -0.01))
			var aspis := _pivot(body, "Aspis", Vector3(-0.03, 0.17, 0.07))
			var disc := _part(aspis, _m("aspis", func(): return LowPoly.prism(0.085, 0.016, 10)), BRONZE, Vector3.ZERO)
			disc.rotation.x = PI / 2
			var face := _part(aspis, _m("aspis_face", func(): return LowPoly.prism(0.068, 0.018, 10)), color, Vector3(0, 0, 0.002))
			face.rotation.x = PI / 2
			var spear := _pivot(hand_r, "Weapon", Vector3.ZERO)
			spear.set_meta("level", true)
			var shaft := _part(spear, _m("spear", func(): return LowPoly.prism(0.008, 0.5, 5)), WOOD, Vector3(0, 0, 0.17))
			shaft.rotation.x = PI / 2
			_part(spear, _m("spear_tip", func(): return LowPoly.cone(0.016, 0.05, 4)), IRON, Vector3(0, 0, 0.44)).rotation.x = PI / 2
	return p


static func _helmet(head: Node3D, great: bool) -> void:
	if great:
		_part(head, _m("great_helm", func(): return LowPoly.prism(0.05, 0.075, 8)), IRON, Vector3(0, 0.005, 0))
		_box(head, Vector3(0.06, 0.008, 0.01), Color("#2b1d10"), Vector3(0, 0.005, 0.05))
	else:
		_part(head, _m("helmet", func(): return LowPoly.blob(0.05, 0.75, 7, 3)), IRON, Vector3(0, 0.018, 0))
		_box(head, Vector3(0.008, 0.035, 0.008), IRON, Vector3(0, -0.005, 0.048))


# --- Horses --------------------------------------------------------------------

## A horse facing +z, legs on "Leg0".."Leg3" pivots. `cloth`: a barding in
## that color (Color(0,0,0,0) for none); `long`: a knight's caparison.
static func horse(cloth := Color(0, 0, 0, 0), long := false) -> Node3D:
	var h := Node3D.new()
	var i := 0
	for p in [Vector3(-0.035, 0.13, 0.08), Vector3(0.035, 0.13, 0.08), Vector3(-0.035, 0.13, -0.08), Vector3(0.035, 0.13, -0.08)]:
		var leg := _pivot(h, "Leg%d" % i, p)
		_box(leg, Vector3(0.024, 0.13, 0.026), HORSE_DARK, Vector3(0, -0.065, 0))
		i += 1
	_box(h, Vector3(0.09, 0.09, 0.24), HORSE, Vector3(0, 0.13, 0))
	var neck := _box(h, Vector3(0.055, 0.12, 0.06), HORSE, Vector3(0, 0.22, 0.12))
	neck.rotation.x = 0.55
	_box(h, Vector3(0.05, 0.05, 0.11), HORSE, Vector3(0, 0.28, 0.18))
	_box(h, Vector3(0.012, 0.03, 0.05), HORSE_DARK, Vector3(0, 0.3, 0.12))
	var tail := _box(h, Vector3(0.02, 0.1, 0.02), HORSE_DARK, Vector3(0, 0.14, -0.13))
	tail.rotation.x = 0.4
	if cloth.a > 0.0:
		var size := Vector3(0.105, 0.1 if long else 0.07, 0.25 if long else 0.2)
		_box(h, size, cloth, Vector3(0, 0.1 if long else 0.135, 0))
	return h


## Cavalry and knights: a rider (no legs) on a horse, with a lance.
static func rider(type: String, tier: int, color: Color) -> Node3D:
	var root := Node3D.new()
	var knight := type == "knight"
	var h := horse(color if knight or tier >= 1 else Color(0, 0, 0, 0), knight)
	h.name = "Horse"
	root.add_child(h)
	var man := person(color, {"seated": true})
	man.position = Vector3(0, 0.1, -0.02)
	man.name = "Rider"
	root.add_child(man)
	for side in [-1, 1]:
		_box(man, Vector3(0.03, 0.09, 0.035), LEG, Vector3(side * 0.06, 0.07, 0.01))
	var head: Node3D = man.get_node("Body/Head")
	if knight or tier >= 2:
		_helmet(head, knight)
	var lance := _pivot(man.get_node("Body/ArmR/Hand"), "Weapon", Vector3.ZERO)
	lance.set_meta("level", true)
	var shaft := _part(lance, _m("lance", func(): return LowPoly.prism(0.009, 0.55, 5)), WOOD, Vector3(0, 0, 0.2))
	shaft.rotation.x = PI / 2
	_part(lance, _m("lance_tip", func(): return LowPoly.cone(0.014, 0.05, 4)), IRON, Vector3(0, 0, 0.49)).rotation.x = PI / 2
	if knight:
		_box(lance, Vector3(0.004, 0.04, 0.07), color, Vector3(0, 0.02, 0.4))
	if knight or tier >= 2:
		var shield := _pivot(man.get_node("Body/ArmL/Hand"), "Shield", Vector3(-0.01, 0.01, 0.01))
		var disc := _part(shield, _m("shield", func(): return LowPoly.prism(0.05, 0.014, 8)), color.darkened(0.15), Vector3.ZERO)
		disc.rotation.z = PI / 2
	return root


## The Roman chariot: two horses ahead of a car with two archers.
static func chariot(tier: int, color: Color) -> Node3D:
	var root := Node3D.new()
	for side in [-1, 1]:
		var h := horse(color if tier >= 1 else Color(0, 0, 0, 0))
		h.name = "Horse%d" % (side + 1)
		h.position = Vector3(side * 0.06, 0, 0.2)
		h.scale = Vector3.ONE * 0.85
		root.add_child(h)
	_box(root, Vector3(0.18, 0.09, 0.12), color, Vector3(0, 0.06, -0.06))
	_box(root, Vector3(0.012, 0.012, 0.18), WOOD_DARK, Vector3(0, 0.08, 0.08))
	for side in [-1, 1]:
		var wheel := _pivot(root, "Wheel%d" % (side + 1), Vector3(side * 0.1, 0.065, -0.06))
		var disc := _part(wheel, _m("wheel", func(): return LowPoly.prism(0.065, 0.014, 10)), WOOD_DARK, Vector3.ZERO)
		disc.rotation.z = PI / 2
	for side in [-1, 1]:
		var crew := person(color, {"seated": true})
		crew.position = Vector3(side * 0.04, 0.03, -0.07)
		crew.scale = Vector3.ONE * 0.85
		crew.name = "Crew%d" % (side + 1)
		root.add_child(crew)
	return root


# --- Batching -------------------------------------------------------------------

static var _merged := {}


## Merge the parts that move together (the direct parts of each joint) into
## one mesh, colors in its vertices, shared by every figure with the same
## `spec`: a person ends up with about six parts. A joint's single part is
## kept as it is, so its color can still change (a villager's load).
static func compact(fig: Node3D, spec: String) -> void:
	# Joints only (parts get freed below, so they mustn't be in this list).
	var joints: Array = [fig]
	joints.append_array(fig.find_children("*", "Node3D", true, false).filter(func(n): return not n.has_meta("mesh")))
	for joint in joints:
		var parts: Array = joint.get_children().filter(func(c): return c.has_meta("mesh") and c.get_child_count() == 0)
		if parts.size() < 2:
			continue
		var key := "%s|%s" % [spec, _path(fig, joint)]
		if not _merged.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for part in parts:
				LowPoly._append(st, part.get_meta("mesh"), part.get_meta("color"), part.transform)
			_merged[key] = st.commit()
		for part in parts:
			joint.remove_child(part)
			part.free()
		_part(joint, _merged[key], Color.WHITE, Vector3.ZERO, "Merged")
	fig.set_meta("parts", fig.find_children("*", "Node3D", true, false).filter(func(n): return n.has_meta("mesh")))


static func _path(root: Node, n: Node) -> String:
	var names := []
	while n != root:
		names.push_front(n.name)
		n = n.get_parent()
	return "/".join(names)


# --- Posing ----------------------------------------------------------------------

## Pose a figure for this frame. info: {"walk": step phase or -1, "fight":
## attack phase 0..1 or -1, "type": troop type or "villager", "tool": job
## (villager working), "carry": bool, "hammer": bool}.
static func animate(fig: Node3D, info: Dictionary, now: float) -> void:
	var walk: float = info.get("walk", -1.0)
	var fight: float = info.get("fight", -1.0)
	var type: String = info.get("type", "")
	match type:
		"cavalry", "knight":
			_gallop(fig.get_node("Horse"), walk, 0.0)
			var arm: Node3D = fig.get_node("Rider/Body/ArmR")
			arm.rotation.x = -PI / 2 + 0.25
			arm.position.z = sin(now * 10.0) * 0.03 if fight >= 0.0 else 0.0
			fig.get_node("Rider/Body/ArmL").rotation.x = -0.9
			_level(fig.get_node("Rider/Body"))
			return
		"chariot":
			for i in [0, 2]:
				_gallop(fig.get_node("Horse%d" % i), walk, i)
				if walk >= 0.0:
					fig.get_node("Wheel%d" % i).rotation.x = now * 8.0
			for i in [0, 2]:
				var crew: Node3D = fig.get_node("Crew%d" % i)
				crew.get_node("Body/ArmL").rotation.x = -PI / 2 if fight >= 0.0 else -0.3
				crew.get_node("Body/ArmR").rotation.x = -PI / 2 + 0.4 if fight >= 0.0 else -0.2
			return
	# People: legs step, the body bobs.
	var legs := [fig.get_node_or_null("LegL"), fig.get_node_or_null("LegR")]
	for k in 2:
		if legs[k]:
			legs[k].rotation.x = sin(walk) * 0.6 * (1 if k == 0 else -1) if walk >= 0.0 else 0.0
	var body: Node3D = fig.get_node("Body")
	body.position.y = absf(sin(walk)) * 0.012 if walk >= 0.0 else 0.0
	var arm_r: Node3D = body.get_node("ArmR")
	var arm_l: Node3D = body.get_node("ArmL")
	# Arms swing with the stride by default.
	var swing := sin(walk) * 0.45 if walk >= 0.0 else 0.0
	arm_r.rotation.x = -swing
	arm_l.rotation.x = swing
	arm_r.position.z = 0.0
	match type:
		"fighter":
			# Overhead blow: raised high, chopped down fast, lifted back slowly.
			if fight >= 0.0:
				var raised := -2.9
				var struck := -0.7
				arm_r.rotation.x = lerpf(raised, struck, ease(fight / 0.25, 2.2)) if fight < 0.25 else lerpf(struck, raised, ease((fight - 0.25) / 0.75, 0.6))
				arm_l.rotation.x = -1.0
			else:
				arm_r.rotation.x = -0.5 - swing * 0.5
				if fig.get_node_or_null("Body/ArmL/Hand/Shield"):
					arm_l.rotation.x = -0.7
		"archer":
			var xbow := fig.get_node_or_null("Body/ArmL/Hand/Crossbow") != null
			if fight >= 0.0:
				arm_l.rotation.x = -PI / 2
				arm_r.rotation.x = -PI / 2 + (0.0 if xbow else 0.25 + 0.5 * smoothstep(0.1, 0.85, fight))
				arm_r.position.z = 0.0 if xbow else -0.03 * smoothstep(0.1, 0.85, fight)
			elif xbow:
				arm_l.rotation.x = -1.1
				arm_r.rotation.x = -1.2
			else:
				arm_l.rotation.x = -0.25
		"phalanx":
			arm_r.rotation.x = -PI / 2
			arm_l.rotation.x = -1.2
			if fight >= 0.0:
				arm_r.position.z = maxf(sin(fight * TAU), 0.0) * 0.05
		"villager":
			var tool: Node3D = body.get_node("ArmR/Hand/Tool")
			var job: String = info.get("tool", "")
			tool.visible = job != "" or info.get("hammer", false)
			if job != "" or info.get("hammer", false):
				var rate := 6.0 if job == "food" else 9.0
				arm_r.rotation.x = -1.4 + sin(now * rate + info.get("seed", 0)) * 0.7
			var load: Node3D = body.get_node("Load")
			load.visible = info.get("carry", "") != ""
			if load.visible:
				load.get_node("Box").set_meta("color", info.get("carry_color", HAIR))
				arm_r.rotation.x = -2.9
				arm_l.rotation.x = -2.9
	_level(body)


## Held things stay level however the arm turns: the bow upright, the
## crossbow, spear and lance pointing ahead, the shield facing front.
static func _level(body: Node3D) -> void:
	for path in ["ArmL/Hand/Bow", "ArmL/Hand/Crossbow", "ArmL/Hand/Shield"]:
		var g: Node3D = body.get_node_or_null(path)
		if g:
			g.rotation.x = -body.get_node("ArmL").rotation.x
	var w: Node3D = body.get_node_or_null("ArmR/Hand/Weapon")
	if w and w.has_meta("level"):
		w.rotation.x = -body.get_node("ArmR").rotation.x


static func _gallop(horse: Node3D, gallop: float, offset: float) -> void:
	for i in 4:
		var leg: Node3D = horse.get_node("Leg%d" % i)
		var phase := 0.0 if i == 0 or i == 3 else PI
		leg.rotation.x = sin(gallop + phase + offset) * 0.7 if gallop >= 0.0 else 0.0


# --- Trees -----------------------------------------------------------------------

## An olive tree: a twisted grey trunk and a silvery-green crown.
static func olive_tree(seed: int) -> Node3D:
	var t := Node3D.new()
	var trunk := _part(t, _m("olive_trunk", func(): return LowPoly.prism(0.022, 0.12, 5, 0.014)), Color("#7d7462"), Vector3(0, 0.06, 0))
	trunk.rotation.z = 0.25 if seed % 2 == 0 else -0.25
	var green := Color("#7f9a5a").darkened((seed % 3) * 0.06)
	_part(t, _m("olive_crown", func(): return LowPoly.blob(0.085, 0.7, 7, 4)), green, Vector3(0, 0.15, 0))
	_part(t, _m("olive_crown2", func(): return LowPoly.blob(0.055, 0.8, 6, 3)), green.lightened(0.1), Vector3(0.04 if seed % 2 == 0 else -0.04, 0.19, 0.02))
	t.rotation.y = seed * 1.3
	return t
