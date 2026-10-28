extends SceneTree
## Size of a network snapshot during a busy AI-vs-AI game (bytes, raw and compressed).

func _init() -> void:
	var game := Match.new("romans", "franks", "ai:hard")
	var other := EnemyAI.new("greeks", game.battle, "hard", Battlefield.PLAYER)
	game.economies[Battlefield.PLAYER] = other.economy
	var t := 0.0
	while t < 420.0 and game.battle.winner == -1:
		other.tick(0.1)
		game.tick(0.1)
		t += 0.1
		if int(round(t * 10)) % 600 == 0:
			var bytes := var_to_bytes(Snapshot.capture(game, Battlefield.ENEMY, []))
			print("%ds units %d arrows %d -> %d bytes, %d compressed" % [int(t), game.battle.units.size(), game.battle.arrows.size(),
				bytes.size(), bytes.compress(FileAccess.COMPRESSION_ZSTD).size()])
	quit()
