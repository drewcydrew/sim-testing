extends CharacterBody2D

@export var movement_speed: float = 0.5
@export var navigation_agent: NavigationAgent2D
@export var max_visits: int = 5


@export var tooltip_scene: PackedScene

var tooltip_instance: Control = null
var _tooltip_open: bool = false


@onready var tap_button: TouchScreenButton = $TapButton


var home_entry_point: Node2D = null
var exit_target: Node2D = null
var traveller_name: String = ""
var visits_completed: int = 0
var is_leaving: bool = false
var _env: Node = null
var _env_is_open: bool = true
var localEvents: Array = []
var current_attraction: Node2D = null
var is_visiting: bool = false


func set_traveller_name(n: String) -> void:
	traveller_name = n


func set_home_entry_point(p: Node2D) -> void:
	home_entry_point = p


func set_environment(env: Node) -> void:
	_env = env
	_env_is_open = env._is_open()
	print("spawning in park: ", _env_is_open)
	env.workday_state_changed.connect(_on_workday_state_changed)


func _on_workday_state_changed(open: bool) -> void:
	_env_is_open = open


func _ready() -> void:
	# --- Physics layers: assume environment/obstacles = layer 1, travellers = layer 2 ---
	# Put traveller on layer 2:
	set_collision_layer_value(1, false) # not on world layer
	set_collision_layer_value(2, true)  # on travellers layer

	# Collide only with world (layer 1), not with other travellers (layer 2):
	set_collision_mask_value(1, true)   # collide with world/obstacles
	set_collision_mask_value(2, false)  # ignore other travellers
	
	tap_button.pressed.connect(_on_tap_button_pressed)


	_pick_and_go_to_next_attraction()


func _physics_process(delta: float) -> void:
	# If we’re in a visiting coroutine, movement is paused.
	if is_visiting:
		return

	if navigation_agent == null:
		return

	var current_agent_position: Vector2 = global_position
	var next_path_position: Vector2 = navigation_agent.get_next_path_position()

	# If navigation is finished, we’re either:
	#  - at an attraction, or
	#  - at an exit target, or
	#  - just "stuck" because there was no path.
	var nav_finished: bool = navigation_agent.is_navigation_finished()

	if not nav_finished:
		var direction: Vector2 = (next_path_position - current_agent_position).normalized()
		velocity = direction * movement_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	# --- Arrival logic ---

	# 1) If we’re in "leaving" mode, check for arrival at exit_target.
	if is_leaving and exit_target:
		if nav_finished or global_position.distance_to(exit_target.global_position) < 20.0:
			_on_reached_exit()
			return

	# 2) Otherwise, normal "arrived at attraction" behaviour.
	if (not is_leaving) and current_attraction:
		if global_position.distance_to(current_attraction.global_position) < 50.0:
			start_visiting()


func visit_attraction(attraction: Node2D) -> void:
	if is_visiting:
		return
	current_attraction = attraction
	navigation_agent.target_position = attraction.global_position

	GanttHub.start_named(
		"Travelling",
		SimulationClock.now(),
		traveller_name,
		Color8(52, 152, 219),
		"PERSON"
	)
	localEvents.append("moving to attraction")


func start_visiting() -> void:
	is_visiting = true
	velocity = Vector2.ZERO

	# Close "Travelling"
	GanttHub.finish_named(traveller_name, SimulationClock.now())

	# Request a visit and wait to enter queue/ride
	current_attraction.emit_signal("visit_requested", self)
	GanttHub.start_named("Waiting", SimulationClock.now(), traveller_name, Color8(46, 204, 113), "PERSON")

	# Wait until this exact traveller is started
	while true:
		var started_traveller: Node = await current_attraction.visit_started
		if started_traveller == self:
			break

	# Close "Waiting", open attraction segment
	GanttHub.finish_named(traveller_name, SimulationClock.now())
	GanttHub.start_named(current_attraction.name, SimulationClock.now(), traveller_name, Color8(243, 156, 18), "PERSON")

	# Wait until this exact traveller is finished
	while true:
		var finished_traveller: Node = await current_attraction.visit_finished
		if finished_traveller == self:
			break

	# Close attraction segment
	GanttHub.finish_named(traveller_name, SimulationClock.now())
	localEvents.append("finished at attraction")

	# If park is closed, force this to be the final visit
	if not _env_is_open:
		visits_completed = max_visits

	visits_completed += 1

	is_visiting = false
	if visits_completed >= max_visits:
		_begin_leaving()
	else:
		_pick_and_go_to_next_attraction()


