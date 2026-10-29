class_name WorldView
extends SubViewportContainer
## The battlefield in 3D: a lit ground seen by a tilted camera, Clash Royale
## style. The flat map (BattleView) is still the game's layout: every
## position is a point on it, in pixels. Here it is drawn off screen and laid
## on the 3D ground as its texture, and 3D models stand on it. Taps on the
## 3D view are traced back to map pixels, so BattleView's tap handling, the
## card drops and the menus work unchanged.
##
## For testing, the camera zooms (mouse wheel or pinch) and pans (drag);
## a double tap goes back to the whole-battlefield view.

## World units per map pixel: the map is laid out 1 unit per 100 pixels.
const PX := 0.01
## Camera pitch below the horizon, and field of view (degrees).
const PITCH := 54.0
const FOV := 32.0
## Buildings are modeled a little small; this brings them to the size the
## flat map drew them.
const BUILDING_SCALE := 1.3
## Lanes are this share of the length they would have on the tall map.
const LANE_SHARE := 0.9
## Slack when checking that the tilted map fills the view (pixels).
const FIT_MARGIN := 2.0
## Map rendered at this many times its size, so the tilted ground stays sharp.
const MAP_SUPERSAMPLE := 2.0
## Below this frame rate (over a few seconds) quality steps down: a less
## sharp map, then no edge smoothing, then cheaper shadows.
const MIN_FPS := 40.0

var view: BattleView
var camera: Camera3D
var _world_vp: SubViewport
var _map_vp: SubViewport
var _ground: MeshInstance3D
## The grass painted once, for the map to draw as one picture.
var _grass_vp: SubViewport
var _grass_painter: Control
var _root: Node3D
## Trees and rocks, rebuilt when the map changes size.
var _scenery: Node3D
## Building models by slot ("fort0", "hut1_4", ...), kept in step with the game.
var _buildings := {}
var _building_root: Node3D
## Troops ("u<id>") and villagers ("vm<n>" men, "vw<n>" women) as 3D figures.
var _figures := {}
var _figure_root: Node3D
var _arrows: Array[Node3D] = []
## One batch per part mesh, drawing that part of every figure.
var _batches := {}
## Health bars drawn over the 3D view: [screen point, hp, max hp, team].
var _bars := []
var _overlay: Control
## Menu pictures of the 3D models, by model, color and upgrade.
var _icons := {}
var _icon_holder: Node
## See-through models standing on the open build plots.
var _ghosts := {}
var _map_size := Vector2.ZERO
## Whole-battlefield camera, and the testing zoom on top of it.
var _home := Transform3D.IDENTITY
var _zoom := 1.0
var _pan := Vector3.ZERO
var _touches := {}
var _pinch_from := 0.0
var _press_at := Vector2.INF
var _dragged := false
var _last_tap_ms := 0
## The view size the map was last fitted to.
var _fitted_for := Vector2.ZERO
var _sun: DirectionalLight3D
var _env: Environment
var _supersample := MAP_SUPERSAMPLE
var _quality := 0
var _slow_frames := 0.0
var _timed := 0.0


func _init(battle_view: BattleView) -> void:
	view = battle_view
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_world_vp = SubViewport.new()
	_world_vp.msaa_3d = Viewport.MSAA_4X
	_world_vp.handle_input_locally = false
	add_child(_world_vp)
	# The flat map, drawn off screen into a texture for the ground.
	_map_vp = SubViewport.new()
	_map_vp.transparent_bg = false
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_vp.size_2d_override_stretch = true
	_map_vp.gui_disable_input = true
	view.visible = false  # until it is given its size (_fit)
	_map_vp.add_child(view)
	# Inside the 3D viewport, not this container (which would show it flat).
	_world_vp.add_child(_map_vp)
	_build_world()
	# Health bars float over the 3D figures, drawn flat on top of the view.
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_bars)
	add_child(_overlay)


## Frame the map once the 3D viewport has taken this view's size (the
## camera's projection uses it).
func _process(delta: float) -> void:
	if size.x >= 2 and Vector2(_world_vp.size) == size.floor() and _fitted_for != size:
		_fit()
	if _map_size != Vector2.ZERO and view.battle != null:
		_sync_buildings()
		_animate(delta)
		_sync_figures()
		_sync_ghosts()
		_overlay.queue_redraw()
	_watch_speed(delta)


