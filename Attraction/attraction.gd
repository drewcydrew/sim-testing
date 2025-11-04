extends Area2D

signal attraction_selected(attraction)

@onready var tooltip: Control = $Tooltip
@export var visit_duration_seconds: float = 120.0


func _ready():
	print("initialised")
	connect("area_entered",_on_mouse_entered)
	connect("area_exited",_on_mouse_exited)

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("emitting signal")
		emit_signal("attraction_selected", self)


func _on_mouse_entered() -> void:
	print("Entered")
	tooltip.visible = true


func _on_mouse_exited() -> void:
	print("Exited")
	tooltip.visible = false
	
	
func get_visit_duration() -> float:
	# e.g., vary by traveller, queue length, time of day, etc.
	return visit_duration_seconds
