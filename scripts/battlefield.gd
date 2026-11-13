class_name Battlefield
extends RefCounted
## Lanes, buildings and units for both sides.
## Lane coordinate `y`: 0 = player's tower line, 1 = enemy's tower line.
## Each side has a road from its fort to each lane tower: straight for the
## middle lane, L-shaped for the outer ones. Units start at their own fort,
## walk their road, the lane, then the enemy's road to the enemy fort.
## MAIN_DIST[lane] is a road's length beyond the tower line, in lane units.

signal unit_died(team: int)
signal game_over(winner: int)
## A lane's shrine changed hands (team: its new owner).
signal shrine_taken(lane: int, team: int)

const LANES := 3
const PLAYER := 0
const ENEMY := 1
const TOWER_Y := [0.0, 1.0]
const MAIN_DIST := [0.5, 0.12, 0.5]
## Slack so a unit that walked exactly to its range still counts as in range.
const REACH_EPS := 0.001

## buildings[team] = {"towers": [hp, hp, hp], "main": hp}. Towers start
## unbuilt (hp 0, nothing to fight) until build_tower() raises one (from Era II).
var buildings: Array = []
## Per side and lane: whether a tower was ever built there (a destroyed one
## leaves a ruin until it is rebuilt).
var towers_built := [[false, false, false], [false, false, false]]
## Seconds since each tower was last hit: left alone, it repairs like the fort.
var tower_quiet := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
## Full health of each side's lane towers (raised by the stone towers upgrade).
var tower_max_hp := [0.0, 0.0]
var units: Array[Dictionary] = []
## Units that died since the view last looked (it leaves corpses for them).
var fallen: Array[Dictionary] = []
## Arrows in flight: {"team", "lane", "target": unit, "t": 0..1, "damage"}.
## Damage is applied when the arrow lands.
var arrows: Array[Dictionary] = []
## Seconds until each tower may shoot again: cooldowns[team][lane].
var cooldowns := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
var main_cooldowns := [0.0, 0.0]
var winner := -1
## Every unit gets a number of its own (network snapshots refer to units by it).
var _next_id := 0
## Standing orders per side and lane: "march" (walk on and fight), "stop"
## (halt where they are; new ones wait at the rally point in front of their
## tower) or "retreat" (walk back to the rally point and wait).
var lane_orders := [["march", "march", "march"], ["march", "march", "march"]]
## A holding unit within this of a foe defends itself.
const AGGRO := 0.25
## Rally point: just behind the tower (negative: on the road into town), and
## how much further back archers stand.
const RALLY := -0.03
const RALLY_DEPTH := {"archer": 0.035, "chariot": 0.035, "cavalry": 0.015, "knight": 0.015}

## Whether each side's fort shoots: not in Era I, from Era II on.
var fort_armed := [false, false]
## Share of damage each fort shrugs off (rises with each era).
var fort_armor := [0.0, 0.0]
## Seconds since each fort was last hit; after a while it slowly repairs.
var fort_quiet := [0.0, 0.0]
## Full health of each fort, and armor a civ adds to every era's armor.
var fort_max_hp := [0.0, 0.0]
var _fort_extra_armor := [0.0, 0.0]

var _cfg: Dictionary
## Each lane's shrine, halfway along it: {"owner": -1 (a neutral obelisk) or
## the team holding it, "hp", "max_hp", "quiet"}. Troops marching on the
## enemy stop to break any shrine that isn't theirs; whoever breaks it takes
## it and raises their own (sturdier with each era), and it earns them faith.
const SHRINE_Y := 0.5
var shrines: Array = []
## Off (config shrine.enabled false): troops ignore the shrines (tests).
var shrines_on := true
var eras := [0, 0]


