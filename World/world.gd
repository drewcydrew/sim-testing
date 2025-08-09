extends Node2D

@export var enemy_instance: Node2D

@onready var time_slider: HSlider = $TabContainer/Environment/SimSpeedSlider
@onready var gantt_chart: Control = $TabContainer/Data/GanttChart

func _ready() -> void:
	# Connect all attractions
	for attraction in get_tree().get_nodes_in_group("attractions"):
		if attraction.has_signal("attraction_selected"):
			attraction.connect("attraction_selected", Callable(self, "_on_attraction_selected"))

func _on_attraction_selected(attraction):
	if enemy_instance.has_method("visit_attraction"):
		print("responding to signal")
		enemy_instance.visit_attraction(attraction)
		


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var clicked_attraction = null

		# Manually check for clicked attractions
		for attraction in get_tree().get_nodes_in_group("attractions"):
				clicked_attraction = attraction
				break

		#if clicked_attraction:
			#_on_attraction_selected(clicked_attraction)



func _on_sim_speed_slider_value_changed(value: float) -> void:
	print("Updating sim time")
	Engine.time_scale = value
	#_update_time_label(new_value)
