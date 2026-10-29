## Snapshot of an earlier EnemyAI, kept as a sparring partner for tests/ai_sim.gd
## ("old:hard" etc.). Refresh it from scripts/enemy_ai.gd before a tuning round.

extends RefCounted
## The computer opponent. Works through a build order (lumberjack, farm,
## barracks, Era II, towers, workshop upgrades, archery range, gold mine,
## stables, unit upgrades, stone mine, Era III, ...), saving up for the next
## step while it keeps recruiting villagers, building huts before it runs out
## of room and moving workers to whatever resource that step is short of.
## Its army: a minimum guard per era, defenders sent to any lane the enemy is
## pushing, units that counter what the enemy fields (archers against
## fighters, cavalry against archers), and attacks focused on the enemy lane
## that is weakest. Difficulty (config ai.difficulty) sets how many villagers
## it aims for, how often it thinks, a gathering bonus, and whether it plays
## the lanes smartly or sends units at random.

var economy: Economy
var battle: Battlefield
var difficulty: String
var team: int
var _cfg: Dictionary
var _d: Dictionary  # this difficulty's settings
var _timer := 0.0
var _focus_lane := -1
var _focus_left := 0.0


func _init(civ_id: String, field: Battlefield, level := "normal", side := Battlefield.ENEMY, cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	difficulty = level
	team = side
	_d = cfg.ai.difficulty[level]
	economy = Economy.new(civ_id, cfg)
	economy.gather_bonus = _d.get("gather_bonus", 0.0)
	battle = field
	battle.fort_civ_bonus(team, economy.civ().get("fort_bonus", {}))
	battle.unit_died.connect(func(t): if t == team: economy.army_size -= 1)
	economy.job_done.connect(_on_job_done)


## Finished jobs that touch the battlefield: units walk out, towers go up.
func _on_job_done(job: Dictionary) -> void:
	match job.kind:
		"unit":
			battle.spawn_squad(team, job.id, job.lane, economy.squad(job.id), economy.unit_bonus(job.id), economy.unit_tier(job.id))
		"towers":
			battle.build_tower(team)
		"era":
			battle.fort_new_era(team, economy.era_index)
		"upgrade":
			if job.id == "stone_towers":
				battle.upgrade_towers(team, _cfg.upgrades.stone_towers.tower_hp_bonus)


func tick(delta: float) -> void:
	economy.tick(delta)
	_focus_left -= delta
	_timer += delta
	if _timer < _d.think_interval:
		return
	_timer = 0.0
	_think()


func _think() -> void:
	var goal := _next_goal()
	_assign_workers(goal)
	# Houses and villagers first: they keep the economy growing.
	if economy.population() >= economy.max_population() - 2 and not economy.is_pending("hut", "hut") \
			and economy.max_population() < _cfg.population.max_cap:
		economy.build_hut()
	if economy.total_villagers() + economy.pending_count("villager") < _d.target_villagers \
			and economy.pending_count("villager") < 2 and economy.has_room():
		economy.recruit()
	if not goal.is_empty() and economy.can_afford(goal.cost):
		goal.act.call()
		goal = _next_goal()
	_army(goal)


# --- Build order ------------------------------------------------------------

## The first step of the build order that is open now: {"cost", "act"}, or {}.
func _next_goal() -> Dictionary:
	var e := economy
	var steps := [
		["camp", "lumberjack"], ["camp", "farm"], ["military", "barracks"], ["mine", "gold"], ["era", "1"],
		["towers", ""], ["upgrade", "lumber_camp"], ["upgrade", "mill"], ["military", "archery_range"],
		["mine", "gold"], ["military", "stables"], ["upgrade", "barracks1"], ["upgrade", "archery_range1"],
		["upgrade", "stables1"], ["military", "barracks:2"], ["mine", "stone"], ["era", "2"],
		["upgrade", "stone_towers"], ["military", "archery_range:2"], ["military", "stables:2"],
		["upgrade", "mill2"], ["upgrade", "lumber_camp2"], ["upgrade", "barracks2"], ["upgrade", "archery_range2"],
		["upgrade", "stables2"], ["military", "barracks:3"], ["military", "stables:3"], ["upgrade", "gold_mine2"],
		["upgrade", "stone_mine2"],
	]
	for step in steps:
		var kind: String = step[0]
		var id: String = step[1]
		match kind:
			"camp":
				if e.site_open("camp", id):
					return {"cost": _cfg.buildings[id].cost, "act": e.build_camp.bind(id)}
			"military":
				# "barracks:2" = a second barracks.
				var nth := int(id.get_slice(":", 1)) if id.contains(":") else 1
				id = id.get_slice(":", 0)
				var enough: bool = id != "barracks" or e.total_villagers() >= _d.barracks_at_villagers
				if e.site_open("military", id) and enough and e.military.get(id, 0) < nth:
					return {"cost": _cfg.military[id].cost, "act": e.build_military.bind(id)}
			"era":
				var era_cost := e.next_era_cost()
				var ready: bool = e.total_villagers() >= _d.era_at_villagers[mini(e.era_index, _d.era_at_villagers.size() - 1)]
				if e.era_index + 1 == int(id) and not era_cost.is_empty() and not e.is_pending("era", "next") and ready:
					return {"cost": era_cost, "act": e.advance}
			"towers":
				if e.next_tower_lane() >= 0:
					return {"cost": _cfg.buildings.towers.cost, "act": e.build_tower}
			"mine":
				if e.site_open("mine", id):
					return {"cost": e.mine_cost(), "act": e.build_mine.bind(id)}
			"upgrade":
				var up: Dictionary = _cfg.upgrades[id]
				if not e.upgrades.has(id) and not e.is_pending("upgrade", id) and e.era_index >= up.min_era \
						and e.upgrade_unlocked(id):
					return {"cost": up.cost, "act": e.buy_upgrade.bind(id)}
	return {}


# --- Villagers --------------------------------------------------------------

## Share of workers per resource: a steady base, tilted toward whatever the
## next goal is still short of. Moves at most one worker per think so it
## does not shuffle villagers back and forth.
func _assign_workers(goal: Dictionary) -> void:
	var e := economy
	var weights := {"food": 0.5, "wood": 0.4, "gold": 0.0, "stone": 0.0}
	if e.mines.has("gold"):
		weights.gold = 0.25
	if e.mines.has("stone"):
		weights.stone = 0.1
	# Less of what is already piling up.
	for res in weights:
		weights[res] /= 1.0 + e.resources.get(res, 0.0) / 200.0
	if not goal.is_empty():
		var short := {}
		var total_short := 0.0
		for res in weights:
			short[res] = maxf(float(goal.cost.get(res, 0)) - e.resources.get(res, 0.0), 0.0)
			total_short += short[res]
		if total_short > 0:
			for res in weights:
				if res in Economy.MINED and not e.mines.has(res):
					continue
				weights[res] = weights[res] * 0.5 + short[res] / total_short
	var workable := weights.keys().filter(func(r): return e.can_work(r) and weights[r] > 0)
	if workable.is_empty():
		return
	var total_w := 0.0
	for r in workable:
		total_w += weights[r]
	var people := e.total_villagers()
	var gap := func(r: String) -> float: return weights[r] / total_w * people - e.villagers.get(r, 0)
	# Idle villagers go where the gap is largest...
	while e.villagers.get("idle", 0) > 0:
		var best: String = workable[0]
		for r in workable:
			if gap.call(r) > gap.call(best):
				best = r
		if not e.reassign("idle", best):
			break
	# ...and one worker moves from the most over-staffed job to the most under-staffed.
	var most: String = workable[0]
	var least: String = workable[0]
	for r in workable:
		if gap.call(r) > gap.call(most):
			most = r
		if gap.call(r) < gap.call(least):
			least = r
	if gap.call(most) >= 1.5 and gap.call(least) <= -1.5:
		e.reassign(least, most)


# --- Army -------------------------------------------------------------------

func _army(goal: Dictionary) -> void:
	var e := economy
	var threat := _threatened_lane() if _d.tactics else -1
	if threat == -1 and e.pending_count("unit") >= 2 * maxi(e.military_count(), 1):
		return  # enough queued
	var army := e.army_size + e.pending_count("unit")
	var guard: int = _d.min_army[mini(e.era_index, _d.min_army.size() - 1)]
	# Defend first; keep a minimum guard; otherwise only spend what the next goal does not need.
	var reserve: Dictionary = {}
	if threat == -1 and army >= guard:
		reserve = goal.get("cost", {}).duplicate()
		# Still growing: keep food for the next villager too.
		if e.total_villagers() + e.pending_count("villager") < _d.target_villagers:
			for res in e.villager_cost():
				reserve[res] = reserve.get(res, 0) + e.villager_cost()[res]
	if threat != -1 or army < guard or _surplus(reserve):
		var lane := threat if threat != -1 else _attack_lane()
		var unit := _pick_unit(reserve)
		if unit != "":
			e.train(unit, lane)


## Can it pay for a unit and still afford `reserve`?
func _surplus(reserve: Dictionary) -> bool:
	for id in _cfg.units:
		if _affordable_beyond(_cfg.units[id].cost, reserve) and economy.unit_unlocked(id):
			return true
	return false


## Can it pay `cost` and still keep `reserve` of each resource that cost uses?
func _affordable_beyond(cost: Dictionary, reserve: Dictionary) -> bool:
	for res in cost:
		if economy.resources.get(res, 0.0) - reserve.get(res, 0) < cost[res]:
			return false
	return true


## A lane where the enemy's units on our half outweigh ours there, or -1.
func _threatened_lane() -> int:
	var worst := -1
	var worst_gap := float(_d.defend_threshold_hp)
	for lane in Battlefield.LANES:
		var gap := 0.0
		for u in battle.units:
			if u.lane != lane or absf(u.y - Battlefield.TOWER_Y[team]) > 0.55:
				continue
			gap += u.hp if u.team != team else -u.hp
		if gap > worst_gap:
			worst_gap = gap
			worst = lane
	return worst


## Where to attack: the enemy lane with the weakest defence (its units there
## plus a share of its tower), kept for a while so units arrive together.
func _attack_lane() -> int:
	if not _d.tactics:
		return randi() % Battlefield.LANES
	if _focus_lane != -1 and _focus_left > 0:
		return _focus_lane
	var foe := 1 - team
	var best := 0
	var best_score := INF
	for lane in Battlefield.LANES:
		var score: float = battle.buildings[foe].towers[lane] * 0.3 + randf() * 40.0
		for u in battle.units:
			if u.lane == lane:
				score += u.hp if u.team == foe else -u.hp * 0.5
		if score < best_score:
			best_score = score
			best = lane
	_focus_lane = best
	_focus_left = _d.focus_sec
	return best


## A unit it can train now without touching `reserve`: archers are favoured
## against fighters, cavalry against archers, fighters against cavalry, and
## its civ's unique unit (Era III) most of all.
func _pick_unit(reserve: Dictionary) -> String:
	var e := economy
	var weight := {"fighter": 1.0, "archer": 1.0, "cavalry": 1.0}
	if _d.tactics:
		for u in battle.units:
			if u.team != team:
				match u.type:
					"fighter":
						weight.archer += 1.0
					"archer":
						weight.cavalry += 1.0
					"cavalry", "knight", "chariot":
						weight.fighter += 1.0
						weight.phalanx = weight.get("phalanx", 2.5) + 2.0  # spears vs horses
	var options := []
	var total := 0.0
	for id in _cfg.units:
		if not e.can_train(id):
			continue
		if not weight.has(id):
			weight[id] = 2.5  # its civ's unique unit: a favourite once unlocked
		if _affordable_beyond(_cfg.units[id].cost, reserve):
			options.append(id)
			total += weight[id]
	if options.is_empty():
		return ""
	var roll := randf() * total
	for id in options:
		roll -= weight[id]
		if roll <= 0:
			return id
	return options[-1]
