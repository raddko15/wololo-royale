class_name Match
extends RefCounted
## One game: both sides' economies, the battlefield and, against the computer,
## its AI. Players change the game only through commands (apply), so the same
## commands can come from this device or, in a network game, from the other
## player. Each command is a Dictionary with an "op" and its arguments.

signal game_over(winner: int)
## Something only a player's own screen needs: {"team", "type", ...} — e.g. a
## deleted villager ({"type": "villager_died", "gone": {...}}).
signal event(e: Dictionary)

var battle: Battlefield
var economies: Array[Economy] = []
## The computer opponent (team ENEMY), or null when both sides are players.
var ai: EnemyAI
var paused := false
## Per side: troop types on AUTO, the lit recruit lanes, and the next lane
## each AUTO type takes.
var sides := []


## `opponent`: "ai:<easy|normal|hard>" for the computer, or "human".
func _init(player_civ: String, enemy_civ: String, opponent := "ai:normal") -> void:
	battle = Battlefield.new()
	economies.resize(2)
	economies[Battlefield.PLAYER] = Economy.new(player_civ)
	if opponent.begins_with("ai:"):
		ai = EnemyAI.new(enemy_civ, battle, opponent.trim_prefix("ai:"))
		economies[Battlefield.ENEMY] = ai.economy
	else:
		economies[Battlefield.ENEMY] = Economy.new(enemy_civ)
	for team in 2:
		sides.append({"auto": {}, "lanes_on": [false, true, false], "next_lane": {}})
		if is_human(team):
			# Players' troops wait by their towers until sent.
			battle.lane_orders[team] = ["stop", "stop", "stop"]
			battle.fort_civ_bonus(team, economies[team].civ().get("fort_bonus", {}))
			economies[team].job_done.connect(_on_job_done.bind(team))
	battle.unit_died.connect(func(team: int): if is_human(team): economies[team].army_size -= 1)
	battle.game_over.connect(func(w: int): game_over.emit(w))


func is_human(team: int) -> bool:
	return team == Battlefield.PLAYER or ai == null


func tick(delta: float) -> void:
	if paused or battle.winner != -1:
		return
	for team in 2:
		if is_human(team):
			_run_auto(team)
			economies[team].tick(delta)
	if ai:
		ai.tick(delta)
	battle.tick(delta)


# --- Commands -----------------------------------------------------------------

## Carry out one player's command. Returns {"ok": bool} plus, for some, a
## "hint" to show that player.
func apply(team: int, cmd: Dictionary) -> Dictionary:
	if battle.winner != -1 and cmd.op != "pause":
		return {"ok": false}
	var e: Economy = economies[team]
	var side: Dictionary = sides[team]
	match cmd.op:
		"recruit":
			return {"ok": e.recruit()}
		"recruit_to":  # a villager card dropped on a field: recruit, and send an idle one
			var ok := e.recruit()
			if ok:
				e.reassign("idle", cmd.job)
			return {"ok": ok}
		"train":
			return {"ok": e.train(cmd.unit, cmd.lane)}
		"auto":
			if cmd.on and e.unit_unlocked(cmd.unit):
				side.auto[cmd.unit] = true
				_run_auto(team)
			else:
				side.auto.erase(cmd.unit)
			return {"ok": true}
		"lanes_on":
			side.lanes_on[cmd.lane] = cmd.on
			return {"ok": true}
		"lane_order":
			battle.set_order(team, cmd.lane, cmd.order)
			return {"ok": true}
		"reassign":
			return {"ok": e.reassign(cmd.from, cmd.to)}
		"hut":
			return {"ok": e.build_hut()}
		"advance":
			return {"ok": e.advance()}
		"upgrade":
			return {"ok": e.buy_upgrade(cmd.id)}
		"military":
			return {"ok": e.build_military(cmd.id)}
		"mine":
			return {"ok": e.build_mine(cmd.id)}
		"camp":
			return {"ok": e.build_camp(cmd.id)}
		"towers":
			return {"ok": e.build_towers()}
		"cancel":
			if cmd.kind == "unit":
				side.auto.erase(cmd.id)  # or AUTO would queue it straight back
			return {"ok": e.cancel(cmd.kind, cmd.id)}
		"kill_villager":
			var gone := e.kill_villager()
			if not gone.is_empty():
				event.emit({"team": team, "type": "villager_died", "gone": gone})
			return {"ok": not gone.is_empty()}
		"pause":
			paused = cmd.on
			return {"ok": true}
		"fast":  # testing aids (single player)
			e.job_speed = cmd.speed
			return {"ok": true}
		"bonus":
			for res in Economy.RESOURCES:
				e.resources[res] += cmd.amount
			e.changed.emit()
			return {"ok": true}
	push_warning("unknown command %s" % cmd)
	return {"ok": false}


# --- Per side upkeep ----------------------------------------------------------

## Next lit lane in turn for a troop type, or -1 when none is lit.
func take_lane(team: int, unit_id: String) -> int:
	var side: Dictionary = sides[team]
	for k in Battlefield.LANES:
		var lane: int = (side.next_lane.get(unit_id, 0) + k) % Battlefield.LANES
		if side.lanes_on[lane]:
			side.next_lane[unit_id] = lane + 1
			return lane
	return -1


## Keep each AUTO troop type training at every building of its kind.
func _run_auto(team: int) -> void:
	var e: Economy = economies[team]
	var side: Dictionary = sides[team]
	if not side.lanes_on.has(true):
		return
	for id in side.auto:
		var waiting := e.jobs.filter(func(j): return j.kind == "unit" and j.id == id).size()
		var buildings: int = e.military.get(GameConfig.data().units[id].requires, 0)
		while waiting < buildings and e.can_train(id):
			e.train(id, -1)  # the lane is picked when it comes out
			waiting += 1


## Finished jobs that touch the battlefield: troops walk out, towers go up.
func _on_job_done(job: Dictionary, team: int) -> void:
	var e: Economy = economies[team]
	match job.kind:
		"unit":
			# AUTO troops take the next lit lane as they come out (so changing
			# the lanes redirects troops already in training); a dragged one
			# keeps the lane it was dropped on.
			var lane: int = job.lane if job.lane >= 0 else take_lane(team, job.id)
			if lane < 0:
				lane = 1  # no lane lit: the middle
			battle.spawn_squad(team, job.id, lane, e.squad(job.id), e.unit_bonus(job.id), e.unit_tier(job.id))
		"towers":
			battle.build_towers(team)
		"era":
			battle.fort_new_era(team, e.era_index)
		"upgrade":
			if job.id == "stone_towers":
				battle.upgrade_towers(team, GameConfig.data().upgrades.stone_towers.tower_hp_bonus)
