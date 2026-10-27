extends Control
## Pick a civ, then play: header, battlefield, card bar.
## Cards: drag Villager onto farm/forest (tap = idle villager), drag Fighter onto a lane.
## Tapping the town center opens its build window (era advance, later upgrades).

## Finger travel (px) below which a press counts as a tap, not a drag.
const TAP_SLOP := 20.0

var economy: Economy
var battle: Battlefield
var ai: EnemyAI
var _view: BattleView
var _ui := {}
var _cards := {}
## Active press on a card: {"card": id, "start": Vector2} or empty.
var _press := {}
var _ghost: Card
var _menu: RadialMenu
## Per unit type: lanes its auto-trained units go to (they take turns), the
## next lane in that rotation, and which types are on repeat.
var _lanes_on := {}
var _next_lane := {}
var _auto := {}
## Pause button: nothing moves, trains or gathers until the player resumes.
var _paused := false
var _pause_overlay: Control

## Opponent strength picked on the start screen (config ai.difficulty).
var _difficulty := "normal"


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 26
	_show_civ_select()


func _process(delta: float) -> void:
	if _paused:
		return
	if economy and battle.winner == -1:
		_run_auto()
	if economy and battle.winner == -1:
		economy.tick(delta)
		ai.tick(delta)
		battle.tick(delta)


func _show_civ_select() -> void:
	var screen := StartScreen.new(_difficulty)
	screen.chosen.connect(func(civ_id: String, level: String):
		_difficulty = level
		_start_game(civ_id, screen))
	add_child(screen)


func _start_game(civ_id: String, menu: Control) -> void:
	menu.queue_free()
	economy = Economy.new(civ_id)
	# Testing: "fast_at_start" starts with the Fast ×10 button on.
	var testing: Dictionary = GameConfig.data().get("testing", {})
	if testing.has("player_starting_resources"):
		economy.resources = testing.player_starting_resources.duplicate()
	economy.job_speed = testing.get("job_speed", 1.0) if testing.get("fast_at_start", false) else 1.0
	battle = Battlefield.new()
	var others: Array = GameConfig.data().civs.keys().filter(func(id): return id != civ_id)
	var enemy_civ: String = others.pick_random()
	ai = EnemyAI.new(enemy_civ, battle, _difficulty)
	battle.fort_civ_bonus(Battlefield.PLAYER, economy.civ().get("fort_bonus", {}))
	battle.unit_died.connect(func(team): if team == Battlefield.PLAYER: economy.army_size -= 1)
	battle.game_over.connect(_on_game_over)
	var box := _vbox(self, 0)

	box.add_child(_header())
	_ui.fast.set_pressed_no_signal(economy.job_speed > 1.0)
	_ui.fast.text = "Fast ×10 ON" if economy.job_speed > 1.0 else "Fast ×10"

	_view = BattleView.new()
	_view.economy = economy
	_view.enemy_economy = ai.economy
	_view.battle = battle
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.building_tapped.connect(_open_menu)
	_view.hut_tapped.connect(func():
		if not economy.build_hut():
			_flash_hint("Need %d wood for a hut" % GameConfig.data().buildings.hut.cost.wood if economy.max_population() < GameConfig.data().population.max_cap else "Population is at the maximum"))
	_view.site_tapped.connect(_on_site_tapped)
	_view.gather_tapped.connect(func(lane: int):
		var on: bool = not battle.gather[Battlefield.PLAYER][lane]
		battle.set_gather(Battlefield.PLAYER, lane, on)
		_flash_hint("Gathering: new troops wait by the tower. Tap the swords to charge!" if on else "Gathering off: troops march straight out"))
	_view.charge_tapped.connect(func(lane: int): battle.charge(Battlefield.PLAYER, lane))
	_view.hint.connect(_flash_hint)
	_view.upgrade_badge_tapped.connect(func(id: String):
		if id == "era":
			economy.advance()
		else:
			economy.buy_upgrade(id))
	box.add_child(_view)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	box.add_child(bar)
	for id in ["villager"] + economy.available_units():
		var title: String = "Villager" if id == "villager" else GameConfig.data().units[id].name
		var card := Card.new(title)
		card.pressed.connect(_on_card_pressed.bind(id))
		card.cancel_pressed.connect(_on_card_cancel.bind(id))
		if id == "villager":
			card.delete_pressed.connect(func():
				var gone := economy.kill_villager()
				if not gone.is_empty():
					_view.villager_died(gone)
				_refresh())
		_cards[id] = card
		# Unit cards get their own L / M / R lane switches underneath.
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		col.add_child(card)
		if id == "villager":
			var spacer := Control.new()
			spacer.custom_minimum_size.y = 40
			col.add_child(spacer)
		else:
			_lanes_on[id] = [false, true, false]
			_next_lane[id] = 0
			col.add_child(_lane_switches(id))
		bar.add_child(col)
	_update_lane_marks()

	economy.changed.connect(_refresh)
	economy.job_done.connect(_on_job_done)
	_refresh()


