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
		card.set_state("", true, false)
		card.pressed.connect(_start_game.bind(id, box.get_parent()))
		box.add_child(card)
	box.add_child(_label("Romans: +10% wood   Greeks: +10% food", 24))


func _start_game(civ_id: String, menu: Control) -> void:
	menu.queue_free()
	economy = Economy.new(civ_id)
	# Testing override: give the player a head start (remove from config.json to disable).
	var testing: Dictionary = GameConfig.data().get("testing", {})
	if testing.has("player_starting_resources"):
		economy.resources = testing.player_starting_resources.duplicate()
	battle = Battlefield.new()
	var enemy_civ: String = "greeks" if civ_id == "romans" else "romans"
	ai = EnemyAI.new(enemy_civ, battle)
	battle.unit_died.connect(func(team): if team == Battlefield.PLAYER: economy.army_size -= 1)
	battle.game_over.connect(_on_game_over)
	var box := _vbox(self, 0)

	box.add_child(_header())

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
	for id in ["villager", "fighter"]:
		var title: String = {"villager": "Villager", "fighter": GameConfig.data().units.fighter.name}[id]
		var card := Card.new(title)
		card.pressed.connect(_on_card_pressed.bind(id))
		bar.add_child(card)
		_cards[id] = card

	economy.changed.connect(_refresh)
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
	_ui.title = _label("", 26)
	col.add_child(_ui.title)
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
		"fighter":
			_flash_hint("Drag the Fighter card onto a lane")


func _drop(id: String, local: Vector2) -> void:
	match id:
		"villager":
			var job := _view.job_at(local)
			if job != "" and economy.recruit():
				economy.reassign("idle", job)
		"fighter":
			var lane := _view.lane_at(local)
			var cost: Dictionary = GameConfig.data().units.fighter.cost
			if lane != -1 and economy.has_room() and economy.spend(cost):
				battle.spawn(Battlefield.PLAYER, "fighter", lane)
				economy.army_size += 1


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
			if _can_build_towers() and economy.spend(cfg.buildings.towers.cost):
				battle.build_towers(Battlefield.PLAYER)
				_close_menu()
		"gold", "stone":
			if economy.build_mine(id):
				_close_menu()
		"mill", "lumber_camp":
			if economy.buy_upgrade(id):
				_close_menu()
		"stone_towers":
			if economy.buy_upgrade(id):
				battle.upgrade_towers(Battlefield.PLAYER, cfg.upgrades.stone_towers.tower_hp_bonus)
				_close_menu()
	_refresh()


func _can_build_towers() -> bool:
	var towers: Dictionary = GameConfig.data().buildings.towers
	return economy.era_index >= towers.min_era and not battle.towers_built[Battlefield.PLAYER] \
		and economy.can_afford(towers.cost)


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


func _option(id: String, icon: String, title: String, note: String, enabled: bool) -> Dictionary:
	return {"id": id, "icon": icon, "title": title, "note": note, "enabled": enabled}


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
				opts.append(_option("era", "era", era_name.call(economy.era_index + 1), _cost_text(ecost), economy.can_advance()))
			var hut: Dictionary = cfg.buildings.hut
			var full: bool = economy.max_population() >= cfg.population.max_cap
			opts.append(_option("hut", "hut", "Hut +%d" % hut.population, "max pop" if full else _cost_text(hut.cost), economy.can_build_hut()))
			var towers: Dictionary = cfg.buildings.towers
			var tnote := "built" if battle.towers_built[Battlefield.PLAYER] else \
				("%s" % era_name.call(towers.min_era) if economy.era_index < towers.min_era else _cost_text(towers.cost))
			opts.append(_option("towers", "towers", "Towers", tnote, _can_build_towers()))
			var mine: Dictionary = cfg.buildings.mine
			for res in Economy.MINED:
				var mnote: String = "built" if economy.mines.has(res) else \
					(era_name.call(mine.min_era) if economy.era_index < mine.min_era else _cost_text(mine.cost))
				opts.append(_option(res, res, "%s mine" % res.capitalize(), mnote, economy.can_build_mine(res)))
		"mill", "lumber_camp":
			opts.append(_upgrade_option(kind))
		"towers":
			opts.append(_upgrade_option("stone_towers"))
	return opts


func _upgrade_option(id: String) -> Dictionary:
	var cfg := GameConfig.data()
	var up: Dictionary = cfg.upgrades[id]
	var note: String
	if economy.upgrades.has(id):
		note = "done"
	elif economy.era_index < up.min_era:
		note = "needs %s" % cfg.eras[up.min_era].name
	else:
		note = _cost_text(up.cost)
	return _option(id, "upgrade", up.name, note, economy.can_upgrade(id))


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
	_cards.villager.set_state("%d food" % vcost.food, economy.can_recruit(), dragging == "villager")
	var fcost: Dictionary = GameConfig.data().units.fighter.cost
	_cards.fighter.set_state("%d food · %d wood" % [fcost.food, fcost.wood], economy.has_room() and economy.can_afford(fcost), dragging == "fighter")


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
