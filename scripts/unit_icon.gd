class_name UnitIcon
extends Control
## A troop's portrait for its card: head and shoulders with its helmet,
## weapon and gear, in the civ's color; horsemen with their horse's head.

var unit_id: String
var color: Color
## The troop's level (0-2): archers carry a crossbow at level 3.
var tier := 0
var _tex := {}


func _init(id: String, civ_color: Color) -> void:
	unit_id = id
	color = civ_color
	custom_minimum_size = Vector2(0, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_tier(t: int) -> void:
	if t != tier:
		tier = t
		queue_redraw()


func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := "res://assets/art/%s.svg" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _layer(name: String, r: Rect2, tint := Color.WHITE) -> void:
	var t := _t(name)
	if t:
		draw_texture_rect(t, r, false, tint)


## Portrait layers (assets/art/portrait), back to front, per troop and level
## (the last list applies to higher levels too). Layers ending in "_tint"
## take the civ's color (the villager's tunic: undyed cloth).
const PORTRAITS := {
	"villager": [["hoe", "tunic_tint", "head", "hair", "straw_hat"]],
	"fighter": [["club", "tunic_tint", "head", "beard", "hair"],
		["club", "tunic_tint", "head", "beard", "helm_nasal", "shield_tint", "shield"],
		["sword", "tunic_tint", "mail", "head", "great_helm", "shield_tint", "shield"]],
	"archer": [["tunic_tint", "head", "hair", "bow"],
		["quiver", "tunic_tint", "head", "hood", "bow"],
		["quiver", "tunic_tint", "head", "kettle_hat", "crossbow"]],
	"phalanx": [["spear", "tunic_tint", "head", "hoplite_helm", "crest_tint", "aspis_tint", "aspis"]],
	"cavalry": [["lance", "tunic_tint", "head", "hair", "horse"],
		["lance", "tunic_tint", "head", "hair", "horse", "barding_tint"],
		["lance", "tunic_tint", "head", "helm_nasal", "horse", "barding_tint", "chamfron"]],
	"knight": [["lance", "pennant_tint", "tunic_tint", "head", "great_helm", "plume_tint", "horse", "barding_tint", "chamfron"]],
	"chariot": [["tunic_tint", "head", "hair", "bow", "horse", "wheel"],
		["tunic_tint", "head", "helm_nasal", "bow", "horse", "barding_tint", "wheel"]],
}
const VILLAGER_CLOTH := Color("#d9c8a0")
const HORSE_LAYERS := ["horse", "barding_tint", "chamfron"]


## A head-and-shoulders portrait on a soft disc of the civ's color.
func _draw() -> void:
	var tiers: Array = PORTRAITS.get(unit_id, PORTRAITS.fighter)
	var layers: Array = tiers[mini(tier, tiers.size() - 1)]
	var side := minf(size.x, size.y + 10)
	var box := Rect2(Vector2((size.x - side) / 2.0, size.y - side + 4), Vector2(side, side))
	draw_circle(box.get_center() + Vector2(0, 2), side * 0.42, Color(color, 0.18))
	# With a horse: the horse's head smaller at the lower left, the rider a
	# little to the right, so neither hides the other's face.
	var mounted := layers.has("horse")
	for name in layers:
		var t := _t("portrait/" + name)
		if t == null:
			continue
		var at := box
		if mounted and name in HORSE_LAYERS:
			at = Rect2(box.position + Vector2(side * 0.01, side * 0.3), box.size * 0.72)
		elif mounted and name != "wheel":
			at = Rect2(box.position + Vector2(side * 0.12, side * 0.02), box.size * 0.96)
		var tint := Color.WHITE
		if name.ends_with("_tint"):
			tint = VILLAGER_CLOTH if unit_id == "villager" else color
		draw_texture_rect(t, at, false, tint)
