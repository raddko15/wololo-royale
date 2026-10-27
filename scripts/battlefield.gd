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

const LANES := 3
const PLAYER := 0
const ENEMY := 1
const TOWER_Y := [0.0, 1.0]
const MAIN_DIST := [0.5, 0.12, 0.5]
## Slack so a unit that walked exactly to its range still counts as in range.
const REACH_EPS := 0.001

## buildings[team] = {"towers": [hp, hp, hp], "main": hp}. Towers start
## unbuilt (hp 0, nothing to fight) until build_towers() is called in Era II.
var buildings: Array = []
var towers_built := [false, false]
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


func _init(cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	for team in 2:
		buildings.append({"towers": [0.0, 0.0, 0.0], "main": float(_cfg.buildings.main.hp)})
		fort_max_hp[team] = float(_cfg.buildings.main.hp)
		tower_max_hp[team] = float(_cfg.buildings.tower.hp)


## A fort left alone for regen_delay_sec repairs itself slowly.
func _repair_forts(delta: float) -> void:
	var fort: Dictionary = _cfg.buildings.main
	for team in 2:
		fort_quiet[team] += delta
		if fort_quiet[team] >= fort.regen_delay_sec and buildings[team].main > 0:
			buildings[team].main = minf(buildings[team].main + fort.regen_per_sec * delta, fort_max_hp[team])


func fort_repairing(team: int) -> bool:
	return fort_quiet[team] >= _cfg.buildings.main.regen_delay_sec and buildings[team].main < fort_max_hp[team]


## A new era: the fort shoots (from Era II), gets tougher and is patched up.
func fort_new_era(team: int, era: int) -> void:
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


## All three lane towers of `team` at full health.
func build_towers(team: int) -> void:
	for lane in LANES:
		buildings[team].towers[lane] = tower_max_hp[team]
	towers_built[team] = true


## Stone towers: more maximum health, and standing towers gain the difference.
func upgrade_towers(team: int, hp_bonus: float) -> void:
	var extra := float(_cfg.buildings.tower.hp) * hp_bonus
	tower_max_hp[team] += extra
	for lane in LANES:
		if buildings[team].towers[lane] > 0:
			buildings[team].towers[lane] += extra


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
	var unit := {
		"team": team, "type": unit_id, "lane": lane, "y": TOWER_Y[team] + behind * MAIN_DIST[lane], "hp": hp,
		"max_hp": hp, "speed": stats.speed * (1.0 + bonus.get("speed", 0.0)), "dps": stats.damage_per_sec * (1.0 + bonus.get("damage", 0.0)),
		"range": stats.range * (1.0 + bonus.get("range", 0.0)), "tier": tier,
		# Damage multipliers against unit types, e.g. spears vs horses.
		"bonus_vs": stats.get("bonus_vs", {}),
		# How far ahead a horseman spots prey to charge past others for (0: never).
		"charge": stats.get("charge", 0.0),
		# What it is hitting this tick: "unit", "tower", "main" or "" when walking;
		# `foe` is the unit it hits when target is "unit".
		"target": "", "foe": null,
		# Sideways spread inside the lane (-1..1) so walking units don't overlap.
		"side": randf_range(-1.0, 1.0),
	}
	units.append(unit)
	return unit


func tick(delta: float) -> void:
	if winner != -1:
		return
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
	var dir := 1.0 if u.team == PLAYER else -1.0
	u.target = ""
	u.foe = null
	var foe = _best_target(u)
	var blocker = _blocker(u)
	# A charging rider with prey ahead does not stop for lesser foes.
	var charging: bool = blocker != null and u.charge > 0 and u.bonus_vs.get(blocker.type, 1.0) > 1.0
	if foe and charging and u.bonus_vs.get(foe.type, 1.0) <= 1.0:
		foe = null
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
	if absf(target_y - u.y) <= u.range + REACH_EPS:
		if buildings[enemy].towers[u.lane] > 0:
			buildings[enemy].towers[u.lane] -= u.dps * delta
			u.target = "tower"
		else:
			buildings[enemy].main -= u.dps * (1.0 - fort_armor[enemy]) * delta
			fort_quiet[enemy] = 0.0
			u.target = "main"
		return
	var step: float = u.speed * delta
	if blocker:
		step = minf(step, absf(blocker.y - u.y) - u.range)
	u.y += dir * maxf(minf(step, absf(target_y - u.y) - u.range), 0.0)


## The foe this unit hits now: among enemies in its lane within reach (in
## front or behind, e.g. riders that charged past), the one it does most
## damage to, then the nearest.
func _best_target(u: Dictionary):
	var best = null
	var best_mult := 0.0
	var best_dist := INF
	for o in units:
		if o.team == u.team or o.lane != u.lane or o.hp <= 0:
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
		var target = null
		for o in units:
			var dist := absf(o.y - fort_y(team, o.lane))
			if o.team != team and o.hp > 0 and dist <= fort.range:
				if target == null or dist < absf(target.y - fort_y(team, target.lane)):
					target = o
		if target:
			arrows.append({"team": team, "lane": target.lane, "from": "main", "target": target, "t": 0.0, "damage": fort.arrow_damage})
			main_cooldowns[team] = fort.attack_interval_sec
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
				arrows.append({"team": team, "lane": lane, "from": "tower", "target": best, "t": 0.0, "damage": stats.arrow_damage})
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
