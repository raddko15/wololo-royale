class_name BattleView
extends Control
## Draws the whole portrait battlefield and turns taps into game actions.
## Both cities share one layout: the player's at the bottom, the enemy's
## mirrored at the top, with 3 lanes between the tower lines.

## A hut was tapped: build another one.
signal hut_tapped
## A gold upgrade badge was tapped: buy that upgrade ("era": next era).
signal upgrade_badge_tapped(id: String)
## A building of the player's was tapped: "town_center", "mill", "lumber_camp",
## "towers", "gold_mine", "stone_mine", "barracks", "archery_range" or "stables".
signal building_tapped(kind: String, at: Vector2)

const LANE_X := [0.18, 0.5, 0.82]
const VILLAGER_R := 9.0
const FIGHTER_R := 11.0
const FARM_COLS := 4
const FARM_ROWS := 2
const TREE_COLS := 4
const TREE_ROWS := 2
const LANE_W := 0.07
## Distance (px) from a fort's center to where a road meets it.
const FORT_SIDE := 100.0
const FORT_FRONT := 55.0
const COLORS := {
	"grass": Color("#3b6e3b"), "lane": Color("#8a7a5c"), "farm": Color("#c8a951"),
	"crop": Color("#e8d27a"), "crop_stem": Color("#7a8f3a"), "trunk": Color("#5b3a1e"),
	"leaf_dark": Color("#1e4d2b"), "leaf_light": Color("#2f7a3f"), "villager": Color("#f5f6fa"),
	"stone": Color("#a5a5a0"), "wood": Color("#8b5a2b"), "stick": Color("#4a3520"),
	"marble": Color("#ecebe4"), "marble_shade": Color("#c9c4b8"), "terracotta": Color("#c8553d"),
	"olive": Color("#6b7f3a"), "olive_leaf": Color("#8a9a5b"), "plaster": Color("#f2ead8"),
}

var economy: Economy
var enemy_economy: Economy
## Loaded art textures by name (res://assets/art/<name>.svg).
var _art := {}
var battle: Battlefield
## Card being dragged ("" when none) and where the finger is, in local coordinates.
var drag_card := ""
var drag_pos := Vector2.ZERO
## Lanes some AUTO unit is being sent down; each is marked with moving chevrons.
var active_lanes := [false, false, false]


func _process(_delta: float) -> void:
	queue_redraw()


# --- Layout -------------------------------------------------------------
# Cities have a fixed depth measured in pixels from their own back edge (the
# bottom for the player, the top for the enemy); the lanes get all the height
# in between, so taller phones get longer lanes. x stays a fraction of width.
# Fort and roads sit right behind the towers; fields, mill, lumber camp and
# huts are in the back strip where fighters never walk.

const TOWER_DEPTH := 300.0
const FORT_DEPTH := 180.0

## Point at width fraction x and `depth` px in front of `team`'s back edge.
func _cp(team: int, x: float, depth: float) -> Vector2:
	return Vector2(x * size.x, size.y - depth if team == Battlefield.PLAYER else depth)


## Rect spanning width fractions x..x+w and depths far..near from the back edge.
func _crect(team: int, x: float, w: float, near: float, far: float) -> Rect2:
	var top := size.y - near if team == Battlefield.PLAYER else far
	return Rect2(Vector2(x * size.x, top), Vector2(w * size.x, near - far))


func tower_line(team: int) -> float:
	return _cp(team, 0, TOWER_DEPTH).y


func econ(team: int) -> Economy:
	return economy if team == Battlefield.PLAYER else enemy_economy


func farm_rect(team := Battlefield.PLAYER) -> Rect2:
	return _crect(team, 0.015, 0.20, 125, 5)


func forest_rect(team := Battlefield.PLAYER) -> Rect2:
	return _crect(team, 0.785, 0.20, 125, 5)


## Military buildings: barracks beside the left tower, archery range and
## stables on the grass between the roads.
func military_pos(team: int, id: String) -> Vector2:
	match id:
		"barracks":
			return _cp(team, 0.075, TOWER_DEPTH)
		"archery_range":
			return _cp(team, 0.34, 232)
	return _cp(team, 0.66, 232)


## Gold / stone mine: small, on the grass between the lane towers.
func mine_pos(team: int, res: String) -> Vector2:
	return _cp(team, 0.34 if res == "gold" else 0.66, TOWER_DEPTH)


## Drop-off for a job: the mill (food), lumber camp (wood), or the town center (mined).
func drop_off(team: int, job: String) -> Vector2:
	match job:
		"food":
			return _cp(team, 0.28, 100)
		"wood":
			return _cp(team, 0.72, 100)
	return town_center(team)


## Center of crop plot / tree number `spot` (wraps around when there are more workers).
func work_spot(team: int, job: String, spot: int) -> Vector2:
	if job in Economy.MINED:
		# Miners stand around the mine, filling a ring then a wider one.
		return mine_pos(team, job) + Vector2.from_angle(PI / 2 + spot * 0.8) * (26 + (spot / 8) * 14)
	var area := farm_rect(team) if job == "food" else forest_rect(team)
	var cols := FARM_COLS if job == "food" else TREE_COLS
	var rows := FARM_ROWS if job == "food" else TREE_ROWS
	var i := spot % (cols * rows)
	var cell := area.size / Vector2(cols, rows)
	var p := area.position + cell * Vector2(i % cols + 0.5, i / cols + 0.5)
	# Extra workers on the same plot/tree stand a little to the side.
	return p + Vector2((spot / (cols * rows)) * 8, 0)


## Where a worker is drawn: at its plot/tree, or walking to/from the drop-off.
func worker_pos(team: int, w: Dictionary) -> Vector2:
	var spot := work_spot(team, w.job, w.spot)
	if w.job == "wood":
		spot += Vector2(-14, 8)  # stand beside the tree, not inside it
	match w.phase:
		"to_drop":
			return spot.lerp(drop_off(team, w.job), w.t)
		"to_work":
			return drop_off(team, w.job).lerp(spot, w.t)
	return spot


## The "send a worker back to the town center" icon, in the outer corner
## beside the road (player only).
func unassign_icon(job: String) -> Vector2:
	return _cp(Battlefield.PLAYER, 0.06 if job == "food" else 0.94, 200)


func town_center(team := Battlefield.PLAYER) -> Vector2:
	return _cp(team, 0.5, FORT_DEPTH)


## +1 when "toward the back edge" is down the screen (player), -1 for the enemy.
func _back(team: int) -> float:
	return 1.0 if team == Battlefield.PLAYER else -1.0


func idle_area(team := Battlefield.PLAYER) -> Rect2:
	return _crect(team, 0.38, 0.24, 108, 78)


## Huts fill rows behind the town center, from the fort outward.
func hut_pos(team: int, i: int) -> Vector2:
	# 13 columns x 3 rows: room for every hut up to the 200 population cap.
	var area := _crect(team, 0.33, 0.345, 70, 3)
	var step := 19.0
	var cols := int(area.size.x / step)
	var row := i / cols
	if team == Battlefield.ENEMY:
		row = -row  # enemy rows grow toward the top edge
		area.position.y = area.end.y - step
	return area.position + Vector2(step / 2 + (i % cols) * step, step / 2 + row * step)


## Lane under a point on the battlefield, or -1 outside the lanes.
func lane_at(pos: Vector2) -> int:
	if pos.y < tower_line(Battlefield.ENEMY) - 30 or pos.y > tower_line(Battlefield.PLAYER) + 40:
		return -1
	return clampi(int(pos.x / size.x * Battlefield.LANES), 0, Battlefield.LANES - 1)


## Work area under a point: "food", "wood", a built mine, or "".
func job_at(pos: Vector2) -> String:
	if farm_rect().has_point(pos):
		return "food"
	if forest_rect().has_point(pos):
		return "wood"
	for res in Economy.MINED:
		if economy.mines.has(res) and pos.distance_to(mine_pos(Battlefield.PLAYER, res)) < 36:
			return res
	return ""