# --- Buildings ------------------------------------------------------------------

## What should stand where: {slot: [model id, map pixel, civ color, scale, tier 2]}.
## Mirrors what the flat map used to draw (BattleView._draw_city).
func _wanted_buildings() -> Dictionary:
	var want := {}
	for team in 2:
		var e := view.econ(team)
		var color := Color(e.civ().color)
		var classical := e.style() == "classical"
		var era := e.era_index
		var fort := "fort_era0"
		if era >= 1:
			fort = ("timber_hall" if era == 1 else "marble_palace") if classical else ("fort_wood" if era == 1 else "castle_stone")
		want["fort%d" % team] = [fort, view.town_center(team) + Vector2(0, -12), color]
		var hut := "hut_era0" if era == 0 else ("hut_classical" if classical else "hut_medieval")
		for i in e.huts:
			want["hut%d_%d" % [team, i]] = [hut, view.hut_pos(team, i), color, 1.0, false, i]
		want["fire%d" % team] = ["campfire", view.campfire_pos(team), color]
		if e.camps.has("farm") and classical:
			# The olive grove's trees (wheat fields stay flat on the ground).
			var area := view.farm_rect(team)
			var cell := area.size / Vector2(BattleView.FARM_COLS, BattleView.FARM_ROWS)
			for i in BattleView.FARM_COLS * BattleView.FARM_ROWS:
				var c := area.position + cell * Vector2(i % BattleView.FARM_COLS + 0.5, i / BattleView.FARM_COLS + 0.5)
				want["olive%d_%d" % [team, i]] = ["olive_tree", c, color, 1.0, false, i]
		if e.camps.has("farm"):
			var food := "granary"
			if e.upgrades.has("mill2"):
				food = "oil_workshop" if classical else "grand_mill"
			elif e.upgrades.has("mill"):
				food = "olive_press" if classical else "windmill"
			want["food%d" % team] = [food, view.drop_off(team, "food"), color]
		if e.camps.has("lumberjack"):
			var wood := "lean_to"
			if e.upgrades.has("lumber_camp2"):
				wood = "carpentry" if classical else "sawmill"
			elif e.upgrades.has("lumber_camp"):
				wood = "timber_yard" if classical else "lumber_camp"
			want["wood%d" % team] = [wood, view.drop_off(team, "wood"), color]
		for res in e.mines:
			want["mine%d_%s" % [team, res]] = [res + ("_mine2" if e.upgrades.has(res + "_mine2") else "_mine"), view.mine_pos(team, res), color]
		for id in e.military:
			var tier := int(e.upgrades.has(id + "1")) + int(e.upgrades.has(id + "2"))
			var look := "era0" if tier == 0 else ("classical" if classical else "medieval")
			# Second and third ones stand behind, smaller.
			var behind := [Vector2.ZERO, Vector2(24, -22), Vector2(-24, -22)]
			for k in mini(e.military[id], 3):
				want["mil%d_%s_%d" % [team, id, k]] = ["%s_%s" % [id, look], view.military_pos(team, id) + behind[k],
					color, 1.0 if k == 0 else 0.78, tier >= 2]
		for lane in Battlefield.LANES:
			var hp: float = view.battle.buildings[team].towers[lane]
			var ruin: bool = view.battle.towers_built[team][lane] and not e.is_pending("towers", str(lane)) \
				and not (team == Battlefield.PLAYER and e.site_open("towers", str(lane)))
			if hp > 0:
				var look := "tower_wood" if not e.upgrades.has("stone_towers") else ("tower_marble" if classical else "tower_stone")
				want["tower%d_%d" % [team, lane]] = [look, view.building_pos(team, "tower", lane), color]
			elif ruin:
				want["tower%d_%d" % [team, lane]] = ["tower_ruin", view.building_pos(team, "tower", lane), color]
	return want


