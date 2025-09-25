extends Node2D

@export var enemy_instance: Node2D

# Remember the last non-zero speed so we can resume to it.
var _last_nonzero_speed: float = 1.0

@onready var _sim_controls: Node = $SimulationControls
@onready var _play_pause_btn: Button = $SimulationControls/PlayPause

func _ready() -> void:
	# Keep UI in sync if the rate is changed elsewhere
	SimulationClock.rate_changed.connect(_on_rate_changed)
	# Initialize UI from current Engine.time_scale
	_on_rate_changed(Engine.time_scale)

func _on_simulation_controls_sim_speed_changed(value: float) -> void:
	# Drive the entire sim with Engine.time_scale via SimClock
	
	SimulationClock.set_rate(value)
	# Track the last non-zero so we can resume properly
	if value > 0.0:
		_last_nonzero_speed = value

func _on_play_pause_pressed() -> void:
	
	var current: float = Engine.time_scale
	if current > 0.0:
		# Pause
		SimulationClock.set_rate(0.0)
	else:
		# Resume to last non-zero (fallback to 1.0 if somehow 0)
		var target := (_last_nonzero_speed if _last_nonzero_speed > 0.0 else 1.0)
		SimulationClock.set_rate(target)

func _on_rate_changed(rate: float) -> void:
	# Update button label/icon based on paused/playing
	if is_instance_valid(_play_pause_btn):
		_play_pause_btn.text = ("Play" if rate == 0.0 else "Pause")


func _on_reset_pressed() -> void:
	print ("Button pressed")
	# Try soft reset first (calls enemy.reset())
	if is_instance_valid(enemy_instance) and enemy_instance.has_method("reset"):
		enemy_instance.reset()
		return