func building_pos(team: int, kind: String, lane: int) -> Vector2:
	if kind == "main":
		return town_center(team)
	return Vector2(LANE_X[lane] * size.x, tower_line(team))


## Road from `team`'s lane tower to its fort: straight on for the middle
## lane, an L (up/down to the fort's row, then sideways) for outer lanes.
func road(team: int, lane: int) -> PackedVector2Array:
	var tower := building_pos(team, "tower", lane)
	var tc := town_center(team)
	if lane == 1:
		return PackedVector2Array([tower, tc - Vector2(0, FORT_FRONT * _back(team))])
	var side := -1.0 if lane == 0 else 1.0
	return PackedVector2Array([tower, Vector2(tower.x, tc.y), tc + Vector2(side * FORT_SIDE, 0)])


## Point `frac` (0..1) of the way along a polyline.
func _along(points: PackedVector2Array, frac: float) -> Vector2:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var left := clampf(frac, 0.0, 1.0) * total
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if left <= seg:
			return points[i].lerp(points[i + 1], left / seg)
		left -= seg
	return points[-1]


## Where a unit stands: on its lane between the tower lines, or past the
## enemy tower on the road to the enemy fort.
func _unit_lane_pos(u: Dictionary) -> Vector2:
	return _lane_pos_at(u.lane, u.y, u.side)


## Screen point for lane coordinate `y` (beyond 1: on the enemy's road, below
## 0: on the player's road), with sideways spread `side` on the lane itself.
func _lane_pos_at(lane: int, y: float, side: float) -> Vector2:
	if y > 1.0:
		return _along(road(Battlefield.ENEMY, lane), (y - 1.0) / Battlefield.MAIN_DIST[lane])
	if y < 0.0:
		return _along(road(Battlefield.PLAYER, lane), -y / Battlefield.MAIN_DIST[lane])
	var sy := lerpf(tower_line(Battlefield.PLAYER), tower_line(Battlefield.ENEMY), y)
	# Sideways spread fades out near both tower lines, where the roads (which
	# have no spread) join, so units don't snap sideways there.
	var fade := smoothstep(0.0, 0.08, minf(y, 1.0 - y))
	return Vector2(LANE_X[lane] * size.x + side * size.x * 0.025 * fade, sy)


## Direction a unit faces on screen: toward its target while fighting,
## otherwise along its path (so it turns at the road corners). Smoothed.
func _heading(u: Dictionary, target: Vector2) -> float:
	var want: float
	if target != Vector2.INF:
		want = (target - _unit_lane_pos(u)).angle()
	else:
		var ahead := 0.02 if u.team == Battlefield.PLAYER else -0.02
		want = (_lane_pos_at(u.lane, u.y + ahead, u.side) - _lane_pos_at(u.lane, u.y, u.side)).angle()
	var h: float = lerp_angle(u.get("view_heading", want), want, 0.2)
	u["view_heading"] = h
	return h


## Screen positions for all units. Walkers spread sideways in their lane;
## units hitting the same building fan out in an arc on the side they came from.
func unit_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	result.resize(battle.units.size())
	var groups := {}
	for i in battle.units.size():
		var u: Dictionary = battle.units[i]
		if u.target == "tower" or u.target == "main":
			var key := "%d:%s:%d" % [u.team, u.target, u.lane]
			groups[key] = groups.get(key, []) + [i]
		else:
			result[i] = _unit_lane_pos(u)
	for key in groups:
		var idxs: Array = groups[key]
		var u: Dictionary = battle.units[idxs[0]]
		var center: Vector2
		var front: float
		var radius := 48.0
		if u.target == "tower":
			center = building_pos(1 - u.team, "tower", u.lane)
			# Player units attack from below (90°), enemy units from above.
			front = PI / 2 if u.team == Battlefield.PLAYER else -PI / 2
		else:
			# Fan out at the end of the road, facing the way they came.
			var path := road(1 - u.team, u.lane)
			center = path[-1]
			front = (path[-2] - path[-1]).angle()
			radius = 26.0
		var per_ring := 7
		var spread := deg_to_rad(150.0)
		for n in idxs.size():
			var ring := n / per_ring
			var in_ring := mini(per_ring, idxs.size() - ring * per_ring)
			var a := front if in_ring == 1 else front - spread / 2 + spread * (n % per_ring) / (in_ring - 1)
			result[idxs[n]] = center + Vector2.from_angle(a) * (radius + ring * 30)
	# Glide toward the spot instead of jumping (e.g. into or out of an attack
	# formation): move at most a few pixels per frame.
	for n in result.size():
		var u: Dictionary = battle.units[n]
		var prev: Vector2 = u.get("view_pos", result[n])
		u["view_pos"] = prev.move_toward(result[n], clampf(prev.distance_to(result[n]) * 0.15, 3.0, 6.0))
		result[n] = u["view_pos"]
	return result


## Dot positions for `count` villagers laid out in centered rows inside `area`.
func villager_spots(count: int, area: Rect2) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var step := VILLAGER_R * 2.6
	var cols := maxi(1, int((area.size.x - 8) / step))
	for i in count:
		var in_row := mini(cols, count - (i / cols) * cols)
		var left := area.get_center().x - (in_row - 1) * step / 2
		spots.append(Vector2(left + (i % cols) * step, area.position.y + VILLAGER_R + 6 + (i / cols) * step))
	return spots


# --- Input --------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = event.position
	# Badges sit on top of buildings, so they win the tap (generous finger radius).
	for b in upgrade_badges(economy):
		if pos.distance_to(b[0]) < 24:
			upgrade_badge_tapped.emit(b[1])
			return
	for job in ["food", "wood"]:
		if pos.distance_to(unassign_icon(job)) < 34:
			economy.reassign(job, "idle")
			return
	for res in Economy.MINED:
		if economy.mines.has(res) and pos.distance_to(mine_pos(Battlefield.PLAYER, res)) < 36:
			building_tapped.emit(res + "_mine", mine_pos(Battlefield.PLAYER, res))
			return
	for id in economy.military:
		if pos.distance_to(military_pos(Battlefield.PLAYER, id)) < 36:
			building_tapped.emit(id, military_pos(Battlefield.PLAYER, id))
			return
	var job := job_at(pos)
	if job != "":
		# Tapping a working villager sends it back to idle; tapping the area sends an idle one in.
		for w in economy.workers:
			if w.job == job and worker_pos(Battlefield.PLAYER, w).distance_to(pos) < VILLAGER_R * 2.2:
				economy.reassign(job, "idle")
				return
		economy.reassign("idle", job)
		return
	if pos.distance_to(town_center()) < size.x * 0.12:
		building_tapped.emit("town_center", town_center())
		return
	for i in economy.huts:
		if pos.distance_to(hut_pos(Battlefield.PLAYER, i) + Vector2(0, -3)) < 14:
			hut_tapped.emit()
			return
	for res in ["food", "wood"]:
		if pos.distance_to(drop_off(Battlefield.PLAYER, res)) < 40:
			building_tapped.emit("mill" if res == "food" else "lumber_camp", drop_off(Battlefield.PLAYER, res))
			return
	if battle.towers_built[Battlefield.PLAYER]:
		for lane in Battlefield.LANES:
			var t := building_pos(Battlefield.PLAYER, "tower", lane)
			if pos.distance_to(t) < 40:
				building_tapped.emit("towers", t)
				return


# --- Drawing ------------------------------------------------------------

const GRASS := Color("#4f8a3c")
const ROAD := Color("#b8a074")
const ROAD_EDGE := Color("#8a7552")
## Scattered grass detail, generated once per screen size so it never flickers.
var _ground_size := Vector2.ZERO
var _ground_bits := {}