func _sync_buildings() -> void:
	if _building_root == null:
		_building_root = Node3D.new()
		_root.add_child(_building_root)
	var want := _wanted_buildings()
	for slot in _buildings.keys():
		if not want.has(slot) or _buildings[slot].get_meta("spec") != want[slot]:
			_buildings[slot].queue_free()
			_buildings.erase(slot)
	for slot in want:
		if _buildings.has(slot):
			continue
		var spec: Array = want[slot]
		var variant: int = spec[5] if spec.size() > 5 else 0
		var model: Node3D = Figures.olive_tree(variant) if spec[0] == "olive_tree" else Models.make(spec[0], spec[2], variant)
		if spec.size() > 4 and spec[4]:
			Models.military_tier2(model, spec[2])
		model.position = map_to_world(spec[1])
		model.scale = Vector3.ONE * BUILDING_SCALE * (spec[3] if spec.size() > 3 else 1.0)
		LowPoly.merge(model)
		model.set_meta("spec", spec)
		_building_root.add_child(model)
		model.set_meta("box", _bounds(model))
		_buildings[slot] = model


# --- Build plots and menu icons ---------------------------------------------------

## The 3D model shown for a build plot or a menu option, by the plot's or
## option's id: [model id, with the second-upgrade stone base].
func model_for(id: String, e: Economy) -> Array:
	var classical := e.style() == "classical"
	match id:
		"era":
			var next := mini(e.era_index + 1, 2)
			if next == 1:
				return ["timber_hall" if classical else "fort_wood", false]
			return ["marble_palace" if classical else "castle_stone", false]
		"farm":
			return ["granary", false]
		"lumberjack":
			return ["lean_to", false]
		"hut":
			return ["hut_era0" if e.era_index == 0 else ("hut_classical" if classical else "hut_medieval"), false]
		"towers":
			return ["tower_wood", false]
		"stone_towers":
			return ["tower_marble" if classical else "tower_stone", false]
		"gold", "stone":
			return [id + "_mine", false]
		"gold_mine2", "stone_mine2":
			return [id, false]
		"barracks", "archery_range", "stables":
			return [id + "_era0", false]
		"mill":
			return ["olive_press" if classical else "windmill", false]
		"mill2":
			return ["oil_workshop" if classical else "grand_mill", false]
		"lumber_camp":
			return ["timber_yard" if classical else "lumber_camp", false]
		"lumber_camp2":
			return ["carpentry" if classical else "sawmill", false]
	if id.begins_with("tower:"):
		return ["tower_wood", false]
	for mil in ["barracks", "archery_range", "stables"]:
		for tier in [1, 2]:
			if id == mil + str(tier):
				return ["%s_%s" % [mil, "classical" if classical else "medieval"], tier == 2]
	return []


## A picture of a 3D model (for the building menus), rendered once in a
## small scene of its own and kept.
func model_icon(model_id: String, tint: Color, tier2 := false) -> Texture2D:
	var key := "%s|%s|%s" % [model_id, tint.to_html(), tier2]
	if _icons.has(key):
		return _icons[key]
	var model := Models.make(model_id, tint, 1)
	if tier2:
		Models.military_tier2(model, tint)
	var tex := _snapshot(model, Vector2i(180, 150), Vector3(0.35, 0.75, 1.0), 0.95)
	_icons[key] = tex
	return tex


## Render `model` once into a small picture of its own, lit like the
## battlefield, the camera looking at it from `dir` (`fill`: how much of the
## picture it fills, smaller is bigger).
func _snapshot(model: Node3D, size_px: Vector2i, dir: Vector3, fill: float) -> Texture2D:
	if _icon_holder == null:
		_icon_holder = Node.new()
		_world_vp.add_child(_icon_holder)
	var vp := SubViewport.new()
	vp.size = size_px
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_icon_holder.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = _env.duplicate()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = _sun.light_color
	sun.light_energy = _sun.light_energy
	sun.rotation = _sun.rotation
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	vp.add_child(sun)
	vp.add_child(model)
	var box := _bounds(model)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var center := box.get_center()
	var radius := box.size.length() / 2.0
	cam.look_at_from_position(center + dir.normalized() * radius / sin(deg_to_rad(cam.fov / 2.0)) * fill, center, Vector3.UP)
	return vp.get_texture()


## A see-through model on every open build plot of the player's.
func _sync_ghosts() -> void:
	var want := {}
	for site in view.build_sites(view.economy):
		var spec := model_for(site[0], view.economy)
		if spec.is_empty():
			continue
		want["%s@%s" % [site[0], site[1]]] = [spec[0], site[1]]
	for key in _ghosts.keys():
		if not want.has(key):
			_ghosts[key].queue_free()
			_ghosts.erase(key)
	for key in want:
		if _ghosts.has(key):
			continue
		var model := Models.make(want[key][0], Color.WHITE)
		LowPoly.merge(model)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = _ghost_material()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.position = map_to_world(want[key][1])
		model.scale = Vector3.ONE * BUILDING_SCALE
		_building_root.add_child(model)
		_ghosts[key] = model


