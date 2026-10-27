extends SceneTree
## Head-to-head fights in one lane: godot --headless -s res://tests/duel_sim.gd
## Prints who is left standing for each pairing of N vs N.

func _init() -> void:
	var pairs := [["cavalry", "archer"], ["archer", "fighter"], ["fighter", "cavalry"],
		["fighter", "fighter"], ["knight", "fighter"], ["phalanx", "cavalry"], ["chariot", "fighter"]]
	for p in pairs:
		for mixed in [false, true]:
			print(_fight(p[0], p[1], 5, mixed))
	# Roughly equal spending: 7 fighters (560) vs 5 cavalry (550).
	print(_fight("fighter", "cavalry", 7, false, 5))
	quit()


## `mixed`: the defender (b) has fighters in front of its archers/others, to
## see if a charge gets through to what it counters.
func _fight(a: String, b: String, n: int, mixed: bool, n_b := -1) -> String:
	if n_b < 0:
		n_b = n
	var f := Battlefield.new()
	f.buildings[0].main = 1e9
	f.buildings[1].main = 1e9
	for i in n:
		var u := f.spawn(Battlefield.PLAYER, a, 1)
		u.y = 0.3 - i * 0.01
	for i in n_b:
		var unit_type: String = b
		var y := 0.7 + i * 0.01
		if mixed and i < 2 and b != "fighter":
			unit_type = "fighter"
			y = 0.62 + i * 0.01
		var v := f.spawn(Battlefield.ENEMY, unit_type, 1)
		v.y = y
	var t := 0.0
	while t < 120.0:
		f.tick(0.1)
		t += 0.1
		var left := [0, 0]
		for u in f.units:
			left[u.team] += 1
		if left[0] == 0 or left[1] == 0:
			break
	var left_a := f.units.filter(func(u): return u.team == 0).map(func(u): return u.type)
	var left_b := f.units.filter(func(u): return u.team == 1).map(func(u): return u.type)
	return "%d %s vs %d %s%s: %ds -> A left %s, B left %s" % [n, a, n_b, b, " (2 fighters in front)" if mixed else "", int(t), left_a, left_b]