## Left / Middle / Right play-pause switches for one unit type: where its
## auto-trained units walk.
func _lane_switches(unit_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for lane in Battlefield.LANES:
		var t := LaneToggle.new(["L", "M", "R"][lane], _lanes_on[unit_id][lane], true)
		t.toggled.connect(func(on: bool):
			_lanes_on[unit_id][lane] = on
			_update_lane_marks())
		row.add_child(t)
	return row


## Chevrons on the map: lanes that some AUTO unit is currently sent down.
func _update_lane_marks() -> void:
	var marks := [false, false, false]
	for id in _auto:
		for lane in Battlefield.LANES:
			marks[lane] = marks[lane] or _lanes_on[id][lane]
	_view.active_lanes = marks


## Next active lane in turn for a unit type, or -1 when all its lanes are paused.
func _take_lane(unit_id: String) -> int:
	for k in Battlefield.LANES:
		var lane: int = (_next_lane[unit_id] + k) % Battlefield.LANES
		if _lanes_on[unit_id][lane]:
			_next_lane[unit_id] = lane + 1
			return lane
	return -1


func _header() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2b2620")
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	panel.add_child(col)
	# Title row with a restart button (testing aid) on the right.
	var top := HBoxContainer.new()
	col.add_child(top)
	_ui.title = _label("", 22)
	_ui.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Never wider than the space left by the buttons: a long title would push
	# the whole screen wider than the phone.
	_ui.title.clip_text = true
	_ui.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_ui.title)
	var restart := Button.new()
	restart.text = "Restart"
	restart.add_theme_font_size_override("font_size", 20)
	restart.focus_mode = Control.FOCUS_NONE
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	# Testing aid: makes the player's builds, training and research 10x faster.
	_ui.fast = Button.new()
	_ui.fast.toggle_mode = true
	_ui.fast.add_theme_font_size_override("font_size", 20)
	_ui.fast.focus_mode = Control.FOCUS_NONE
	_ui.fast.toggled.connect(func(on: bool):
		economy.job_speed = maxf(GameConfig.data().get("testing", {}).get("job_speed", 10.0), 2.0) if on else 1.0
		_ui.fast.text = "Fast ×10 ON" if on else "Fast ×10")
	top.add_child(_ui.fast)
	# Testing aid: tap for +10k of every resource.
	var rich := Button.new()
	var bonus: int = GameConfig.data().get("testing", {}).get("bonus_resources", 10000)
	rich.text = "+%dk" % (bonus / 1000)
	rich.add_theme_font_size_override("font_size", 20)
	rich.focus_mode = Control.FOCUS_NONE
	rich.pressed.connect(func():
		for res in Economy.RESOURCES:
			economy.resources[res] += bonus
		_refresh())
	top.add_child(rich)
	var pause := Button.new()
	pause.text = "Pause"
	pause.add_theme_font_size_override("font_size", 20)
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(_set_paused.bind(true))
	top.add_child(pause)
	top.add_child(restart)
	for row_keys in [Economy.RESOURCES, ["villagers", "pop"]]:
		var row := HBoxContainer.new()
		col.add_child(row)
		for key in row_keys:
			var item := HBoxContainer.new()
			item.alignment = BoxContainer.ALIGNMENT_CENTER
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item.add_child(HudIcon.new(key))
			_ui[key] = _label("", 26)
			item.add_child(_ui[key])
			row.add_child(item)
	_ui.hint = _label("", 22)
	_ui.hint.add_theme_color_override("font_color", Color("#f9ca24"))
	# Always exactly one line (long hints end in "…"), so the map never shifts.
	_ui.hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ui.hint.clip_text = true
	col.add_child(_ui.hint)
	return panel