static var _ghost_mat: StandardMaterial3D


static func _ghost_material() -> StandardMaterial3D:
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.albedo_color = Color(0.92, 0.94, 0.98, 0.32)
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _ghost_mat


# --- Troops, villagers and arrows -------------------------------------------------

## Troop figures are drawn a little larger than life, to read at a distance.
const FIGURE_SCALE := 1.25


## Place and pose a 3D figure for everyone the map recorded this frame
## (BattleView.figures_3d), and fly the arrows.
func _sync_figures() -> void:
	if _figure_root == null:
		_figure_root = Node3D.new()
		_root.add_child(_figure_root)
	var now := Time.get_ticks_msec() / 1000.0
	var seen := {}
	var count := {"vm": 0, "vw": 0}
	var flights := []  # [from, to, t, high arc]
	_bars.clear()
	for f in view.figures_3d:
		match f.kind:
			"unit":
				var u: Dictionary = f.u
				var key := "u%d" % u.id
				var spec := "%s:%d:%s" % [u.type, u.get("tier", 0), (f.color as Color).to_html()]
				var fig: Node3D = _figure(key, spec, func(): return _make_troop(u.type, u.get("tier", 0), f.color))
				fig.position = map_to_world(f.pos)
				var d := Vector2.from_angle(f.heading)
				fig.rotation.y = atan2(d.x, d.y)
				Figures.animate(fig, {"walk": f.walk, "fight": f.fight, "type": u.type}, now)
				seen[key] = true
				var tall := 0.5 if u.type in BattleView.MOUNTED else 0.45
				_bars.append([camera.unproject_position(fig.position + Vector3(0, tall, 0)), u.hp, u.max_hp, u.team])
				if f.fight >= 0.0 and u.type in ["archer", "chariot"] and f.target != Vector2.INF:
					var from := fig.position + Vector3(0, 0.25, 0)
					var to := map_to_world(f.target) + Vector3(0, 0.15, 0)
					flights.append([from, to, f.fight, false])
					if u.type == "chariot":
						flights.append([from, to, fmod(f.fight + 0.5, 1.0), false])
			"villager":
				var kind := "vw" if posmod(f.seed, 2) == 1 else "vm"
				var key := "%s%d" % [kind, count[kind]]
				count[kind] += 1
				var fig: Node3D = _figure(key, kind, func(): return Figures.villager(kind == "vw"))
				var at := map_to_world(f.pos)
				var was: Vector3 = fig.get_meta("was", at)
				var move := at - was
				if f.has("work_at"):
					var w: Vector3 = map_to_world(f.work_at) - at
					if w.length() > 0.01:
						fig.rotation.y = atan2(w.x, w.z)
				elif move.length() > 0.004:
					fig.rotation.y = lerp_angle(fig.rotation.y, atan2(move.x, move.z), 0.35)
				elif f.walk < 0.0 and f.get("tool", "") == "":
					# Resting: face the nearest campfire.
					var fire := map_to_world(view.campfire_pos(0 if f.pos.y > _map_size.y / 2.0 else 1))
					fig.rotation.y = atan2(fire.x - at.x, fire.z - at.z)
				fig.position = at
				fig.set_meta("was", at)
				Figures.animate(fig, {"walk": f.walk, "type": "villager", "tool": f.get("tool", ""), "seed": f.seed,
					"carry": f.get("carry", ""), "carry_color": f.get("carry_color", Color.WHITE), "hammer": f.get("hammer", false)}, now)
				seen[key] = true
			"arrow":
				flights.append([map_to_world(f.from) + Vector3(0, 0.45, 0), map_to_world(f.to) + Vector3(0, 0.15, 0), f.t, true])
	for key in _figures.keys():
		if not seen.has(key):
			_figures[key].queue_free()
			_figures.erase(key)
	_draw_parts()
	_fly_arrows(flights)


