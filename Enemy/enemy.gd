extends CharacterBody2D

@export var movement_speed: float = 200.0

@export var movement_target: Node2D
@export var navigation_agent: NavigationAgent2D
@export var gantt_path: NodePath

@onready var progress_bar: ProgressBar = $ProgressBar

var current_attraction: Node2D = null
var is_visiting: bool = false
var travelStart: float = 0.0
var travelFinish: float = 0.0

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

func _ready():
	call_deferred("actor_setup")
	_pick_and_go_to_next_attraction()

func actor_setup():
	pass

func set_movement_target(movement_target: Vector2):
	navigation_agent.target_position = movement_target

func visit_attraction(attraction: Node2D):
	if is_visiting:
		return
	current_attraction = attraction
	navigation_agent.target_position = attraction.global_position
	travelStart = SimulationClock.now()
	print("Heading to attraction:", attraction.name)

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
	print("Recording travel event from ", travelStart, " to ", travelFinish)
	GanttHub.record("Travelling", travelStart, travelFinish, 0, Color8(52, 152, 219))

	print("Visiting attraction:", current_attraction.name)
	var t1: float = SimulationClock.now()

	await _visit_for_sim_seconds(2.0)

	var t2: float = SimulationClock.now()
	GanttHub.record(current_attraction.name, t1, t2, 0, Color8(46, 204, 113) )

	print("Done visiting:", current_attraction.name)
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
	visit_attraction(choice)