func _init(cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	for team in 2:
		buildings.append({"towers": [0.0, 0.0, 0.0], "main": float(_cfg.buildings.main.hp)})
		fort_max_hp[team] = float(_cfg.buildings.main.hp)
		tower_max_hp[team] = float(_cfg.buildings.tower.hp)
	shrines_on = _shrine_cfg().get("enabled", true)
	var hp: float = _shrine_cfg().neutral_hp
	for lane in LANES:
		shrines.append({"owner": -1, "hp": hp, "max_hp": hp, "quiet": 0.0})


func _shrine_cfg() -> Dictionary:
	return _cfg.get("shrine", {"neutral_hp": 400, "hp": [500, 800, 1200], "faith_per_sec": [1, 2, 3], "regen_delay_sec": 5, "regen_per_sec": 3})


## Health of `team`'s shrine in its era.
func shrine_hp(team: int) -> float:
	var hp: Array = _shrine_cfg().hp
	return float(hp[mini(eras[team], hp.size() - 1)])


## Faith per second `team` earns from the shrines it holds.
func faith_rate(team: int) -> float:
	var per: Array = _shrine_cfg().faith_per_sec
	var n := 0
	for s in shrines:
		if s.owner == team:
			n += 1
	return n * float(per[mini(eras[team], per.size() - 1)])


func shrines_held(team: int) -> int:
	return shrines.filter(func(s): return s.owner == team).size()


## Damage a lane's shrine; broken, it becomes `by`'s.
func _hit_shrine(lane: int, by: int, amount: float) -> void:
	var s: Dictionary = shrines[lane]
	s.quiet = 0.0
	var fence: float = s.get("fence", 0.0)
	if fence > 0.0:
		s["fence"] = fence - amount
		if s.fence >= 0.0:
			return
		amount = -s.fence
		s.fence = 0.0
	s.hp -= amount
	if s.hp <= 0.0:
		s.owner = by
		s.max_hp = shrine_hp(by)
		s.hp = s.max_hp
		s["fence"] = fence_hp[by]
		shrine_taken.emit(lane, by)


## A fort or tower left alone for regen_delay_sec repairs itself slowly
## (a destroyed tower stays down until it is rebuilt).
func _repair_forts(delta: float) -> void:
	var fort: Dictionary = _cfg.buildings.main
	var tower: Dictionary = _cfg.buildings.tower
	for team in 2:
		fort_quiet[team] += delta
		if fort_quiet[team] >= fort.regen_delay_sec and buildings[team].main > 0:
			buildings[team].main = minf(buildings[team].main + fort.regen_per_sec * delta, fort_max_hp[team])
		for lane in LANES:
			tower_quiet[team][lane] += delta
			var hp: float = buildings[team].towers[lane]
			if hp > 0 and hp < tower_max_hp[team] and tower_quiet[team][lane] >= tower.regen_delay_sec:
				buildings[team].towers[lane] = minf(hp + tower.regen_per_sec * delta, tower_max_hp[team])
			if hp > 0 and tower_quiet[team][lane] >= tower.regen_delay_sec:
				fences[team][lane] = minf(fences[team][lane] + _fence_regen() * delta, fence_hp[team])
			elif hp <= 0:
				fences[team][lane] = 0.0
	var sc := _shrine_cfg()
	for sh in shrines:
		sh.quiet += delta
		if sh.quiet >= sc.regen_delay_sec:
			sh.hp = minf(sh.hp + sc.regen_per_sec * delta, sh.max_hp)
			if sh.owner != -1:
				sh["fence"] = minf(sh.get("fence", 0.0) + _fence_regen() * delta, fence_hp[sh.owner])


func fort_repairing(team: int) -> bool:
	return fort_quiet[team] >= _cfg.buildings.main.regen_delay_sec and buildings[team].main < fort_max_hp[team]


## A new era: the fort shoots (from Era II), gets tougher and is patched up.
func fort_new_era(team: int, era: int) -> void:
	eras[team] = era
	# Its shrines are rebuilt grander (a temple, a church...): new health.
	for sh in shrines:
		if sh.owner == team:
			var extra: float = shrine_hp(team) - sh.max_hp
			sh.max_hp += extra
			sh.hp += extra
	var fort: Dictionary = _cfg.buildings.main
	fort_armed[team] = era >= 1
	fort_armor[team] = fort.era_armor[mini(era, fort.era_armor.size() - 1)] + _fort_extra_armor[team]
	buildings[team].main = minf(buildings[team].main + fort_max_hp[team] * fort.era_heal, fort_max_hp[team])


## A civ's sturdier fort (e.g. Franks): more health and a little armor.
func fort_civ_bonus(team: int, bonus: Dictionary) -> void:
	fort_max_hp[team] = float(_cfg.buildings.main.hp) * (1.0 + bonus.get("hp", 0.0))
	buildings[team].main = fort_max_hp[team]
	_fort_extra_armor[team] = bonus.get("armor", 0.0)
	fort_armor[team] += _fort_extra_armor[team]


## A lane tower of `team` goes up (again) at full health.
func build_tower(team: int, lane: int) -> void:
	buildings[team].towers[lane] = tower_max_hp[team]
	fences[team][lane] = fence_hp[team]
	towers_built[team][lane] = true
	tower_quiet[team][lane] = 0.0


## All three lane towers at once (tests).
func build_towers(team: int) -> void:
	for lane in LANES:
		build_tower(team, lane)


## Stone towers: more maximum health, and standing towers gain the difference.
func upgrade_towers(team: int, hp_bonus: float) -> void:
	var extra := float(_cfg.buildings.tower.hp) * hp_bonus
	tower_max_hp[team] += extra
	for lane in LANES:
		if buildings[team].towers[lane] > 0:
			buildings[team].towers[lane] += extra


## Palisades (forge upgrade): a fence round each tower and held shrine that
## takes the blows first. fence_hp: a full fence's health per team (0: none);
## fences[team][lane]: what is left of each tower's.
var fence_hp := [0.0, 0.0]
var fences := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]


