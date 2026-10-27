extends SceneTree
## Traces one AI's economy: godot --headless -s res://tests/ai_trace.gd -- <level> [seconds] [civ]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var level: String = args[0] if args.size() > 0 else "hard"
	var secs: float = float(args[1]) if args.size() > 1 else 600.0
	var civ: String = args[2] if args.size() > 2 else "franks"
	var field := Battlefield.new()
	var ai := EnemyAI.new(civ, field, level, Battlefield.ENEMY)
	var t := 0.0
	while t < secs:
		ai.tick(0.1)
		field.tick(0.1)
		t += 0.1
		if int(round(t * 10)) % 300 == 0:
			var e := ai.economy
			var goal := ai._next_goal()
			print("%4ds era %d vil %s pop %d/%d res %s army %d jobs %s mil %s mines %s ups %d goal %s" % [int(t), e.era_index, e.villagers, e.population(), e.max_population(),
				e.resources.values().map(func(v): return int(v)), e.army_size, e.jobs.map(func(j): return j.kind + ":" + j.id), e.military, e.mines.keys(), e.upgrades.size(), goal.get("cost", {})])
	quit()