func _pick_and_go_to_next_attraction() -> void:
	var all := get_tree().get_nodes_in_group("attractions")
	if all.is_empty():
		return

	var candidates: Array = []
	for a in all:
		if a != current_attraction:
			candidates.append(a)

	var choice: Node2D = all[randi() % all.size()] if candidates.is_empty() else candidates[randi() % candidates.size()]
	visit_attraction(choice)


func _build_bbcode_from_local_events() -> String:
	if localEvents.is_empty():
		return "[b]%s[/b]\n[i]No events yet[/i]" % (traveller_name if traveller_name != "" else "Traveller")

	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % (traveller_name if traveller_name != "" else "Traveller"))
	lines.append("[i]Events so far[/i]")

	for ev in localEvents:
		lines.append(ev)

	return "\n".join(lines)


func _begin_leaving() -> void:
	is_leaving = true
	is_visiting = false
	current_attraction = null

	# Close any active segment (e.g. last attraction)
	GanttHub.finish_named(traveller_name, SimulationClock.now())

	# Decide where to go: prefer the "home" entry point
	var target_point: Node2D = home_entry_point

	if target_point:
		exit_target = target_point
		navigation_agent.target_position = target_point.global_position

		GanttHub.start_named("Leaving", SimulationClock.now(), traveller_name, Color8(155, 89, 182), "PERSON")
		localEvents.append("heading to exit")
	else:
		# No exit point available – fall back to immediate despawn.
		_despawn_now()


func _despawn_now() -> void:
	queue_free()


func _on_reached_exit() -> void:
	# Finish the "Leaving" segment if we started one
	GanttHub.finish_named(traveller_name, SimulationClock.now())
	localEvents.append("left the park")
	_despawn_now()


#func _on_mouse_entered() -> void:
#	tooltip_label.text = _build_bbcode_from_local_events()
#	_toggle_tooltip()


#func _on_mouse_exited() -> void:
#	_toggle_tooltip()


#func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
#	if event is InputEventMouseButton:
#		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
#			_toggle_tooltip()
#	# Touch tap (tablet/mobile)
#	elif event is InputEventScreenTouch:
#		if event.pressed:
#			_toggle_tooltip()



func _toggle_tooltip() -> void:
	# If tooltip is currently open, close and free it
	print("Touch registered")
	if tooltip_instance and is_instance_valid(tooltip_instance):
		tooltip_instance.queue_free()
		tooltip_instance = null
		_tooltip_open = false
		return

	# Otherwise, create and show a new one
	if tooltip_scene == null:
		push_warning("Traveller has no tooltip_scene assigned.")
		return

	tooltip_instance = tooltip_scene.instantiate()
	add_child(tooltip_instance)

	# Position it relative to the traveller (tweak as desired)
	tooltip_instance.position = Vector2(0, -60)


	# Populate the text via API if available
	if tooltip_instance is Tooltip:
		tooltip_instance.show_tooltip(_build_bbcode_from_local_events())
	elif tooltip_instance.has_method("show_tooltip"):
		tooltip_instance.call("show_tooltip", _build_bbcode_from_local_events())
	elif tooltip_instance.has_method("set_text"):
		tooltip_instance.call("set_text", _build_bbcode_from_local_events())

	_tooltip_open = true



func _on_tap_button_pressed() -> void:
	_toggle_tooltip()