func _draw_ground() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GRASS)
	if _ground_size != size:
		_ground_size = size
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var patches := []
		for i in 90:
			patches.append([Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(14, 46), rng.randf() < 0.5])
		var tufts := []
		for i in 320:
			tufts.append(Vector2(rng.randf() * size.x, rng.randf() * size.y))
		var flowers := []
		for i in 45:
			flowers.append([Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randi() % 3])
		_ground_bits = {"patches": patches, "tufts": tufts, "flowers": flowers}
	for pt in _ground_bits.patches:  # soft light and dark patches
		draw_circle(pt[0], pt[1], Color(1, 1, 0.8, 0.035) if pt[2] else Color(0, 0.1, 0, 0.04))
	for t in _ground_bits.tufts:  # little grass blades
		draw_line(t, t + Vector2(-2, -5), Color("#3d7230"), 1.4)
		draw_line(t, t + Vector2(2, -5), Color("#6aa84f"), 1.4)
	for f in _ground_bits.flowers:
		draw_circle(f[0], 2.0, [Color("#f5f6fa"), Color("#f9ca24"), Color("#e8a0c8")][f[1]])


## Dirt lanes and L roads: a darker edge under a lighter fill, then pebbles.
func _draw_roads(lane_fill: Array[Color]) -> void:
	var w := size.x * LANE_W
	var top := tower_line(Battlefield.ENEMY)
	var lane_rects := []
	for lane in Battlefield.LANES:
		lane_rects.append(Rect2(LANE_X[lane] * size.x - w / 2, top, w, tower_line(Battlefield.PLAYER) - top))
	var paths := []
	for team in [Battlefield.ENEMY, Battlefield.PLAYER]:
		for lane in Battlefield.LANES:
			paths.append(road(team, lane))
	for pass_i in 2:
		var edge := pass_i == 0
		var grow := 3.0 if edge else 0.0
		for path in paths:
			draw_polyline(path, ROAD_EDGE if edge else ROAD, w + grow * 2)
			for corner in path:  # square joints
				draw_rect(Rect2(corner - Vector2.ONE * (w / 2 + grow), Vector2.ONE * (w + grow * 2)), ROAD_EDGE if edge else ROAD)
		for lane in Battlefield.LANES:
			draw_rect(lane_rects[lane].grow_individual(grow, 0, grow, 0), ROAD_EDGE if edge else lane_fill[lane])
	# Pebbles and wheel ruts along the lanes.
	for lane in Battlefield.LANES:
		var r: Rect2 = lane_rects[lane]
		var y := r.position.y + 14.0
		var k := 0
		while y < r.end.y:
			var x := r.position.x + r.size.x * (0.25 + 0.5 * float((k * 37) % 7) / 6.0)
			draw_circle(Vector2(x, y), 1.8, ROAD_EDGE)
			y += 23.0
			k += 1
		draw_line(Vector2(r.position.x + w * 0.3, r.position.y), Vector2(r.position.x + w * 0.3, r.end.y), Color(0, 0, 0, 0.06), 2)
		draw_line(Vector2(r.position.x + w * 0.7, r.position.y), Vector2(r.position.x + w * 0.7, r.end.y), Color(0, 0, 0, 0.06), 2)


func _tex(name: String) -> Texture2D:
	if not _art.has(name):
		var path := "res://assets/art/%s.svg" % name
		_art[name] = load(path) if ResourceLoader.exists(path) else null
	return _art[name]


## Draws an art asset centered on `center` at `size`; its `_tint` layer (if
## any) is drawn on top in `tint` (the civ color).
func _draw_art(name: String, center: Vector2, size_px: Vector2, tint := Color.WHITE) -> void:
	var rect := Rect2(center - size_px / 2, size_px)
	var base := _tex(name)
	if base:
		draw_texture_rect(base, rect, false)
	var t := _tex(name + "_tint")
	if t:
		draw_texture_rect(t, rect, false, tint)

func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_draw_ground()
	var unit_drag: bool = GameConfig.data().units.has(drag_card)
	var hover_lane := lane_at(drag_pos) if unit_drag else -1
	var lane_fill: Array[Color] = []
	for lane in Battlefield.LANES:
		var c: Color = ROAD
		if unit_drag:
			c = Color("#f9ca24") if lane == hover_lane else ROAD.lightened(0.2)
		lane_fill.append(c)
	_draw_roads(lane_fill)
	# Chevrons moving up every active lane.
	var top := tower_line(Battlefield.ENEMY) + 40
	var bottom := tower_line(Battlefield.PLAYER) - 40
	var shift := fmod(Time.get_ticks_msec() / 1000.0 * 30.0, 90.0)
	for lane in Battlefield.LANES:
		if not active_lanes[lane]:
			continue
		var lx: float = LANE_X[lane] * size.x
		var y := bottom - shift
		while y > top:
			draw_polyline(PackedVector2Array([Vector2(lx - 10, y + 6), Vector2(lx, y - 3), Vector2(lx + 10, y + 6)]), Color(1, 1, 1, 0.13), 3)
			y -= 90

	for team in [Battlefield.ENEMY, Battlefield.PLAYER]:
		_draw_city(team, now)

	if drag_card == "villager":
		var hover := job_at(drag_pos)
		for job in ["food", "wood"]:
			var area := farm_rect() if job == "food" else forest_rect()
			draw_rect(area.grow(4), Color("#f9ca24") if hover == job else Color(1, 1, 1, 0.5), false, 4)
		for res in economy.mines:
			draw_arc(mine_pos(Battlefield.PLAYER, res), 34, 0, TAU, 32, Color("#f9ca24") if hover == res else Color(1, 1, 1, 0.5), 4)
	for job in ["food", "wood"]:
		_draw_unassign_icon(unassign_icon(job), economy.villagers.get(job, 0) > 0)

	var positions := unit_positions()
	for i in battle.units.size():
		var u: Dictionary = battle.units[i]
		var color := Color(econ(u.team).civ().color)
		match u.type:
			"archer":
				_draw_archer(u, positions[i], color, now, _target_pos(u, positions))
			"cavalry":
				_draw_cavalry(u, positions[i], color, now, _target_pos(u, positions))
			_:
				_draw_fighter(u, positions[i], color, now)
	for a in battle.arrows:
		var idx := battle.units.find(a.target)
		if idx != -1:
			_draw_arrow(a, positions[idx])


