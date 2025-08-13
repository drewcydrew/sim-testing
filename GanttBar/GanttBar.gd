extends Control
class_name GanttBar

signal hovered(bar: GanttBar, inside: bool)

@export var label_text: String = "Task"
@export var start_time: float = 0.0
@export var end_time: float = 1.0
@export var row_index: int = 0
@export var bar_color: Color = Color(0.50, 0.80, 1.00, 1.0)

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_label.text = label_text
	_update_style()

func set_data(label: String, start_t: float, end_t: float, row: int, color: Color) -> void:
	label_text = label
	start_time = start_t
	end_time = end_t
	row_index = row
	bar_color = color
	if is_inside_tree():
		_label.text = label_text
		_update_style()

func _update_style() -> void:
	if not is_instance_valid(_panel):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)



func _on_mouse_entered() -> void:
	emit_signal("hovered", self, true)

func _on_mouse_exited() -> void:
	emit_signal("hovered", self, false)
