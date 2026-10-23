extends SceneTree
## Renders game screens to PNGs (needs a display, e.g. xvfb-run).
## Args: <out.png> <era1|era2|era3|window|mill>
## era3 also buys every upgrade; window / mill open that building's ring menu.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[1] if args.size() > 1 else "era1"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._start_game("romans", main.get_child(0))
	var era: int = {"era1": 0, "era2": 1, "era3": 2, "window": 1, "mill": 1}[mode]
	for e in [main.economy, main.ai.economy]:
		e.era_index = era
		e.huts = 10
	if era >= 1:
		main.battle.build_towers(Battlefield.PLAYER)
		main.battle.build_towers(Battlefield.ENEMY)
		main.economy.mines = {"gold": true, "stone": true}
	if era == 2:
		main.economy.upgrades = {"mill": true, "lumber_camp": true, "stone_towers": true}
	for job in ["food", "food", "food", "wood", "wood"] + (["gold", "gold", "stone", "stone"] if era >= 1 else []):
		main.economy.villagers.idle += 1
		main.economy.reassign("idle", job)
	for job in ["food", "food", "wood", "wood"]:
		main.ai.economy.villagers.idle += 1
		main.ai.economy.reassign("idle", job)
	for lane in [0, 1, 2, 1]:
		main.battle.spawn(Battlefield.PLAYER, "fighter", lane)
		main.battle.spawn(Battlefield.ENEMY, "fighter", lane)
	for i in 300:
		main.battle.tick(0.05)
		main.economy.tick(0.05)
		main.ai.economy.tick(0.05)
	await process_frame
	if mode == "window":
		main._open_menu("town_center", main._view.town_center())
	elif mode == "mill":
		main._open_menu("mill", main._view.drop_off(Battlefield.PLAYER, "food"))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0])
	quit()