## Everything one side owns: farm, forest, mill, lumber camp, fort, huts,
## villagers and lane towers. Identical for both sides.
func _draw_city(team: int, now: float) -> void:
	var e := econ(team)
	var color := Color(e.civ().color)
	var style := e.style()
	# Romans and Greeks grow olives from the start; the press comes with the upgrade.
	var olives := style == "classical"
	if olives:
		_draw_olive_grove(farm_rect(team))
	else:
		_draw_farm(farm_rect(team))
	for i in TREE_COLS * TREE_ROWS:
		_draw_tree(work_spot(team, "wood", i))
	# A granary hut and a lean-to until the player buys the windmill / lumber camp upgrades.
	# Food and wood buildings: Era I hut, then the Era II and Era III upgrades.
	var food_at := drop_off(team, "food")
	if e.upgrades.has("mill2"):
		if olives: _draw_oil_workshop(food_at)
		else: _draw_grand_mill(food_at, now)
	elif e.upgrades.has("mill"):
		if olives: _draw_olive_press(food_at)
		else: _draw_mill(food_at, now, 1.5)
	else:
		_draw_granary(food_at)
	var wood_at := drop_off(team, "wood")
	if e.upgrades.has("lumber_camp2"):
		if style == "classical": _draw_carpentry(wood_at)
		else: _draw_sawmill(wood_at, now)
	elif e.upgrades.has("lumber_camp"):
		if style == "classical": _draw_timber_yard(wood_at)
		else: _draw_lumber_camp(wood_at, 1.5)
	else:
		_draw_lean_to(wood_at)
	for res in e.mines:
		_draw_mine(mine_pos(team, res), res, e.upgrades.has(res + "_mine2"))
	for id in e.military:
		_draw_military(id, military_pos(team, id), color, e.era_index, style, int(e.upgrades.has(id + "1")) + int(e.upgrades.has(id + "2")))
		if team == Battlefield.PLAYER and not e.has_room():
			_draw_pop_full(military_pos(team, id) + Vector2(0, -52), now)
	var tc := town_center(team)
	_draw_fort(tc, color, e.era_index, style)
	# Health bar on the fort's back side: under the player's gate, above the enemy's flag.
	var bar_y := 50.0 if team == Battlefield.PLAYER else -95.0
	_draw_hp(tc + Vector2(0, bar_y), battle.buildings[team].main, battle.max_hp("main"), 110)
	for i in e.huts:
		_draw_hut(hut_pos(team, i), e.era_index, style)
	for w in e.workers:
		_draw_worker(worker_pos(team, w), w, now, olives)
	for p in villager_spots(e.villagers.get("idle", 0), idle_area(team)):
		_draw_figure(p + Vector2(0, 6), VILLAGER_TUNIC, [], 0.6)
	# Towers last so their health bars stay visible over the fields.
	if battle.towers_built[team]:
		for lane in Battlefield.LANES:
			_draw_tower(building_pos(team, "tower", lane), color, battle.buildings[team].towers[lane], e.upgrades.has("stone_towers"), style, battle.tower_max_hp[team])
	_draw_jobs(team, e, now)
	if team == Battlefield.PLAYER:
		_draw_upgrade_badges(e, now)


## Gold arrow badges: one over every building with an upgrade the player can
## buy right now, as [position, upgrade id] ("era" for the town center).
func upgrade_badges(e: Economy) -> Array:
	var spots := []
	if e.can_advance():
		spots.append([town_center() + Vector2(70, -60), "era"])
	var food_next := "mill2" if e.upgrades.has("mill") else "mill"
	if e.can_upgrade(food_next):
		spots.append([drop_off(Battlefield.PLAYER, "food") + Vector2(24, -40), food_next])
	var wood_next := "lumber_camp2" if e.upgrades.has("lumber_camp") else "lumber_camp"
	if e.can_upgrade(wood_next):
		spots.append([drop_off(Battlefield.PLAYER, "wood") + Vector2(24, -40), wood_next])
	for res in e.mines:
		if e.can_upgrade(res + "_mine2"):
			spots.append([mine_pos(Battlefield.PLAYER, res) + Vector2(22, -34), res + "_mine2"])
	if e.can_upgrade("stone_towers"):
		spots.append([building_pos(Battlefield.PLAYER, "tower", 1) + Vector2(30, -70), "stone_towers"])
	for id in e.military:
		var next: String = id + ("2" if e.upgrades.has(id + "1") else "1")
		if e.can_upgrade(next):
			# The barracks stands next to the left tower's health bar, so its badge goes left.
			spots.append([military_pos(Battlefield.PLAYER, id) + Vector2(-26 if id == "barracks" else 30, -36), next])
	return spots


func _draw_upgrade_badges(e: Economy, now: float) -> void:
	var spots := []
	for b in upgrade_badges(e):
		spots.append(b[0])
	var bob := sin(now * 4.0) * 3.0
	for p in spots:
		var c: Vector2 = p + Vector2(0, bob)
		draw_circle(c, 13, Color("#2b2620"))
		draw_arc(c, 13, 0, TAU, 20, Color("#f9ca24"), 2.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(-7, 0), c + Vector2(7, 0)]), Color("#f9ca24"))
		draw_rect(Rect2(c + Vector2(-3, 0), Vector2(6, 7)), Color("#f9ca24"))


## Everything under way: scaffolding with a hammering builder for buildings,
## upgrades and the era; a progress bar for villagers and units in training.
func _draw_jobs(team: int, e: Economy, now: float) -> void:
	var tc := town_center(team)
	var huts_seen := 0
	for job in e.jobs:
		if job.kind == "hut":
			if e.active_jobs().has(job):
				_draw_scaffold(hut_pos(team, e.huts + huts_seen), Vector2(18, 16), job.t / job.total, now, true)
			huts_seen += 1
	for job in e.active_jobs():
		var frac: float = job.t / job.total
		match job.kind:
			"villager":
				var bar_y := 64.0 if team == Battlefield.PLAYER else -108.0
				_draw_progress(tc + Vector2(0, bar_y), 110, frac, Color("#f9ca24"), _queue_label(e, job))
			"era":
				# The scaffolding carries the only bar; villagers queued behind show as "×n".
				_draw_scaffold(tc, Vector2(150, 96), frac, now, false, true, _queue_label(e, job))
			"mine":
				_draw_scaffold(mine_pos(team, job.id), Vector2(44, 32), frac, now, true)
			"military":
				_draw_scaffold(military_pos(team, job.id), Vector2(56, 40), frac, now, true)
			"towers":
				# One job for all three: only the middle site shows the bar.
				for lane in Battlefield.LANES:
					_draw_scaffold(building_pos(team, "tower", lane), Vector2(44, 56), frac, now, true, lane == 1)
			"upgrade":
				var sites := _upgrade_sites(team, job.id)
				for k in sites.size():
					_draw_scaffold(sites[k], Vector2(56, 48), frac, now, false, k == sites.size() / 2)
			"unit":
				var at := military_pos(team, GameConfig.data().units[job.id].requires) + Vector2(0, -44)
				_draw_progress(at, 60, frac, Color("#e67e22"), _queue_label(e, job))


func _upgrade_sites(team: int, id: String) -> Array[Vector2]:
	match Economy.upgrade_site(id):
		"mill":
			return [drop_off(team, "food")]
		"lumber_camp":
			return [drop_off(team, "wood")]
		"towers":
			var t: Array[Vector2] = []
			for lane in Battlefield.LANES:
				t.append(building_pos(team, "tower", lane))
			return t
	return [mine_pos(team, Economy.upgrade_site(id))]


## "×3" when more of the same are waiting in that queue.
func _queue_label(e: Economy, job: Dictionary) -> String:
	var n := e.queue_length(job.queue)
	return "×%d" % n if n > 1 else ""


## Red "POP FULL" sign that pulses above a building that can't train.
func _draw_pop_full(c: Vector2, now: float) -> void:
	var font := get_theme_default_font()
	var text := "POP FULL"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var pulse := 0.75 + 0.25 * sin(now * 5.0)
	var r := Rect2(c - Vector2(w / 2 + 8, 12), Vector2(w + 16, 24))
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#c0392b", pulse)
	box.set_corner_radius_all(8)
	draw_style_box(box, r)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 12), c + Vector2(6, 12), c + Vector2(0, 19)]), Color("#c0392b", pulse))
	draw_string(font, c + Vector2(-w / 2, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _draw_progress(center: Vector2, width: float, frac: float, color: Color, label := "") -> void:
	var r := Rect2(center - Vector2(width / 2, 5), Vector2(width, 10))
	draw_rect(r.grow(2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0, 1), r.size.y)), color)
	if label != "":
		draw_string(get_theme_default_font(), r.end + Vector2(6, 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


## Wooden scaffolding over a site (with a dirt patch for new buildings), a
## villager swinging a hammer beside it, and a progress bar underneath.
func _draw_scaffold(c: Vector2, sz: Vector2, frac: float, now: float, new_site: bool, show_bar := true, label := "") -> void:
	var r := Rect2(c - sz / 2, sz)
	if new_site:
		draw_rect(r.grow(4), Color("#8a6d45"))
		# The building rises: a pale outline filling up from the bottom.
		var h := r.size.y * frac
		draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), Color(1, 1, 1, 0.25))
	var pole := Color("#c8a26b")
	for x in [r.position.x, r.get_center().x, r.end.x]:
		draw_line(Vector2(x, r.position.y - 4), Vector2(x, r.end.y), pole, 2)
	var y := r.position.y
	while y <= r.end.y:
		draw_line(Vector2(r.position.x - 3, y), Vector2(r.end.x + 3, y), pole, 2)
		y += 12
	draw_line(r.position, Vector2(r.get_center().x, r.end.y), pole.darkened(0.2), 1.5)
	# Builder with a hammer.
	var b := Vector2(r.end.x + 10, r.end.y - 4)
	var swing := sin(now * 10.0 + c.x * 0.1) * 0.9
	var head := b + Vector2(-2, -6) + Vector2.from_angle(-PI / 2 - 0.6 + swing) * 12
	draw_line(b + Vector2(-2, -6), head, COLORS.stick, 2)
	draw_rect(Rect2(head - Vector2(3, 2), Vector2(6, 4)), COLORS.stone)
	_draw_figure(b + Vector2(0, 4), VILLAGER_TUNIC, [], 0.55)
	if show_bar:
		_draw_progress(Vector2(c.x, r.end.y + 12), sz.x, frac, Color("#f9ca24"), label)


