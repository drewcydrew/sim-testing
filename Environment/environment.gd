extends Control

@export var traveller_scene: PackedScene
@export var max_travellers: int = 20
@export var auto_spawn: bool = true
@export var auto_spawn_interval_sec: float = 5

@onready var _spawn_points: Node = $SpawnPoints
@onready var _targets_root: Node = $NavTargets
@onready var _travellers_root: Node = $Travellers

var _auto_timer: Timer
var _targets: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()

signal traveller_spawned(node: Node2D)
signal traveller_despawned(node: Node2D)
signal count_changed(count: int)

func _ready() -> void:
	_rng.randomize()
	_collect_targets()
	_setup_timer()
	emit_signal("count_changed", get_traveller_count())

	if auto_spawn:
		_auto_timer.start()

func _collect_targets() -> void:
	_targets.clear()
	for c in _targets_root.get_children():
		if c is Node2D:
			_targets.append((c as Node2D).global_position)

func _setup_timer() -> void:
	_auto_timer = Timer.new()
	_auto_timer.one_shot = false
	_auto_timer.wait_time = max(0.1, auto_spawn_interval_sec)
	add_child(_auto_timer)
	_auto_timer.timeout.connect(_on_auto_timer_timeout)

func _on_auto_timer_timeout() -> void:
	if auto_spawn:
		spawn_one()

# --- Public API ---

func set_auto_spawn(enabled: bool) -> void:
	auto_spawn = enabled
	if enabled:
		_auto_timer.start()
	else:
		_auto_timer.stop()

func set_auto_spawn_interval(seconds: float) -> void:
	auto_spawn_interval_sec = max(0.1, seconds)
	if is_instance_valid(_auto_timer):
		_auto_timer.wait_time = auto_spawn_interval_sec

func spawn_one() -> Node2D:
	if get_traveller_count() >= max_travellers:
		return null

	var spawn_at := _pick_spawn_point()
	var inst := traveller_scene.instantiate() as Node2D
	_travellers_root.add_child(inst)
	inst.global_position = spawn_at

	# Optional: hand initial targets to the traveller if it supports initialize()
	if inst and inst.has_method("initialize"):
		inst.initialize(_targets)

	# Defensive: track when it frees itself
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
	# If you need to also reset targets/barriers, do so here.
	clear_all()

func get_traveller_count() -> int:
	return _travellers_root.get_child_count()

# --- Helpers ---

func _pick_spawn_point() -> Vector2:
	var options: Array[Node] = _spawn_points.get_children()
	if options.is_empty():
		return global_position
	var idx := _rng.randi_range(0, options.size() - 1)
	var n := options[idx]
	return (n as Node2D).global_position if n is Node2D else global_position