func raise_fences(team: int, hp: float) -> void:
	fence_hp[team] = hp
	for lane in LANES:
		if buildings[team].towers[lane] > 0:
			fences[team][lane] = hp
	for sh in shrines:
		if sh.owner == team:
			sh["fence"] = hp


func _fence_regen() -> float:
	return float(_cfg.get("upgrades", {}).get("palisade", {}).get("fence_regen_per_sec", 8.0))


## Arrow damage multiplier from `team`'s forge upgrades (towers, fort, shrines).
var arrow_bonuses := [1.0, 1.0]


func arrow_bonus(team: int) -> float:
	return arrow_bonuses[team]


## Lane coordinate of `team`'s fort at the end of a lane's road.
func fort_y(team: int, lane: int) -> float:
	return TOWER_Y[team] + (-1.0 if team == PLAYER else 1.0) * MAIN_DIST[lane]


## `bonus` comes from the owner's upgrades ({"hp", "damage", "range"} as
## fractions); `tier` is how many upgrades it has, for its look.
## Spawns `count` side by side (a phalanx's three hoplites keep in line).
func spawn_squad(team: int, unit_id: String, lane: int, count: int, bonus := {}, tier := 0) -> void:
	for k in count:
		var u := spawn(team, unit_id, lane, bonus, tier)
		if count > 1:
			u.side = lerpf(-0.7, 0.7, float(k) / (count - 1))


func spawn(team: int, unit_id: String, lane: int, bonus := {}, tier := 0) -> Dictionary:
	var stats: Dictionary = _cfg.units[unit_id]
	var hp: float = stats.hp * (1.0 + bonus.get("hp", 0.0))
	var behind := -1.0 if team == PLAYER else 1.0
	_next_id += 1
	var unit := {
		"id": _next_id, "team": team, "type": unit_id, "lane": lane, "y": TOWER_Y[team] + behind * MAIN_DIST[lane], "hp": hp,
		"max_hp": hp, "speed": stats.speed * (1.0 + bonus.get("speed", 0.0)), "dps": stats.damage_per_sec * (1.0 + bonus.get("damage", 0.0)),
		"range": stats.range * (1.0 + bonus.get("range", 0.0)), "tier": tier,
		# Damage multipliers against unit types, e.g. spears vs horses.
		"bonus_vs": stats.get("bonus_vs", {}),
		# How far ahead a horseman spots prey to charge past others for (0: never).
		"charge": stats.get("charge", 0.0),
		# Share of its damage dealt to every other foe close by (horses, chariots).
		"trample": stats.get("trample", 0.0),
		# What it is hitting this tick: "unit", "tower", "main" or "" when walking;
		# `foe` is the unit it hits when target is "unit".
		"target": "", "foe": null,
		# Sideways spread inside the lane (-1..1) so walking units don't overlap.
		"side": randf_range(-1.0, 1.0),
		# `released`: sent off by a charge even though its order is stop.
		# `march`: the pace of the group it charged with (the slowest member)
		# until it meets the enemy. `waiting`: holding still under its order.
		"released": false, "march": 0.0, "moving": false, "waiting": false,
		# "siege": its place at a building it hits ("" when none).
		"siege": "",
	}
	if lane_orders[team][lane] != "march":
		_formation_side(unit)
	units.append(unit)
	return unit


