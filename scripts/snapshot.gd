class_name Snapshot
extends RefCounted
## The state of a match packed for one player's screen (a network game's
## guest), and unpacked into a Mirror there. For the guest (team ENEMY on the
## host) everything is flipped so that their side becomes the bottom one:
## teams swap and lane positions y become 1 - y. Lanes keep their letters.
## Only plain arrays and dictionaries, so it travels with var_to_bytes.

const TARGETS := ["", "unit", "tower", "main"]


static func capture(game: Match, viewer: int, events: Array) -> Dictionary:
	var flip := viewer == Battlefield.ENEMY
	var b := game.battle
	var types: Array = GameConfig.data().units.keys()
	var units := []
	for u in b.units:
		var foe_id: int = u.foe.id if u.foe != null else 0
		units.append([u.id, _t(u.team, flip), types.find(u.type), u.lane, _y(u.y, flip), u.hp, u.max_hp, u.side,
			u.tier, TARGETS.find(u.target), foe_id, int(u.waiting) + 2 * int(u.moving), u.speed])
	var arrows := []
	for a in b.arrows:
		arrows.append([_t(a.team, flip), a.lane, a.get("from", "tower"), a.target.id, a.t])
	var snap := {
		"units": units, "arrows": arrows,
		"winner": b.winner if b.winner == -1 else _t(b.winner, flip), "paused": game.paused,
		"economies": [], "sides": [],
		"events": events.filter(func(e): return e.team == viewer),
	}
	for key in ["buildings", "towers_built", "tower_max_hp", "fort_armor", "fort_max_hp", "fort_quiet", "fort_armed", "lane_orders"]:
		var pair: Array = b.get(key)
		snap[key] = [pair[1], pair[0]] if flip else [pair[0], pair[1]]
	for local in 2:
		var team := _t(local, flip)
		snap.economies.append(_economy(game.economies[team]))
		snap.sides.append({"lanes_on": game.sides[team].lanes_on, "auto": game.sides[team].auto.keys()})
	return snap


static func _t(team: int, flip: bool) -> int:
	return 1 - team if flip else team


static func _y(y: float, flip: bool) -> float:
	return 1.0 - y if flip else y


static func _economy(e: Economy) -> Dictionary:
	return {
		"resources": e.resources, "villagers": e.villagers, "army_size": e.army_size, "huts": e.huts,
		"mines": e.mines, "camps": e.camps, "military": e.military, "upgrades": e.upgrades,
		"towers_up": e.towers_up, "era_index": e.era_index, "job_speed": e.job_speed,
		"workers": e.workers.map(func(w): return [w.job, w.phase, w.t, w.carry, w.spot]),
		"leaving": e.leaving.map(func(l): return [l.job, l.phase, l.t, l.carry, l.spot, l.from, l.t0]),
		"jobs": e.jobs.map(func(j): return [j.queue, j.kind, j.id, j.lane, j.t, j.total]),
	}


## Copy a snapshot into the mirror's battlefield and economies. Units keep
## their dictionaries between snapshots (the view keeps glide and heading
## state in them); units gone since the last snapshot fell (corpses).
static func restore(snap: Dictionary, battle: Battlefield, economies: Array) -> void:
	var types: Array = GameConfig.data().units.keys()
	var known := {}
	for u in battle.units:
		known[u.id] = u
	var units: Array[Dictionary] = []
	for row in snap.units:
		var u: Dictionary = known.get(int(row[0]), {})
		known.erase(int(row[0]))
		u.merge({"id": int(row[0]), "team": int(row[1]), "type": types[int(row[2])], "lane": int(row[3]), "y": row[4],
			"hp": row[5], "max_hp": row[6], "side": row[7], "tier": int(row[8]), "target": TARGETS[int(row[9])],
			"waiting": int(row[11]) & 1 != 0, "moving": int(row[11]) & 2 != 0, "speed": row[12]}, true)
		u["foe_id"] = int(row[10])
		units.append(u)
	var by_id := {}
	for u in units:
		by_id[u.id] = u
	for u in units:
		u["foe"] = by_id.get(u.foe_id, null)
	for gone in known.values():
		battle.fallen.append(gone)
	battle.units = units
	var arrows: Array[Dictionary] = []
	for row in snap.arrows:
		if by_id.has(int(row[3])):
			arrows.append({"team": int(row[0]), "lane": int(row[1]), "from": row[2], "target": by_id[int(row[3])], "t": row[4]})
	battle.arrows = arrows
	for key in ["buildings", "towers_built", "tower_max_hp", "fort_armor", "fort_max_hp", "fort_quiet", "fort_armed", "lane_orders"]:
		battle.set(key, snap[key])
	battle.winner = snap.winner
	for local in 2:
		var e: Economy = economies[local]
		var s: Dictionary = snap.economies[local]
		for key in ["resources", "villagers", "army_size", "huts", "mines", "camps", "military", "upgrades", "towers_up", "era_index", "job_speed"]:
			e.set(key, s[key])
		var workers: Array[Dictionary] = []
		for w in s.workers:
			workers.append({"job": w[0], "phase": w[1], "t": w[2], "carry": w[3], "spot": w[4]})
		e.workers = workers
		var leaving: Array[Dictionary] = []
		for l in s.get("leaving", []):
			leaving.append({"job": l[0], "phase": l[1], "t": l[2], "carry": l[3], "spot": l[4], "from": l[5], "t0": l[6]})
		e.leaving = leaving
		var jobs: Array[Dictionary] = []
		for j in s.jobs:
			jobs.append({"queue": j[0], "kind": j[1], "id": j[2], "lane": j[3], "t": j[4], "total": j[5]})
		e.jobs = jobs
