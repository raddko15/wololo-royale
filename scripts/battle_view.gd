class_name BattleView
extends Control
## Draws the whole portrait battlefield and turns taps into game actions.
## Both cities share one layout: the player's at the bottom, the enemy's
## mirrored at the top, with 3 lanes between the tower lines.

## A building of the player's was tapped: "town_center", "mill", "lumber_camp",
## "towers", "gold_mine" or "stone_mine".
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
var battle: Battlefield
## Card being dragged ("" when none) and where the finger is, in local coordinates.
var drag_card := ""
var drag_pos := Vector2.ZERO
## Lanes auto-trained units are sent to; each is marked with moving chevrons.
var active_lanes := [false, true, false]


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
	var area := _crect(team, 0.35, 0.30, 70, 3)
	var step := 21.0
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
	# Lane y beyond 1 is on the enemy's road, below 0 on the player's road.
	if u.y > 1.0:
		return _along(road(Battlefield.ENEMY, u.lane), (u.y - 1.0) / Battlefield.MAIN_DIST[u.lane])
	if u.y < 0.0:
		return _along(road(Battlefield.PLAYER, u.lane), -u.y / Battlefield.MAIN_DIST[u.lane])
	var y := lerpf(tower_line(Battlefield.PLAYER), tower_line(Battlefield.ENEMY), u.y)
	return Vector2(LANE_X[u.lane] * size.x + u.side * size.x * 0.025, y)


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
	for job in ["food", "wood"]:
		if pos.distance_to(unassign_icon(job)) < 34:
			economy.reassign(job, "idle")
			return
	for res in Economy.MINED:
		if economy.mines.has(res) and pos.distance_to(mine_pos(Battlefield.PLAYER, res)) < 36:
			building_tapped.emit(res + "_mine", mine_pos(Battlefield.PLAYER, res))
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

func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.grass)
	var unit_drag: bool = GameConfig.data().units.has(drag_card)
	var hover_lane := lane_at(drag_pos) if unit_drag else -1
	for lane in Battlefield.LANES:
		var lane_color: Color = COLORS.lane
		if unit_drag:
			lane_color = Color("#f9ca24") if lane == hover_lane else COLORS.lane.lightened(0.2)
		var top := tower_line(Battlefield.ENEMY)
		draw_rect(Rect2((LANE_X[lane] - LANE_W / 2) * size.x, top, LANE_W * size.x, tower_line(Battlefield.PLAYER) - top), lane_color)
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
		for lane in Battlefield.LANES:
			var path := road(team, lane)
			draw_polyline(path, COLORS.lane, size.x * LANE_W)
			for corner in path:  # square joints
				draw_rect(Rect2(corner - Vector2.ONE * size.x * LANE_W / 2, Vector2.ONE * size.x * LANE_W), COLORS.lane)

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
				_draw_cavalry(u, positions[i], color, now)
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
		_draw_military(id, military_pos(team, id), color, e.era_index, style)
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
		_draw_ball(p, VILLAGER_R, COLORS.villager)
	# Towers last so their health bars stay visible over the fields.
	if battle.towers_built[team]:
		for lane in Battlefield.LANES:
			_draw_tower(building_pos(team, "tower", lane), color, battle.buildings[team].towers[lane], e.upgrades.has("stone_towers"), style, battle.tower_max_hp[team])
	_draw_jobs(team, e, now)


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
	_draw_ball(b, VILLAGER_R - 2, COLORS.villager)
	if show_bar:
		_draw_progress(Vector2(c.x, r.end.y + 12), sz.x, frac, Color("#f9ca24"), label)