# --- Cards: tap and drag ------------------------------------------------

func _on_card_pressed(id: String) -> void:
	if battle.winner != -1:
		return
	_press = {"card": id, "start": get_global_mouse_position()}


func _input(event: InputEvent) -> void:
	if _press.is_empty():
		return
	var pos := get_global_mouse_position()
	if event is InputEventMouseMotion:
		if pos.distance_to(_press.start) > TAP_SLOP:
			_drag_to(pos)
	elif event is InputEventMouseButton and not event.pressed:
		if _ghost:
			_drop(_press.card, pos - _view.global_position)
		else:
			_tap(_press.card)
		_end_drag()


func _drag_to(pos: Vector2) -> void:
	if not _ghost:
		_ghost = Card.new(_cards[_press.card]._title.text)
		_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ghost.set_state("", true, true)
		_ghost.modulate.a = 0.7
		_ghost.top_level = true
		_ghost.custom_minimum_size = Vector2(130, 100)
		add_child(_ghost)
		_view.drag_card = _press.card
	_ghost.position = pos - Vector2(65, 120)
	_view.drag_pos = pos - _view.global_position


func _end_drag() -> void:
	_press = {}
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_view.drag_card = ""
	_refresh()


func _tap(id: String) -> void:
	match id:
		"villager":
			economy.recruit()
		_:
			# Tap toggles training on repeat into this unit's active lanes.
			if _auto.has(id):
				_auto.erase(id)
			elif economy.unit_unlocked(id):
				_auto[id] = true
				_run_auto()
			else:
				_flash_hint(_unit_lock(id))
			_update_lane_marks()


func _drop(id: String, local: Vector2) -> void:
	match id:
		"villager":
			var job := _view.job_at(local)
			if job != "" and economy.recruit():
				economy.reassign("idle", job)
		_:
			var lane := _view.lane_at(local)
			if lane != -1:
				economy.train(id, lane)  # walks out when its building finishes it


## Keep each auto unit training at every building of its kind; the next starts as soon as it is
## affordable, sent to that unit's active lanes in turn. All paused: wait.
func _run_auto() -> void:
	for id in _auto:
		if not _lanes_on[id].has(true):
			continue
		# One in training per building of its kind, so 3 barracks train 3 at once.
		var waiting := economy.jobs.filter(func(j): return j.kind == "unit" and j.id == id).size()
		var buildings: int = economy.military.get(GameConfig.data().units[id].requires, 0)
		while waiting < buildings and economy.can_train(id):
			economy.train(id, _take_lane(id))
			waiting += 1


## Freeze or resume the whole game. While paused a dark screen says so;
## tapping anywhere resumes.
func _set_paused(on: bool) -> void:
	if on == _paused or battle == null or battle.winner != -1:
		return
	_paused = on
	_view.paused = on
	if on:
		_end_drag()
		_close_menu()
		_pause_overlay = ColorRect.new()
		_pause_overlay.color = Color(0, 0, 0, 0.6)
		_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_pause_overlay)
		var title := _label("Paused", 72)
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_pause_overlay.add_child(title)
		var again := _label("Tap to resume", 30)
		again.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		again.offset_top = -260
		again.offset_bottom = -200
		_pause_overlay.add_child(again)
		_pause_overlay.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				_set_paused(false))
	elif _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null


func _flash_hint(text: String) -> void:
	_ui.hint.text = text
	_ui.hint_until = Time.get_ticks_msec() + 2000


# --- Building menus ------------------------------------------------------
# Tapping a building opens a ring of round options above it (Polytopia style).
# Only the town center changes with the era; other buildings change look
# through the upgrades bought here.

