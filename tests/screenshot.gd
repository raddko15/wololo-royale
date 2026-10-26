extends SceneTree
## Renders game screens to PNGs (needs a display, e.g. xvfb-run).
## Args: <out.png> <era1|era2|era2up|era3|window|mill|mine|jobs|sites|sites0> [player_civ] [enemy_civ] [huts]
## era2up buys the mill and lumber upgrades, era3 every upgrade (both sides);
## window / mill open that building's ring menu.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[1] if args.size() > 1 else "era1"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._start_game(args[2] if args.size() > 2 else "romans", main.get_child(0))
	if args.size() > 3:
		main.ai.economy = Economy.new(args[3])
		main._view.enemy_economy = main.ai.economy
	var era: int = {"era1": 0, "era2": 1, "era2up": 1, "era3": 2, "window": 1, "mill": 1, "mine": 2, "jobs": 1, "sites": 1, "sites0": 0}[mode]
	for e in [main.economy, main.ai.economy]:
		e.era_index = era
		e.huts = int(args[4]) if args.size() > 4 else 10
		e.military = {"barracks": true} if era == 0 else {"barracks": true, "archery_range": true, "stables": true}
		if mode.begins_with("sites"):
			e.military = {} if mode == "sites0" else {"barracks": true}
		if mode == "era2up":
			e.upgrades = {"mill": true, "lumber_camp": true}
		elif mode == "era3":
			e.upgrades = {"mill": true, "lumber_camp": true, "stone_towers": true, "mill2": true,
				"lumber_camp2": true, "gold_mine2": true, "stone_mine2": true, "barracks1": true,
				"barracks2": true, "archery_range1": true, "stables1": true}
			e.mines = {"gold": true, "stone": true}
	if era >= 1 and mode != "sites":
		main.battle.build_towers(Battlefield.PLAYER)
		main.battle.build_towers(Battlefield.ENEMY)
		main.economy.mines = {"gold": true, "stone": true}
	for job in ["food", "food", "food", "wood", "wood"] + (["gold", "gold", "stone", "stone"] if era >= 1 else []):
		main.economy.villagers.idle += 1
		main.economy.reassign("idle", job)
	for job in ["food", "food", "wood", "wood"]:
		main.ai.economy.villagers.idle += 1
		main.ai.economy.reassign("idle", job)
	var mix := ["fighter", "archer", "cavalry", "fighter"] if era >= 1 else ["fighter", "fighter", "fighter", "fighter"]
	for i in 4:
		main.battle.spawn(Battlefield.PLAYER, mix[i], [0, 1, 2, 1][i])
		main.battle.spawn(Battlefield.ENEMY, mix[(i + 1) % 4], [0, 1, 2, 1][i])
	for i in 300:
		main.battle.tick(0.05)
		main.economy.tick(0.05)
		main.ai.economy.tick(0.05)
	if mode == "jobs":
		# Something of every kind under way on the player's side.
		var e = main.economy
		e.resources = {"food": 9000.0, "wood": 9000.0, "gold": 9000.0, "stone": 9000.0}
		e.military = {"barracks": true}
		e.mines = {"gold": true}
		main.battle.towers_built[Battlefield.PLAYER] = false
		main.battle.buildings[Battlefield.PLAYER].towers = [0.0, 0.0, 0.0]
		e.advance()
		e.recruit()
		e.recruit()
		e.build_hut()
		e.build_hut()
		e.build_military("archery_range")
		e.build_mine("stone")
		e.build_towers()
		e.buy_upgrade("mill")
		e.train("fighter", 0)
		e.train("fighter", 1)
		e.train("fighter", 2)
		for i in 40:
			e.tick(0.1)
	await process_frame
	if mode == "window":
		main._open_menu("town_center", main._view.town_center())
	elif mode == "mill":
		main._open_menu("mill", main._view.drop_off(Battlefield.PLAYER, "food"))
	elif mode == "mine":
		main._open_menu("gold_mine", main._view.mine_pos(Battlefield.PLAYER, "gold"))
	for i in 5:
		await process_frame
	print("hut slots: ", main._view._slots().size())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0])
	quit()