## Town center, drawn around (0, 0). Era I is a longhouse for every civ.
## Medieval (Franks): wooden fort, then stone castle. Classical (Romans,
## Greeks): timber hall with wooden columns, then a marble palace.
func _draw_fort(c: Vector2, civ_color: Color, era: int, style: String) -> void:
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
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	var mud := Color("#9c7a54")
	var straw: Color = COLORS.farm.darkened(0.15)
	draw_circle(Vector2(-4, 6), 14, mud)
	draw_rect(Rect2(-18, 0, 28, 14), mud)
	draw_rect(Rect2(-8, 4, 8, 10), Color("#2b1d10"))
	draw_colored_polygon(PackedVector2Array([Vector2(-22, 2), Vector2(-4, -22), Vector2(14, 2)]), straw)
	for k in 3:  # straw bands
		var y := -14.0 + k * 6
		var half := (y + 22) * 0.75
		draw_line(Vector2(-4 - half, y), Vector2(-4 + half, y), straw.darkened(0.25), 1)
	# Grindstone: flat rock with a round stone on top.
	draw_rect(Rect2(14, 8, 14, 6), Color("#7f7f7a"))
	draw_circle(Vector2(21, 6), 5, Color("#a5a5a0"))
	draw_circle(Vector2(21, 6), 1.5, Color("#5a5a55"))
	# Basket of grain.
	draw_rect(Rect2(-26, 8, 8, 7), Color("#a0784a"))
	draw_circle(Vector2(-22, 8), 3.5, COLORS.crop)
	draw_set_transform(Vector2.ZERO)


## Era I woodcutter camp: slanted pole-and-bark lean-to, a chopping stump with
## an axe in it, and a few logs.
func _draw_lean_to(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(1.6, 1.6))
	var bark := Color("#6b4a2b")
	draw_colored_polygon(PackedVector2Array([Vector2(-20, 12), Vector2(-14, -14), Vector2(8, 12)]), bark)
	for k in 4:  # poles
		var x := -18.0 + k * 7
		draw_line(Vector2(x, 12), Vector2(-14 + k * 1.5, -14), COLORS.trunk, 2)
	draw_line(Vector2(-16, -16), Vector2(-10, -10), COLORS.trunk, 2)
	# Chopping stump with an axe.
	draw_rect(Rect2(12, 4, 10, 9), COLORS.trunk)
	draw_circle(Vector2(17, 4), 5, Color("#c8a26b"))
	draw_line(Vector2(17, 3), Vector2(25, -8), COLORS.stick, 2)
	draw_rect(Rect2(14, 0, 5, 5), COLORS.stone)
	# Log pile.
	for p in [Vector2(-6, 15), Vector2(2, 15), Vector2(-2, 10)]:
		draw_circle(p, 3.5, COLORS.wood)
		draw_circle(p, 1.5, COLORS.crop)
	draw_set_transform(Vector2.ZERO)


## Small rocky mine: grey mound with gold nuggets or pale stone blocks, and a
## dark entrance. Upgraded: a deep gold mine gets a headframe and a cart;
## a stone quarry gets cut terraces and stacked blocks.
func _draw_mine(c: Vector2, res: String, upgraded := false) -> void:
	if upgraded and res == "stone":
		for k in 3:  # terraces cut into the rock
			draw_rect(Rect2(c + Vector2(-24 + k * 6, -12 + k * 8), Vector2(48 - k * 12, 9)), Color("#9a9a94").darkened(k * 0.1))
		for p in [Vector2(18, 10), Vector2(24, 10), Vector2(21, 4)]:
			draw_rect(Rect2(c + p - Vector2(3, 3), Vector2(6, 5)), Color("#d5d8dc"))
		return
	var rock := Color("#7f7f7a")
	draw_colored_polygon(PackedVector2Array([c + Vector2(-22, 12), c + Vector2(-14, -8), c + Vector2(-2, -16), c + Vector2(12, -10), c + Vector2(22, 12)]), rock)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 12), c + Vector2(-6, 2), c + Vector2(0, -3), c + Vector2(6, 2), c + Vector2(6, 12)]), Color("#1b120a"))
	var bit := Color("#f1c40f") if res == "gold" else Color("#d5d8dc")
	for p in [Vector2(-13, 0), Vector2(11, -2), Vector2(-4, -10), Vector2(15, 7)]:
		if res == "gold":
			draw_circle(c + p, 3, bit)
		else:
			draw_rect(Rect2(c + p - Vector2(3, 3), Vector2(6, 5)), bit)
	if upgraded:  # headframe over the shaft and a cart of ore
		draw_line(c + Vector2(-10, 4), c + Vector2(0, -26), COLORS.trunk, 3)
		draw_line(c + Vector2(10, 4), c + Vector2(0, -26), COLORS.trunk, 3)
		draw_circle(c + Vector2(0, -26), 5, COLORS.trunk)
		draw_circle(c + Vector2(0, -26), 2, Color("#1b120a"))
		draw_rect(Rect2(c + Vector2(16, 4), Vector2(14, 8)), COLORS.wood)
		draw_circle(c + Vector2(23, 3), 4, bit)
		draw_circle(c + Vector2(19, 13), 2.5, Color.BLACK)
		draw_circle(c + Vector2(27, 13), 2.5, Color.BLACK)