## Gathered units line up: infantry in front across the lane, archers
## behind, horsemen on the flanks.
func _formation_side(u: Dictionary) -> void:
	if u.type in ["cavalry", "knight"]:
		u.side = (0.85 + randf() * 0.15) * (1.0 if randf() < 0.5 else -1.0)
	else:
		u.side = randf_range(-0.7, 0.7)
	u.rank = randf() * 0.03  # a little depth so they stand in ranks, not one pile


## Where `u` waits while it holds.
func rally_y(u: Dictionary) -> float:
	var forward := 1.0 if u.team == PLAYER else -1.0
	return TOWER_Y[u.team] + forward * (RALLY - RALLY_DEPTH.get(u.type, 0.0) - u.get("rank", 0.0))


## What `u` does now: its lane's order, unless a charge released it.
func current_order(u: Dictionary) -> String:
	return "march" if u.released else lane_orders[u.team][u.lane]


## Give a lane a new standing order; it applies to the troops already there
## too. On "march" the ones that were holding set off together.
func set_order(team: int, lane: int, what: String) -> void:
	if what == "march":
		charge(team, lane)
	lane_orders[team][lane] = what
	for u in units:
		if u.team == team and u.lane == lane:
			u.released = false
			if what != "march":
				u.march = 0.0
				_formation_side(u)


## Send everyone holding in a lane at once (all types); they march at the
## pace of the slowest so they arrive together.
func charge(team: int, lane: int) -> void:
	var group := units.filter(func(u): return u.team == team and u.lane == lane and current_order(u) != "march")
	if group.is_empty():
		return
	var pace: float = group.map(func(u): return u.speed).min()
	for u in group:
		u.released = true
		u.march = pace


## Units holding (stopped or retreated) in a lane.
func waiting_count(team: int, lane: int) -> int:
	return units.filter(func(u): return u.team == team and u.lane == lane and current_order(u) != "march").size()


func units_in(team: int, lane: int) -> int:
	return units.filter(func(u): return u.team == team and u.lane == lane).size()


func tick(delta: float) -> void:
	if winner != -1:
		return
	# How many melee troops each unit has on it (last tick's), so no more than
	# MAX_ON_FOE pile onto one foe.
	_melee_on.clear()
	for u in units:
		if u.foe != null and u.range < RANGED:
			_melee_on[u.foe.id] = _melee_on.get(u.foe.id, 0) + 1
	for u in units:
		_unit_act(u, delta)
	_towers_shoot(delta)
	_remove_dead()
	_repair_forts(delta)
	for team in 2:
		if buildings[team].main <= 0:
			winner = 1 - team
			game_over.emit(winner)


