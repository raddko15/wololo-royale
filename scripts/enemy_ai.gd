class_name EnemyAI
extends RefCounted
## A deliberately simple opponent: keeps villagers busy, builds huts near the
## population cap, recruits a few villagers, keeps a small army while saving
## up for Era II, builds its towers, and otherwise sends a fighter down a random
## lane whenever it can afford one. After its towers it buys the windmill and
## lumber camp. It does not use mines or go past Era II.

var economy: Economy
var battle: Battlefield
var _cfg: Dictionary
var _timer := 0.0


func _init(civ_id: String, field: Battlefield, cfg: Dictionary = GameConfig.data()) -> void:
	_cfg = cfg
	economy = Economy.new(civ_id, cfg)
	battle = field
	battle.unit_died.connect(func(team): if team == Battlefield.ENEMY: economy.army_size -= 1)


func tick(delta: float) -> void:
	economy.tick(delta)
	_timer += delta
	if _timer < _cfg.ai.think_interval:
		return
	_timer = 0.0
	# Alternate idle villagers between food and wood.
	while economy.villagers.get("idle", 0) > 0:
		var job := "food" if economy.villagers.get("food", 0) <= economy.villagers.get("wood", 0) else "wood"
		economy.reassign("idle", job)
	# Keep a little headroom so it never gets stuck at the population cap.
	if economy.population() >= economy.max_population() - 1 and economy.build_hut():
		return
	if economy.total_villagers() < _cfg.ai.target_villagers:
		economy.recruit()
		return
	# In Era I keep only a small army out and save everything else for Era II.
	if economy.era_index == 0 and economy.army_size >= _cfg.ai.era1_max_army:
		economy.advance()
		return
	if economy.era_index >= 1 and not battle.towers_built[Battlefield.ENEMY]:
		if economy.spend(_cfg.buildings.towers.cost):
			battle.build_towers(Battlefield.ENEMY)
		return
	for id in ["mill", "lumber_camp"]:
		if economy.buy_upgrade(id):
			return
	var fighter: Dictionary = _cfg.units.fighter
	if economy.has_room() and economy.spend(fighter.cost):
		battle.spawn(Battlefield.ENEMY, "fighter", randi() % Battlefield.LANES)
		economy.army_size += 1