## House: a straw hut in Era I; from Era II a whitewashed house with a
## terracotta roof (classical) or a timber-framed house (medieval).
func _draw_hut(c: Vector2, era: int, style: String) -> void:
	draw_set_transform(c, 0, Vector2(0.85, 0.85))
	var door := Color("#2b1d10")
	if era == 0:
		draw_rect(Rect2(-9, -3, 18, 12), COLORS.wood)
		draw_rect(Rect2(-2, 2, 4, 7), door)
		draw_colored_polygon(PackedVector2Array([Vector2(-12, -3), Vector2(0, -13), Vector2(12, -3)]), COLORS.farm.darkened(0.2))
	elif style == "classical":
		draw_rect(Rect2(-10, -3, 20, 12), COLORS.plaster)
		draw_rect(Rect2(-2, 2, 4, 7), door)
		draw_colored_polygon(PackedVector2Array([Vector2(-12, -3), Vector2(0, -10), Vector2(12, -3)]), COLORS.terracotta)
		draw_line(Vector2(-12, -3), Vector2(12, -3), COLORS.terracotta.darkened(0.3), 1.5)
	else:
		draw_rect(Rect2(-9, -3, 18, 12), COLORS.plaster)
		for x in [-9, -1, 7]:
			draw_rect(Rect2(x, -3, 2, 12), COLORS.trunk)
		draw_line(Vector2(-9, 3), Vector2(9, 3), COLORS.trunk, 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(-12, -3), Vector2(0, -14), Vector2(12, -3)]), Color("#4a3b35"))
	draw_set_transform(Vector2.ZERO)


