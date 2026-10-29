extends SceneTree
## Two players on one machine through a running relay: the host's screen
## (hidden) and the guest's, which is saved as a PNG (needs a display).
## Args: <out.png> <relay url, e.g. ws://127.0.0.1:8099>

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await process_frame


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var url: String = args[1]
	var host = load("res://scenes/main.tscn").instantiate()
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(host)
	root.add_child(guest)
	host.visible = false
	await process_frame
	for m in [host, guest]:
		m.net = Net.new()
		m.add_child(m.net)
	var code := []
	host.net.room_made.connect(func(c: String): code.append(c))
	host.net.host("romans", url)
	await _wait(1.0)
	_check(code.size() == 1, "the host gets a room code")
	var roles := {}
	for m in [host, guest]:
		m.net.started.connect(func(role: String, civ: String): roles[role] = civ)
	guest.net.join(code[0].to_lower(), "greeks", url)
	await _wait(1.0)
	_check(roles.get("host") == "greeks" and roles.get("guest") == "romans", "both hear who they play")
	host._start_game("romans", host.get_child(0), "greeks", "host")
	guest._start_game("greeks", guest.get_child(0), "romans", "guest")
	await _wait(0.5)
	_check(guest.game is Mirror and guest.economy.civ().name == "Greeks", "the guest plays the Greeks at the bottom")
	_check(guest._ui.title.text.contains("Friend"), "the title names the friend")
	var before: int = host.game.economies[Battlefield.ENEMY].jobs.size()
	guest._do({"op": "recruit"})
	guest._do({"op": "lane_order", "lane": 0, "order": "march"})
	await _wait(1.5)  # two 3D games in one process draw slowly
	_check(host.game.economies[Battlefield.ENEMY].jobs.size() == before + 1, "the guest's recruit reaches the host")
	_check(host.battle.lane_orders[Battlefield.ENEMY][0] == "march", "the guest's order reaches the host")
	_check(guest.economy.jobs.size() == before + 1, "the guest sees their villager training")
	# A fighter for each side, then let them walk.
	for m in [host, guest]:
		m._do({"op": "bonus", "amount": 0})
	for team in 2:
		host.game.economies[team].military = {"barracks": 1}
		host.game.economies[team].resources.gold += 500
		host.game.economies[team].job_speed = 20.0
	host._do({"op": "train", "unit": "fighter", "lane": 1})
	guest._do({"op": "train", "unit": "fighter", "lane": 1})
	host._do({"op": "lane_order", "lane": 1, "order": "march"})
	guest._do({"op": "lane_order", "lane": 1, "order": "march"})
	await _wait(4.0)
	var mine: Array = guest.battle.units.filter(func(u): return u.team == Battlefield.PLAYER)
	var theirs: Array = guest.battle.units.filter(func(u): return u.team == Battlefield.ENEMY)
	_check(mine.size() > 0 and theirs.size() > 0, "the guest sees both armies (%d, %d)" % [mine.size(), theirs.size()])
	guest._set_paused(true)
	await _wait(0.5)
	_check(host.game.paused and host._paused, "the guest's pause stops the host's game too")
	host._set_paused(false)
	await _wait(1.0)
	_check(not guest._paused, "the host's resume reaches the guest")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0])
	guest.net.close()
	await _wait(0.5)
	_check(host._over, "the host wins when the guest leaves")
	print("FAILURES: %d" % _fails)
	quit()
