class_name GameConfig
## Loads the tunable game rules from data/config.json.

const PATH := "res://data/config.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(file.get_as_text())
	return _data
