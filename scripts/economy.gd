class_name Economy
extends RefCounted
## Pure economy state for one player: resources, villagers, era.
## No UI here so it can be reused by the AI and tested headless.

signal changed

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
## Building upgrades the player chose, e.g. {"mill": true}. Only the town
## center changes with the era; everything else changes through these.
var upgrades := {}
## One entry per working villager: {"job", "phase", "t", "carry", "spot"}.
## phase: "gather" (filling up), "to_drop" (walking to mill/camp), "to_work" (walking back).
## t: 0..1 walk progress. spot: which crop plot / tree it works at.
var workers: Array[Dictionary] = []

var _cfg: Dictionary


func _init(civ: String, cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	civ_id = civ
	resources = _cfg.starting_resources.duplicate()
	villagers = {"idle": 0, "food": 0, "wood": 0, "gold": 0, "stone": 0}
	for job in _cfg.starting_villagers:
		for i in _cfg.starting_villagers[job]:
			villagers[job] += 1
			if job != "idle":
				_add_worker(job)


## Workers fill up to carry_capacity, walk to the drop-off, and only then
## does the load land in the stockpile (Age of Empires style).
func tick(delta: float) -> void:
	var g: Dictionary = _cfg.gathering
	for w in workers:
		match w.phase:
			"gather":
				w.carry = minf(w.carry + rate_per_villager(w.job) * delta, g.carry_capacity)
				if w.carry >= g.carry_capacity:
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


## Resources a villager picks up per second while gathering.
func rate_per_villager(res: String) -> float:
	var base: float = _cfg.gathering.rate_per_sec.get(res, 0.0)
	var bonus := 0.0
	for id in upgrades:
		bonus += _cfg.upgrades[id].get("gather_bonus", {}).get(res, 0.0)
	return base * civ().gather_multiplier.get(res, 1.0) * (1.0 + bonus)


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
func _remove_worker(job: String) -> void:
	for i in range(workers.size() - 1, -1, -1):
		if workers[i].job == job:
			workers.remove_at(i)
			return


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


func population() -> int:
	return total_villagers() + army_size


## Starting cap plus what huts add, never above the hard maximum.
func max_population() -> int:
	var cap: int = _cfg.population.starting_cap + huts * _cfg.buildings.hut.population
	return mini(cap, _cfg.population.max_cap)


func hut_cost() -> Dictionary:
	return _cfg.buildings.hut.cost


func can_build_hut() -> bool:
	return max_population() < _cfg.population.max_cap and can_afford(hut_cost())


func build_hut() -> bool:
	if not can_build_hut():
		return false
	_pay(hut_cost())
	huts += 1
	changed.emit()
	return true


func has_room() -> bool:
	return population() < max_population()


func villager_cost() -> Dictionary:
	return _cfg.villager_cost


func can_recruit() -> bool:
	return has_room() and can_afford(villager_cost())


## New villagers start idle until the player assigns them.
func recruit() -> bool:
	if not can_recruit():
		return false
	_pay(villager_cost())
	villagers.idle = villagers.get("idle", 0) + 1
	changed.emit()
	return true


## Food and wood are always available; gold and stone need their mine.
func can_work(job: String) -> bool:
	return job == "idle" or job == "food" or job == "wood" or mines.has(job)


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
	return not cost.is_empty() and can_afford(cost)


func advance() -> bool:
	if not can_advance():
		return false
	_pay(next_era_cost())
	era_index += 1
	changed.emit()
	return true


func mine_cost() -> Dictionary:
	return _cfg.buildings.mine.cost


func can_build_mine(res: String) -> bool:
	return era_index >= _cfg.buildings.mine.min_era and not mines.has(res) and can_afford(mine_cost())


func build_mine(res: String) -> bool:
	if not can_build_mine(res):
		return false
	_pay(mine_cost())
	mines[res] = true
	changed.emit()
	return true


## Whatever an upgrade builds on (an earlier upgrade or a mine) is in place.
func upgrade_unlocked(id: String) -> bool:
	var req: Dictionary = _cfg.upgrades[id].get("requires", {})
	if req.has("upgrade") and not upgrades.has(req.upgrade):
		return false
	if req.has("mine") and not mines.has(req.mine):
		return false
	return true


func can_upgrade(id: String) -> bool:
	var up: Dictionary = _cfg.upgrades[id]
	return not upgrades.has(id) and era_index >= up.min_era and upgrade_unlocked(id) and can_afford(up.cost)


func buy_upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	_pay(_cfg.upgrades[id].cost)
	upgrades[id] = true
	changed.emit()
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
