class_name BattleView
extends Control
## Draws the whole portrait battlefield and turns taps into game actions.
## Both cities share one layout: the player's at the bottom, the enemy's
## mirrored at the top, with 3 lanes between the tower lines.

## A building of the player's was tapped: "town_center", "mill", "lumber_camp" or "towers".
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
}

var economy: Economy
var enemy_economy: Economy
var battle: Battlefield
## Card being dragged ("" when none) and where the finger is, in local coordinates.
var drag_card := ""
var drag_pos := Vector2.ZERO


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
	return _crect(team, 0.38, 0.24, 122, 88)


## Huts fill rows behind the town center, from the fort outward.
func hut_pos(team: int, i: int) -> Vector2:
	var area := _crect(team, 0.35, 0.30, 80, 5)
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
	var hover_lane := lane_at(drag_pos) if drag_card == "fighter" else -1
	for lane in Battlefield.LANES:
		var lane_color: Color = COLORS.lane
		if drag_card == "fighter":
			lane_color = Color("#f9ca24") if lane == hover_lane else COLORS.lane.lightened(0.2)
		var top := tower_line(Battlefield.ENEMY)
		draw_rect(Rect2((LANE_X[lane] - LANE_W / 2) * size.x, top, LANE_W * size.x, tower_line(Battlefield.PLAYER) - top), lane_color)
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
		_draw_fighter(u, positions[i], Color(econ(u.team).civ().color), now)
	for a in battle.arrows:
		var idx := battle.units.find(a.target)
		if idx != -1:
			_draw_arrow(a, positions[idx])


## Everything one side owns: farm, forest, mill, lumber camp, fort, huts,
## villagers and lane towers. Identical for both sides.
func _draw_city(team: int, now: float) -> void:
	var e := econ(team)
	var color := Color(e.civ().color)
	_draw_farm(farm_rect(team))
	for i in TREE_COLS * TREE_ROWS:
		_draw_tree(work_spot(team, "wood", i))
	# A granary hut and a lean-to until the player buys the windmill / lumber camp upgrades.
	if e.upgrades.has("mill"):
		_draw_mill(drop_off(team, "food"), now, 1.5)
	else:
		_draw_granary(drop_off(team, "food"))
	if e.upgrades.has("lumber_camp"):
		_draw_lumber_camp(drop_off(team, "wood"), 1.5)
	else:
		_draw_lean_to(drop_off(team, "wood"))
	for res in e.mines:
		_draw_mine(mine_pos(team, res), res)
	var tc := town_center(team)
	_draw_fort(tc, color, e.era_index, 1.0)
	# Health bar on the fort's back side: under the player's gate, above the enemy's flag.
	var bar_y := 50.0 if team == Battlefield.PLAYER else -95.0
	_draw_hp(tc + Vector2(0, bar_y), battle.buildings[team].main, battle.max_hp("main"), 110)
	for i in e.huts:
		_draw_hut(hut_pos(team, i))
	for w in e.workers:
		_draw_worker(worker_pos(team, w), w, now)
	for p in villager_spots(e.villagers.get("idle", 0), idle_area(team)):
		_draw_ball(p, VILLAGER_R, COLORS.villager)
	# Towers last so their health bars stay visible over the fields.
	if not battle.towers_built[team]:
		return
	for lane in Battlefield.LANES:
		_draw_tower(building_pos(team, "tower", lane), color, battle.buildings[team].towers[lane], e.upgrades.has("stone_towers"), battle.tower_max_hp[team])


## Town center, drawn around (0, 0). Both sides share this look:
## Era I a longhouse, Era II a wooden fort, Era III a stone castle.
func _draw_fort(c: Vector2, civ_color: Color, era: int, scale: float) -> void:
	draw_set_transform(c, 0, Vector2(scale, scale))
	if era == 0:
		_draw_longhouse(civ_color)
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
## dark entrance.
func _draw_mine(c: Vector2, res: String) -> void:
	var rock := Color("#7f7f7a")
	draw_colored_polygon(PackedVector2Array([c + Vector2(-22, 12), c + Vector2(-14, -8), c + Vector2(-2, -16), c + Vector2(12, -10), c + Vector2(22, 12)]), rock)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 12), c + Vector2(-6, 2), c + Vector2(0, -3), c + Vector2(6, 2), c + Vector2(6, 12)]), Color("#1b120a"))
	var bit := Color("#f1c40f") if res == "gold" else Color("#d5d8dc")
	for p in [Vector2(-13, 0), Vector2(11, -2), Vector2(-4, -10), Vector2(15, 7)]:
		if res == "gold":
			draw_circle(c + p, 3, bit)
		else:
			draw_rect(Rect2(c + p - Vector2(3, 3), Vector2(6, 5)), bit)


## Small wooden hut with a straw roof.
func _draw_hut(c: Vector2) -> void:
	draw_set_transform(c, 0, Vector2(0.85, 0.85))
	c = Vector2.ZERO
	draw_rect(Rect2(c + Vector2(-9, -3), Vector2(18, 12)), COLORS.wood)
	draw_rect(Rect2(c + Vector2(-2, 2), Vector2(4, 7)), Color("#2b1d10"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -3), c + Vector2(0, -13), c + Vector2(12, -3)]), COLORS.farm.darkened(0.2))
	draw_set_transform(Vector2.ZERO)


## Lane tower: a wooden watchtower, or stone after the Stone Towers upgrade, with an
## arrow slit and a civ-colored roof. Destroyed towers leave broken logs.
func _draw_tower(pos: Vector2, color: Color, hp: float, stone: bool, max_hp: float) -> void:
	draw_set_transform(pos, 0, Vector2(1.4, 1.4))
	var c := Vector2.ZERO
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
func _draw_worker(p: Vector2, w: Dictionary, now: float) -> void:
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
		var load_color: Color = {"food": COLORS.crop, "wood": COLORS.wood, "gold": Color("#f1c40f"), "stone": Color("#d5d8dc")}[w.job]
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
