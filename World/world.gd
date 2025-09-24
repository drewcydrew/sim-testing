extends Node2D

@export var enemy_instance: Node2D

func _ready() -> void:
	pass

func _on_simulation_controls_sim_speed_changed(value: float) -> void:
	# Drive the entire sim with Engine.time_scale via SimClock
	SimulationClock.set_rate(value)