## Lane tower: a wooden watchtower, or after the Stone Towers upgrade a stone
## tower (medieval) or a marble tower (classical), with an
## arrow slit and a civ-colored roof. Destroyed towers leave broken logs.
func _draw_tower(pos: Vector2, color: Color, hp: float, stone: bool, style: String, max_hp: float) -> void:
	draw_set_transform(pos, 0, Vector2(1.4, 1.4))
	var c := Vector2.ZERO
	if stone and style == "classical" and hp > 0:
		# Marble tower with pilasters and a terracotta roof.
		draw_rect(Rect2(-15, -18, 30, 40), COLORS.marble)
		for x in [-13, -3, 7]:
			draw_rect(Rect2(x, -16, 4, 36), COLORS.marble_shade)
		draw_rect(Rect2(-17, -20, 34, 4), COLORS.marble_shade)
		draw_rect(Rect2(-2, -12, 4, 9), Color("#1b120a"))
		draw_colored_polygon(PackedVector2Array([Vector2(-19, -20), Vector2(0, -36), Vector2(19, -20)]), COLORS.terracotta)
		draw_rect(Rect2(-4, -31, 8, 5), color)
		draw_set_transform(Vector2.ZERO)
		_draw_hp(pos + Vector2(0, -36 * 1.4 - 10), hp, max_hp)
		return
	var body: Color = COLORS.stone if stone else COLORS.wood
	if hp <= 0:
		for k in 4:
			var a := 0.4 + k * 0.7
			var p := c + Vector2(-14 + k * 9, 10 - (k % 2) * 6)
			draw_line(p, p + Vector2.from_angle(a) * 16, body.darkened(0.25), 5)
		draw_set_transform(Vector2.ZERO)
		return
	if stone:
		draw_rect(Rect2(c + Vector2(-16, -14), Vector2(32, 36)), body)
		for x in [-16, -6, 4]:
			draw_rect(Rect2(c + Vector2(x, -20), Vector2(7, 6)), body)
	else:
		# Four log legs with a cross brace, then the lookout on top.
		for x in [-14, -5, 4, 11]:
			draw_rect(Rect2(c + Vector2(x, -2), Vector2(4, 24)), COLORS.trunk)
		draw_line(c + Vector2(-13, 2), c + Vector2(13, 18), COLORS.trunk, 2)
		draw_line(c + Vector2(13, 2), c + Vector2(-13, 18), COLORS.trunk, 2)
		draw_rect(Rect2(c + Vector2(-18, -4), Vector2(36, 5)), body.darkened(0.2))
		draw_rect(Rect2(c + Vector2(-14, -20), Vector2(28, 16)), body)
	draw_rect(Rect2(c + Vector2(-2, -15), Vector2(4, 9)), Color("#1b120a"))  # arrow slit
	var roof_y := -20.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-19, roof_y), c + Vector2(0, roof_y - 16), c + Vector2(19, roof_y)]), color)
	draw_set_transform(Vector2.ZERO)
	_draw_hp(pos + Vector2(0, (roof_y - 16) * 1.4 - 10), hp, max_hp)


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


## A ball with a bow; while attacking, an arrow flies to the target every second.
func _draw_archer(u: Dictionary, p: Vector2, color: Color, now: float, target: Vector2) -> void:
	var facing := -PI / 2 if u.team == Battlefield.PLAYER else PI / 2
	if target != Vector2.INF:
		facing = (target - p).angle()
	var bow_c := p + Vector2.from_angle(facing) * 9
	draw_arc(bow_c, 11, facing - 1.2, facing + 1.2, 10, COLORS.stick, 3)
	var tip_a := bow_c + Vector2.from_angle(facing - 1.2) * 11
	var tip_b := bow_c + Vector2.from_angle(facing + 1.2) * 11
	draw_line(tip_a, tip_b, Color("#e8e8e8"), 1)
	_draw_ball(p, FIGHTER_R - 1, color)
	if target != Vector2.INF:
		var t := fmod(now * 1.2 + u.side, 1.0)
		var ap := p.lerp(target, t) + Vector2(0, -sin(PI * t) * 18)
		var dir := (target - p).normalized()
		draw_line(ap - dir * 12, ap, Color("#1b120a"), 2)
		draw_circle(ap, 2, Color("#d0d0d0"))
	_draw_hp(p + Vector2(0, -20), u.hp, u.max_hp, 28)


## Rider (civ-colored ball) on a brown horse, lance pointing forward.
func _draw_cavalry(u: Dictionary, p: Vector2, color: Color, now: float) -> void:
	var dir := -1.0 if u.team == Battlefield.PLAYER else 1.0
	var gait := sin(now * 14.0 + u.side * 5.0) * 2.0 if u.target == "" else 0.0
	var horse := Color("#7a4a26")
	draw_rect(Rect2(p + Vector2(-14, 2), Vector2(28, 11)), horse)  # body
	draw_rect(Rect2(p + Vector2(10, -6), Vector2(7, 12)), horse)  # neck/head
	for x in [-11, -5, 5, 10]:  # legs
		draw_line(p + Vector2(x, 13), p + Vector2(x + gait * (1 if x > 0 else -1), 22), horse.darkened(0.3), 3)
	_draw_ball(p + Vector2(-2, -4), FIGHTER_R - 2, color)
	var lance_from := p + Vector2(4, -6)
	var swing := sin(now * 10.0 + u.side * 7.0) * 0.3 if u.target != "" else 0.0
	draw_line(lance_from, lance_from + Vector2.from_angle(PI / 2 * dir + PI + 0.6 * dir + swing) * -26, COLORS.stick, 3)
	_draw_hp(p + Vector2(0, -24), u.hp, u.max_hp, 32)