## Town center, drawn around (0, 0). Era I is a longhouse for every civ.
## Medieval (Franks): wooden fort, then stone castle. Classical (Romans,
## Greeks): timber hall with wooden columns, then a marble palace.
func _draw_fort(c: Vector2, civ_color: Color, era: int, style: String) -> void:
	if era == 0:
		_draw_art("longhouse", c + Vector2(0, -16), Vector2(150, 120), civ_color)
		return
	if era == 1 and style != "classical":
		_draw_art("fort_wood", c + Vector2(0, -20), Vector2(170, 140), civ_color)
		return
	draw_set_transform(c, 0, Vector2.ONE)
	if era == 0:
		_draw_longhouse(civ_color)
		draw_set_transform(Vector2.ZERO)
		return
	if style == "classical":
		if era == 1:
			_draw_timber_hall(civ_color)
		else:
			_draw_marble_palace(civ_color)
		draw_set_transform(Vector2.ZERO)
		return
	var stone := era >= 2
	var wall: Color = COLORS.stone if stone else COLORS.wood
	var wall_dark := wall.darkened(0.3)
	# Back and side walls (lower, behind the keep).
	draw_rect(Rect2(-58, -38, 116, 14), wall_dark)
	draw_rect(Rect2(-62, -38, 12, 60), wall_dark)
	draw_rect(Rect2(50, -38, 12, 60), wall_dark)
	# Keep with a civ-colored roof and a flag.
	var keep := Rect2(-26, -44, 52, 40) if stone else Rect2(-22, -36, 44, 32)
	draw_rect(keep, wall.darkened(0.1) if stone else COLORS.trunk)
	draw_colored_polygon(PackedVector2Array([Vector2(keep.position.x - 6, keep.position.y), Vector2(0, keep.position.y - 22), Vector2(keep.end.x + 6, keep.position.y)]), civ_color)
	var pole := Vector2(0, keep.position.y - 22)
	draw_line(pole, pole + Vector2(0, -18), Color.BLACK, 2)
	draw_colored_polygon(PackedVector2Array([pole + Vector2(0, -18), pole + Vector2(16, -13), pole + Vector2(0, -8)]), civ_color)
	# Front wall: pointed log stakes, or stone blocks with battlements.
	if stone:
		draw_rect(Rect2(-60, 4, 120, 36), wall)
		for x in range(-60, 60, 12):
			draw_rect(Rect2(x, -2, 7, 7), wall)
		for row in 3:
			draw_line(Vector2(-60, 4 + row * 12), Vector2(60, 4 + row * 12), wall_dark, 1)
	else:
		for x in range(-60, 60, 10):
			draw_rect(Rect2(x + 1, 8, 8, 32), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(x + 1, 8), Vector2(x + 5, 1), Vector2(x + 9, 8)]), wall)
			draw_line(Vector2(x + 1, 8), Vector2(x + 1, 40), wall_dark, 1)
	# Gate.
	draw_rect(Rect2(-12, 16, 24, 24), Color("#2b1d10"))
	draw_circle(Vector2(0, 16), 12, Color("#2b1d10"))
	# Corner towers: wooden watchtowers, or taller stone towers with banners.
	for side in [-1, 1]:
		var t := Vector2(side * 64, 0)
		if stone:
			draw_rect(Rect2(t.x - 14, -26, 28, 66), wall)
			draw_colored_polygon(PackedVector2Array([t + Vector2(-18, -26), t + Vector2(0, -50), t + Vector2(18, -26)]), civ_color)
			draw_rect(Rect2(t.x - 4, -10, 8, 14), civ_color)
		else:
			for leg in [-8, 6]:
				draw_rect(Rect2(t.x + leg, 0, 3, 40), COLORS.trunk)
			draw_rect(Rect2(t.x - 12, -18, 24, 18), COLORS.wood)
			draw_colored_polygon(PackedVector2Array([t + Vector2(-15, -18), t + Vector2(0, -32), t + Vector2(15, -18)]), civ_color.darkened(0.2))
	draw_set_transform(Vector2.ZERO)


## Era I town center around (0, 0): a straw-roofed longhouse inside a low
## fence, with a campfire by the door.
func _draw_longhouse(civ_color: Color) -> void:
	var straw: Color = COLORS.farm.darkened(0.15)
	# Low stake fence.
	for x in range(-58, 60, 9):
		draw_rect(Rect2(x, 24, 4, 14), COLORS.trunk)
	draw_line(Vector2(-58, 30), Vector2(-24, 30), COLORS.trunk, 2)
	draw_line(Vector2(24, 30), Vector2(60, 30), COLORS.trunk, 2)
	# Hall and roof.
	draw_rect(Rect2(-40, -8, 80, 30), COLORS.wood)
	for x in range(-36, 40, 10):
		draw_line(Vector2(x, -8), Vector2(x, 22), COLORS.wood.darkened(0.25), 1)
	draw_colored_polygon(PackedVector2Array([Vector2(-48, -8), Vector2(-30, -34), Vector2(30, -34), Vector2(48, -8)]), straw)
	draw_line(Vector2(-30, -34), Vector2(30, -34), straw.darkened(0.3), 3)
	draw_rect(Rect2(-8, 4, 16, 18), Color("#2b1d10"))
	# Banner on the roof ridge in the civ's color.
	draw_line(Vector2(0, -34), Vector2(0, -52), Color.BLACK, 2)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -52), Vector2(14, -47), Vector2(0, -42)]), civ_color)
	# Campfire.
	var fire := Vector2(30, 32)
	draw_circle(fire, 6, Color("#e67e22"))
	draw_circle(fire + Vector2(0, -2), 3, Color("#f9ca24"))


## Era I food store: round mud hut with a cone of straw, a hand grindstone
## on a flat rock, and a basket of grain.
func _draw_granary(c: Vector2) -> void:
	_draw_art("granary", c + Vector2(0, -6), Vector2(84, 67))


## Era I woodcutter camp: pole-and-bark lean-to, chopping stump, log pile.
func _draw_lean_to(c: Vector2) -> void:
	_draw_art("lean_to", c + Vector2(0, -8), Vector2(62, 46))


## Small rocky mine: grey mound with gold nuggets or pale stone blocks, and a
## dark entrance. Upgraded: a deep gold mine gets a headframe and a cart;
## a stone quarry gets cut terraces and stacked blocks.
func _draw_mine(c: Vector2, res: String, upgraded := false) -> void:
	_draw_art(res + ("_mine2" if upgraded else "_mine"), c + Vector2(0, -8), Vector2(62, 49))


## House: a straw hut in Era I; from Era II a timber-framed house (medieval)
## or a whitewashed house with a terracotta roof (classical).
func _draw_hut(c: Vector2, era: int, style: String) -> void:
	var look := "era0" if era == 0 else ("classical" if style == "classical" else "medieval")
	_draw_art("hut_" + look, c + Vector2(0, -3), Vector2(22, 20))


