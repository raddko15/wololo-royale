class_name Net
extends Node
## Connection to the relay server for a game with a friend. The host's device
## runs the match; the relay pairs the two players by a room code and passes
## their messages on. Lobby messages are JSON text; in the game the host sends
## snapshots and the guest sends commands, both as var_to_bytes in binary
## messages (snapshots ZSTD-compressed, behind their unpacked size).

signal connected
signal room_made(code: String)
## The other player is here: role is "host" or "guest", civ is theirs.
signal started(role: String, their_civ: String)
signal failed(message: String)
## The other player disconnected, or the connection to the relay was lost.
signal left
signal command_received(cmd: Dictionary)
signal snapshot_received(snap: Dictionary)

## Commands the host accepts from the guest (no testing aids).
const GUEST_OPS := ["recruit", "recruit_to", "train", "auto", "lanes_on", "lane_order", "reassign", "hut", "advance",
	"upgrade", "military", "mine", "camp", "towers", "cancel", "kill_villager", "pause"]

var role := ""
var _ws := WebSocketPeer.new()
var _was_open := false
var _on_open: Dictionary = {}


## The relay address: config network.relay_url, or on the web a ?relay=
## parameter in the page address (for testing against a local relay).
static func relay_url() -> String:
	if OS.has_feature("web"):
		var param = JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay') || ''")
		if param is String and param != "":
			return param
	return GameConfig.data().get("network", {}).get("relay_url", "ws://127.0.0.1:8080")


## A room code in the page address (?room=ABCD), from a shared link.
static func room_in_link() -> String:
	if OS.has_feature("web"):
		var param = JavaScriptBridge.eval("new URLSearchParams(location.search).get('room') || ''")
		if param is String:
			return param.to_upper()
	return ""


func host(civ: String, url := relay_url()) -> void:
	_open(url, {"op": "host", "civ": civ})


func join(code: String, civ: String, url := relay_url()) -> void:
	_open(url, {"op": "join", "code": code.strip_edges().to_upper(), "civ": civ})


func close() -> void:
	_ws.close()
	_was_open = false
	role = ""


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send_command(cmd: Dictionary) -> void:
	if is_open():
		_ws.send(var_to_bytes(cmd))


func send_snapshot(snap: Dictionary) -> void:
	if is_open():
		var raw := var_to_bytes(snap)
		var packed := PackedByteArray()
		packed.resize(4)
		packed.encode_u32(0, raw.size())
		_ws.send(packed + raw.compress(FileAccess.COMPRESSION_ZSTD))


func _open(url: String, hello: Dictionary) -> void:
	close()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_on_open = hello
	var err := _ws.connect_to_url(url)
	if err != OK:
		failed.emit("Can't reach the game server")


func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connected.emit()
				_ws.send_text(JSON.stringify(_on_open))
			while _ws.get_available_packet_count() > 0:
				var data := _ws.get_packet()
				if _ws.was_string_packet():
					_lobby(data.get_string_from_utf8())
				else:
					_game(data)
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				_was_open = false
				left.emit()
			elif not _on_open.is_empty():
				failed.emit("Can't reach the game server")
			_on_open = {}


func _lobby(text: String) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match msg.get("op", ""):
		"room":
			room_made.emit(str(msg.code))
		"start":
			role = str(msg.role)
			started.emit(role, str(msg.civ))
		"error":
			failed.emit(str(msg.message))
		"left":
			left.emit()


func _game(data: PackedByteArray) -> void:
	if role == "guest" and data.size() > 4:
		var raw := data.slice(4).decompress(data.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
		var snap = bytes_to_var(raw)
		if snap is Dictionary:
			snapshot_received.emit(snap)
	elif role == "host":
		var cmd = bytes_to_var(data)
		if cmd is Dictionary and GUEST_OPS.has(cmd.get("op", "")):
			command_received.emit(cmd)
