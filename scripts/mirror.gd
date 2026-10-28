class_name Mirror
extends RefCounted
## The guest's side of a network game: a copy of the match kept up to date
## from the host's snapshots, shaped like Match (battle, economies, sides,
## apply, tick) so the screen works the same. It simulates nothing; commands
## are sent to the host, and the guest always plays the bottom side (PLAYER),
## since snapshots for the guest are flipped.

signal game_over(winner: int)
signal event(e: Dictionary)

var battle := Battlefield.new()
var economies: Array[Economy] = []
var sides := [{"lanes_on": [false, true, false], "auto": {}}, {"lanes_on": [false, true, false], "auto": {}}]
var ai = null
var paused := false
## Sends a command to the host: send.call(cmd).
var send: Callable
var _over := false


func _init(my_civ: String, their_civ: String, sender: Callable) -> void:
	economies.append(Economy.new(my_civ))
	economies.append(Economy.new(their_civ))
	send = sender


func is_human(_team: int) -> bool:
	return true


func tick(_delta: float) -> void:
	pass  # the host runs the game


## Send the command to the host. The answer only predicts whether it will go
## through (from the copy here), for hints and closing menus.
func apply(_team: int, cmd: Dictionary) -> Dictionary:
	send.call(cmd)
	var e: Economy = economies[Battlefield.PLAYER]
	var ok := true
	match cmd.op:
		"recruit", "recruit_to":
			ok = e.can_recruit()
		"train":
			ok = e.can_train(cmd.unit)
		"hut":
			ok = e.can_build_hut()
		"advance":
			ok = e.can_advance()
		"upgrade":
			ok = e.can_upgrade(cmd.id)
		"military":
			ok = e.can_build_military(cmd.id)
		"mine":
			ok = e.can_build_mine(cmd.id)
		"camp":
			ok = e.can_build_camp(cmd.id)
		"towers":
			ok = e.can_build_towers()
		"lanes_on":
			sides[Battlefield.PLAYER].lanes_on[cmd.lane] = cmd.on  # show it at once
		"auto":
			if cmd.on:
				sides[Battlefield.PLAYER].auto[cmd.unit] = true
			else:
				sides[Battlefield.PLAYER].auto.erase(cmd.unit)
	return {"ok": ok}


## A snapshot arrived from the host.
func receive(snap: Dictionary) -> void:
	Snapshot.restore(snap, battle, economies)
	for local in 2:
		sides[local].lanes_on = snap.sides[local].lanes_on
		var auto := {}
		for id in snap.sides[local].auto:
			auto[id] = true
		sides[local].auto = auto
	for e in snap.events:
		e.team = Battlefield.PLAYER
		event.emit(e)
	economies[Battlefield.PLAYER].changed.emit()
	if battle.winner != -1 and not _over:
		_over = true
		game_over.emit(battle.winner)
