extends SceneTree
## Headless logic tests: godot --headless -s res://tests/run_tests.gd

var _failures := 0


func _init() -> void:
	for path in ["res://scripts/main.gd", "res://scripts/battle_view.gd", "res://scripts/card.gd", "res://scripts/hud_icon.gd", "res://scripts/radial_menu.gd", "res://scripts/lane_toggle.gd"]:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "script compiles: " + path.get_file())

	var e := Economy.new("romans")
	_check(e.villagers.idle == 5 and e.workers.is_empty(), "starts with 5 idle villagers gathering nothing")
	_check(e.rate_per_villager("wood") > e.rate_per_villager("food"), "romans gather wood faster")
	var g := Economy.new("greeks")
	_check(g.rate_per_villager("food") > g.rate_per_villager("wood"), "greeks gather food faster")
	var f := Economy.new("franks")
	_check(f.style() == "medieval" and is_equal_approx(f.unit_bonus("cavalry").get("hp", 0.0), 0.2) and is_equal_approx(f.unit_bonus("knight").get("hp", 0.0), 0.2), "franks: medieval style, horsemen +20% HP")
	_check(is_equal_approx(e.rate_per_villager("wood"), 1.3 * 1.05) and is_equal_approx(e.unit_bonus("fighter").get("speed", 0.0), 0.1) and e.unit_bonus("cavalry").is_empty(), "romans: +5% wood, foot soldiers +10% speed")
	var fast := Battlefield.new().spawn(Battlefield.PLAYER, "fighter", 1, e.unit_bonus("fighter"))
	_check(is_equal_approx(fast.speed, 0.06 * 1.1), "a Roman fighter walks 10% faster")
	_check(g.style() == "classical" and g.upgrade_name("mill") == "Olive Press" and e.upgrade_name("mill") == "Olive Press" and f.upgrade_name("mill") == "Windmill", "romans and greeks press olives; franks build a windmill")

	_check(not e.reassign("idle", "food") and not e.reassign("idle", "wood"), "no gathering before the farm and lumberjack stand")
	e.resources.wood = 90.0
	_check(e.build_camp("farm") and e.build_camp("lumberjack") and e.resources.wood == 0, "farm costs 50 wood, lumberjack 40")
	_check(not e.can_upgrade("mill"), "no mill upgrade without a farm")
	var nb := Economy.new("romans")
	nb.resources.wood = 1000.0
	_check(not nb.build_military("barracks") and nb.build_camp("lumberjack"), "no barracks before the lumberjack")
	nb.finish_jobs()
	_check(nb.build_military("barracks"), "barracks once the lumberjack stands")
	e.finish_jobs()
	e.resources.wood = 100.0
	_check(e.reassign("idle", "food") and e.reassign("idle", "food") and e.villagers.food == 2, "assign idle to food")
	var food_before: float = e.resources.food
	# Walk out 1.2s, gather 10 at 1.3/s, walk back 1.2s: nothing lands before the trip ends.
	for i in 70:
		e.tick(0.1)
	_check(e.resources.food == food_before and e.workers[0].carry > 4.0, "food is carried, not yet in the pile")
	for i in 65:
		e.tick(0.1)
	_check(is_equal_approx(e.resources.food, food_before + 20), "two farmers drop off 10 food each")
	_check(e.workers[0].spot != e.workers[1].spot, "farmers work different plots")
	_check(e.reassign("food", "idle") and e.villagers.idle == 4, "send worker back to idle")
	e.villagers.wood = 0
	_check(not e.reassign("wood", "idle"), "cannot reassign from empty job")

	e.resources.food = 50
	var total := e.total_villagers()
	_check(e.recruit() and e.resources.food == 0 and e.total_villagers() == total and e.population() == total + 1, "recruit costs 50 food and reserves population")
	e.tick(5.9)
	_check(e.total_villagers() == total, "villager still training before 6 s")
	e.tick(0.2)
	_check(e.total_villagers() == total + 1 and e.villagers.idle >= 1, "villager comes out idle after 6 s")
	_check(not e.recruit(), "cannot recruit when broke")

	var p := Economy.new("romans")
	p.camps = {"farm": true, "lumberjack": true}
	_check(p.population() == 5 and p.max_population() == 10 and p.huts == 1, "starts at 5/10 population with one hut")
	p.resources = {"food": 1e6, "wood": 30.0}
	_check(p.build_hut() and p.max_population() == 10 and p.resources.wood == 0, "hut costs 30 wood, still being built")
	p.finish_jobs()
	_check(p.max_population() == 15, "finished hut adds +5 cap")
	p.era_index = 1
	p.resources.wood = 30.0
	p.build_hut()
	p.finish_jobs()
	p.resources.wood = 1e6
	while p.build_hut():
		pass
	p.finish_jobs()
	_check(p.max_population() == 100, "population cap tops out at 100")
	p.villagers.idle = 99 - p.total_villagers() + p.villagers.idle
	p.army_size = 1
	_check(p.population() == 100 and not p.recruit(), "cannot recruit at 100 incl. army")

	e.resources = {"food": 0.0, "wood": 0.0}
	_check(not e.can_advance(), "cannot advance without 300/300")
	e.resources = {"food": 300.0, "wood": 300.0, "gold": 0.0, "stone": 0.0}
	_check(not e.can_build_mine("gold"), "no mines in Era I")
	_check(e.advance() and e.era_index == 0 and e.resources.food == 0 and not e.can_advance(), "advancing to Era II takes time; paid up front")
	e.finish_jobs()
	_check(e.era_index == 1, "Era II reached when the research finishes")
	e.resources = {"food": 1000.0, "wood": 1150.0, "gold": 500.0, "stone": 499.0}
	_check(not e.reassign("idle", "gold"), "cannot mine gold before the mine exists")
	_check(e.build_mine("gold") and e.resources.wood == 1000 and not e.build_mine("gold"), "gold mine costs 150 wood, built once")
	e.finish_jobs()
	e.villagers.idle += 1
	_check(e.reassign("idle", "gold") and e.villagers.gold == 1, "villager works the gold mine")
	_check(not e.can_advance(), "Era III needs 500 stone too")
	e.resources.stone = 500.0
	_check(e.advance(), "advance to Era III with 1000/1000/500/500")
	e.finish_jobs()
	_check(e.era_index == 2, "Era III reached")
	_check(e.next_era_cost().is_empty() and not e.advance(), "no era beyond the last")

	var m := Economy.new("franks")
	m.camps = {"farm": true, "lumberjack": true}
	m.resources = {"food": 1000.0, "wood": 1000.0, "gold": 1000.0, "stone": 0.0}
	_check(not m.can_train("fighter"), "no fighters without a barracks")
	_check(m.build_military("barracks") and not m.can_train("fighter"), "barracks under construction")
	m.finish_jobs()
	_check(m.can_train("fighter"), "barracks unlocks fighters")
	_check(not m.build_military("stables"), "stables need Era II")
	m.era_index = 1
	m.build_military("stables")
	m.finish_jobs()
	var spawned := []
	m.job_done.connect(func(j): if j.kind == "unit": spawned.append([j.id, j.lane]))
	_check(m.train("cavalry", 2) and m.army_size == 0 and m.population() == 6, "queued cavalry reserves population")
	m.tick(9.1)
	_check(m.army_size == 1 and spawned == [["cavalry", 2]], "cavalry ready after 9 s, bound for its lane")
	m.train("fighter", 0)
	m.train("fighter", 1)
	m.tick(6.1)
	_check(spawned.size() == 2, "one barracks trains one fighter at a time")
	m.job_speed = 10.0
	m.tick(0.61)
	_check(spawned.size() == 3, "testing job speed: 10x faster training")
	_check(not m.can_train("archer"), "archers need an archery range")
	m.resources.gold = 1000.0
	_check(not m.can_upgrade("archery_range1"), "archery upgrade needs the range")
	_check(m.buy_upgrade("barracks1"), "barracks upgrade in Era II")
	m.finish_jobs()
	_check(m.unit_tier("fighter") == 1 and is_equal_approx(m.unit_bonus("fighter").hp, 0.4), "veteran fighters: tier 1, +40% HP")
	var bv := Battlefield.new()
	var vet := bv.spawn(Battlefield.PLAYER, "fighter", 0, m.unit_bonus("fighter"), m.unit_tier("fighter"))
	_check(is_equal_approx(vet.max_hp, 84) and is_equal_approx(vet.dps, 13) and vet.tier == 1, "upgraded fighter spawns stronger")

	var ba := Battlefield.new()
	var archer := ba.spawn(Battlefield.PLAYER, "archer", 1)
	var dummy := ba.spawn(Battlefield.ENEMY, "fighter", 1)
	archer.y = 0.5
	dummy.y = 0.62
	dummy.speed = 0.0
	ba.tick(0.1)
	_check(archer.target == "unit" and dummy.hp < 60 and archer.y == 0.5, "archer shoots from range without walking up")

	var u2 := Economy.new("greeks")
	u2.camps = {"farm": true, "lumberjack": true}
	u2.resources = {"food": 0.0, "wood": 1000.0, "gold": 0.0, "stone": 1000.0}
	_check(not u2.buy_upgrade("mill"), "windmill needs Era II")
	u2.era_index = 1
	var food_rate := u2.rate_per_villager("food")
	u2.buy_upgrade("mill")
	u2.finish_jobs()
	_check(is_equal_approx(u2.rate_per_villager("food"), food_rate * 1.15), "windmill: +15% food gathering")
	_check(not u2.buy_upgrade("mill"), "upgrade bought only once")
	_check(not u2.can_upgrade("stone_towers"), "stone towers need Era III")
	u2.era_index = 2
	u2.resources.gold = 1000.0
	_check(not u2.can_upgrade("lumber_camp2"), "sawmill needs the lumber camp first")
	_check(not u2.can_upgrade("gold_mine2"), "deep mine needs the gold mine first")
	u2.buy_upgrade("mill2")
	u2.finish_jobs()
	_check(is_equal_approx(u2.rate_per_villager("food"), food_rate * 1.35), "Era III food upgrade stacks: +15% +20%")
	_check(u2.upgrade_name("mill2") == "Oil Workshop" and Economy.new("franks").upgrade_name("mill2") == "Grand Mill", "Era III food building named per style")
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
	_check(b0.units.size() == 1 and b0.buildings[Battlefield.PLAYER].main < 1000, "the Era I fort does not shoot: a fighter hacks at it unharmed")
	var hurt: float = b0.buildings[Battlefield.PLAYER].main
	b0.fort_new_era(Battlefield.PLAYER, 1)
	_check(is_equal_approx(b0.buildings[Battlefield.PLAYER].main, minf(hurt + 400.0, 1000.0)) and b0.fort_armor[Battlefield.PLAYER] == 0.2, "a new era heals the fort 40% and gives it 20% armor")
	for i in 200:
		b0.tick(0.1)
	_check(b0.units.is_empty(), "from Era II the fort shoots it down")

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

	var b6 := Battlefield.new()
	var smart := EnemyAI.new("franks", b6, "normal")
	for i in 4800:
		smart.tick(0.1)
	_check(smart.economy.era_index >= 1 and smart.economy.military.has("barracks"), "normal AI reaches Era II within 8 minutes")
	b6.units.clear()  # its own army (the field was not ticked, so it never left the fort)
	for i in 6:
		b6.spawn(Battlefield.PLAYER, "fighter", 2).y = 0.8
	smart.economy.huts += 10  # room to train
	smart.economy.resources = {"food": 500.0, "wood": 500.0, "gold": 0.0, "stone": 0.0}
	smart._think()
	_check(smart.economy.jobs.any(func(j): return j.kind == "unit" and j.lane == 2), "AI sends defenders to the lane being pushed")

	var cq := Economy.new("romans")
	cq.resources.food = 100.0
	cq.recruit()
	cq.recruit()
	_check(cq.cancel("villager", "villager") and cq.pending_count("villager") == 1 and cq.resources.food == 50, "cancel a queued villager for a refund")
	_check(cq.cancel("villager", "villager") and not cq.cancel("villager", "villager") and cq.resources.food == 100, "cancel the one in training too; nothing left to cancel")

	# Up to 3 of each military building, each training on its own.
	var mb := Economy.new("romans")
	mb.camps = {"farm": true, "lumberjack": true}
	mb.resources = {"food": 9000.0, "wood": 9000.0, "gold": 0.0, "stone": 0.0}
	mb.huts = 10
	for i in 3:
		mb.build_military("barracks")
		mb.finish_jobs()
	_check(mb.military.barracks == 3 and not mb.can_build_military("barracks"), "three barracks at most")
	for i in 3:
		mb.train("fighter", 1)
	mb.tick(6.1)
	_check(mb.army_size == 3, "three barracks train three fighters at once")
	_check(is_equal_approx(mb.villager_time(), 6.0), "villagers take 6 s in Era I")
	mb.era_index = 2
	_check(mb.villager_time() < 4.5, "the town center trains villagers faster in later eras")

	var rb := Battlefield.new()
	rb.buildings[Battlefield.PLAYER].main = 500.0
	rb.tick(4.0)
	_check(rb.buildings[Battlefield.PLAYER].main == 500.0, "no repairs within 5 s of the last hit")
	for i in 20:
		rb.tick(0.1)
	_check(rb.buildings[Battlefield.PLAYER].main > 500.0 and rb.buildings[Battlefield.PLAYER].main < 520.0, "then the fort slowly repairs itself")

	# Unique units: one per civ, Era III, sharing their building's upgrades.
	var gr := Economy.new("greeks")
	gr.military = {"barracks": 1, "stables": 1}
	gr.huts = 10
	gr.resources = {"food": 9000.0, "wood": 9000.0, "gold": 9000.0, "stone": 0.0}
	_check(gr.available_units().has("phalanx") and not gr.available_units().has("knight") and not gr.available_units().has("chariot"), "greeks get the phalanx, not the others' units")
	_check(not gr.can_train("phalanx"), "phalanx needs Era III")
	gr.era_index = 2
	gr.upgrades = {"barracks1": true}
	var army_before := gr.population()
	_check(gr.train("phalanx", 1) and gr.population() == army_before + 3, "a phalanx is three hoplites (3 population)")
	_check(gr.unit_tier("phalanx") == 1 and gr.unit_bonus("phalanx").has("hp"), "the phalanx gets the fighter upgrades")
	gr.finish_jobs()
	_check(gr.army_size == 3, "three hoplites join the army")
	var bf := Battlefield.new()
	bf.spawn_squad(Battlefield.PLAYER, "phalanx", 1, 3)
	_check(bf.units.size() == 3 and bf.units[0].side < bf.units[2].side, "the three hoplites stand side by side")
	var duel := Battlefield.new()
	var hop := duel.spawn(Battlefield.PLAYER, "phalanx", 1)
	var horse := duel.spawn(Battlefield.ENEMY, "knight", 1)
	hop.y = 0.5
	horse.y = 0.53
	var knight_hp: float = horse.hp
	duel.tick(1.0)
	_check(is_equal_approx(knight_hp - horse.hp, 24.0), "hoplites deal triple damage to horsemen")
	var joust := Battlefield.new()
	var kn := joust.spawn(Battlefield.PLAYER, "knight", 1)
	var ft := joust.spawn(Battlefield.ENEMY, "fighter", 1)
	kn.y = 0.5
	ft.y = 0.53
	var ft_hp: float = ft.hp
	joust.tick(1.0)
	_check(is_equal_approx(ft_hp - ft.hp, 32.0), "knights deal double damage to fighters")
	_check(Economy.new("franks").available_units().has("knight") and Economy.new("romans").available_units().has("chariot"), "franks get knights, romans chariots")

	var kv := Economy.new("romans")
	kv.camps = {"farm": true, "lumberjack": true}
	kv.reassign("idle", "food")
	kv.villagers.idle = 1
	_check(kv.kill_villager().job == "idle" and kv.total_villagers() == 1, "delete takes an idle villager first")
	var gone := kv.kill_villager()
	_check(gone.job == "food" and not gone.worker.is_empty() and kv.workers.is_empty() and kv.kill_villager().is_empty(), "then a worker; none left to delete")

	# Idle villagers help build: +30% speed each.
	var hb := Economy.new("romans")
	hb.resources.wood = 60.0
	hb.villagers.idle = 0
	hb.build_hut()
	hb.tick(3.0)
	_check(hb.huts == 1, "a hut takes its full 6 s with nobody helping")
	hb.finish_jobs()
	hb.villagers.idle = 5
	hb.build_hut()
	hb.tick(3.0)
	_check(hb.huts == 3 and hb.builders().is_empty(), "5 idle villagers build a hut 2.5x faster")

	# Attackers around a tower keep their spots when one of them falls.
	var vb := Battlefield.new()
	var view: BattleView = load("res://scripts/battle_view.gd").new()
	view.battle = vb
	view.size = Vector2(720, 1100)
	for i in 4:
		vb.spawn(Battlefield.PLAYER, "fighter", 1).target = "tower"
	for i in 60:
		view.unit_positions()
	var before_pos := view.unit_positions()
	vb.units.remove_at(1)
	for i in 60:
		view.unit_positions()
	var after_pos := view.unit_positions()
	_check(after_pos[0] == before_pos[0] and after_pos[1] == before_pos[2] and after_pos[2] == before_pos[3], "attackers stay put when one of them dies")
	view.free()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures else 0)


func _check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_failures += 1