## Draw every visible part of every figure: one batch per mesh.
func _draw_parts() -> void:
	var groups := {}
	for fig in _figures.values():
		for part in fig.get_meta("parts"):
			if not part.is_visible_in_tree():
				continue
			var mesh: Mesh = part.get_meta("mesh")
			if not groups.has(mesh):
				groups[mesh] = [[], []]
			groups[mesh][0].append(part.global_transform)
			groups[mesh][1].append(part.get_meta("color"))
	for mesh in _batches:
		if not groups.has(mesh):
			_batches[mesh].multimesh.visible_instance_count = 0
	for mesh in groups:
		var batch: MultiMeshInstance3D = _batches.get(mesh)
		if batch == null:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			batch = MultiMeshInstance3D.new()
			batch.multimesh = mm
			batch.material_override = LowPoly.vertex_material()
			_figure_root.add_child(batch)
			_batches[mesh] = batch
		var xforms: Array = groups[mesh][0]
		var colors: Array = groups[mesh][1]
		var mm := batch.multimesh
		if mm.instance_count < xforms.size():
			mm.instance_count = xforms.size() + 16
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, colors[i])
		mm.visible_instance_count = xforms.size()


## The figure for `key`, made anew when it doesn't exist or its look changed.
func _figure(key: String, spec: String, make: Callable) -> Node3D:
	var fig: Node3D = _figures.get(key)
	if fig == null or fig.get_meta("spec") != spec:
		if fig:
			fig.queue_free()
		fig = make.call()
		Figures.compact(fig, spec)
		fig.set_meta("spec", spec)
		if not key.begins_with("v"):
			fig.scale = Vector3.ONE * FIGURE_SCALE
		_figure_root.add_child(fig)
		_figures[key] = fig
	return fig


func _make_troop(type: String, tier: int, color: Color) -> Node3D:
	match type:
		"cavalry", "knight":
			return Figures.rider(type, tier, color)
		"chariot":
			return Figures.chariot(tier, color)
	return Figures.soldier(type, tier, color)


## Arrows in flight: each rises and falls along an arc from `from` to `to`.
func _fly_arrows(flights: Array) -> void:
	while _arrows.size() < flights.size():
		var a := Node3D.new()
		var shaft := MeshInstance3D.new()
		shaft.mesh = LowPoly.box(Vector3(0.008, 0.008, 0.11))
		shaft.material_override = LowPoly.material(Color("#3b2614"))
		a.add_child(shaft)
		var tip := MeshInstance3D.new()
		tip.mesh = LowPoly.box(Vector3(0.016, 0.016, 0.02))
		tip.material_override = LowPoly.material(Color("#d0d0d0"))
		tip.position.z = 0.06
		a.add_child(tip)
		for mi in [shaft, tip]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_figure_root.add_child(a)
		_arrows.append(a)
	for i in _arrows.size():
		var a := _arrows[i]
		a.visible = i < flights.size()
		if not a.visible:
			continue
		var fl: Array = flights[i]
		var from: Vector3 = fl[0]
		var to: Vector3 = fl[1]
		var t: float = fl[2]
		var lift := from.distance_to(to) * (0.3 if fl[3] else 0.2)
		var at := from.lerp(to, t) + Vector3(0, sin(PI * t) * lift, 0)
		var ahead := from.lerp(to, minf(t + 0.03, 1.0)) + Vector3(0, sin(PI * minf(t + 0.03, 1.0)) * lift, 0)
		a.position = at
		if ahead.distance_to(at) > 0.0001:
			a.look_at(ahead, Vector3.UP, true)


## Small health bars over the figures (red for the enemy, green for yours),
## then the map's buttons, labels and bars at their places in the 3D view.
func _draw_bars() -> void:
	if not view.in_3d:
		return  # not laid out yet
	_draw_unit_bars()
	view.draw_overlay(_overlay, map_to_screen)


func _draw_unit_bars() -> void:
	for b in _bars:
		var at: Vector2 = b[0]
		var frac := clampf(b[1] / maxf(b[2], 1.0), 0.0, 1.0)
		var w := 28.0
		var r := Rect2(at - Vector2(w / 2.0, 3.0), Vector2(w, 5.0))
		_overlay.draw_rect(r.grow(1.0), Color("#2b1d10"))
		_overlay.draw_rect(Rect2(r.position, Vector2(w * frac, r.size.y)), Color("#44bd32") if b[3] == Battlefield.PLAYER else Color("#e84118"))


