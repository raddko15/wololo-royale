extends SceneTree
## AI-vs-AI matches for tuning: godot --headless -s res://tests/ai_sim.gd -- <level_a> <level_b> [games]
## The first AI plays the player's side. Prints era timings and who won.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var a: String = args[0] if args.size() > 0 else "normal"
	var b: String = args[1] if args.size() > 1 else "easy"
	var games: int = int(args[2]) if args.size() > 2 else 4
	var wins := {a + "(A)": 0, b + "(B)": 0, "draw": 0}
	for g in games:
		var field := Battlefield.new()
		var ais := [EnemyAI.new("romans", field, a, Battlefield.PLAYER), EnemyAI.new("franks", field, b, Battlefield.ENEMY)]
		var eras := [[], []]
		var t := 0.0
		var dt := 0.1
		while field.winner == -1 and t < 1200.0:
			for k in 2:
				var before: int = ais[k].economy.era_index
				ais[k].tick(dt)
				if ais[k].economy.era_index != before:
					eras[k].append(int(t))
			field.tick(dt)
			t += dt
		var line := "game %d: %s in %ds" % [g, ["A wins", "B wins"][field.winner] if field.winner != -1 else "no winner", int(t)]
		for k in 2:
			var e: Economy = ais[k].economy
			line += " | %s eras@%s vil %d army %d ups %d" % ["A" if k == 0 else "B", eras[k], e.total_villagers(), e.army_size, e.upgrades.size()]
		print(line)
		if field.winner == -1:
			wins.draw += 1
		else:
			wins[[a + "(A)", b + "(B)"][field.winner]] += 1
	print(wins)
	quit()