## A ball holding a stick; the stick swings while attacking.
func _draw_fighter(u: Dictionary, p: Vector2, color: Color, now: float) -> void:
	var facing := -PI / 2 if u.team == Battlefield.PLAYER else PI / 2
	var hand := p + Vector2.from_angle(facing + PI / 2) * FIGHTER_R * 0.8
	var angle := facing + 0.5  # stick held forward-right at rest
	if u.target != "":
		angle = facing + 0.2 + sin(now * 12.0 + u.side * 7.0) * 0.9
	draw_line(hand, hand + Vector2.from_angle(angle) * 20, COLORS.stick, 4)
	_draw_ball(p, FIGHTER_R, color)
	_draw_hp(p + Vector2(0, -20), u.hp, u.max_hp, 28)


## Villager ball: farmers bob, lumberjacks swing an axe, walkers carry their load.
func _draw_worker(p: Vector2, w: Dictionary, now: float, olives := false) -> void:
	var phase: float = w.spot * 1.7
	if w.phase == "gather":
		if w.job == "food":
			p.y += sin(now * 6.0 + phase) * 2.5
			var hoe := sin(now * 6.0 + phase) * 0.6
			draw_line(p + Vector2(6, 0), p + Vector2(6, 0) + Vector2.from_angle(PI / 2 - hoe) * 14, COLORS.stick, 3)
		else:  # lumberjacks and miners swing a tool
			var swing := sin(now * 9.0 + phase)
			var axe_end := p + Vector2(7, -2) + Vector2.from_angle(-0.9 + swing * 0.9) * 15
			draw_line(p + Vector2(7, -2), axe_end, COLORS.stick, 3)
			draw_rect(Rect2(axe_end - Vector2(3, 3), Vector2(6, 6)), COLORS.stone)
	_draw_ball(p, VILLAGER_R, COLORS.villager)
	if w.phase == "to_drop":
		var load_color: Color = {"food": COLORS.olive if olives else COLORS.crop, "wood": COLORS.wood, "gold": Color("#f1c40f"), "stone": Color("#d5d8dc")}[w.job]
		draw_rect(Rect2(p + Vector2(-6, -VILLAGER_R - 10), Vector2(12, 9)), load_color)
		draw_rect(Rect2(p + Vector2(-6, -VILLAGER_R - 10), Vector2(12, 9)), Color.BLACK, false, 1.5)


func _draw_farm(area: Rect2) -> void:
	draw_rect(area, COLORS.farm)
	var cell := area.size / Vector2(FARM_COLS, FARM_ROWS)
	for i in FARM_COLS * FARM_ROWS:
		var plot := Rect2(area.position + cell * Vector2(i % FARM_COLS, i / FARM_COLS), cell).grow(-4)
		draw_rect(plot, COLORS.farm.darkened(0.12))
		for k in 4:  # a few wheat stalks per plot
			var base := plot.position + Vector2(plot.size.x * (0.2 + 0.2 * k), plot.size.y * 0.85)
			draw_line(base, base + Vector2(0, -plot.size.y * 0.55), COLORS.crop_stem, 2)
			draw_circle(base + Vector2(0, -plot.size.y * 0.6), 3, COLORS.crop)


