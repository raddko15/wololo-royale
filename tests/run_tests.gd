extends SceneTree
## Headless logic tests: godot --headless -s res://tests/run_tests.gd

var _failures := 0


func _init() -> void:
	for path in ["res://scripts/main.gd", "res://scripts/battle_view.gd", "res://scripts/card.gd", "res://scripts/hud_icon.gd", "res://scripts/radial_menu.gd"]:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "script compiles: " + path.get_file())

	var e := Economy.new("romans")
	_check(e.villagers.idle == 5 and e.workers.is_empty(), "starts with 5 idle villagers gathering nothing")
	_check(e.rate_per_villager("wood") > e.rate_per_villager("food"), "romans gather wood faster")
	var g := Economy.new("greeks")
	_check(g.rate_per_villager("food") > g.rate_per_villager("wood"), "greeks gather food faster")
	var f := Economy.new("franks")
	_check(f.rate_per_villager("stone") > f.rate_per_villager("gold") and f.style() == "medieval", "franks: medieval style, mine stone faster")
	_check(g.style() == "classical" and g.upgrade_name("mill") == "Olive Press" and e.upgrade_name("mill") == "Olive Press" and f.upgrade_name("mill") == "Windmill", "romans and greeks press olives; franks build a windmill")

	_check(e.reassign("idle", "food") and e.reassign("idle", "food") and e.villagers.food == 2, "assign idle to food")
	var food_before: float = e.resources.food
	# Walk out 1.5s, gather 5 at 1/s, walk back 1.5s: nothing lands before the trip ends.
	for i in 70:
		e.tick(0.1)
	_check(e.resources.food == food_before and e.workers[0].carry > 4.0, "food is carried, not yet in the pile")
	for i in 20:
		e.tick(0.1)
	_check(is_equal_approx(e.resources.food, food_before + 10), "two farmers drop off 5 food each")
	_check(e.workers[0].spot != e.workers[1].spot, "farmers work different plots")
	_check(e.reassign("food", "idle") and e.villagers.idle == 4, "send worker back to idle")
	e.villagers.wood = 0
	_check(not e.reassign("wood", "idle"), "cannot reassign from empty job")

	e.resources.food = 50
	var total := e.total_villagers()
	_check(e.recruit() and e.resources.food == 0 and e.total_villagers() == total + 1, "recruit costs 50 food, adds idle")
	_check(not e.recruit(), "cannot recruit when broke")

	var p := Economy.new("romans")
	_check(p.population() == 5 and p.max_population() == 10, "starts at 5/10 population")
	p.resources = {"food": 1e6, "wood": 30.0}
	_check(p.build_hut() and p.max_population() == 15 and p.resources.wood == 0, "hut costs 30 wood, +5 cap")
	p.resources.wood = 1e6
	while p.build_hut():
		pass
	_check(p.max_population() == 200, "population cap tops out at 200")
	p.villagers.idle = 199 - p.total_villagers() + p.villagers.idle
	p.army_size = 1
	_check(p.population() == 200 and not p.recruit(), "cannot recruit at 200 incl. army")

	e.resources = {"food": 0.0, "wood": 0.0}
	_check(not e.can_advance(), "cannot advance without 500/500")
	e.resources = {"food": 500.0, "wood": 500.0, "gold": 0.0, "stone": 0.0}
	_check(not e.can_build_mine("gold"), "no mines in Era I")
	_check(e.advance() and e.era_index == 1 and e.resources.food == 0, "advance to Era II spends 500/500")
	e.resources = {"food": 1000.0, "wood": 1150.0, "gold": 500.0, "stone": 499.0}
	_check(not e.reassign("idle", "gold"), "cannot mine gold before the mine exists")
	_check(e.build_mine("gold") and e.resources.wood == 1000 and not e.build_mine("gold"), "gold mine costs 150 wood, built once")
	e.villagers.idle += 1
	_check(e.reassign("idle", "gold") and e.villagers.gold == 1, "villager works the gold mine")
	_check(not e.can_advance(), "Era III needs 500 stone too")
	e.resources.stone = 500.0
	_check(e.advance() and e.era_index == 2, "advance to Era III with 1000/1000/500/500")
	_check(e.next_era_cost().is_empty() and not e.advance(), "no era beyond the last")

	var u2 := Economy.new("greeks")
	u2.resources = {"food": 0.0, "wood": 1000.0, "gold": 0.0, "stone": 1000.0}
	_check(not u2.buy_upgrade("mill"), "windmill needs Era II")
	u2.era_index = 1
	var food_rate := u2.rate_per_villager("food")
	_check(u2.buy_upgrade("mill") and is_equal_approx(u2.rate_per_villager("food"), food_rate * 1.15), "windmill: +15% food gathering")
	_check(not u2.buy_upgrade("mill"), "upgrade bought only once")
	_check(not u2.can_upgrade("stone_towers"), "stone towers need Era III")
	var bt := Battlefield.new()
	bt.build_towers(Battlefield.PLAYER)
	bt.buildings[Battlefield.PLAYER].towers[0] = 100.0
	bt.upgrade_towers(Battlefield.PLAYER, 0.5)
	_check(bt.tower_max_hp[0] == 750 and bt.buildings[0].towers[1] == 750 and bt.buildings[0].towers[0] == 350, "stone towers: +50% max HP")

	var b0 := Battlefield.new()
	var rusher := b0.spawn(Battlefield.ENEMY, "fighter", 1)
	_check(not b0.towers_built[Battlefield.PLAYER], "no towers in Era I")
	for i in 400:
		b0.tick(0.1)
	_check(b0.units.is_empty() and b0.buildings[Battlefield.PLAYER].main < 1000, "with no towers, a fighter reaches the fort, which shoots it down")

	var b := Battlefield.new()
	b.build_towers(Battlefield.ENEMY)
	b.build_towers(Battlefield.PLAYER)
	_check(b.buildings[Battlefield.ENEMY].towers.size() == 3 and b.towers_built[Battlefield.ENEMY], "build_towers raises all 3 at once")
	var u := b.spawn(Battlefield.PLAYER, "fighter", 2)
	_check(is_equal_approx(u.y, -0.5), "fighter starts at its own fort, at the start of the L road")
	for i in 280:
		b.tick(0.1)
	_check(u.y < 1.0 and u.y > 0.9 and b.buildings[Battlefield.ENEMY].towers[2] < b.max_hp("tower"), "fighter walks up and hits the enemy tower")
	_check(u.hp < 60, "enemy tower shoots the fighter")
	for i in 200:
		b.tick(0.1)
	_check(b.units.is_empty(), "lone fighter dies to the tower")

	var b2 := Battlefield.new()
	b2.build_towers(Battlefield.PLAYER)
	b2.build_towers(Battlefield.ENEMY)
	var a := b2.spawn(Battlefield.PLAYER, "fighter", 1)
	var z := b2.spawn(Battlefield.ENEMY, "fighter", 1)
	var deaths := []
	b2.unit_died.connect(func(team): deaths.append(team))
	for i in 300:
		b2.tick(0.1)
	_check(deaths.size() >= 1, "fighters in the same lane fight each other")

	var b3 := Battlefield.new()
	b3.build_towers(Battlefield.PLAYER)
	b3.build_towers(Battlefield.ENEMY)
	var adj := b3.spawn(Battlefield.ENEMY, "fighter", 0)
	adj.y = 0.1
	b3.buildings[Battlefield.PLAYER].towers[0] = 0.0
	b3.buildings[Battlefield.PLAYER].towers[1] = 300.0
	var hp_before: float = adj.hp
	b3.tick(0.1)
	_check(b3.arrows.is_empty(), "towers ignore fighters in other lanes")
	b3.buildings[Battlefield.PLAYER].towers[0] = 300.0
	b3.tick(0.1)
	_check(b3.arrows.size() == 1 and adj.hp == hp_before, "own-lane tower looses an arrow; no damage until it lands")
	for i in 5:
		b3.tick(0.1)
	_check(adj.hp == hp_before - 6 and b3.arrows.is_empty(), "arrow lands for 6 damage")

	var b4 := Battlefield.new()
	b4.build_towers(Battlefield.PLAYER)
	b4.build_towers(Battlefield.ENEMY)
	b4.buildings[Battlefield.ENEMY].towers[0] = 0.0
	var runner := b4.spawn(Battlefield.PLAYER, "fighter", 0)
	b4.buildings[Battlefield.ENEMY].towers[1] = 0.0
	var won := []
	b4.game_over.connect(func(w): won.append(w))
	b4.buildings[Battlefield.ENEMY].main = 5.0
	for i in 600:
		b4.tick(0.1)
	_check(runner.y > 1.4 and won == [Battlefield.PLAYER], "past a fallen outer tower, fighter takes the L road and destroys the main building")

	var b5 := Battlefield.new()
	var ai := EnemyAI.new("greeks", b5)
	for i in 600:
		ai.tick(0.5)
		b5.tick(0.5)
	_check(ai.economy.total_villagers() >= 10 and b5.units.size() + 0 >= 0 and ai.economy.army_size >= 0, "AI recruits villagers")
	_check(ai.economy.army_size == b5.units.filter(func(x): return x.team == Battlefield.ENEMY).size(), "AI army count matches its living units")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures else 0)


func _check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_failures += 1
