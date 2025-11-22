extends CharacterBody2D

@export var movement_speed: float = 0.5
@export var navigation_agent: NavigationAgent2D
@export var max_visits: int = 5


@export var tooltip_scene: PackedScene

var tooltip_instance: Control = null
var _tooltip_open: bool = false


@onready var tap_button: TouchScreenButton = $TapButton

var _has_open_event: bool = false
var _current_event_label: String = ""



var home_entry_point: Node2D = null
var exit_target: Node2D = null
var traveller_name: String = ""
var visits_completed: int = 0
var is_leaving: bool = false
var _env: Node = null
var _env_is_open: bool = true
# Per-traveller event log, mirroring what we send to GanttHub
var event_log: Array = []   # each entry: { "label", "start", "end", "color", "category", "note" }
var _current_event_index: int = -1

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

func visit_attraction(attraction: Node2D) -> void:
	if is_visiting:
		return
	current_attraction = attraction
	navigation_agent.target_position = attraction.global_position

	_start_event(
		"Travelling",
		#"moving to attraction: %s" % attraction.name,
		Color8(52, 152, 219),
		"PERSON"
	)


func _start_event(
	label: String,
	color: Color = Color.WHITE,
	category: String = "PERSON"
) -> void:
	var now: float = SimulationClock.now()

	# Close any open event both in Gantt and locally
	if _has_open_event and _current_event_index >= 0 and _current_event_index < event_log.size():
		# Close in Gantt
		GanttHub.finish_named(traveller_name, now)
		# Close in local log
		event_log[_current_event_index]["end"] = now

	# Start new event in Gantt
	GanttHub.start_named(
		label,
		now,
		traveller_name,
		color,
		category
	)

	# Start new event in local log
	var ev := {
		"label": label,
		"start": now,
		"end": -1.0,  # -1 = still open
		"color": color,
		"category": category,
		"note": ""
	}
	event_log.append(ev)
	_current_event_index = event_log.size() - 1
	_current_event_label = label
	_has_open_event = true



func _finish_event(note: String = "") -> void:
	if not _has_open_event:
		return

	var now: float = SimulationClock.now()

	# Close in Gantt
	GanttHub.finish_named(traveller_name, now)

	# Close in local log
	if _current_event_index >= 0 and _current_event_index < event_log.size():
		event_log[_current_event_index]["end"] = now
		if note != "":
			var existing_note: String = event_log[_current_event_index].get("note", "")
			if existing_note == "":
				event_log[_current_event_index]["note"] = note
			else:
				event_log[_current_event_index]["note"] = str(existing_note, "\n", note)

	_has_open_event = false
	_current_event_label = ""
	_current_event_index = -1




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
	
	




	


func start_visiting() -> void:
	is_visiting = true
	velocity = Vector2.ZERO

	# We don't manually finish "Travelling" here; _start_event("Waiting")
	# will auto-close it for us.
	current_attraction.emit_signal("visit_requested", self)

	_start_event(
		"Waiting",
		#"waiting for %s" % (current_attraction.name if current_attraction else "attraction"),
		Color8(46, 204, 113),
		"PERSON"
	)

	# Wait until this exact traveller is started
	while true:
		var started_traveller: Node = await current_attraction.visit_started
		if started_traveller == self:
			break

	# Open attraction segment; this will auto-close "Waiting"
	_start_event(
		current_attraction.name,
		#"riding %s" % current_attraction.name,
		Color8(243, 156, 18),
		"PERSON"
	)

	# Wait until this exact traveller is finished
	while true:
		var finished_traveller: Node = await current_attraction.visit_finished
		if finished_traveller == self:
			break

	# If park is closed, force this to be the final visit
	if not _env_is_open:
		visits_completed = max_visits

	visits_completed += 1

	is_visiting = false
	if visits_completed >= max_visits:
		_begin_leaving()
	else:
		_pick_and_go_to_next_attraction()


func _begin_leaving() -> void:
	is_leaving = true
	is_visiting = false
	current_attraction = null

	# Start a "Leaving" segment; this will auto-close any previous segment
	var target_point: Node2D = home_entry_point

	if target_point:
		exit_target = target_point
		navigation_agent.target_position = target_point.global_position

		_start_event(
			"Leaving",
			#"heading to exit",
			Color8(155, 89, 182),
			"PERSON"
		)
	else:
		# No exit point available – fall back to immediate despawn.
		_despawn_now()




func _despawn_now() -> void:
	queue_free()


func _on_reached_exit() -> void:
	# Finish the "Leaving" segment if we started one
	_finish_event("left the park")
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
	print("Touch registered")
	# If tooltip is currently open, close and free it
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

	# Tell the tooltip which row_key/entity to follow
	if tooltip_instance.has_method("set_row_key"):
		tooltip_instance.call("set_row_key", traveller_name)
	elif "row_key" in tooltip_instance:
		tooltip_instance.row_key = traveller_name

	# Optional: if your tooltip has display_type and you only want PERSON events
	if "display_type" in tooltip_instance:
		tooltip_instance.display_type = "PERSON"

	_tooltip_open = true




func _on_tap_button_pressed() -> void:
	_toggle_tooltip()
