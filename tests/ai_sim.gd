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
		var civs := ["romans", "franks", "greeks"]
		var ca: String = civs[g % 3]
		var cb: String = civs[(g + 1) % 3]
		var ais := [_make(a, ca, field, Battlefield.PLAYER), _make(b, cb, field, Battlefield.ENEMY)]
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
			if OS.get_environment("AI_SIM_TRACE") != "" and int(round(t * 10)) % 300 == 0:
				var line := "  %3ds" % int(t)
				for k in 2:
					var e: Economy = ais[k].economy
					line += " | %s vil %d army %d res %s fort %d mil %s" % ["AB"[k], e.total_villagers(), e.army_size,
						e.resources.values().map(func(v): return int(v)), int(field.buildings[k].main), e.military]
				print(line)
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


## "old:hard" plays the saved previous AI (tests/baseline_ai.gd) for comparison.
func _make(level: String, civ: String, field: Battlefield, side: int):
	if level.begins_with("old:"):
		return load("res://tests/baseline_ai.gd").new(civ, field, level.trim_prefix("old:"), side)
	return EnemyAI.new(civ, field, level, side)