func _open_menu(kind: String, at: Vector2) -> void:
	if _menu or battle.winner != -1:
		return
	_menu = RadialMenu.new(_view.global_position + at, _menu_options.bind(kind))
	_menu.chosen.connect(_on_menu_choice)
	_menu.closed.connect(_close_menu)
	add_child(_menu)


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _on_menu_choice(id: String) -> void:
	var cfg := GameConfig.data()
	match id:
		"era":
			if economy.advance():
				_close_menu()
		"hut":
			economy.build_hut()
		"towers":
			if economy.build_towers():
				_close_menu()
		"gold", "stone":
			if economy.build_mine(id):
				_close_menu()
		"farm", "lumberjack":
			if economy.build_camp(id):
				_close_menu()
		"barracks", "archery_range", "stables":
			if economy.build_military(id):
				_close_menu()
		_ when cfg.upgrades.has(id):
			if economy.buy_upgrade(id):
				_close_menu()
		"worker_gold", "worker_stone":
			economy.reassign("idle", id.trim_prefix("worker_"))
		"unworker_gold", "unworker_stone":
			economy.reassign(id.trim_prefix("unworker_"), "idle")
	_refresh()


## An empty plot on the map was tapped: build it, or say what's missing.
func _on_site_tapped(id: String) -> void:
	var cfg := GameConfig.data()
	var cost: Dictionary
	var name: String
	if cfg.military.has(id):
		cost = cfg.military[id].cost
		name = cfg.military[id].name
	elif id in Economy.CAMP_FOR.values():
		cost = cfg.buildings[id].cost
		name = cfg.buildings[id].name
	elif id in Economy.MINED:
		cost = economy.mine_cost()
		name = "%s mine" % id.capitalize()
	else:
		cost = cfg.buildings.towers.cost
		name = "Towers"
	var before := economy.jobs.size()
	_on_menu_choice(id)
	if economy.jobs.size() == before:
		_flash_hint("%s needs %s" % [name, _cost_text(cost).replace("\n", " ")])


## The ✕ on a card: take back the newest queued one (refunded). Cancelling a
## unit also stops its AUTO, or AUTO would queue it straight back.
func _on_card_cancel(id: String) -> void:
	if id == "villager":
		economy.cancel("villager", "villager")
	else:
		_auto.erase(id)
		economy.cancel("unit", id)
	_refresh()


## Why a unit card is locked: "needs Stables" or "needs Era III".
func _unit_lock(id: String) -> String:
	var cfg := GameConfig.data()
	var unit: Dictionary = cfg.units[id]
	if not economy.military.has(unit.requires):
		return "needs %s" % cfg.military[unit.requires].name
	return "needs %s" % cfg.eras[unit.get("min_era", 0)].name


## Finished jobs that touch the battlefield: units walk out, towers go up.
func _on_job_done(job: Dictionary) -> void:
	match job.kind:
		"unit":
			battle.spawn_squad(Battlefield.PLAYER, job.id, job.lane, economy.squad(job.id), economy.unit_bonus(job.id), economy.unit_tier(job.id))
		"towers":
			battle.build_towers(Battlefield.PLAYER)
		"era":
			battle.fort_new_era(Battlefield.PLAYER, economy.era_index)
		"upgrade":
			if job.id == "stone_towers":
				battle.upgrade_towers(Battlefield.PLAYER, GameConfig.data().upgrades.stone_towers.tower_hp_bonus)


## Ring note for something that may be done, under way, locked by era, or buyable.
func _status_note(done: bool, kind: String, id: String, min_era: int, cost: Dictionary) -> String:
	if done:
		return "built"
	if economy.is_pending(kind, id):
		return "in progress"
	if economy.era_index < min_era:
		return GameConfig.data().eras[min_era].name
	return _cost_text(cost)


## "150 wood", or two per line for bigger costs so ring labels stay narrow.
static func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for res in Economy.RESOURCES:
		if cost.has(res):
			parts.append("%d %s" % [cost[res], res])
	var lines := []
	for i in range(0, parts.size(), 2):
		lines.append(" ".join(parts.slice(i, i + 2)))
	return "\n".join(lines)


func _option(id: String, icon: String, title: String, note: String, enabled: bool, ring := 0) -> Dictionary:
	return {"id": id, "icon": icon, "title": title, "note": note, "enabled": enabled, "ring": ring, "art": _icon_art(id)}