## Lane tower: a wooden watchtower, or after the Stone Towers upgrade a stone
## tower (medieval) or a marble tower (classical), with an
## arrow slit and a civ-colored roof. Destroyed towers leave broken logs.
func _draw_tower(pos: Vector2, color: Color, hp: float, stone: bool, style: String, max_hp: float) -> void:
	var name := "tower_ruin" if hp <= 0 else ("tower_wood" if not stone else ("tower_marble" if style == "classical" else "tower_stone"))
	_draw_art(name, pos + Vector2(0, -10), Vector2(56, 84), color)
	if hp > 0:
		_draw_hp(pos + Vector2(0, -60), hp, max_hp)


## Arrow from a tower's slit to its target, rising and falling in a short arc.
func _draw_arrow(a: Dictionary, target: Vector2) -> void:
	var start := building_pos(a.team, "tower" if a.from == "tower" else "main", a.lane) + Vector2(0, -12)
	var lift := Vector2(0, -start.distance_to(target) * 0.25)
	var pos := start.lerp(target, a.t) + lift * sin(PI * a.t)
	var ahead := start.lerp(target, minf(a.t + 0.05, 1.0)) + lift * sin(PI * minf(a.t + 0.05, 1.0))
	var dir := (ahead - pos).normalized()
	if dir == Vector2.ZERO:
		dir = (target - start).normalized()
	var side := dir.orthogonal()
	draw_line(pos - dir * 22, pos, Color("#1b120a"), 3)
	draw_colored_polygon(PackedVector2Array([pos + dir * 8, pos + side * 5, pos - side * 5]), Color("#1b120a"))
	draw_line(pos - dir * 22, pos - dir * 15 + side * 5, Color.WHITE, 2.5)
	draw_line(pos - dir * 22, pos - dir * 15 - side * 5, Color.WHITE, 2.5)


func _draw_hp(center: Vector2, hp: float, max_hp: float, width := 70.0) -> void:
	var r := Rect2(center - Vector2(width / 2, 5), Vector2(width, 10))
	draw_rect(r, Color("#2d3436"))
	if hp > 0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * hp / max_hp, r.size.y)), Color("#44bd32"))


## A villager dot with a "back" arrow; faded when nobody works there.
func _draw_unassign_icon(c: Vector2, active: bool) -> void:
	var alpha := 1.0 if active else 0.35
	draw_circle(c, 26, Color("#2b2620", alpha))
	draw_arc(c, 26, 0, TAU, 24, Color("#f9ca24", alpha), 3)
	draw_circle(c + Vector2(6, 0), 8, Color(COLORS.villager, alpha))
	draw_line(c + Vector2(-16, 0), c + Vector2(-4, 0), Color("#f9ca24", alpha), 3)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-18, 0), c + Vector2(-10, -7), c + Vector2(-10, 7)]), Color("#f9ca24", alpha))


func _draw_ball(p: Vector2, r: float, color: Color) -> void:
	draw_circle(p, r, color)
	draw_arc(p, r, 0, TAU, 16, Color.BLACK, 2)


## Where a unit's current target stands on screen (Vector2.INF when walking).
func _target_pos(u: Dictionary, positions: Array[Vector2]) -> Vector2:
	match u.target:
		"unit":
			var idx := battle.units.find(u.foe)
			return positions[idx] if idx != -1 else Vector2.INF
		"tower":
			return building_pos(1 - u.team, "tower", u.lane)
		"main":
			return town_center(1 - u.team)
	return Vector2.INF


const FIGURE := Vector2(32, 40)
## Size soldiers are drawn at, relative to their 32x40 art.
const UNIT_SCALE := 0.9
const LEG := Color("#4a2f1a")
const OUTLINE := Color("#2b1d10")
## Civilian tunic color for villagers (soldiers wear their civ color).
const VILLAGER_TUNIC := Color("#d9c8a0")


## Top-left of a figure's 32x40 art box when it stands at `p`.
func _figure_origin(p: Vector2, scale: float) -> Vector2:
	return p - Vector2(16, 26) * scale


## A little character: legs and hands, a tunic in `color`, a head, then any
## gear layers (helmets, hood, chainmail) in order. `walk` is the step phase
## in radians while walking (legs alternate, body bobs), or -1 standing.
## `back`: seen from behind (the player's troops face the enemy, up the
## screen), using the *_back head and gear art where it exists.
## `seated`: astride a horse, legs hanging down both sides.
func _draw_figure(p: Vector2, color: Color, gear: Array, scale := 1.0, walk := -1.0, back := false, seated := false) -> void:
	if walk >= 0.0:
		p.y -= absf(sin(walk)) * 1.6 * scale
	var o := _figure_origin(p, scale)
	var box := Rect2(o, FIGURE * scale)
	if seated:
		for side in [-1, 1]:
			var hip := o + Vector2(16 + side * 5, 30) * scale
			var boot := o + Vector2(16 + side * 10, 37) * scale
			draw_line(hip, boot, OUTLINE, 5.0 * scale)
			draw_line(hip, boot, LEG, 3.0 * scale)
		var layers := ["unit_tint", "head_back" if back else "head"]
		for name in layers + gear.map(func(g): return _facing_art(g, back)):
			draw_texture_rect(_tex(name), box, false, color if name == "unit_tint" else Color.WHITE)
		return
	# Legs: each lifts and swings in turn while walking.
	for side in [-1, 1]:
		var lift := 0.0
		var swing := 0.0
		if walk >= 0.0:
			var s: float = sin(walk) * side
			lift = maxf(s, 0.0) * 1.8
			swing = s * 1.2
		var leg := Rect2(o + Vector2(16 + side * 3.5 - 2 + swing, 31 - lift) * scale, Vector2(4, 6) * scale)
		draw_rect(leg, LEG)
		draw_rect(leg, OUTLINE, false, 1.0)
	var head := "head_back" if back else "head"
	for name in ["unit", "unit_tint", head] + gear.map(func(g): return _facing_art(g, back)):
		var t := _tex(name)
		if t:
			draw_texture_rect(t, box, false, color if name == "unit_tint" else Color.WHITE)


## Gear art for the side we see: "<name>_back" when seen from behind and it exists.
func _facing_art(name: String, back: bool) -> String:
	if back and _tex(name + "_back") != null:
		return name + "_back"
	return name


## A weapon texture drawn pointing along `angle`, pivoting at `pivot` (in the
## texture's own pixels, at 1x) placed on `at`. Textures point up by default.
func _draw_weapon(name: String, tex_size: Vector2, pivot: Vector2, at: Vector2, angle: float, scale := 1.0) -> void:
	var t := _tex(name)
	if t == null:
		return
	draw_set_transform(at, angle + PI / 2, Vector2(scale, scale))
	draw_texture_rect(t, Rect2(-pivot, tex_size), false)
	draw_set_transform(Vector2.ZERO)


## Step phase for a unit on the move, or -1 when it stands or fights.
func _walk_phase(u: Dictionary, now: float, rate := 11.0) -> float:
	if u.target != "" or u.speed <= 0.0:
		return -1.0
	return fmod(now * rate + u.side * 5.0, TAU)


func _draw_shield(at: Vector2, color: Color, scale := 1.0) -> void:
	var r := Rect2(at - Vector2(8, 8) * scale, Vector2(16, 16) * scale)
	draw_texture_rect(_tex("shield"), r, false)
	draw_texture_rect(_tex("shield_tint"), r, false, color)


