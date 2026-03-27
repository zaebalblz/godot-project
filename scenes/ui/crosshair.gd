extends Node2D


func _ready() -> void:
	top_level = true
	z_index = 100
	queue_redraw()


func _process(_delta: float) -> void:
	position = get_viewport_rect().size * 0.5


func _draw() -> void:
	draw_rect(Rect2(Vector2(-1, -4), Vector2(2, 8)), Color(0.96, 0.96, 0.96, 0.95))
	draw_rect(Rect2(Vector2(-4, -1), Vector2(8, 2)), Color(0.96, 0.96, 0.96, 0.95))
	draw_rect(Rect2(Vector2(-1, -1), Vector2(2, 2)), Color(0.08, 0.08, 0.08, 0.98))