func _draw_tree(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(1.25, 1.25))
	c = Vector2.ZERO
	draw_rect(Rect2(c + Vector2(-3, 2), Vector2(6, 14)), COLORS.trunk)
	draw_circle(c + Vector2(0, -4), 15, COLORS.leaf_dark)
	draw_circle(c + Vector2(-5, -9), 8, COLORS.leaf_light)
	draw_circle(c + Vector2(5, -2), 6, COLORS.leaf_light.darkened(0.15))
	draw_set_transform(Vector2.ZERO)


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
	draw_rect(area, Color("#b5a46a"))
	var cell := area.size / Vector2(FARM_COLS, FARM_ROWS)
	for i in FARM_COLS * FARM_ROWS:
		var c := area.position + cell * Vector2(i % FARM_COLS + 0.5, i / FARM_COLS + 0.5)
		draw_line(c + Vector2(0, 12), c + Vector2(-2, 0), COLORS.trunk, 3)
		draw_circle(c + Vector2(-2, -6), 11, COLORS.olive)
		draw_circle(c + Vector2(3, -9), 7, COLORS.olive_leaf)
		for k in 3:  # olives
			draw_circle(c + Vector2(-7 + k * 5, -3 + (k % 2) * 3), 1.8, Color("#2d3a1a"))


