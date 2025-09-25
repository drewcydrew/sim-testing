extends Node2D


# Remember the last non-zero speed so we can resume to it.
var _last_nonzero_speed: float = 100.0


const START_OF_DAY_SECONDS: int = 9 * 3600  # 9:00 AM

@onready var _time_label: Label = $SimulationControls/SimTimeLabel


@onready var _sim_controls: Node = $SimulationControls
@onready var _play_pause_btn: Button = $SimulationControls/PlayPause
@onready var _env: Node = $TabContainer/Environment
@onready var _chk_auto_spawn: BaseButton = $SimulationControls/AutoSpawn if has_node("SimulationControls/AutoSpawn") else null
@onready var _gantt: BasicGantt = $TabContainer/Data/ScrollContainer/GanttNew


func _ready() -> void:
	# Keep UI in sync if the rate is changed elsewhere
	SimulationClock.rate_changed.connect(_on_rate_changed)
	# Initialize UI from current Engine.time_scale
	_on_rate_changed(Engine.time_scale)
	
func _process(_delta: float) -> void:
	_update_time_label()

	

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
		var target := (_last_nonzero_speed if _last_nonzero_speed > 0.0 else 100.0)
		SimulationClock.set_rate(target)

func _on_rate_changed(rate: float) -> void:
	# Update button label/icon based on paused/playing
	if is_instance_valid(_play_pause_btn):
		_play_pause_btn.text = ("Play" if rate == 0.0 else "Pause")


func _on_reset_pressed() -> void:
	print ("Button pressed")
	# Optional: pause the simulation before clearing
	#if Engine.time_scale > 0.0:
	#	SimulationClock.set_rate(0.0)

	# Clear all travellers
	if is_instance_valid(_env) and _env.has_method("clear_all"):
		_env.clear_all()

	# Optional: reset your clock/time if you want a full sim reset
	if Engine.has_singleton("SimulationClock") or true:
		SimulationClock.reset(0.0)
		
			# Clear Gantt (bars are drawn from _events, so this fully wipes the chart)
	if is_instance_valid(_gantt):
		_gantt.clear()
		
	# (optional) also reset the visible domain so the next event starts from a clean window
	# _gantt.set_axis(0.0, 1.0)  # or your preferred baseline

	# (optional) if the gantt sits inside a ScrollContainer, snap scroll back to origin
	var sc := _gantt.get_parent() as ScrollContainer
	if sc:
		sc.scroll_horizontal = 0
		sc.scroll_vertical = 0


func _on_spawn_pressed() -> void:
	if is_instance_valid(_env) and _env.has_method("spawn_one"):
		_env.spawn_one()
		
		
func _update_time_label() -> void:
	
	if not is_instance_valid(_time_label):
		return
		
	print("Updating time label")
	var sim_sec: int = int(SimulationClock.now())
	var display_sec: int = START_OF_DAY_SECONDS + sim_sec
	print("Added", sim_sec)
	_time_label.text = _format_time_of_day(display_sec)

func _format_time_of_day(total_seconds: float) -> String:
	# Floor to whole seconds, then do all-int math (3.x: avoid //)
	var secs: int = int(total_seconds)

	var hours: int = int(secs / 3600) % 24
	var minutes: int = int((secs % 3600) / 60)
	var seconds: int = secs % 60

	var is_am: bool = hours < 12
	var h12: int = hours % 12
	if h12 == 0:
		h12 = 12

	var meridiem := "AM" if is_am else "PM"
	return "%d:%02d:%02d %s" % [h12, minutes, seconds, meridiem]