## Archer: a figure with a bow (hood and quiver at level 2, steel cap and a
## crossbow at level 3); while attacking, an arrow flies to the target.
func _draw_archer(u: Dictionary, p: Vector2, color: Color, now: float, target: Vector2) -> void:
	var facing := -PI / 2 if u.team == Battlefield.PLAYER else PI / 2
	if target != Vector2.INF:
		facing = (target - p).angle()
	var tier: int = u.get("tier", 0)
	var k := UNIT_SCALE
	var o := _figure_origin(p, k)
	if tier >= 1:
		draw_texture_rect(_tex("quiver"), Rect2(o, FIGURE * k), false)
	var gear := ["hood"] if tier == 1 else (["helmet_1"] if tier >= 2 else [])
	_draw_figure(p, color, gear, k, _walk_phase(u, now), u.team == Battlefield.PLAYER)
	var hand := o + Vector2(26, 27) * k
	if tier >= 2:
		_draw_weapon("crossbow", Vector2(18, 30), Vector2(9, 22), hand, facing, k)
	else:
		# The bow's image faces right; turn it so it faces the target.
		_draw_weapon("bow", Vector2(16, 30), Vector2(5, 15), hand, facing - PI / 2, k)
	if target != Vector2.INF:
		var t := fmod(now * 1.2 + u.side, 1.0)
		var ap := hand.lerp(target, t) + Vector2(0, -sin(PI * t) * 18)
		var dir := (target - hand).normalized()
		draw_line(ap - dir * 12, ap, Color("#1b120a"), 2)
		draw_circle(ap, 2, Color("#d0d0d0"))
	_draw_hp(p + Vector2(0, -30), u.hp, u.max_hp, 26)


## Cavalry seen from directly above, so the whole unit can turn: it rotates
## to follow its road (round the L corners) and to face what it attacks.
## Hooves step at the sides while galloping. Armored horse at level 2; knight
## with a plumed helm, shield and pennant at level 3.
func _draw_cavalry(u: Dictionary, p: Vector2, color: Color, now: float, target: Vector2) -> void:
	var tier: int = u.get("tier", 0)
	var gallop := _walk_phase(u, now, 13.0)
	var k := UNIT_SCALE * 1.15
	var heading := _heading(u, target)
	# Local space: art points up, centered on the rider at (15, 31).
	draw_set_transform(p + Vector2(0, -8), heading + PI / 2, Vector2(k, k))
	var o := -Vector2(15, 31)
	for hoof in [[8.0, 24.0, 0.0], [22.0, 24.0, PI], [8.0, 43.0, PI], [22.0, 43.0, 0.0]]:
		var step: float = sin(gallop + hoof[2]) * 2.5 if gallop >= 0.0 else 0.0
		draw_circle(o + Vector2(hoof[0], hoof[1] + step), 2.2, Color("#2b1d10"))
	var box := Rect2(o, Vector2(30, 56))
	draw_texture_rect(_tex("cav_horse"), box, false)
	if tier >= 1:
		draw_texture_rect(_tex("cav_barding"), box, false)
		draw_texture_rect(_tex("cav_barding_tint"), box, false, color)
	if tier >= 2:  # shield on the left arm
		var sh := Rect2(o + Vector2(1, 26), Vector2(10, 10))
		draw_texture_rect(_tex("shield"), sh, false)
		draw_texture_rect(_tex("shield_tint"), sh, false, color)
	draw_texture_rect(_tex("cav_rider"), box, false)
	draw_texture_rect(_tex("cav_rider_tint"), box, false, color)
	draw_texture_rect(_tex("cav_helm" if tier >= 2 else "cav_head"), box, false)
	# Lance couched under the right arm, pointing ahead; it jabs while fighting.
	var jab := maxf(sin(now * 10.0 + u.side * 7.0), 0.0) * 4.0 if u.target != "" else 0.0
	var lance := _tex("lance")
	var grip := o + Vector2(21, 30 - jab)
	draw_texture_rect(lance, Rect2(grip - Vector2(4, 44) * 0.85, Vector2(8, 56) * 0.85), false)
	if tier >= 2:
		draw_texture_rect(_tex("pennant_tint"), Rect2(grip - Vector2(4, 44) * 0.85, Vector2(8, 56) * 0.85), false, color)
	draw_set_transform(Vector2.ZERO)
	_draw_hp(p + Vector2(0, -42), u.hp, u.max_hp, 30)


## Fighter: a figure with a club (helmet and shield at level 2; great helm,
## chainmail and a sword at level 3). The weapon swings while attacking.
func _draw_fighter(u: Dictionary, p: Vector2, color: Color, now: float) -> void:
	var facing := -PI / 2 if u.team == Battlefield.PLAYER else PI / 2
	var angle := facing + 0.5  # held forward-right at rest
	if u.target != "":
		angle = facing + 0.2 + sin(now * 12.0 + u.side * 7.0) * 0.9
	var tier: int = u.get("tier", 0)
	var gear := ["helmet_1"] if tier == 1 else (["chainmail", "helmet_2"] if tier >= 2 else [])
	var k := UNIT_SCALE
	var walk := _walk_phase(u, now)
	_draw_figure(p, color, gear, k, walk, u.team == Battlefield.PLAYER)
	if walk >= 0.0:
		p.y -= absf(sin(walk)) * 1.6 * k  # keep shield and weapon with the bobbing body
	var o := _figure_origin(p, k)
	if tier >= 1:
		_draw_shield(o + Vector2(6, 26) * k, color, k)
	_draw_weapon("sword" if tier >= 2 else "club", Vector2(10, 30), Vector2(5, 27), o + Vector2(26, 27) * k, angle, k)
	_draw_hp(p + Vector2(0, -30), u.hp, u.max_hp, 26)


## Villager: a small figure in a plain tunic. Farmers bob with a hoe,
## lumberjacks and miners swing a tool, walkers carry their load.
func _draw_worker(p: Vector2, w: Dictionary, now: float, olives := false) -> void:
	var phase: float = w.spot * 1.7
	if w.phase == "gather" and w.job == "food":
		p.y += sin(now * 6.0 + phase) * 2.0
	var walking: bool = w.phase == "to_drop" or w.phase == "to_work"
	_draw_figure(p, VILLAGER_TUNIC, [], 0.6, fmod(now * 12.0 + phase, TAU) if walking else -1.0)
	var hand := _figure_origin(p, 0.6) + Vector2(26, 27) * 0.6
	if w.phase == "gather":
		if w.job == "food":
			var hoe := sin(now * 6.0 + phase) * 0.6
			draw_line(hand, hand + Vector2.from_angle(PI / 2 - hoe) * 11, COLORS.stick, 2)
		else:  # lumberjacks and miners swing a tool
			var swing := sin(now * 9.0 + phase)
			var head := hand + Vector2.from_angle(-0.9 + swing * 0.9) * 11
			draw_line(hand, head, COLORS.stick, 2)
			draw_rect(Rect2(head - Vector2(2.5, 2.5), Vector2(5, 5)), COLORS.stone)
	if w.phase == "to_drop":
		var load_color: Color = {"food": COLORS.olive if olives else COLORS.crop, "wood": COLORS.wood, "gold": Color("#f1c40f"), "stone": Color("#d5d8dc")}[w.job]
		var top := p + Vector2(-5, -24)
		draw_rect(Rect2(top, Vector2(10, 7)), load_color)
		draw_rect(Rect2(top, Vector2(10, 7)), Color.BLACK, false, 1.2)


func _draw_farm(area: Rect2) -> void:
	draw_rect(area.grow(3), Color("#6e5a3a"))
	var cell := area.size / Vector2(FARM_COLS, FARM_ROWS)
	for i in FARM_COLS * FARM_ROWS:
		var plot := Rect2(area.position + cell * Vector2(i % FARM_COLS, i / FARM_COLS), cell).grow(-1.5)
		draw_texture_rect(_tex("wheat_plot"), plot, false)


func _draw_tree(c: Vector2) -> void:
	_draw_art("tree", c + Vector2(0, -6), Vector2(44, 51))