## Fight the nearest enemy unit ahead, else the lane tower, else the main building; otherwise walk.
## Fight the best enemy unit within reach, else the lane tower, else the main
## building; otherwise walk on. Everyone within reach of a foe fights at once
## (a brawl, not a queue of duels), each picking the foe it counters most.
## Horsemen charge: with a foe they counter (archers) a short way ahead, they
## ride past whatever stands in front instead of stopping for it.
func _unit_act(u: Dictionary, delta: float) -> void:
	# Its place at a building last tick (kept below while it still hits it).
	var had: String = u.get("siege", "")
	u.siege = ""
	var dir := 1.0 if u.team == PLAYER else -1.0
	u.target = ""
	var prev_foe = u.foe
	u.foe = null
	_defend_fort(u)
	var foe = _best_target(u, prev_foe)
	if foe != null and foe != prev_foe and u.range < RANGED:
		_melee_on[foe.id] = _melee_on.get(foe.id, 0) + 1
	var blocker = _blocker(u)
	if u.trample > 0:
		_trample(u, foe, delta)
	# A charging rider with prey ahead does not stop for lesser foes.
	var charging: bool = blocker != null and u.charge > 0 and u.bonus_vs.get(blocker.type, 1.0) > 1.0
	if foe and charging and u.bonus_vs.get(foe.type, 1.0) <= 1.0:
		foe = null
	u.moving = false
	var what := current_order(u)
	u.waiting = what != "march"
	# Behind its own tower line it is home: there it fights whatever comes.
	var at_home: bool = (u.y - TOWER_Y[u.team]) * dir <= 0.0
	if what == "retreat" and not (foe and at_home):
		# Walking back to the rally point: no stopping to fight on the way.
		var home := rally_y(u)
		if absf(home - u.y) > 0.002:
			var before_y: float = u.y
			u.y = move_toward(u.y, home, u.speed * delta)
			u.moving = not is_equal_approx(before_y, u.y)
			return
	if foe:
		foe.hp -= u.dps * u.bonus_vs.get(foe.type, 1.0) * delta
		u.target = "unit"
		u.foe = foe
		return
	var enemy: int = 1 - u.team
	var target_y: float
	if buildings[enemy].towers[u.lane] > 0:
		target_y = TOWER_Y[enemy]
	else:
		target_y = fort_y(enemy, u.lane)
	# A shrine not its own, not yet passed: break it first.
	var shrine: Dictionary = shrines[u.lane]
	if shrines_on and shrine.owner != u.team and (SHRINE_Y - u.y) * dir > -(u.range + REACH_EPS):
		target_y = SHRINE_Y
		if absf(target_y - u.y) <= u.range + REACH_EPS:
			var at := "shrine:%d" % u.lane
			if u.range < RANGED:
				if had != at and _sieging(at) >= SIEGE_SLOTS:
					u.target = "queue"
					return
				u.siege = at
			_hit_shrine(u.lane, u.team, u.dps * delta)
			u.target = "shrine"
			return
	elif absf(target_y - u.y) <= u.range + REACH_EPS:
		# Only so many fighters fit around a building: melee troops beyond
		# that wait behind for a place (archers and chariots shoot from back).
		var kind := "tower" if buildings[enemy].towers[u.lane] > 0 else "main"
		var spot := "%d:%s:%d" % [enemy, kind, u.lane]
		if u.range < RANGED:
			if had != spot and _sieging(spot) >= SIEGE_SLOTS:
				u.target = "queue"
				return
			u.siege = spot
		if buildings[enemy].towers[u.lane] > 0:
			var blow: float = u.dps * delta
			var fence: float = fences[enemy][u.lane]
			if fence > 0.0:
				fences[enemy][u.lane] = maxf(fence - blow, 0.0)
				blow = maxf(blow - fence, 0.0)
			buildings[enemy].towers[u.lane] -= blow
			tower_quiet[enemy][u.lane] = 0.0
			u.target = "tower"
		else:
			buildings[enemy].main -= u.dps * (1.0 - fort_armor[enemy]) * delta
			fort_quiet[enemy] = 0.0
			u.target = "main"
		return
	var pace: float = u.speed
	if u.march > 0:
		# Marching with its group until the enemy is near.
		if blocker != null and absf(blocker.y - u.y) < AGGRO:
			u.march = 0.0
		else:
			pace = u.march
	var step: float = pace * delta
	if blocker:
		step = minf(step, absf(blocker.y - u.y) - u.range)
	var limit: float = absf(target_y - u.y) - u.range
	if what != "march" and (blocker == null or absf(blocker.y - u.y) > AGGRO):
		# Holding: new ones walk up to the rally point, the rest halt in place.
		limit = maxf((rally_y(u) - u.y) * dir, 0.0)
	var before: float = u.y
	u.y += dir * maxf(minf(step, limit), 0.0)
	u.moving = not is_equal_approx(before, u.y)


