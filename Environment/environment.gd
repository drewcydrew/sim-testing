extends Control

@export var traveller_scene: PackedScene
@export var max_travellers: int = 20
@export var auto_spawn: bool = false
@export var auto_spawn_interval_sec: float = 1000.0

@onready var _spawn_points: Node = $SpawnPoints
@onready var _targets_root: Node = $NavTargets
@onready var _travellers_root: Node = $Travellers
@onready var _open_status_label: Label = $OpenStatusLabel

@export var day_start_seconds := 9 * 3600
@export var closing_time_seconds := 17 * 3600

signal workday_state_changed(is_open: bool)

var cutoff_sim_seconds: float = closing_time_seconds - day_start_seconds

var is_open := true
func _is_open() -> bool: return is_open

var _targets: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
var _traveller_seq: int = 1

var _sim_prev_time: float = 0.0
var _sim_accum: float = 0.0
var _seconds_per_spawn: float = 1000.0

signal traveller_spawned(node: Node2D)
signal traveller_despawned(node: Node2D)
signal count_changed(count: int)

func _ready() -> void:
	_rng.randomize()
	_collect_targets()

	_seconds_per_spawn = max(0.1, auto_spawn_interval_sec)
	_sim_prev_time = _sim_now()

	# Initialise open state based on current sim time
	var sim_t := SimulationClock.now() if typeof(SimulationClock) != TYPE_NIL else 0.0
	var open_now := sim_t < cutoff_sim_seconds
	_set_open_state(open_now)

	emit_signal("count_changed", get_traveller_count())

	# Listen to SimulationClock reset if available
	if typeof(SimulationClock) != TYPE_NIL:
		if SimulationClock.has_signal("reset"):
			SimulationClock.connect("reset", Callable(self, "_on_sim_clock_reset"))

func _process(_delta: float) -> void:
	var now := _sim_now()
	var dt: float = max(0.0, now - _sim_prev_time)
	_sim_prev_time = now

	# --- OPEN / CLOSED STATE -----------------------------------------
	if typeof(SimulationClock) != TYPE_NIL:
		var sim_t := SimulationClock.now()
		var open_now := sim_t < cutoff_sim_seconds
		if open_now != is_open:
			_set_open_state(open_now)
	# -----------------------------------------------------------------

	# Only spawn if enabled and we have a valid cadence
	if not auto_spawn or _seconds_per_spawn <= 0.0:
		return

	# Don't spawn while closed
	if not is_open:
		return

	if get_traveller_count() >= max_travellers:
		return

	_sim_accum += dt

	while _sim_accum >= _seconds_per_spawn and get_traveller_count() < max_travellers:
		_sim_accum -= _seconds_per_spawn
		spawn_one()

# --- Public API -----------------------------------------------------

func set_auto_spawn(enabled: bool) -> void:
	auto_spawn = enabled
	if enabled:
		_sim_prev_time = _sim_now()

func set_auto_spawn_interval(seconds: float) -> void:
	auto_spawn_interval_sec = max(0.1, seconds)
	_seconds_per_spawn = auto_spawn_interval_sec

func set_spawn_rate_per_hour(rate_per_hour: float) -> void:
	if rate_per_hour <= 0.0:
		auto_spawn = false
		_seconds_per_spawn = 0.0
		return

	auto_spawn = true
	_seconds_per_spawn = 3600.0 / rate_per_hour
	_sim_prev_time = _sim_now()

func get_spawn_rate_per_hour() -> float:
	if _seconds_per_spawn <= 0.0:
		return 0.0
	return 3600.0 / _seconds_per_spawn

func spawn_one() -> Node2D:
	if get_traveller_count() >= max_travellers:
		return null

	var spawn_at := _pick_spawn_point()
	var inst := traveller_scene.instantiate() as Node2D
	if inst == null:
		return null

	inst.global_position = spawn_at

	var name_str := "Traveller_%03d" % _traveller_seq
	_traveller_seq += 1
	inst.name = name_str
	inst.set_traveller_name(name_str)
	_travellers_root.add_child(inst)
	inst.set_environment(self)
		
	inst.tree_exited.connect(func():
		if is_instance_valid(_travellers_root):
			emit_signal("count_changed", get_traveller_count())
	)

	emit_signal("traveller_spawned", inst)
	emit_signal("count_changed", get_traveller_count())
	return inst

func clear_all() -> void:
	for t in _travellers_root.get_children():
		t.queue_free()
	await get_tree().process_frame
	emit_signal("count_changed", get_traveller_count())

func reset_environment() -> void:
	clear_all()
	_sim_accum = 0.0
	_sim_prev_time = _sim_now()
	_traveller_seq = 1

	# On environment reset, reopen the park
	_set_open_state(true)

func get_traveller_count() -> int:
	return _travellers_root.get_child_count()

# --- Helpers --------------------------------------------------------

func _collect_targets() -> void:
	_targets.clear()
	for c in _targets_root.get_children():
		if c is Node2D:
			_targets.append((c as Node2D).global_position)

func _pick_spawn_point() -> Vector2:
	var options: Array[Node] = _spawn_points.get_children()
	if options.is_empty():
		return global_position
	var idx := _rng.randi_range(0, options.size() - 1)
	var n := options[idx]
	return (n as Node2D).global_position if n is Node2D else global_position

func _sim_now() -> float:
	if typeof(SimulationClock) != TYPE_NIL and SimulationClock.has_method("now"):
		return float(SimulationClock.now())
	return float(Time.get_ticks_msec()) / 1000.0

func _on_sim_clock_reset(_to_time := 0.0) -> void:
	_sim_accum = 0.0
	_sim_prev_time = _sim_now()

	# When the SimulationClock resets, treat it as start of a new day → OPEN
	_set_open_state(true)

# --- Open/close helpers --------------------------------------------

func _set_open_state(open_now: bool) -> void:
	if open_now == is_open:
		return

	is_open = open_now
	workday_state_changed.emit(is_open)
	_update_open_status_indicator()

func _update_open_status_indicator() -> void:
	if not is_instance_valid(_open_status_label):
		return

	if is_open:
		_open_status_label.text = "OPEN"
		_open_status_label.modulate = Color(0.2, 0.8, 0.2)
	else:
		_open_status_label.text = "CLOSED"
		_open_status_label.modulate = Color(0.8, 0.2, 0.2)
