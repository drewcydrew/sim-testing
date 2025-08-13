extends Node2D

@export var enemy_instance: Node2D

func _ready() -> void:
	pass

func _on_simulation_controls_sim_speed_changed(value: float) -> void:
	print("Updating sim time")
	Engine.time_scale = value
	#_update_time_label(new_value)
