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


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 26
	_show_civ_select()


func _process(delta: float) -> void:
	if economy and battle.winner == -1:
		economy.tick(delta)
		ai.tick(delta)
		battle.tick(delta)


func _show_civ_select() -> void:
	var box := _vbox(self, 24)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_label("Choose your civilization", 40))
	var civs: Dictionary = GameConfig.data().civs
	for id in civs:
		var card := Card.new(civs[id].name)
		card.custom_minimum_size.y = 110
		var look := "classical: wood to marble" if civs[id].style == "classical" else "medieval: forts and castles"
		card.set_state("%s · %s" % [civs[id].bonus, look], true, false)
		card.pressed.connect(_start_game.bind(id, box.get_parent()))
		box.add_child(card)


func _start_game(civ_id: String, menu: Control) -> void:
	menu.queue_free()
	economy = Economy.new(civ_id)
	# Testing override: give the player a head start (remove from config.json to disable).
	var testing: Dictionary = GameConfig.data().get("testing", {})
	if testing.has("player_starting_resources"):
		economy.resources = testing.player_starting_resources.duplicate()
	economy.job_speed = testing.get("job_speed", 1.0)
	battle = Battlefield.new()
	var others: Array = GameConfig.data().civs.keys().filter(func(id): return id != civ_id)
	var enemy_civ: String = others.pick_random()
	ai = EnemyAI.new(enemy_civ, battle)
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
	box.add_child(_view)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	box.add_child(bar)
	for id in ["villager"] + GameConfig.data().units.keys():
		var title: String = "Villager" if id == "villager" else GameConfig.data().units[id].name
		var card := Card.new(title)
		card.pressed.connect(_on_card_pressed.bind(id))
		bar.add_child(card)
		_cards[id] = card

	economy.changed.connect(_refresh)
	economy.job_done.connect(_on_job_done)
	_refresh()


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
	_ui.title = _label("", 26)
	_ui.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_ui.hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
			_flash_hint("Drag the %s card onto a lane" % GameConfig.data().units[id].name)


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
		"barracks", "archery_range", "stables":
			if economy.build_military(id):
				_close_menu()
		"mill", "lumber_camp", "mill2", "lumber_camp2", "gold_mine2", "stone_mine2":
			if economy.buy_upgrade(id):
				_close_menu()
		"worker_gold", "worker_stone":
			economy.reassign("idle", id.trim_prefix("worker_"))
		"stone_towers":
			if economy.buy_upgrade(id):
				_close_menu()
	_refresh()


## Finished jobs that touch the battlefield: units walk out, towers go up.
func _on_job_done(job: Dictionary) -> void:
	match job.kind:
		"unit":
			battle.spawn(Battlefield.PLAYER, job.id, job.lane)
		"towers":
			battle.build_towers(Battlefield.PLAYER)
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
	return {"id": id, "icon": icon, "title": title, "note": note, "enabled": enabled, "ring": ring}


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
			var hut: Dictionary = cfg.buildings.hut
			var full: bool = economy.max_population() >= cfg.population.max_cap
			opts.append(_option("hut", "hut", "Hut +%d" % hut.population, "max pop" if full else _cost_text(hut.cost), economy.can_build_hut()))
			var towers: Dictionary = cfg.buildings.towers
			var tnote := _status_note(economy.has_towers, "towers", "towers", towers.min_era, towers.cost)
			opts.append(_option("towers", "towers", "Towers", tnote, economy.can_build_towers()))
			var mine: Dictionary = cfg.buildings.mine
			for res in Economy.MINED:
				var mnote := _status_note(economy.mines.has(res), "mine", res, mine.min_era, mine.cost)
				opts.append(_option(res, res, "%s mine" % res.capitalize(), mnote, economy.can_build_mine(res)))
			# Middle ring: military buildings.
			for id in cfg.military:
				var b: Dictionary = cfg.military[id]
				var bnote := _status_note(economy.military.has(id), "military", id, b.min_era, b.cost)
				opts.append(_option(id, id, b.name, bnote, economy.can_build_military(id), 1))
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
			opts.append(_upgrade_option(kind + "2"))
		"towers":
			opts.append(_upgrade_option("stone_towers"))
	return opts


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
	text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.add_child(text)
	var again := _label("Tap to play again", 30)
	again.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	again.position.y -= 200
	overlay.add_child(again)
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			get_tree().reload_current_scene())


func _refresh() -> void:
	var r := economy.resources
	_ui.title.text = "%s · %s   vs   %s (AI) · %s" % [economy.civ().name, economy.era().name, ai.economy.civ().name, ai.economy.era().name]
	for res in Economy.RESOURCES:
		_ui[res].text = "%d" % r[res]
	_ui.villagers.text = "%d (%d idle)" % [economy.total_villagers(), economy.villagers.get("idle", 0)]
	_ui.pop.text = "%d/%d" % [economy.population(), economy.max_population()]
	if Time.get_ticks_msec() > _ui.get("hint_until", 0):
		_ui.hint.text = "Drag cards onto the map · tap a worker to send it back"

	var dragging: String = _press.get("card", "") if _ghost else ""
	var vcost := economy.villager_cost()
	var vq := economy.pending_count("villager")
	_cards.villager.set_state("%d food%s" % [vcost.food, " · %d queued" % vq if vq else ""], economy.can_recruit(), dragging == "villager")
	var cfg := GameConfig.data()
	for id in cfg.units:
		var unit: Dictionary = cfg.units[id]
		var note: String = _cost_text(unit.cost).replace("\n", " ") if economy.unit_unlocked(id) \
			else "needs %s" % cfg.military[unit.requires].name
		var queued := economy.jobs.filter(func(j): return j.kind == "unit" and j.id == id).size()
		if queued:
			note += " · %d queued" % queued
		_cards[id].set_state(note, economy.can_train(id), dragging == id)


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