## Olive press: stone basin with a crushing wheel, a wooden lever beam, and
## amphorae of oil.
func _draw_olive_press(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	draw_rect(Rect2(-18, -2, 30, 16), COLORS.plaster)  # little press house
	draw_colored_polygon(PackedVector2Array([Vector2(-21, -2), Vector2(-3, -13), Vector2(15, -2)]), COLORS.terracotta)
	draw_rect(Rect2(-6, 4, 7, 10), Color("#2b1d10"))
	draw_circle(Vector2(18, 10), 7, COLORS.stone)  # basin
	draw_circle(Vector2(18, 7), 4, COLORS.stone.darkened(0.2))  # wheel
	draw_line(Vector2(18, 7), Vector2(28, -4), COLORS.trunk, 2)  # lever
	for x in [-24, -19]:  # amphorae
		draw_circle(Vector2(x, 10), 3, COLORS.terracotta)
		draw_rect(Rect2(x - 1, 4, 2, 4), COLORS.terracotta.darkened(0.2))
	draw_set_transform(Vector2.ZERO)


## Classical lumber yard: tiled roof on two columns sheltering stacked logs.
func _draw_timber_yard(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	for x in [-18, 12]:
		draw_rect(Rect2(x, -6, 5, 20), COLORS.plaster)
	draw_colored_polygon(PackedVector2Array([Vector2(-22, -6), Vector2(-16, -16), Vector2(16, -16), Vector2(22, -6)]), COLORS.terracotta)
	for p in [Vector2(-8, 10), Vector2(0, 10), Vector2(8, 10), Vector2(-4, 4), Vector2(4, 4)]:
		draw_circle(p, 4, COLORS.wood)
		draw_circle(p, 1.8, COLORS.crop)
	draw_line(Vector2(20, 14), Vector2(28, 6), COLORS.stick, 2)  # saw horse
	draw_line(Vector2(28, 14), Vector2(20, 6), COLORS.stick, 2)
	draw_set_transform(Vector2.ZERO)


## Era III medieval food: round stone tower windmill with big sails and sacks.
func _draw_grand_mill(c: Vector2, now: float) -> void:
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	draw_rect(Rect2(-12, -14, 24, 30), COLORS.stone)
	draw_circle(Vector2(0, -14), 12, COLORS.stone)
	for y in [-6, 2, 10]:
		draw_line(Vector2(-12, y), Vector2(12, y), COLORS.stone.darkened(0.2), 1)
	draw_rect(Rect2(-4, 6, 8, 10), Color("#2b1d10"))
	var hub := Vector2(0, -16)
	for k in 4:
		var a := now * 1.2 + k * PI / 2
		var tip := hub + Vector2.from_angle(a) * 32
		draw_line(hub, tip, COLORS.trunk, 3)
		draw_line(tip, tip + Vector2.from_angle(a + PI / 2) * 9, Color("#f5f6fa"), 6)
	draw_circle(hub, 4, Color.BLACK)
	for p in [Vector2(18, 12), Vector2(24, 12), Vector2(21, 6)]:  # grain sacks
		draw_circle(p, 4, Color("#d9c49a"))
	draw_set_transform(Vector2.ZERO)


## Era III classical food: columned oil workshop with rows of amphorae.
func _draw_oil_workshop(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	draw_rect(Rect2(-22, 14, 44, 4), COLORS.marble_shade)
	draw_rect(Rect2(-18, -4, 36, 18), COLORS.plaster)
	for x in [-20, -8, 4, 16]:
		draw_rect(Rect2(x, -4, 4, 18), COLORS.marble)
	draw_colored_polygon(PackedVector2Array([Vector2(-24, -4), Vector2(0, -18), Vector2(24, -4)]), COLORS.terracotta)
	for i in 5:  # amphorae
		var p := Vector2(-22 + i * 6, 24)
		draw_circle(p, 3, COLORS.terracotta)
		draw_rect(Rect2(p.x - 1, p.y - 7, 2, 4), COLORS.terracotta.darkened(0.2))
	draw_set_transform(Vector2.ZERO)


## Era III medieval wood: sawmill with a turning water wheel and planks.
func _draw_sawmill(c: Vector2, now: float) -> void:
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	draw_rect(Rect2(-14, -6, 28, 22), COLORS.wood)
	draw_colored_polygon(PackedVector2Array([Vector2(-18, -6), Vector2(0, -20), Vector2(18, -6)]), Color("#4a3b35"))
	var wheel := Vector2(-20, 8)
	draw_circle(wheel, 10, Color("#3f6f8f"))
	draw_arc(wheel, 10, 0, TAU, 20, COLORS.trunk, 3)
	for k in 6:
		draw_line(wheel, wheel + Vector2.from_angle(now * 2.0 + k * PI / 3) * 10, COLORS.trunk, 2)
	draw_circle(Vector2(4, 4), 6, COLORS.stone)  # saw blade
	for k in 3:  # planks
		draw_rect(Rect2(16, 14 - k * 4, 16, 3), COLORS.wood.lightened(0.2))
	draw_set_transform(Vector2.ZERO)


## Era III classical wood: carpentry workshop with marble columns and planks.
func _draw_carpentry(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(1.5, 1.5))
	draw_rect(Rect2(-22, 14, 44, 4), COLORS.marble_shade)
	for x in [-20, -6, 8]:
		draw_rect(Rect2(x, -6, 5, 20), COLORS.marble)
	draw_rect(Rect2(-22, -9, 44, 4), COLORS.marble)
	draw_colored_polygon(PackedVector2Array([Vector2(-24, -9), Vector2(0, -20), Vector2(24, -9)]), COLORS.terracotta)
	for k in 3:
		draw_rect(Rect2(-16, 10 - k * 4, 26, 3), COLORS.wood.lightened(0.15))
	draw_line(Vector2(20, 14), Vector2(28, 6), COLORS.stick, 2)
	draw_line(Vector2(28, 14), Vector2(20, 6), COLORS.stick, 2)
	draw_set_transform(Vector2.ZERO)


## Barracks, archery range or stables around `c`. Era I: rough wood and
## straw for everyone; later medieval (dark roofs, timber) or classical
## (plaster, columns, terracotta), with the civ color on a banner or shield.
func _draw_military(id: String, c: Vector2, civ_color: Color, era: int, style: String) -> void:
	draw_set_transform(c, 0, Vector2(1.6, 1.6))
	var classical := style == "classical" and era >= 1
	var wall: Color = COLORS.plaster if classical else COLORS.wood
	var roof: Color = COLORS.terracotta if classical else (COLORS.farm.darkened(0.15) if era == 0 else Color("#4a3b35"))
	match id:
		"barracks":
			draw_rect(Rect2(-16, -4, 32, 18), wall)
			if classical:
				for x in [-15, -6, 3, 12]:
					draw_rect(Rect2(x, -4, 3, 18), COLORS.marble_shade)
			draw_colored_polygon(PackedVector2Array([Vector2(-19, -4), Vector2(0, -16), Vector2(19, -4)]), roof)
			draw_rect(Rect2(-4, 4, 8, 10), Color("#2b1d10"))
			draw_circle(Vector2(0, -8), 4, civ_color)  # shield emblem
			for k in 3:  # spear rack
				draw_line(Vector2(20 + k * 3, 14), Vector2(18 + k * 3, -6), COLORS.stick, 2)
		"archery_range":
			draw_rect(Rect2(-18, -2, 20, 16), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(-21, -2), Vector2(-8, -13), Vector2(5, -2)]), roof)
			if classical:
				for x in [-17, -5]:
					draw_rect(Rect2(x, -2, 3, 16), COLORS.marble_shade)
			var target := Vector2(16, 4)  # straw target on legs
			draw_line(target + Vector2(-4, 8), target + Vector2(-5, 13), COLORS.stick, 2)
			draw_line(target + Vector2(4, 8), target + Vector2(5, 13), COLORS.stick, 2)
			draw_circle(target, 8, Color("#e8d27a"))
			draw_circle(target, 5, Color.WHITE)
			draw_circle(target, 2.5, civ_color)
		"stables":
			draw_rect(Rect2(-18, -4, 36, 18), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(-21, -4), Vector2(-12, -14), Vector2(12, -14), Vector2(21, -4)]), roof)
			for x in [-12, 2]:  # stall doors / arches
				if classical:
					draw_rect(Rect2(x, 4, 10, 10), Color("#2b1d10"))
					draw_circle(Vector2(x + 5, 4), 5, Color("#2b1d10"))
				else:
					draw_rect(Rect2(x, 2, 10, 12), Color("#2b1d10"))
					draw_line(Vector2(x, 2), Vector2(x + 10, 14), COLORS.wood, 1.5)
			draw_circle(Vector2(24, 10), 5, COLORS.farm)  # hay bale
			draw_rect(Rect2(-5, -12, 10, 5), civ_color)
	draw_set_transform(Vector2.ZERO)