## Every lane's road ends at the fort, so troops standing there (new
## recruits) cross to whichever lane the enemy attacks the fort from, and go
## back to their own lane once it is clear.
const FORT_GUARD := 0.06
const FORT_THREAT := 0.12


func _defend_fort(u: Dictionary) -> void:
	if absf(u.y - fort_y(u.team, u.lane)) > FORT_GUARD:
		return
	var threat = null
	for o in units:
		if o.team != u.team and o.hp > 0 and absf(o.y - fort_y(u.team, o.lane)) <= FORT_THREAT:
			if o.lane == u.lane:
				return  # its own lane is under attack: it fights there
			if threat == null or absf(o.y - fort_y(u.team, o.lane)) < absf(threat.y - fort_y(u.team, threat.lane)):
				threat = o
	if threat != null:
		if not u.has("home_lane"):
			u["home_lane"] = u.lane
		u.y = fort_y(u.team, threat.lane) + (u.y - fort_y(u.team, u.lane))
		u.lane = threat.lane
	elif u.has("home_lane"):
		u.y = fort_y(u.team, u.home_lane) + (u.y - fort_y(u.team, u.lane))
		u.lane = u.home_lane
		u.erase("home_lane")


## Melee troops that can hit one building (per lane) at once: the front rank
## right at its walls (the rest queue behind); ranged ones (range from RANGED
## up) are never short of room. And at most MAX_ON_FOE melee troops fight one
## unit at a time.
const SIEGE_SLOTS := 7
const MAX_ON_FOE := 3
var _melee_on := {}
const RANGED := 0.1


func _sieging(spot: String) -> int:
	var n := 0
	for o in units:
		if o.get("siege", "") == spot:
			n += 1
	return n


## Hooves and wheels: every foe in its lane right next to it (other than the
## one it is fighting) takes a share of its damage, also while it rides past.
const TRAMPLE_REACH := 0.04


func _trample(u: Dictionary, target, delta: float) -> void:
	for o in units:
		if o.team != u.team and o.lane == u.lane and o.hp > 0 and o != target \
				and absf(o.y - u.y) <= TRAMPLE_REACH:
			o.hp -= u.dps * u.trample * delta


## The foe this unit hits now: among enemies in its lane within reach (in
## front or behind, e.g. riders that charged past), the one it does most
## damage to, then the nearest.
func _best_target(u: Dictionary, prev = null):
	var best = null
	var best_mult := 0.0
	var best_dist := INF
	var melee: bool = u.range < RANGED
	for o in units:
		if o.team == u.team or o.lane != u.lane or o.hp <= 0:
			continue
		# Only so many can reach one foe hand to hand; the rest wait behind
		# (or pick another foe in reach). Archers shoot over them.
		if melee and o != prev and _melee_on.get(o.id, 0) >= MAX_ON_FOE:
			continue
		var dist := absf(o.y - u.y)
		if dist > u.range + REACH_EPS:
			continue
		var mult: float = u.bonus_vs.get(o.type, 1.0)
		if mult > best_mult + 0.01 or (absf(mult - best_mult) <= 0.01 and dist < best_dist):
			best = o
			best_mult = mult
			best_dist = dist
	return best


## What this unit stops for: the nearest foe ahead, or for a charging unit
## the nearest foe ahead it counters, if one is within charge distance.
func _blocker(u: Dictionary):
	var nearest = null
	var prey = null
	var dir := 1.0 if u.team == PLAYER else -1.0
	var charge: float = u.get("charge", 0.0)
	for o in units:
		if o.team == u.team or o.lane != u.lane or o.hp <= 0:
			continue
		var ahead: float = (o.y - u.y) * dir
		if ahead < -0.01:
			continue
		if nearest == null or ahead < (nearest.y - u.y) * dir:
			nearest = o
		if charge > 0 and ahead <= charge and u.bonus_vs.get(o.type, 1.0) > 1.0:
			if prey == null or ahead < (prey.y - u.y) * dir:
				prey = o
	return prey if prey != null else nearest