## The map pixel of the front-most building whose outline on screen holds
## `local`, or Vector2.INF. Huts and campfires are too small to need it.
func _building_under(local: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_y := -INF
	for slot in _buildings:
		if slot.begins_with("hut") or slot.begins_with("fire") or slot.begins_with("olive"):
			continue
		var model: Node3D = _buildings[slot]
		var box: AABB = model.get_meta("box")
		var shown := Rect2(camera.unproject_position(model.global_transform * box.position), Vector2.ZERO)
		for i in 8:
			shown = shown.expand(camera.unproject_position(model.global_transform * box.get_endpoint(i)))
		var foot := camera.unproject_position(model.global_position)
		if shown.has_point(local) and foot.y > best_y:
			best_y = foot.y
			best = model.get_meta("spec")[1]
	return best


## The bounds of a model's parts, in its own space.
static func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb() if model.is_inside_tree() else mi.transform * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Windmill sails and water wheels turn; campfires flicker.
func _animate(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for n in get_tree().get_nodes_in_group("spin"):
		if n.is_inside_tree() and n.get_viewport() == _world_vp:
			n.rotation.z += delta * 1.5
	for slot in _buildings:
		if slot.begins_with("fire"):
			var flame: Node3D = _buildings[slot].get_node_or_null("Flame")
			if flame:
				var f := 1.0 + sin(now * 9.0) * 0.15 + sin(now * 13.7) * 0.1
				flame.scale = Vector3(1.0, f, 1.0)


## Step quality down while the game runs slowly (checked every 4 seconds).
func _watch_speed(delta: float) -> void:
	if _quality >= 3 or _map_size == Vector2.ZERO:
		return
	_timed += delta
	if delta > 1.0 / MIN_FPS:
		_slow_frames += delta
	if _timed < 4.0:
		return
	if _slow_frames > _timed * 0.5:
		_quality += 1
		match _quality:
			1:
				_supersample = 1.0
				_map_vp.size = Vector2i(_map_size * _supersample)
			2:
				_world_vp.msaa_3d = Viewport.MSAA_DISABLED
			3:
				# Cheaper shadows, not none: without them this renderer
				# lights the whole scene noticeably darker.
				_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				RenderingServer.directional_shadow_atlas_set_size(1024, true)
	_timed = 0.0
	_slow_frames = 0.0


func _build_world() -> void:
	var root := Node3D.new()
	_root = root
	_world_vp.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2c3e22")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#fff4e0")
	e.ambient_light_energy = 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	_env = e
	root.add_child(env)
	# Late-afternoon sun from the front left: lit fronts, shadows falling to
	# the right where they show.
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_color = Color("#fff1d6")
	sun.light_energy = 0.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-42, -60, 0)
	root.add_child(sun)
	# Grass reaching past the map's edges, so the tilted view has no void.
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	field.mesh = plane
	field.position.y = -0.01
	var grass := StandardMaterial3D.new()
	grass.albedo_color = BattleView.GRASS
	grass.roughness = 1.0
	field.material_override = grass
	root.add_child(field)
	# The map itself.
	_ground = MeshInstance3D.new()
	_ground.mesh = PlaneMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _map_vp.get_texture()
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_ground.material_override = mat
	root.add_child(_ground)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.1
	camera.far = 200.0
	root.add_child(camera)


## Lay out the map at this view's size and frame it with the camera.
func _fit() -> void:
	_fitted_for = size
	_map_size = Vector2(size.x, size.y * _stretch())
	# Lanes 10% shorter than the tall map would make them: the room goes to
	# the villages at both ends.
	var villages := 2.0 * BattleView.TOWER_DEPTH
	view.depth_scale = (_map_size.y - LANE_SHARE * (_map_size.y - villages)) / villages
	view.size = _map_size
	view.visible = true
	view.in_3d = true
	_map_vp.size_2d_override = Vector2i(_map_size)
	_map_vp.size = Vector2i(_map_size * _supersample)
	if _grass_vp == null:
		_grass_vp = SubViewport.new()
		_grass_vp.size_2d_override_stretch = true
		_grass_painter = Control.new()
		_grass_painter.draw.connect(func(): view.paint_ground(_grass_painter))
		_grass_vp.add_child(_grass_painter)
		_world_vp.add_child(_grass_vp)
	_grass_painter.size = _map_size
	_grass_vp.size_2d_override = Vector2i(_map_size)
	_grass_vp.size = Vector2i(_map_size * MAP_SUPERSAMPLE)
	_grass_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_grass_painter.queue_redraw()
	view.ground_texture = _grass_vp.get_texture()
	var plane: PlaneMesh = _ground.mesh
	plane.size = _map_size * PX
	_home = _framing()
	_apply_camera()
	_build_scenery()


