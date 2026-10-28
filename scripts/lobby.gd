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
	if _is_phone_browser():
		# Phone browsers show no keyboard for the game's own text field, so
		# an invisible web page text box lies over it: tapping that brings up
		# the phone's keyboard, and what is typed shows in the field.
		_input.editable = false
		_input.add_theme_color_override("font_uneditable_color", _input.get_theme_color("font_color"))
		JavaScriptBridge.eval(PAGE_BOX_JS)
		_seed = _input.text
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


static var _phone := -1


static func _is_phone_browser() -> bool:
	if _phone == -1:
		_phone = int(OS.has_feature("web") and bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0")))
	return _phone == 1


## The page's text box over the code field (phone browsers): 16px text so
## the phone doesn't zoom in, see-through, uppercase letters only.
const PAGE_BOX_JS := """
(function () {
  if (document.getElementById('wr-code')) return;
  var i = document.createElement('input');
  i.id = 'wr-code';
  i.type = 'text';
  i.maxLength = 4;
  i.autocomplete = 'off';
  i.autocapitalize = 'characters';
  i.spellcheck = false;
  i.enterKeyHint = 'go';
  i.style.cssText = 'position:fixed;z-index:10;font-size:16px;color:transparent;caret-color:transparent;' +
    'background:transparent;border:none;outline:none;padding:0;margin:0;-webkit-tap-highlight-color:transparent;';
  i.addEventListener('input', function () {
    i.value = i.value.toUpperCase().replace(/[^A-Z]/g, '').slice(0, 4);
  });
  i.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { window.wrCodeGo = true; i.blur(); }
  });
  document.body.appendChild(i);
})();
"""


## Keep the page's box over the field and copy its letters in (each frame).
func _process(_delta: float) -> void:
	if not _is_phone_browser():
		return
	# The field in window pixels (after the stretch to the screen); the
	# canvas fills the window.
	var xf := get_viewport().get_final_transform() * _input.get_global_transform_with_canvas()
	var r := Rect2(xf * Vector2.ZERO, xf.basis_xform(_input.size))
	var view := Vector2(DisplayServer.window_get_size())
	var shown := not _input.editable and not _buttons[0].disabled and is_visible_in_tree()
	var js := "(function(){var i=document.getElementById('wr-code');if(!i)return '';var c=document.querySelector('canvas').getBoundingClientRect();" \
		+ "var k=c.width/%f;i.style.left=(c.left+%f*k)+'px';i.style.top=(c.top+%f*k)+'px';i.style.width=(%f*k)+'px';i.style.height=(%f*k)+'px';" % [view.x, r.position.x, r.position.y, r.size.x, r.size.y] \
		+ "i.style.display='%s';if(%s)i.value=%s;var go=window.wrCodeGo;window.wrCodeGo=false;return (go?'!':'')+i.value;})()" % [
			"block" if shown else "none", "true" if _seed != "" else "false", JSON.stringify(_seed)]
	_seed = ""
	var typed = JavaScriptBridge.eval(js)
	if typed is String:
		var go: bool = typed.begins_with("!")
		_input.text = typed.trim_prefix("!")
		if go:
			_join()


## Code from a shared link, put into the page's box on the next frame.
var _seed := ""


func _exit_tree() -> void:
	if _is_phone_browser():
		JavaScriptBridge.eval("var i=document.getElementById('wr-code');if(i)i.remove();")


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
	_input.editable = not on and not _is_phone_browser()


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