## Picture for a menu option: the building it makes, in the same art as on the
## map ({} keeps the drawn glyph). "layers" are drawn in order, each with its
## civ-tinted "_tint" layer when one exists; "sails" adds windmill sails at that
## hub (fraction of the picture).
func _icon_art(id: String) -> Dictionary:
	var classical := economy.style() == "classical"
	var tint := Color(economy.civ().color)
	var art := func(layers: Array, size_px: Vector2, extra := {}) -> Dictionary:
		var d := {"layers": layers, "size": size_px, "tint": tint}
		d.merge(extra)
		return d
	match id:
		"era":
			var next := mini(economy.era_index + 1, GameConfig.data().eras.size() - 1)
			if next == 1:
				return art.call(["timber_hall" if classical else "fort_wood"], Vector2(174, 137))
			return art.call(["marble_palace" if classical else "castle_stone"], Vector2(174, 137))
		"farm":
			return art.call(["granary"], Vector2(84, 67))
		"lumberjack":
			return art.call(["lean_to"], Vector2(62, 46))
		"hut":
			var look := "era0" if economy.era_index == 0 else economy.style()
			return art.call(["hut_" + look], Vector2(30, 27))
		"towers":
			return art.call(["tower_wood"], Vector2(56, 84))
		"stone_towers":
			return art.call(["tower_marble" if classical else "tower_stone"], Vector2(56, 84))
		"gold", "stone":
			return art.call([id + "_mine"], Vector2(62, 49))
		"gold_mine2", "stone_mine2":
			return art.call([id], Vector2(62, 49))
		"barracks", "archery_range", "stables":
			return art.call([id + "_era0"], Vector2(80, 65))
		"mill":
			if classical:
				return art.call(["olive_press"], Vector2(64, 56))
			return art.call(["windmill_base"], Vector2(64, 56), {"sails": Vector2(29, 22) / Vector2(64, 56), "blade": 26.0 / 64.0})
		"mill2":
			if classical:
				return art.call(["oil_workshop"], Vector2(64, 56))
			return art.call(["grand_mill_base"], Vector2(64, 56), {"sails": Vector2(29, 14) / Vector2(64, 56), "blade": 32.0 / 64.0})
		"lumber_camp":
			return art.call(["timber_yard" if classical else "lumber_camp"], Vector2(62, 46))
		"lumber_camp2":
			return art.call(["carpentry" if classical else "sawmill"], Vector2(62, 46))
	for mil in GameConfig.data().military:
		for tier in [1, 2]:
			if id == mil + str(tier):
				var layers := [mil + "_" + economy.style()]
				if tier == 2:
					layers.append("mil_tier2")
				layers.append("mil_tier1")
				return art.call(layers, Vector2(80, 65))
	return {}