## Stone base, roof, and four blades turning slowly.
func _draw_mill(c: Vector2, now: float, scale: float) -> void:
	draw_set_transform(c, 0, Vector2(scale, scale))
	c = Vector2.ZERO
	draw_rect(Rect2(c + Vector2(-16, -6), Vector2(32, 30)), COLORS.stone)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -6), c + Vector2(0, -22), c + Vector2(20, -6)]), COLORS.wood)
	var hub := c + Vector2(0, -12)
	for k in 4:
		var a := now * 1.5 + k * PI / 2
		var tip := hub + Vector2.from_angle(a) * 26
		draw_line(hub, tip, COLORS.trunk, 3)
		draw_line(tip, tip + Vector2.from_angle(a + PI / 2) * 7, Color("#f5f6fa"), 5)
	draw_circle(hub, 4, Color.BLACK)
	draw_set_transform(Vector2.ZERO)


## Small hut with a pile of logs next to it.
func _draw_lumber_camp(c: Vector2, scale: float) -> void:
	draw_set_transform(c, 0, Vector2(scale, scale))
	c = Vector2.ZERO
	draw_rect(Rect2(c + Vector2(-18, -4), Vector2(30, 24)), COLORS.wood)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-22, -4), c + Vector2(-3, -20), c + Vector2(16, -4)]), COLORS.trunk)
	for k in 3:
		var log := c + Vector2(20 + (k % 2) * 8, 16 - (k / 2) * 8 - (k % 2) * 0)
		draw_circle(log, 4.5, COLORS.wood)
		draw_circle(log, 2, COLORS.crop)
	draw_set_transform(Vector2.ZERO)
