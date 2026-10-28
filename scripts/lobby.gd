class_name Lobby
extends Control
## Setting up a game with a friend, over the start screen: host a game (and
## get a room code to tell the friend) or join one by its code.

## Both players are in: start the game.
signal ready_to_play(role: String, their_civ: String)
signal back

var net: Net
var civ: String
var _status: Label
var _code: Label
var _input: LineEdit
var _buttons: Array[Button] = []
var _link := ""


func _init(connection: Net, my_civ: String) -> void:
	net = connection
	civ = my_civ
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 600
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e8d5a8")
	style.border_color = Color("#8a6a3a")
	style.set_border_width_all(5)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	col.add_child(_text("Play with a friend", 36, 900))
	col.add_child(_text("You lead the %s" % GameConfig.data().civs[civ].name, 20, 400))
	var host := _button("Host a game")
	host.pressed.connect(_host)
	col.add_child(host)
	_code = _text("", 64, 900)
	_code.add_theme_color_override("font_color", Color("#a93226"))
	_code.visible = false
	col.add_child(_code)
	col.add_child(_text("— or join your friend's game —", 20, 400))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "CODE"
	_input.max_length = 4
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.custom_minimum_size = Vector2(0, 72)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_override("font", UiStyle.cinzel(900))
	_input.add_theme_font_size_override("font_size", 40)
	_input.text = Net.room_in_link()
	_input.text_changed.connect(func(t: String):
		var at := _input.caret_column
		_input.text = t.to_upper()
		_input.caret_column = at)
	_input.text_submitted.connect(func(_t): _join())
	row.add_child(_input)
	var join := _button("Join")
	join.custom_minimum_size.x = 170
	join.pressed.connect(_join)
	row.add_child(join)
	_status = _text("", 22, 700)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status)
	var cancel := _button("Back")
	cancel.pressed.connect(func():
		net.close()
		back.emit())
	col.add_child(cancel)
	net.room_made.connect(_on_room)
	net.started.connect(func(role: String, their_civ: String): ready_to_play.emit(role, their_civ))
	net.failed.connect(_on_failed)
	net.left.connect(func(): _on_failed("Lost the connection"))


func _host() -> void:
	_status.text = "Connecting…"
	_set_busy(true)
	net.host(civ)


func _join() -> void:
	if _input.text.strip_edges().length() != 4:
		_status.text = "Type the 4-letter code from your friend"
		return
	_status.text = "Connecting…"
	_set_busy(true)
	net.join(_input.text, civ)


func _on_room(code: String) -> void:
	_code.text = code
	_code.visible = true
	_status.text = "Tell your friend this code. Waiting for them to join…"
	if OS.has_feature("web"):
		_link = str(JavaScriptBridge.eval("location.origin + location.pathname")) + "?room=" + code
		DisplayServer.clipboard_set(_link)
		_status.text += "\n(A link to join is copied too.)"


func _on_failed(message: String) -> void:
	_status.text = message
	_code.visible = false
	_set_busy(false)


func _set_busy(on: bool) -> void:
	for b in _buttons:
		b.disabled = on
	_input.editable = not on


func _text(t: String, font_size: int, weight: int) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiStyle.cinzel(weight))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiStyle.INK)
	return l


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	UiStyle.plaque(b, 28)
	b.custom_minimum_size.y = 72
	if t != "Back":
		_buttons.append(b)
	return b
