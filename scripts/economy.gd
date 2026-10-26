class_name Economy
extends RefCounted
## Pure economy state for one player: resources, villagers, era.
## No UI here so it can be reused by the AI and tested headless.

signal changed
## A timed job finished: {"kind", "id", "lane"}. Units and towers need the
## battlefield, so whoever owns this economy spawns / builds them on this.
signal job_done(job: Dictionary)

const RESOURCES := ["food", "wood", "gold", "stone"]
const MINED := ["gold", "stone"]

var civ_id: String
var era_index := 0
var resources: Dictionary = {}
## Villagers per job, e.g. {"idle": 1, "food": 3, "wood": 2}. Idle ones gather nothing.
var villagers: Dictionary = {}
## Living military units; they count toward the population cap with villagers.
var army_size := 0
var huts := 0
## Mines built so far, e.g. {"gold": true}. Workers can only mine where one exists.
var mines := {}
## Farm and lumberjack built so far, e.g. {"farm": true}. Food and wood need them.
var camps := {}
## Extra gathering speed on top of civ and upgrades (the Hard AI's handicap).
var gather_bonus := 0.0
## Which camp each gathered resource needs.
const CAMP_FOR := {"food": "farm", "wood": "lumberjack"}
## Military buildings built so far, e.g. {"barracks": true}; each unlocks a unit.
var military := {}
## Building upgrades the player chose, e.g. {"mill": true}. Only the town
## center changes with the era; everything else changes through these.
var upgrades := {}
## One entry per working villager: {"job", "phase", "t", "carry", "spot"}.
## phase: "gather" (filling up), "to_drop" (walking to mill/camp), "to_work" (walking back).
## t: 0..1 walk progress. spot: which crop plot / tree it works at.
var workers: Array[Dictionary] = []
## Lane towers finished (they are built through a job like everything else).
var has_towers := false
## Everything ordered but not finished: {"queue", "kind", "id", "lane", "t", "total"}.
## Jobs in the same queue run one after another (e.g. villagers and the era at
## the town center); different queues run at the same time. Paid up front.
var jobs: Array[Dictionary] = []
## Multiplies how fast jobs progress (testing: the player's builds can run 10x faster).
var job_speed := 1.0

var _cfg: Dictionary