## Each living tower shoots an arrow at the closest enemy in its own lane
## within range, once per attack interval. Forts shoot at enemies close to
## them in any lane (from Era II), so a side without towers is not defenseless.
func _towers_shoot(delta: float) -> void:
	var fort: Dictionary = _cfg.buildings.main
	for team in 2:
		main_cooldowns[team] = maxf(main_cooldowns[team] - delta, 0.0)
		if not fort_armed[team] or buildings[team].main <= 0 or main_cooldowns[team] > 0:
			continue
		# One arrow a volley in Era II, more later, each at a different foe
		# (the nearest first).
		var near: Array = units.filter(func(o): return o.team != team and o.hp > 0 and absf(o.y - fort_y(team, o.lane)) <= fort.range)
		near.sort_custom(func(a, b): return absf(a.y - fort_y(team, a.lane)) < absf(b.y - fort_y(team, b.lane)))
		var volley: Array = fort.get("arrows_per_era", [1, 1, 1])
		for o in near.slice(0, volley[mini(eras[team], volley.size() - 1)]):
			arrows.append({"team": team, "lane": o.lane, "from": "main", "target": o, "t": 0.0, "damage": fort.arrow_damage * arrow_bonus(team)})
		if not near.is_empty():
			main_cooldowns[team] = fort.attack_interval_sec
	# A held shrine shoots at foes in its lane near it.
	var sc := _shrine_cfg()
	if shrines_on:
		for lane in LANES:
			var sh: Dictionary = shrines[lane]
			sh["cooldown"] = maxf(sh.get("cooldown", 0.0) - delta, 0.0)
			if sh.owner == -1 or sh.cooldown > 0:
				continue
			var mark = null
			for o in units:
				var dist := absf(o.y - SHRINE_Y)
				if o.team != sh.owner and o.hp > 0 and o.lane == lane and dist <= sc.get("range", 0.15):
					if mark == null or dist < absf(mark.y - SHRINE_Y):
						mark = o
			if mark:
				arrows.append({"team": sh.owner, "lane": lane, "from": "shrine", "target": mark, "t": 0.0, "damage": sc.get("arrow_damage", 5) * arrow_bonus(sh.owner)})
				sh.cooldown = sc.get("attack_interval_sec", 1.2)
	var stats: Dictionary = _cfg.buildings.tower
	for team in 2:
		for lane in LANES:
			cooldowns[team][lane] = maxf(cooldowns[team][lane] - delta, 0.0)
			if buildings[team].towers[lane] <= 0 or cooldowns[team][lane] > 0:
				continue
			var best = null
			for o in units:
				var dist := absf(o.y - TOWER_Y[team])
				if o.team != team and o.hp > 0 and o.lane == lane and dist <= stats.range:
					if best == null or dist < absf(best.y - TOWER_Y[team]):
						best = o
			if best:
				arrows.append({"team": team, "lane": lane, "from": "tower", "target": best, "t": 0.0, "damage": stats.arrow_damage * arrow_bonus(team)})
				cooldowns[team][lane] = stats.attack_interval_sec
	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		a.t += delta / stats.arrow_flight_sec
		if a.t >= 1.0:
			a.target.hp -= a.damage  # harmless if the target already died
			arrows.remove_at(i)


func _remove_dead() -> void:
	for i in range(units.size() - 1, -1, -1):
		if units[i].hp <= 0:
			var team: int = units[i].team
			fallen.append(units[i])
			if fallen.size() > 64:
				fallen.pop_front()  # nobody is collecting them (e.g. tests)
			units.remove_at(i)
			unit_died.emit(team)


func max_hp(kind: String) -> float:
	return _cfg.buildings[kind].hp