## How much taller than the view the map is laid out, so that seen tilted it
## fills the view's height as well as its width (longer lanes, no empty
## bands). Only the look changes: the game measures lanes from end to end.
func _stretch() -> float:
	var lo := 1.0
	var hi := 3.0
	for i in 16:
		var k := (lo + hi) / 2.0
		_map_size = Vector2(size.x, size.y * k)
		camera.transform = _framing()
		# Still as wide as the view: height is not what limits it yet.
		var half := _map_size * PX / 2.0
		if camera.unproject_position(Vector3(-half.x, 0, half.y)).x <= FIT_MARGIN:
			lo = k
		else:
			hi = k
	return lo


## The forests' trees on the map, and woods and rocks all around it.
func _build_scenery() -> void:
	if _scenery:
		_scenery.queue_free()
	_scenery = Node3D.new()
	_root.add_child(_scenery)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var trees: Array[Vector3] = []
	for team in 2:
		for i in BattleView.TREE_COLS * BattleView.TREE_ROWS:
			trees.append(map_to_world(view.work_spot(team, "wood", i)))
	_scenery.add_child(LowPoly.forest(trees, rng))
	# Around the battlefield: a ring of mixed woods, thicker further out.
	var half := _map_size * PX / 2.0
	var leafy: Array[Vector3] = []
	var pines: Array[Vector3] = []
	var stones: Array[Vector3] = []
	var keep_out := Rect2(-half - Vector2(0.12, 0.12), half * 2.0 + Vector2(0.24, 0.24))
	var tries := 0
	while leafy.size() + pines.size() < 420 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(-half.x - 4.0, half.x + 4.0), rng.randf_range(-half.y - 4.0, half.y + 3.0))
		if keep_out.has_point(p):
			continue
		# Sparse near the map, dense further out.
		var gap := maxf(maxf(absf(p.x) - half.x, absf(p.y) - half.y), 0.0)
		var chance := clampf(0.25 + gap * 0.5, 0.0, 1.0)
		if p.y > half.y:
			chance *= 0.25  # nearest the camera: few, so they don't hide the village
		if rng.randf() > chance:
			continue
		(pines if rng.randf() < 0.35 else leafy).append(Vector3(p.x, 0, p.y))
		if rng.randf() < 0.08:
			stones.append(Vector3(p.x + 0.15, 0, p.y + 0.1))
	_scenery.add_child(LowPoly.forest(leafy, rng))
	_scenery.add_child(LowPoly.forest(pines, rng, true))
	_scenery.add_child(LowPoly.rocks(stones, rng))


## The camera that shows the whole map as large as the view allows, centered.
func _framing() -> Transform3D:
	var half := _map_size * PX / 2.0
	var corners := [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y)]
	var back := Vector3(0, sin(deg_to_rad(PITCH)), cos(deg_to_rad(PITCH)))
	var target := Vector3.ZERO
	var t := Transform3D.IDENTITY
	for pass_i in 4:
		# Nearest distance at which all four corners are on screen...
		var lo := 1.0
		var hi := 200.0
		for i in 40:
			var d := (lo + hi) / 2.0
			camera.transform = Transform3D(Basis.IDENTITY, target + back * d).looking_at(target, Vector3.UP)
			if corners.all(func(c): return _on_screen(c)):
				hi = d
			else:
				lo = d
		t = Transform3D(Basis.IDENTITY, target + back * hi).looking_at(target, Vector3.UP)
		camera.transform = t
		# ...then slide along the map so the top and bottom margins match.
		var top: float = minf(camera.unproject_position(corners[0]).y, camera.unproject_position(corners[1]).y)
		var bottom: float = maxf(camera.unproject_position(corners[2]).y, camera.unproject_position(corners[3]).y)
		var off := (top - (size.y - bottom)) / 2.0
		target.z += off / size.y * half.y * 1.6
	return t


