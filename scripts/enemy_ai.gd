class_name EnemyAI
extends RefCounted
## A deliberately simple opponent: builds its lumberjack and farm, keeps villagers busy, builds huts near the
## population cap, recruits a few villagers, keeps a small army while saving
## up for Era II, builds its towers, and otherwise sends a unit down a random
## lane whenever it can afford one. It builds a barracks first; after its
## towers it buys the windmill and lumber camp, then an archery range and
## stables and a gold mine (for cavalry), and trains a random mix. It does not
## mine stone or go past Era II.

var economy: Economy
var battle: Battlefield
var _cfg: Dictionary
var _timer := 0.0


func _init(civ_id: String, field: Battlefield, cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	economy = Economy.new(civ_id, cfg)
	battle = field
	battle.unit_died.connect(func(team): if team == Battlefield.ENEMY: economy.army_size -= 1)
	economy.job_done.connect(_on_job_done)


## Finished jobs that touch the battlefield: units walk out, towers go up.
func _on_job_done(job: Dictionary) -> void:
	match job.kind:
		"unit":
			battle.spawn(Battlefield.ENEMY, job.id, job.lane, economy.unit_bonus(job.id), economy.unit_tier(job.id))
		"towers":
			battle.build_towers(Battlefield.ENEMY)


func tick(delta: float) -> void:
	economy.tick(delta)
	_timer += delta
	if _timer < _cfg.ai.think_interval:
		return
	_timer = 0.0
	# Alternate idle villagers between food and wood.
	# Keep a few miners on gold (for cavalry) once there is a mine.
	while economy.villagers.get("idle", 0) > 0:
		var job := "food" if economy.villagers.get("food", 0) <= economy.villagers.get("wood", 0) else "wood"
		if not economy.can_work(job):
			job = "wood" if job == "food" else "food"
		if economy.mines.has("gold") and economy.villagers.gold < _cfg.ai.gold_miners:
			job = "gold"
		if not economy.reassign("idle", job):
			break  # nowhere to work yet
	# First the lumberjack, then the farm.
	for id in ["lumberjack", "farm"]:
		if not economy.camps.has(id) and not economy.is_pending("camp", id):
			economy.build_camp(id)
			return
	if economy.mines.has("gold") and economy.villagers.gold < _cfg.ai.gold_miners:
		economy.reassign("wood", "gold")
	# Keep a little headroom so it never gets stuck at the population cap.
	if economy.population() >= economy.max_population() - 1 and not economy.is_pending("hut", "hut") \
			and economy.build_hut():
		return
	if economy.total_villagers() >= 6 and not economy.military.has("barracks") \
			and not economy.is_pending("military", "barracks"):
		economy.build_military("barracks")
		return  # save for it before more villagers
	if economy.total_villagers() + economy.pending_count("villager") < _cfg.ai.target_villagers:
		economy.recruit()
		return
	# Units still in training count too, so it does not over-order while saving.
	var army := economy.army_size + economy.pending_count("unit")
	# In Era I keep only a small army out and save everything else for Era II.
	if economy.era_index == 0 and army >= _cfg.ai.era1_max_army and not economy.is_pending("era", "next"):
		economy.advance()
		return
	if economy.era_index >= 1 and not economy.has_towers and not economy.is_pending("towers", "towers"):
		economy.build_towers()
		return
	for id in ["mill", "lumber_camp", "barracks1", "archery_range1", "stables1"]:
		if economy.buy_upgrade(id):
			return
	if economy.era_index >= 1:
		for id in ["archery_range", "stables"]:
			if not economy.military.has(id) and not economy.is_pending("military", id):
				# Build it, or save up for it while a small army holds the lanes.
				if economy.build_military(id) or army >= _cfg.ai.era1_max_army:
					return
		if not economy.mines.has("gold") and not economy.is_pending("mine", "gold"):
			economy.build_mine("gold")
			return
	# A random unit it can train right now, down a random lane.
	var options: Array = _cfg.units.keys().filter(func(id): return economy.can_train(id))
	if not options.is_empty():
		economy.train(options.pick_random(), randi() % Battlefield.LANES)
