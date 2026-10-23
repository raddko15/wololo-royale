class_name HudIcon
extends Control
## Small drawn icon for the header: food, wood, gold, stone, villagers or pop.

var kind: String


func _init(icon_kind: String) -> void:
	kind = icon_kind
	custom_minimum_size = Vector2(30, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2
	match kind:
		"food":  # wheat bundle
			for dx in [-6, 0, 6]:
				draw_line(c + Vector2(dx * 0.5, 12), c + Vector2(dx, -6), Color("#7a8f3a"), 2)
				draw_circle(c + Vector2(dx, -8), 4, Color("#e8d27a"))
			draw_line(c + Vector2(-5, 5), c + Vector2(5, 5), Color("#8b5a2b"), 3)
		"wood":  # log end with rings
			draw_rect(Rect2(c + Vector2(-12, -6), Vector2(18, 12)), Color("#8b5a2b"))
			draw_circle(c + Vector2(6, 0), 7, Color("#c8a26b"))
			draw_arc(c + Vector2(6, 0), 4, 0, TAU, 12, Color("#8b5a2b"), 1.5)
		"gold":  # nuggets
			for p in [Vector2(-5, 3), Vector2(5, 4), Vector2(0, -5)]:
				draw_circle(c + p, 6, Color("#f1c40f"))
				draw_circle(c + p + Vector2(-2, -2), 2, Color("#fff3b0"))
		"stone":  # stacked blocks
			draw_rect(Rect2(c + Vector2(-12, 0), Vector2(11, 9)), Color("#d5d8dc"))
			draw_rect(Rect2(c + Vector2(1, 0), Vector2(11, 9)), Color("#bdc3c7"))
			draw_rect(Rect2(c + Vector2(-6, -10), Vector2(12, 9)), Color("#aab0b5"))
		"villagers":
			draw_circle(c, 9, Color("#f5f6fa"))
			draw_arc(c, 9, 0, TAU, 16, Color.BLACK, 2)
		"pop":  # hut
			draw_rect(Rect2(c + Vector2(-9, -2), Vector2(18, 13)), Color("#8b5a2b"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -2), c + Vector2(0, -13), c + Vector2(12, -2)]), Color("#b39143"))
