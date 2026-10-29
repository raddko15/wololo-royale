extends SceneTree
## Renders game screens to PNGs (needs a display, e.g. xvfb-run).
## Args: <out.png> <era1|era2|era2up|era3|window|mill|mine|jobs|sites|sites0|corpses|start|menu|victory|unique|paused|gather|lobby|hutsite|leaving> [player_civ] [enemy_civ] [huts]
## era2up buys the mill and lumber upgrades, era3 every upgrade (both sides);
## window / mill open that building's ring menu.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[1] if args.size() > 1 else "era1"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if mode == "lobby":
		main.net = Net.new()
		main.add_child(main.net)
		main._show_lobby("franks", main.get_child(0))
		await process_frame
		main.get_child(-1)._on_room("KXRT")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
		quit()
		return
	if mode == "menu":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
		quit()
		return
	main._start_game(args[2] if args.size() > 2 else "romans", main.get_child(0))
	if args.size() > 3:
		main.game.ai.economy = Economy.new(args[3])
		main.game.economies[Battlefield.ENEMY] = main.game.ai.economy
		main._view.enemy_economy = main.game.ai.economy
	var era: int = {"era1": 0, "era2": 1, "era2up": 1, "era3": 2, "window": 1, "mill": 1, "mine": 2, "jobs": 1, "sites": 1, "sites0": 0, "corpses": 1, "start": 0, "hutsite": 0, "leaving": 0, "victory": 0, "unique": 2, "walkstrip": 2, "fightstrip": 0, "paused": 1, "gather": 1}[mode]
	if mode == "start" or mode == "hutsite" or mode == "leaving":
		# A real opening: the AI plays its first 30 seconds, the player nothing
		# (hutsite: two more villagers, so the next hut's plot shows).
		if mode == "hutsite":
			main.economy.villagers.idle += 2
		if mode == "leaving":
			# Workers called back part way: one carrying a load to the
			# drop-off, others walking from their plot/tree to the fire.
			var e: Economy = main.economy
			e.camps = {"farm": true, "lumberjack": true}
			for job in ["food", "food", "wood", "wood"]:
				e.reassign("idle", job)
			for i in 40:
				e.tick(0.1)
			e.reassign("food", "idle")
			e.reassign("wood", "idle")
			for i in 5:
				e.tick(0.1)
			for job in ["food", "wood"]:
				e.reassign("idle", job)  # and two more on their way out
			e.tick(0.4)
		for i in 600:
			main.game.ai.tick(0.05)
		await process_frame
		for i in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
		quit()
		return
	for e in [main.economy, main.game.ai.economy]:
		e.camps = {"farm": true, "lumberjack": true}
		e.era_index = era
		e.huts = int(args[4]) if args.size() > 4 else 10
		e.military = {"barracks": 1} if era == 0 else {"barracks": 1, "archery_range": 1, "stables": 1}
		if mode.begins_with("sites"):
			e.military = {} if mode == "sites0" else {"barracks": 1}
		if mode == "era2up":
			e.upgrades = {"mill": true, "lumber_camp": true}
		elif mode == "era3":
			e.upgrades = {"mill": true, "lumber_camp": true, "stone_towers": true, "mill2": true,
				"lumber_camp2": true, "gold_mine2": true, "stone_mine2": true, "barracks1": true,
				"barracks2": true, "archery_range1": true, "stables1": true}
			e.mines = {"gold": true, "stone": true}
			e.military = {"barracks": 3, "archery_range": 1, "stables": 2}
	for team in [Battlefield.PLAYER, Battlefield.ENEMY]:
		main.battle.fort_new_era(team, era)
	main.battle.buildings[Battlefield.PLAYER].main = 700.0
	if era >= 1 and mode != "sites":
		main.battle.build_towers(Battlefield.PLAYER)
		main.battle.build_towers(Battlefield.ENEMY)
		main.game.tick(0.0)  # the economies learn their towers stand
		main.economy.mines = {"gold": true, "stone": true}
	for job in ["food", "food", "food", "wood", "wood"] + (["gold", "gold", "stone", "stone"] if era >= 1 else []):
		main.economy.villagers.idle += 1
		main.economy.reassign("idle", job)
	for job in ["food", "food", "wood", "wood"]:
		main.game.ai.economy.villagers.idle += 1
		main.game.ai.economy.reassign("idle", job)
	var mix := ["fighter", "archer", "cavalry", "fighter"] if era >= 1 else ["fighter", "fighter", "fighter", "fighter"]
	if mode == "walkstrip" or mode == "fightstrip":
		main.battle.units.clear()
		if mode == "walkstrip":
			main.battle.spawn(Battlefield.PLAYER, "knight", 1)
			main.battle.spawn(Battlefield.PLAYER, "cavalry", 0)
		else:
			# Two Era I fighters trading blows mid-lane, with plenty of HP.
			for team in [Battlefield.PLAYER, Battlefield.ENEMY]:
				var f: Dictionary = main.battle.spawn(team, "fighter", 1)
				f.y = 0.5 if team == Battlefield.PLAYER else 0.535
				f.hp = 9999.0
				f.max_hp = 9999.0
		for f in 12:
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[0].replace(".png", "_%02d.png" % f))
		quit()
		return
	if mode == "gather":
		# Troops stopped by the left and middle towers (the default order).
		main.battle.units.clear()
		for lane in [0, 1]:
			for t in ["fighter", "fighter", "fighter", "archer", "archer", "cavalry", "cavalry"]:
				main.battle.spawn(Battlefield.PLAYER, t, lane)
		# The right lane marches.
		main.battle.spawn(Battlefield.PLAYER, "archer", 2)
		main.battle.set_order(Battlefield.PLAYER, 2, "march")
	elif mode == "unique":
		# Each civ's unique unit on both sides, one lane each.
		for team in [Battlefield.PLAYER, Battlefield.ENEMY]:
			main.battle.spawn_squad(team, "knight", 0, 1, {}, 0)
			main.battle.spawn_squad(team, "chariot", 1, 1, {}, 1)
			main.battle.spawn_squad(team, "phalanx", 2, 3, {}, 0)
	else:
		for i in 4:
			main.battle.spawn(Battlefield.PLAYER, mix[i], [0, 1, 2, 1][i])
			main.battle.spawn(Battlefield.ENEMY, mix[(i + 1) % 4], [0, 1, 2, 1][i])
	for i in 300:
		main.battle.tick(0.05)
		main.economy.tick(0.05)
		main.game.ai.economy.tick(0.05)
	if mode == "jobs":
		# Something of every kind under way on the player's side.
		var e = main.economy
		e.resources = {"food": 9000.0, "wood": 9000.0, "gold": 9000.0, "stone": 9000.0}
		e.military = {"barracks": 1}
		e.mines = {"gold": true}
		main.battle.towers_built[Battlefield.PLAYER] = [false, false, false]
		main.battle.buildings[Battlefield.PLAYER].towers = [0.0, 0.0, 0.0]
		main.game.tick(0.0)
		e.advance()
		e.recruit()
		e.recruit()
		e.villagers.idle += 7  # helpers for the building sites
		e.build_hut()
		e.build_hut()
		e.build_military("archery_range")
		e.build_mine("stone")
		e.build_tower(1)
		e.buy_upgrade("mill")
		e.train("fighter", 0)
		e.train("fighter", 1)
		e.train("fighter", 2)
		for i in 40:
			e.tick(0.1)
	if mode == "corpses":
		# Every unit type at each stage: fresh, rotten, skeleton (left to right).
		main._view.game_clock = 100.0
		var now: float = main._view.game_clock
		var types := ["fighter", "archer", "cavalry"]
		for row in 3:
			for col in 3:
				main._view.corpses.append({"pos": Vector2(150 + col * 210, 560 + row * 110), "type": types[row],
					"tier": row % 2 + 1, "color": Color("#c0392b") if col % 2 == 0 else Color("#2e86de"), "born": now - [2.0, 10.0, 19.0][col],
					"angle": PI / 2 if col % 2 == 0 else -PI / 2 + 0.2, "weapon_angle": 0.7 + col})
	await process_frame
	if mode == "window":
		main._open_menu("town_center", main._view.town_center())
	elif mode == "mill":
		main._open_menu("mill", main._view.drop_off(Battlefield.PLAYER, "food"))
	elif mode == "paused":
		main._set_paused(true)
	elif mode == "victory":
		main._on_game_over(Battlefield.PLAYER)
	elif mode == "mine":
		main._open_menu("gold_mine", main._view.mine_pos(Battlefield.PLAYER, "gold"))
	for i in (150 if mode == "jobs" else 5):  # jobs: let helpers walk to the sites
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0])
	quit()