func _on_screen(p: Vector3) -> bool:
	if camera.is_position_behind(p):
		return false
	var s := camera.unproject_position(p)
	return s.x >= -0.5 and s.y >= -0.5 and s.x <= size.x + 0.5 and s.y <= size.y + 0.5


func _apply_camera() -> void:
	var t := _home
	var look := t.origin + -t.basis.z * (t.origin.y / -(-t.basis.z).y)
	var origin := look + (t.origin - look) / _zoom + _pan
	camera.transform = Transform3D(t.basis, origin)


# --- Map pixels <-> 3D and the screen --------------------------------------

## The 3D point on the ground at a map pixel.
func map_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - _map_size.x / 2.0) * PX, 0.0, (p.y - _map_size.y / 2.0) * PX)


func world_to_map(w: Vector3) -> Vector2:
	return Vector2(w.x / PX + _map_size.x / 2.0, w.z / PX + _map_size.y / 2.0)


## Where a map pixel shows in this view (local coordinates).
func map_to_screen(p: Vector2) -> Vector2:
	return camera.unproject_position(map_to_world(p))


## The map pixel under a point of this view (local coordinates), or
## Vector2.INF when it is not on the ground.
func screen_to_map(local: Vector2) -> Vector2:
	var from := camera.project_ray_origin(local)
	var dir := camera.project_ray_normal(local)
	if dir.y >= 0.0:
		return Vector2.INF
	var hit := from + dir * (-from.y / dir.y)
	return world_to_map(hit)


## Global screen point -> map pixel (for card drags and drops).
func global_to_map(global: Vector2) -> Vector2:
	return screen_to_map(global - global_position)


# --- Input: taps go to the map; zoom and pan for testing ---------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_from = (pts[0] as Vector2).distance_to(pts[1])
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch_from > 0.0:
			var pts: Array = _touches.values()
			var now_d := (pts[0] as Vector2).distance_to(pts[1])
			_set_zoom(_zoom * now_d / _pinch_from)
			_pinch_from = now_d
			_dragged = true
		return
	if event is InputEventMagnifyGesture:
		_set_zoom(_zoom * event.factor)
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_set_zoom(_zoom * 1.1)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_set_zoom(_zoom / 1.1)
				return
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press_at = event.position
					_dragged = false
					_forward(event)  # BattleView acts on the press, as before
				else:
					_press_at = Vector2.INF
					if not _dragged:
						var now := Time.get_ticks_msec()
						if now - _last_tap_ms < 300 and _zoom != 1.0:
							_reset_camera()
						_last_tap_ms = now
					_forward(event)
		return
	if event is InputEventMouseMotion and _press_at != Vector2.INF and _touches.size() < 2:
		if _zoom > 1.0 and (_dragged or event.position.distance_to(_press_at) > 12.0):
			_dragged = true
			_pan_by(event.relative)


## Hand a mouse button event to the map, at the map pixel under it; a tap
## anywhere on a building (its roof stands up above the ground behind it)
## counts as a tap at its foot.
func _forward(event: InputEventMouseButton) -> void:
	var at := _building_under(event.position)
	if at == Vector2.INF:
		at = screen_to_map(event.position)
	if at == Vector2.INF:
		return
	var ev: InputEventMouseButton = event.duplicate()
	ev.position = at
	ev.global_position = at
	view._gui_input(ev)


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 1.0, 4.0)
	if is_equal_approx(_zoom, 1.0):
		_pan = Vector3.ZERO
	_apply_camera()


## Move the camera so the ground under the finger follows it.
func _pan_by(screen_delta: Vector2) -> void:
	var mid := size / 2.0
	var a := screen_to_map(mid)
	var b := screen_to_map(mid - screen_delta)
	if a == Vector2.INF or b == Vector2.INF:
		return
	_pan += map_to_world(b) - map_to_world(a)
	var half := _map_size * PX / 2.0
	_pan.x = clampf(_pan.x, -half.x, half.x)
	_pan.z = clampf(_pan.z, -half.y, half.y)
	_apply_camera()


func _reset_camera() -> void:
	_zoom = 1.0
	_pan = Vector3.ZERO
	_apply_camera()
