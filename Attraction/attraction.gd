extends Area2D

signal attraction_selected(attraction)

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("emitting signal")
		emit_signal("attraction_selected", self)