## What a tapped building offers right now; locked options say why.
func _menu_options(kind: String) -> Array:
	var cfg := GameConfig.data()
	var era_name := func(i: int) -> String: return cfg.eras[i].name
	var opts := []
	match kind:
		"town_center":
			var ecost := economy.next_era_cost()
			if ecost.is_empty():
				opts.append(_option("era", "era", "Final era", "", false))
			else:
				var enote := "in progress" if economy.is_pending("era", "next") else _cost_text(ecost)
				opts.append(_option("era", "era", era_name.call(economy.era_index + 1), enote, economy.can_advance()))
			# Farm and lumberjack until they are built.
			for id in ["lumberjack", "farm"]:
				if not economy.camps.has(id):
					var c: Dictionary = cfg.buildings[id]
					var cnote := "in progress" if economy.is_pending("camp", id) else _cost_text(c.cost)
					opts.append(_option(id, "hut", c.name, cnote, economy.can_build_camp(id)))
			var hut: Dictionary = cfg.buildings.hut
			var full: bool = economy.max_population() >= cfg.population.max_cap
			opts.append(_option("hut", "hut", "Hut +%d" % hut.population, "max pop" if full else _cost_text(hut.cost), economy.can_build_hut()))
			var towers: Dictionary = cfg.buildings.towers
			var tnote := _status_note(economy.has_towers, "towers", "towers", towers.min_era, towers.cost)
			opts.append(_option("towers", "towers", "Towers", tnote, economy.can_build_towers()))
			var mine: Dictionary = cfg.buildings.mine
			for res in Economy.MINED:
				var mnote := _status_note(economy.mines.has(res), "mine", res, economy.mine_era(res), mine.cost)
				opts.append(_option(res, res, "%s mine" % res.capitalize(), mnote, economy.can_build_mine(res)))
			# Middle ring: military buildings.
			for id in cfg.military:
				opts.append(_military_option(id, 1))
			# Outer ring: the next upgrade of every building, so it can all be done from here.
			for id in _next_upgrades():
				var up := _upgrade_option(id)
				up.ring = 2
				opts.append(up)
		"mill", "lumber_camp":
			# Offer the next tier: the Era II upgrade, then the Era III one.
			opts.append(_upgrade_option(kind + "2" if economy.upgrades.has(kind) else kind))
		"gold_mine", "stone_mine":
			var res := kind.trim_suffix("_mine")
			var idle: int = economy.villagers.get("idle", 0)
			opts.append(_option("worker_" + res, "worker", "+ Worker", "%d idle" % idle, idle > 0))
			var mining: int = economy.villagers.get(res, 0)
			opts.append(_option("unworker_" + res, "unworker", "− Worker", "%d mining" % mining, mining > 0))
			opts.append(_upgrade_option(kind + "2"))
		"towers":
			opts.append(_upgrade_option("stone_towers"))
		"barracks", "archery_range", "stables":
			opts.append(_military_option(kind, 0))
			opts.append(_upgrade_option(kind + ("2" if economy.upgrades.has(kind + "1") else "1")))
	for o in opts:
		o.desc = _describe(o.id)
	return opts


## Barracks / range / stables: the first one, or another (up to 3) that
## trains alongside the others.
func _military_option(id: String, ring: int) -> Dictionary:
	var cfg := GameConfig.data()
	var b: Dictionary = cfg.military[id]
	var have: int = economy.military.get(id, 0)
	var most: int = cfg.max_of_each_military
	var title: String = b.name if have == 0 else "%s %d/%d" % [b.name, have, most]
	var note := _status_note(have >= most, "military", id, b.min_era, b.cost)
	if have >= most:
		note = "max built"
	var camp: String = b.get("requires_camp", "")
	if camp != "" and not economy.camps.has(camp):
		note = "needs " + cfg.buildings[camp].name
	return _option(id, id, title, note, economy.can_build_military(id), ring)


## One short line on what an option does (shown under its title).
func _describe(id: String) -> String:
	var cfg := GameConfig.data()
	if cfg.upgrades.has(id):
		var up: Dictionary = cfg.upgrades[id]
		var parts := []
		for res in up.get("gather_bonus", {}):
			parts.append("+%d%% %s gathering" % [roundi(up.gather_bonus[res] * 100), res])
		for stat in up.get("unit_bonus", {}):
			parts.append("+%d%% %s" % [roundi(up.unit_bonus[stat] * 100), {"hp": "HP", "damage": "dmg", "range": "range"}[stat]])
		if up.has("tower_hp_bonus"):
			parts.append("+%d%% tower HP" % roundi(up.tower_hp_bonus * 100))
		return ", ".join(parts)
	if cfg.military.has(id):
		var unit := ""
		for u in cfg.units:
			if cfg.units[u].requires == id and not cfg.units[u].has("civ"):
				unit = cfg.units[u].name
		return ("trains %ss" % unit) if not economy.military.has(id) else "+1 %s at a time" % unit
	match id:
		"era":
			var next := economy.era_index + 1
			if next >= cfg.eras.size():
				return ""
			return "new buildings, faster villagers"
		"hut":
			return "+%d population" % cfg.buildings.hut.population
		"towers":
			return "a tower on each lane"
		"gold", "stone":
			return "lets villagers mine %s" % id
		"farm":
			return "lets villagers gather food"
		"lumberjack":
			return "lets villagers gather wood"
		"worker_gold", "worker_stone":
			return "send an idle villager"
		"unworker_gold", "unworker_stone":
			return "back to idle"
	return ""