## Classical Era II town center around (0, 0): a timber hall on a low
## platform with wooden columns and a terracotta tiled roof.
func _draw_timber_hall(civ_color: Color) -> void:
	var wood: Color = COLORS.wood
	draw_rect(Rect2(-66, 30, 132, 10), wood.darkened(0.35))  # platform
	draw_rect(Rect2(-56, -10, 112, 40), wood.darkened(0.15))  # back wall
	draw_rect(Rect2(-10, 6, 20, 24), Color("#2b1d10"))  # doorway
	for x in [-52, -32, 22, 42]:  # wooden columns
		draw_rect(Rect2(x, -10, 10, 40), wood)
		draw_rect(Rect2(x - 2, -13, 14, 4), wood.darkened(0.25))
	draw_rect(Rect2(-62, -20, 124, 8), wood.darkened(0.3))  # beam
	draw_colored_polygon(PackedVector2Array([Vector2(-68, -20), Vector2(0, -46), Vector2(68, -20)]), COLORS.terracotta)
	for k in 4:  # roof tile rows
		var y := -24.0 - k * 6
		var half := 68.0 * (y + 46) / 26.0
		draw_line(Vector2(-half, y), Vector2(half, y), COLORS.terracotta.darkened(0.25), 1.5)
	draw_line(Vector2(0, -46), Vector2(0, -62), Color.BLACK, 2)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -62), Vector2(16, -57), Vector2(0, -52)]), civ_color)


## Classical Era III town center around (0, 0): marble palace on steps with
## a colonnade, an entablature and a pediment.
func _draw_marble_palace(civ_color: Color) -> void:
	for k in 3:  # steps
		draw_rect(Rect2(-72 + k * 5, 30 + k * -5, 144 - k * 10, 6), COLORS.marble_shade if k % 2 == 0 else COLORS.marble)
	draw_rect(Rect2(-58, -14, 116, 34), COLORS.marble_shade)  # cella wall
	draw_rect(Rect2(-10, 0, 20, 20), Color("#2b1d10"))
	for i in 6:  # columns with capitals and bases
		var x := -60.0 + i * 22.0
		draw_rect(Rect2(x, -14, 9, 34), COLORS.marble)
		draw_line(Vector2(x + 3, -12), Vector2(x + 3, 18), COLORS.marble_shade, 1)
		draw_rect(Rect2(x - 2, -18, 13, 4), COLORS.marble)
		draw_rect(Rect2(x - 2, 18, 13, 3), COLORS.marble)
	draw_rect(Rect2(-66, -28, 132, 10), COLORS.marble)  # entablature
	draw_rect(Rect2(-66, -24, 132, 3), civ_color)  # painted frieze
	draw_colored_polygon(PackedVector2Array([Vector2(-70, -28), Vector2(0, -52), Vector2(70, -28)]), COLORS.marble)
	draw_colored_polygon(PackedVector2Array([Vector2(-52, -31), Vector2(0, -48), Vector2(52, -31)]), COLORS.marble_shade)
	draw_circle(Vector2(0, -37), 5, civ_color)  # emblem in the pediment
	for side in [-1, 1]:  # banners
		var pole := Vector2(side * 76, 30)
		draw_line(pole, pole + Vector2(0, -64), Color.BLACK, 2)
		draw_rect(Rect2(pole + Vector2(-5 if side < 0 else 0, -62), Vector2(5, 22)), civ_color)


## Olive grove: rows of small grey-green olive trees on dry ground.
func _draw_olive_grove(area: Rect2) -> void:
	draw_rect(area.grow(3), Color("#a8955f"))
	draw_rect(area, Color("#c9b47a"))
	var cell := area.size / Vector2(FARM_COLS, FARM_ROWS)
	for i in FARM_COLS * FARM_ROWS:
		var c := area.position + cell * Vector2(i % FARM_COLS + 0.5, i / FARM_COLS + 0.5)
		_draw_art("olive_tree", c + Vector2(0, -3), Vector2(34, 34))


## Olive press: plaster press house, stone basin with a crushing wheel, amphorae.
func _draw_olive_press(c: Vector2) -> void:
	_draw_art("olive_press", c + Vector2(0, -10), Vector2(64, 56))


## Classical timber yard: tiled roof on columns over stacked logs.
func _draw_timber_yard(c: Vector2) -> void:
	_draw_art("timber_yard", c + Vector2(0, -8), Vector2(62, 46))


## Era III medieval food: tall stone tower windmill with bigger sails.
func _draw_grand_mill(c: Vector2, now: float) -> void:
	_draw_windmill("grand_mill_base", c, now, Vector2(29, 14), 32.0)


## Era III classical food: columned oil workshop with rows of amphorae.
func _draw_oil_workshop(c: Vector2) -> void:
	_draw_art("oil_workshop", c + Vector2(0, -10), Vector2(64, 56))


## Era III medieval wood: sawmill with a turning water wheel.
func _draw_sawmill(c: Vector2, now: float) -> void:
	var rect := Rect2(c + Vector2(-31, -31), Vector2(62, 46))
	draw_texture_rect(_tex("sawmill"), rect, false)
	var k := rect.size.x / 64.0
	var hub := rect.position + Vector2(10, 31) * k
	draw_circle(hub, 9 * k, Color("#6e4a28"))
	draw_arc(hub, 9 * k, 0, TAU, 20, OUTLINE, 1.4)
	for n in 6:
		draw_line(hub, hub + Vector2.from_angle(now * 2.0 + n * PI / 3) * 9 * k, Color("#c08a50"), 2)


## Era III classical wood: columned carpentry with plank stacks.
func _draw_carpentry(c: Vector2) -> void:
	_draw_art("carpentry", c + Vector2(0, -8), Vector2(62, 46))


## Barracks, archery range or stables: Era I wood and straw for everyone, then
## the civ's style (medieval timber frame / classical plaster and columns).
## Shields show at level 2, a stone base and pennants at level 3.
func _draw_military(id: String, c: Vector2, civ_color: Color, era: int, style: String, tier := 0) -> void:
	var look := "era0" if era == 0 else ("classical" if style == "classical" else "medieval")
	var at := c + Vector2(0, -12)
	var sz := Vector2(80, 65)
	_draw_art("%s_%s" % [id, look], at, sz, civ_color)
	if tier >= 2:
		_draw_art("mil_tier2", at, sz, civ_color)
	if tier >= 1:
		_draw_art("mil_tier1", at, sz, civ_color)


## Windmill: stone base from the art, four sails turning slowly.
func _draw_mill(c: Vector2, now: float, _scale := 1.0) -> void:
	_draw_windmill("windmill_base", c, now, Vector2(29, 22), 26.0)


func _draw_windmill(base: String, c: Vector2, now: float, hub_px: Vector2, blade: float) -> void:
	var rect := Rect2(c + Vector2(-32, -38), Vector2(64, 56))
	draw_texture_rect(_tex(base), rect, false)
	var hub := rect.position + hub_px
	for k in 4:
		var a := now * 1.5 + k * PI / 2
		var tip := hub + Vector2.from_angle(a) * blade
		draw_line(hub, tip, OUTLINE, 4)
		draw_line(hub, tip, Color("#6b4426"), 2)
		var side := Vector2.from_angle(a + PI / 2) * 6
		var sail := PackedVector2Array([hub + Vector2.from_angle(a) * blade * 0.35, tip, tip + side, hub + Vector2.from_angle(a) * blade * 0.35 + side])
		draw_colored_polygon(sail, Color("#f5f1e6"))
		draw_polyline(sail + PackedVector2Array([sail[0]]), OUTLINE, 1.2)
	draw_circle(hub, 3.5, OUTLINE)


## Medieval lumber camp: plank hut with a log pile.
func _draw_lumber_camp(c: Vector2, _scale := 1.0) -> void:
	_draw_art("lumber_camp", c + Vector2(0, -8), Vector2(62, 46))