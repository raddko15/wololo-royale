class_name Crowd
extends RefCounted
## The troops' figures on the map, one per unit (map pixels). Each walks
## toward the spot the game wants it at (its goal) at its own pace, slows as
## it arrives and steers around the figures near it: it never jumps, and it
## never melts into the others. This only moves the pictures; who fights whom
## is worked out by the Battlefield.

## Spatial grid cell (pixels), at least the widest figure's room.
const CELL := 44.0
## How hard figures standing too close push each other apart.
const PUSH := 3.0

## Unit id -> {"pos", "vel", "facing"}.
var _agents := {}
## Unit id -> its own place in a walking group, kept for life.
var _place := {}
var _place_count := {}


## A unit's own place in its group on the march: x across the lane (-1 left
## edge .. 1 right edge), y how far back in the group (0 front .. 1 back).
## Spread evenly over the newcomers of each side and lane (a 2D low
## discrepancy sequence) and never changed, so a group keeps its shape
## through every order instead of lining up or shuffling.
func place(u: Dictionary) -> Vector2:
	if not _place.has(u.id):
		var key := "%d:%d" % [u.team, u.lane]
		var n: int = _place_count.get(key, 0)
		_place_count[key] = n + 1
		_place[u.id] = Vector2(fposmod(0.5 + n * 0.7548777, 1.0) * 2.0 - 1.0, fposmod(0.5 + n * 0.5698403, 1.0))
	return _place[u.id]


func position(id: int, fallback := Vector2.INF) -> Vector2:
	return _agents[id].pos if _agents.has(id) else fallback


func facing(id: int, fallback := 0.0) -> float:
	return _agents[id].facing if _agents.has(id) else fallback


func speed(id: int) -> float:
	return _agents[id].vel.length() if _agents.has(id) else 0.0


## Move every figure one step of `dt` seconds. Per unit (same order as
## `units`): its goal, pace (pixels/s), room (pixels across), what it looks at
## when standing (Vector2.INF: nothing) and which way is forward for it.
## Returns the figures' positions.
func step(units: Array, goals: Array[Vector2], paces: Array[float], rooms: Array[float], looks: Array[Vector2], forwards: Array[Vector2], dt: float) -> Array[Vector2]:
	var n := units.size()
	var ids: Array[int] = []
	var seen := {}
	for i in n:
		var id: int = units[i].id
		ids.append(id)
		seen[id] = true
		if not _agents.has(id):
			_agents[id] = {"pos": goals[i], "vel": Vector2.ZERO, "facing": forwards[i].angle()}
	for id in _agents.keys():
		if not seen.has(id):
			_agents.erase(id)
			_place.erase(id)
	# Who stands near whom: a grid of cells.
	var grid := {}
	for i in n:
		var cell := Vector2i((_agents[ids[i]].pos / CELL).floor())
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(i)
	var blend := clampf(dt * 10.0, 0.0, 1.0)
	var wants: Array[Vector2] = []
	wants.resize(n)
	for i in n:
		var a: Dictionary = _agents[ids[i]]
		var to_goal: Vector2 = goals[i] - a.pos
		var dist := to_goal.length()
		var pace: float = paces[i]
		# Its own pace; faster when left well behind; slowing on arrival.
		var top := pace * (1.0 if dist < 60.0 else 1.8)
		var want := Vector2.ZERO
		if dist > 0.5:
			want = to_goal / dist * minf(top, dist * 2.5)
		# Steer away from figures standing within its room.
		var push := Vector2.ZERO
		var cell := Vector2i((a.pos / CELL).floor())
		for cx in range(cell.x - 1, cell.x + 2):
			for cy in range(cell.y - 1, cell.y + 2):
				for j in grid.get(Vector2i(cx, cy), []):
					if j == i:
						continue
					var d: Vector2 = a.pos - _agents[ids[j]].pos
					var need := (rooms[i] + rooms[j]) * 0.5
					var l := d.length()
					if l >= need:
						continue
					if l < 0.01:
						d = Vector2(1.0 if ids[i] > ids[j] else -1.0, 0.0)
						l = 1.0
					var squeeze := (need - l) / need
					push += d / l * squeeze * (1.0 + squeeze)
		want += push * maxf(pace, 30.0) * PUSH
		wants[i] = want
	var out: Array[Vector2] = []
	out.resize(n)
	for i in n:
		var a: Dictionary = _agents[ids[i]]
		a.vel = a.vel.lerp(wants[i], blend)
		a.pos += a.vel * dt
		# Facing: the way it walks; standing, what it looks at, else forward.
		var face: float = forwards[i].angle()
		if a.vel.length() > 10.0:
			face = a.vel.angle()
		elif looks[i] != Vector2.INF and looks[i].distance_to(a.pos) > 1.0:
			face = (looks[i] - a.pos).angle()
		a.facing = lerp_angle(a.facing, face, blend)
		out[i] = a.pos
	return out
