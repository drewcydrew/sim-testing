extends Node2D
class_name TrailOverlay

@export var line_width: float = 3.0
@export var line_color: Color = Color(1.0, 0.4, 0.1, 0.6)

var _points: Array[Vector2] = []

func _ready() -> void:
	# Render in world space, independent of parent transform
	top_level = true
	visible = false

func add_point(world_pos: Vector2) -> void:
	_points.append(world_pos)
	queue_redraw()

func clear_points() -> void:
	_points.clear()
	queue_redraw()

func _draw() -> void:
	if _points.size() < 2:
		return
	draw_polyline(_points, line_color, line_width, true)