## Next not-yet-bought upgrade for each building that exists; finished chains drop out.
func _next_upgrades() -> Array:
	var ids := []
	for chain in [["mill", "mill2"], ["lumber_camp", "lumber_camp2"]]:
		for id in chain:
			if not economy.upgrades.has(id):
				ids.append(id)
				break
	if battle.towers_built[Battlefield.PLAYER] and not economy.upgrades.has("stone_towers"):
		ids.append("stone_towers")
	for res in Economy.MINED:
		if economy.mines.has(res) and not economy.upgrades.has(res + "_mine2"):
			ids.append(res + "_mine2")
	for id in economy.military:
		for next in [id + "1", id + "2"]:
			if not economy.upgrades.has(next):
				ids.append(next)
				break
	return ids


func _upgrade_option(id: String) -> Dictionary:
	var cfg := GameConfig.data()
	var up: Dictionary = cfg.upgrades[id]
	var note: String
	if economy.upgrades.has(id):
		note = "done"
	elif economy.is_pending("upgrade", id):
		note = "in progress"
	elif economy.era_index < up.min_era:
		note = "needs %s" % cfg.eras[up.min_era].name
	elif not economy.upgrade_unlocked(id):
		note = "needs earlier upgrade"
	else:
		note = _cost_text(up.cost)
	return _option(id, "upgrade", economy.upgrade_name(id), note, economy.can_upgrade(id))


# --- Display ------------------------------------------------------------

func _on_game_over(winner: int) -> void:
	_end_drag()
	_close_menu()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var won := winner == Battlefield.PLAYER
	var text := _label("Victory!" if won else "Defeat", 72)
	text.add_theme_color_override("font_color", Color("#f9ca24") if won else Color("#e55039"))
	# Full-width labels with centered text, so they stay centered whatever their size.
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_child(text)
	var again := _label("Tap to play again", 30)
	again.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	again.offset_top = -260
	again.offset_bottom = -200
	overlay.add_child(again)
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			get_tree().reload_current_scene())


func _refresh() -> void:
	var r := economy.resources
	_ui.title.text = "%s · %s  vs  %s (%s) · %s" % [economy.civ().name, economy.era().name, ai.economy.civ().name, ai.difficulty.capitalize(), ai.economy.era().name]
	for res in Economy.RESOURCES:
		_ui[res].text = "%d" % r[res]
	_ui.villagers.text = "%d (%d idle)" % [economy.total_villagers(), economy.villagers.get("idle", 0)]
	_ui.pop.text = "%d/%d" % [economy.population(), economy.max_population()]
	var full := not economy.has_room()
	_ui.pop.add_theme_color_override("font_color", Color("#e55039") if full else Color.WHITE)
	if Time.get_ticks_msec() > _ui.get("hint_until", 0):
		_ui.hint.text = "Tap a unit card for AUTO · its L/M/R switches pick lanes · drag for one unit"

	var dragging: String = _press.get("card", "") if _ghost else ""
	var vcost := economy.villager_cost()
	var vq := economy.pending_count("villager")
	var vnote := "pop full: build huts" if full else "%d food%s" % [vcost.food, " · %d queued" % vq if vq else ""]
	_cards.villager.set_state(vnote, economy.can_recruit(), dragging == "villager")
	_cards.villager.set_queued(vq)
	_cards.villager.set_deletable(economy.total_villagers() > 0)
	var cfg := GameConfig.data()
	for id in economy.available_units():
		var unit: Dictionary = cfg.units[id]
		var note: String = _cost_text(unit.cost).replace("\n", " ") if economy.unit_unlocked(id) else _unit_lock(id)
		var queued := economy.jobs.filter(func(j): return j.kind == "unit" and j.id == id).size()
		if queued:
			note += " · %d queued" % queued
		if full and economy.unit_unlocked(id):
			note = "pop full: build huts"
		_cards[id].set_state(note, economy.can_train(id), dragging == id, _auto.has(id))
		_cards[id].set_queued(queued)
		var tier := economy.unit_tier(id)
		_cards[id]._title.text = unit.name + (" Lv%d" % (tier + 1) if tier else "")


func _vbox(parent: Control, margin_px: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, margin_px)
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	return l