func _init(civ: String, cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	civ_id = civ
	resources = _cfg.starting_resources.duplicate()
	huts = _cfg.population.get("starting_huts", 0)
	villagers = {"idle": 0, "food": 0, "wood": 0, "gold": 0, "stone": 0}
	for job in _cfg.starting_villagers:
		for i in _cfg.starting_villagers[job]:
			villagers[job] += 1
			if job != "idle":
				_add_worker(job)


## Workers fill up to carry_capacity, walk to the drop-off, and only then
## does the load land in the stockpile (Age of Empires style). Also advances
## the front job of every queue.
func tick(delta: float) -> void:
	_tick_jobs(delta)
	var g: Dictionary = _cfg.gathering
	for w in workers:
		match w.phase:
			"gather":
				var cap: float = g.carry_capacity[w.job]
				w.carry = minf(w.carry + rate_per_villager(w.job) * delta, cap)
				if w.carry >= cap:
					w.phase = "to_drop"
					w.t = 0.0
			"to_drop":
				w.t += delta / g.walk_time_sec
				if w.t >= 1.0:
					resources[w.job] = resources.get(w.job, 0.0) + w.carry
					w.carry = 0.0
					w.phase = "to_work"
					w.t = 0.0
			"to_work":
				w.t += delta / g.walk_time_sec
				if w.t >= 1.0:
					w.phase = "gather"
	changed.emit()


# --- Timed jobs ---------------------------------------------------------

func _enqueue(queue: String, kind: String, id: String, total: float, lane := -1) -> void:
	jobs.append({"queue": queue, "kind": kind, "id": id, "lane": lane, "t": 0.0, "total": total})
	changed.emit()


## The job currently being worked on in each queue.
func active_jobs() -> Array[Dictionary]:
	var seen := {}
	var result: Array[Dictionary] = []
	for j in jobs:
		if not seen.has(j.queue):
			seen[j.queue] = true
			result.append(j)
	return result


func queue_length(queue: String) -> int:
	return jobs.filter(func(j): return j.queue == queue).size()


func is_pending(kind: String, id: String) -> bool:
	return jobs.any(func(j): return j.kind == kind and j.id == id)


func pending_count(kind: String) -> int:
	return jobs.filter(func(j): return j.kind == kind).size()


## Jobs that put up or rebuild something (they show scaffolding); idle
## villagers walk over and help with these.
const BUILD_KINDS := ["hut", "camp", "mine", "military", "towers", "upgrade", "era"]


## Idle villagers helping on each construction under way: {queue: count}.
## They are shared out evenly, oldest site first.
func builders() -> Dictionary:
	var sites := active_jobs().filter(func(j): return j.kind in BUILD_KINDS)
	var counts := {}
	if sites.is_empty():
		return counts
	for i in villagers.get("idle", 0):
		var q: String = sites[i % sites.size()].queue
		counts[q] = counts.get(q, 0) + 1
	return counts


func _tick_jobs(delta: float) -> void:
	var helpers := builders()
	var help: float = _cfg.get("construction", {}).get("help_per_idle_villager", 0.0)
	for j in active_jobs():
		j.t += delta * job_speed * (1.0 + help * helpers.get(j.queue, 0))
		if j.t >= j.total:
			_complete(j)


func _complete(j: Dictionary) -> void:
	jobs.erase(j)
	match j.kind:
		"villager":
			villagers.idle = villagers.get("idle", 0) + 1
		"unit":
			army_size += 1
		"era":
			era_index += 1
		"hut":
			huts += 1
		"mine":
			mines[j.id] = true
		"camp":
			camps[j.id] = true
		"military":
			military[j.id] = military.get(j.id, 0) + 1
		"upgrade":
			upgrades[j.id] = true
		"towers":
			has_towers = true
	job_done.emit(j)
	changed.emit()


## Finish every queued job right away (tests and debugging).
func finish_jobs() -> void:
	while not jobs.is_empty():
		_complete(jobs[0])


## Resources a villager picks up per second while gathering.
func rate_per_villager(res: String) -> float:
	var base: float = _cfg.gathering.rate_per_sec.get(res, 0.0)
	var bonus := 0.0
	for id in upgrades:
		bonus += _cfg.upgrades[id].get("gather_bonus", {}).get(res, 0.0)
	return base * civ().gather_multiplier.get(res, 1.0) * (1.0 + bonus + gather_bonus)


## New workers walk out from the drop-off to the first free plot/tree.
func _add_worker(job: String) -> void:
	var used := {}
	for w in workers:
		if w.job == job:
			used[w.spot] = true
	var spot := 0
	while used.has(spot):
		spot += 1
	workers.append({"job": job, "phase": "to_work", "t": 0.0, "carry": 0.0, "spot": spot})


## Removes the newest worker on `job`; whatever it carried is lost.
func _remove_worker(job: String) -> Dictionary:
	for i in range(workers.size() - 1, -1, -1):
		if workers[i].job == job:
			var w: Dictionary = workers[i]
			workers.remove_at(i)
			return w
	return {}


## Deletes a villager to free population: an idle one if any, else one from
## the busiest job. Returns {"job"} plus "worker" (its state, for where it
## stood) when it was working; {} when there are none.
func kill_villager() -> Dictionary:
	var job := "idle"
	if villagers.get("idle", 0) <= 0:
		for res in villagers:
			if res != "idle" and villagers[res] > villagers.get(job, 0):
				job = res
	if villagers.get(job, 0) <= 0:
		return {}
	villagers[job] -= 1
	var result := {"job": job}
	if job != "idle":
		result.worker = _remove_worker(job)
	changed.emit()
	return result


func civ() -> Dictionary:
	return _cfg.civs[civ_id]


## "classical" (Romans, Greeks) or "medieval" (Franks): how buildings look from Era II on.
func style() -> String:
	return civ().get("style", "medieval")


## Display name of an upgrade for this civ (Romans and Greeks press olives instead of milling).
func upgrade_name(id: String) -> String:
	return civ().get("upgrade_names", {}).get(id, _cfg.upgrades[id].name)


func era() -> Dictionary:
	return _cfg.eras[era_index]


func total_villagers() -> int:
	var n := 0
	for res in villagers:
		n += villagers[res]
	return n


## Living units plus villagers and units already queued (they reserve space).
func population() -> int:
	return total_villagers() + army_size + pending_count("villager") + pending_count("unit")


## Starting cap plus what huts add, never above the hard maximum.
func max_population() -> int:
	var cap: int = _cfg.population.starting_cap + huts * _cfg.buildings.hut.population
	return mini(cap, _cfg.population.max_cap)


func hut_cost() -> Dictionary:
	return _cfg.buildings.hut.cost


func can_build_hut() -> bool:
	var cap_after: int = _cfg.population.starting_cap + (huts + pending_count("hut")) * _cfg.buildings.hut.population
	return cap_after < _cfg.population.max_cap and can_afford(hut_cost())


## Huts go up side by side, each on its own site.
func build_hut() -> bool:
	if not can_build_hut():
		return false
	_pay(hut_cost())
	_enqueue("hut:%d" % (huts + pending_count("hut")), "hut", "hut", _cfg.buildings.hut.time)
	return true


func has_room() -> bool:
	return population() < max_population()


func villager_cost() -> Dictionary:
	return _cfg.villager_cost


func can_recruit() -> bool:
	return has_room() and can_afford(villager_cost())


## Trains at the town center; new villagers come out idle.
func recruit() -> bool:
	if not can_recruit():
		return false
	_pay(villager_cost())
	_enqueue("town_center", "villager", "villager", villager_time())
	return true


## Cancel the newest queued villager ("villager") or unit of type `id`
## ("unit"), with a full refund. False when none is queued.
func cancel(kind: String, id: String) -> bool:
	for i in range(jobs.size() - 1, -1, -1):
		if jobs[i].kind == kind and jobs[i].id == id:
			jobs.remove_at(i)
			var cost: Dictionary = villager_cost() if kind == "villager" else _cfg.units[id].cost
			for res in cost:
				resources[res] = resources.get(res, 0.0) + cost[res]
			changed.emit()
			return true
	return false


## Food and wood are always available; gold and stone need their mine.
func can_work(job: String) -> bool:
	if CAMP_FOR.has(job):
		return camps.has(CAMP_FOR[job])
	return job == "idle" or mines.has(job)


func reassign(from: String, to: String) -> bool:
	if villagers.get(from, 0) <= 0 or not can_work(to):
		return false
	villagers[from] -= 1
	villagers[to] = villagers.get(to, 0) + 1
	if from != "idle":
		_remove_worker(from)
	if to != "idle":
		_add_worker(to)
	changed.emit()
	return true


## Cost of the next era, or empty if already in the last one.
func next_era_cost() -> Dictionary:
	if era_index + 1 >= _cfg.eras.size():
		return {}
	return _cfg.eras[era_index + 1].advance_cost


func can_advance() -> bool:
	var cost := next_era_cost()
	return not cost.is_empty() and not is_pending("era", "next") and can_afford(cost)


## Researched at the town center, in the same queue as villagers.
func advance() -> bool:
	if not can_advance():
		return false
	_pay(next_era_cost())
	_enqueue("town_center", "era", "next", _cfg.eras[era_index + 1].time)
	return true


## Whether a building could go up now, cost aside: its era is reached and it is
## neither built (up to 3 of each military building) nor under way. `kind`
## is "military", "mine", "camp" or "towers".
func site_open(kind: String, id: String) -> bool:
	if is_pending(kind, id):
		return false
	match kind:
		"military":
			var camp: String = _cfg.military[id].get("requires_camp", "")
			return military.get(id, 0) < _cfg.max_of_each_military and era_index >= _cfg.military[id].min_era \
				and (camp == "" or camps.has(camp))
		"mine":
			return not mines.has(id) and era_index >= _cfg.buildings.mine.min_era
		"camp":
			return not camps.has(id)
	return not has_towers and era_index >= _cfg.buildings.towers.min_era


func can_build_military(id: String) -> bool:
	return site_open("military", id) and can_afford(_cfg.military[id].cost)


func build_military(id: String) -> bool:
	if not can_build_military(id):
		return false
	_pay(_cfg.military[id].cost)
	_enqueue("build:" + id, "military", id, _cfg.military[id].time)
	return true


func can_build_towers() -> bool:
	return site_open("towers", "towers") and can_afford(_cfg.buildings.towers.cost)


## All three lane towers at once; the owner raises them on job_done.
func build_towers() -> bool:
	if not can_build_towers():
		return false
	_pay(_cfg.buildings.towers.cost)
	_enqueue("build:towers", "towers", "towers", _cfg.buildings.towers.time)
	return true


## The building that trains `unit_id` exists (fighters need a barracks, etc.).
func unit_unlocked(unit_id: String) -> bool:
	return military.has(_cfg.units[unit_id].requires)


func can_train(unit_id: String) -> bool:
	return unit_unlocked(unit_id) and has_room() and can_afford(_cfg.units[unit_id].cost)


## Queues a unit at its building, bound for `lane`; job_done reports when it
## is ready to spawn. It reserves population right away.
func train(unit_id: String, lane := 0) -> bool:
	if not can_train(unit_id):
		return false
	var unit: Dictionary = _cfg.units[unit_id]
	_pay(unit.cost)
	# Every building of the type trains on its own: join the shortest queue.
	var best := ""
	for k in military.get(unit.requires, 0):
		var q := "%s#%d" % [unit.requires, k]
		if best == "" or queue_length(q) < queue_length(best):
			best = q
	_enqueue(best, "unit", unit_id, unit.time, lane)
	return true


## Seconds to train a villager: the town center works faster each era.
func villager_time() -> float:
	return _cfg.villager_time / era().get("villager_speed", 1.0)


## Military buildings of every kind together.
func military_count() -> int:
	var n := 0
	for id in military:
		n += military[id]
	return n


func mine_cost() -> Dictionary:
	return _cfg.buildings.mine.cost


func can_build_mine(res: String) -> bool:
	return site_open("mine", res) and can_afford(mine_cost())


func build_mine(res: String) -> bool:
	if not can_build_mine(res):
		return false
	_pay(mine_cost())
	_enqueue("build:mine:" + res, "mine", res, _cfg.buildings.mine.time)
	return true


## Farm (food) or lumberjack (wood): villagers can only gather there once it stands.
func can_build_camp(id: String) -> bool:
	return site_open("camp", id) and can_afford(_cfg.buildings[id].cost)


func build_camp(id: String) -> bool:
	if not can_build_camp(id):
		return false
	_pay(_cfg.buildings[id].cost)
	_enqueue("build:camp:" + id, "camp", id, _cfg.buildings[id].time)
	return true


## Whatever an upgrade builds on (an earlier upgrade or a mine) is in place.
func upgrade_unlocked(id: String) -> bool:
	var req: Dictionary = _cfg.upgrades[id].get("requires", {})
	if req.has("upgrade") and not upgrades.has(req.upgrade):
		return false
	var site := upgrade_site(id)
	if site == "mill" and not camps.has("farm") or site == "lumber_camp" and not camps.has("lumberjack"):
		return false
	if req.has("mine") and not mines.has(req.mine):
		return false
	if req.has("military") and not military.has(req.military):
		return false
	return true


## How many military upgrades a unit type has (0-2): drives its look.
func unit_tier(unit_id: String) -> int:
	return upgrades.keys().filter(func(id): return _cfg.upgrades[id].get("unit", "") == unit_id).size()


## Summed stat bonuses from upgrades for a unit type, e.g. {"hp": 0.8, "damage": 0.6}.
func unit_bonus(unit_id: String) -> Dictionary:
	var total := {}
	for id in upgrades:
		var up: Dictionary = _cfg.upgrades[id]
		if up.get("unit", "") == unit_id:
			for stat in up.unit_bonus:
				total[stat] = total.get(stat, 0.0) + up.unit_bonus[stat]
	return total


func can_upgrade(id: String) -> bool:
	var up: Dictionary = _cfg.upgrades[id]
	return not upgrades.has(id) and not is_pending("upgrade", id) and era_index >= up.min_era \
		and upgrade_unlocked(id) and can_afford(up.cost)


## Which building an upgrade works on, so its scaffolding can be drawn there.
static func upgrade_site(id: String) -> String:
	if id.begins_with("mill"):
		return "mill"
	if id.begins_with("lumber_camp"):
		return "lumber_camp"
	if id == "stone_towers":
		return "towers"
	for b in ["barracks", "archery_range", "stables"]:
		if id.begins_with(b):
			return b
	return id.trim_suffix("_mine2")  # "gold" / "stone"


func buy_upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	_pay(_cfg.upgrades[id].cost)
	_enqueue("upgrade:" + upgrade_site(id), "upgrade", id, _cfg.upgrades[id].time)
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	_pay(cost)
	changed.emit()
	return true


func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if resources.get(res, 0.0) < cost[res]:
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for res in cost:
		resources[res] -= cost[res]
