extends CharacterBody2D

@export var movement_speed: float = 200.0

@export var movement_target: Node2D
@export var navigation_agent: NavigationAgent2D
@export var gantt_path: NodePath

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var tooltip: Control = $Tooltip
@onready var tooltip_label: RichTextLabel = $Tooltip/PanelContainer/MarginContainer/RichTextLabel




var traveller_name: String = ""
@export var max_visits: int = 5
var visits_completed: int = 0
var is_leaving: bool = false


var localEvents: Array = []


var current_attraction: Node2D = null
var is_visiting: bool = false
var travelStart: float = 0.0
var travelFinish: float = 0.0

const SPEED = 3000.0
const JUMP_VELOCITY = -400.0

func set_traveller_name(n: String) -> void:
	traveller_name = n


func _ready():
	# --- Physics layers: assume environment/obstacles = layer 1, travellers = layer 2 ---
	# Put traveller on layer 2:
	set_collision_layer_value(1, false) # not on world layer
	set_collision_layer_value(2, true)  # on travellers layer

	# Collide only with world (layer 1), not with other travellers (layer 2):
	set_collision_mask_value(1, true)   # collide with world/obstacles
	set_collision_mask_value(2, false)  # ignore other travellers
	
	
	call_deferred("actor_setup")
	_pick_and_go_to_next_attraction()

func actor_setup():
	pass

func set_movement_target(movement_target: Vector2):
	#GanttHub.record_named("Travelling", travelStart, travelFinish, traveller_name, Color8(52, 152, 219))
	
	navigation_agent.target_position = movement_target

func visit_attraction(attraction: Node2D):
	if is_visiting:
		return
	current_attraction = attraction
	navigation_agent.target_position = attraction.global_position
	travelStart = SimulationClock.now()
	localEvents.append("moving to attraction")
	#print("Heading to attraction:", attraction.name)

func _physics_process(delta: float) -> void:
	if is_visiting or navigation_agent.is_navigation_finished():
		return


	var current_agent_position: Vector2 = global_position
	var next_path_position: Vector2 = navigation_agent.get_next_path_position()

	var direction: Vector2 = (next_path_position - current_agent_position).normalized()
	velocity = direction * movement_speed
	move_and_slide()

	if current_attraction and global_position.distance_to(current_attraction.global_position) < 50.0:
		print("arrived")
		start_visiting()

func start_visiting():
	is_visiting = true
	velocity = Vector2.ZERO

	travelFinish = SimulationClock.now()
	GanttHub.finish_named(traveller_name, SimulationClock.now())
	#print("Recording travel event from ", travelStart, " to ", travelFinish)
	#GanttHub.record("Travelling", travelStart, travelFinish, 0, Color8(52, 152, 219))
	print ("recording for ", traveller_name)
	#GanttHub.record_named("Travelling", travelStart, travelFinish, traveller_name, Color8(52, 152, 219))
	
	
	
	var requestStart = SimulationClock.now()
	
	
		#print("Visiting attraction:", current_attraction.name)
	var t1: float = SimulationClock.now()
	#var visitDuration = _get_visit_duration_for(current_attraction)
	#print(visitDuration)
	#await _visit_for_sim_seconds(visitDuration)

	current_attraction.emit_signal("visit_requested", self)
	
	GanttHub.start_named("Waiting", SimulationClock.now(), traveller_name, Color8(46, 204, 113))  # green


	
	#  Wait until this exact traveller is finished
	while true:
		var finished_traveller: Node= await current_attraction.visit_started
		print("traveller started")
		if finished_traveller == self:
			break
			
	
	var t2: float = SimulationClock.now()
	GanttHub.finish_named(traveller_name, SimulationClock.now())  # close Waiting
	GanttHub.start_named(current_attraction.name, SimulationClock.now(), traveller_name, Color8(243, 156, 18))  # orange

	#GanttHub.record("Waiting", t1, t2, 0, Color8(46, 204, 113) )
	#GanttHub.record_named("Waiting", t1, t2, traveller_name, Color8(46, 204, 113))
	t1 = SimulationClock.now()
			
	#  Wait until this exact traveller is finished
	while true:
		var finished_traveller: Node= await current_attraction.visit_finished
		print("traveller finished")
		if finished_traveller == self:
			break
	



	
	GanttHub.finish_named(traveller_name, SimulationClock.now())
	#GanttHub.start_named("Travelling", SimulationClock.now(), traveller_name, Color8(52, 152, 219))  # orange
	

	t2 = SimulationClock.now()
	#GanttHub.record(current_attraction.name, t1, t2, 0, Color8(243, 156, 18) )
	#GanttHub.record_named(current_attraction.name, t1, t2, traveller_name, Color8(243, 156, 18))
	
	localEvents.append("finished at attraction")
	
	
	visits_completed += 1
	if visits_completed >= max_visits:
		is_visiting = false
		_begin_leaving()
	else:
		is_visiting = false
		_pick_and_go_to_next_attraction()


# Helper: wait for a duration in simulation time
func _visit_for_sim_seconds(dur: float) -> void:
	progress_bar.visible = true
	progress_bar.value = 0
	var start_t: float = SimulationClock.now()
	var end_t: float = start_t + dur

	while SimulationClock.now() < end_t:
		var frac: float = clamp((SimulationClock.now() - start_t) / dur, 0.0, 1.0)
		progress_bar.value = frac * 100.0
		await get_tree().process_frame

	progress_bar.value = 100.0
	progress_bar.visible = false

func _pick_and_go_to_next_attraction() -> void:
	var all := get_tree().get_nodes_in_group("attractions")
	if all.is_empty():
		print("no attractions")
		return

	var candidates: Array = []
	for a in all:
		if a != current_attraction:
			candidates.append(a)

	var choice: Node2D = all[randi() % all.size()] if candidates.is_empty() else candidates[randi() % candidates.size()]
	print("Traeller Name: ", traveller_name)
	GanttHub.start_named("Travelling", SimulationClock.now(), traveller_name, Color8(52, 152, 219))  # orange
	visit_attraction(choice)

func _build_bbcode_from_local_events() -> String:
	if localEvents.is_empty():
		return "[b]%s[/b]\n[i]No events yet[/i]" % (traveller_name if traveller_name != "" else "Traveller")

	var now_t: float = SimulationClock.now()
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
	GanttHub.finish_named(traveller_name, SimulationClock.now())
	
	print("Leaving")
	_despawn_now()


func _despawn_now() -> void:
	# close any open 'Leaving' segment
	queue_free()
	
	
func _get_visit_duration_for(a: Node) -> float:
	if a == null:
		return 120.0
	# If the attraction exposes a method, let it decide (supports dynamic durations)
	if a.has_method("get_visit_duration"):
		var dur := float(a.call("get_visit_duration"))
		return max(dur, 0.0)
	# Fallback default
	return 120.0





func _on_mouse_entered() -> void:
	print("entered")
	tooltip_label.text = _build_bbcode_from_local_events()
	tooltip.visible = true
	



func _on_mouse_exited() -> void:
	print("exited")
	tooltip.visible = false
