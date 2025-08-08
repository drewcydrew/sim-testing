extends CharacterBody2D

@export var movement_speed: float = 200.0

@export var movement_target: Node2D
@export var navigation_agent: NavigationAgent2D

var current_attraction: Node2D = null
var is_visiting: bool = false


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

func _ready():
	call_deferred("actor_setup")
	
func actor_setup():
	pass
	#await get_tree().physics_frame
	
	#set_movement_target(movement_target.position)
	
func set_movement_target(movement_target: Vector2):
	navigation_agent.target_position = movement_target
	
func visit_attraction(attraction: Node2D):
	if is_visiting:
		return
	current_attraction = attraction
	navigation_agent.target_position = attraction.global_position
	print("Heading to attraction:", attraction.name)



func _physics_process(delta: float) -> void:
	if is_visiting or navigation_agent.is_navigation_finished():
		return

	var current_agent_position: Vector2 = global_position
	var next_path_position: Vector2 = navigation_agent.get_next_path_position()

	var direction: Vector2 = (next_path_position - current_agent_position).normalized()
	velocity = direction * movement_speed
	#print("moving")
	move_and_slide()

	# Check if we've reached the attraction
	if current_attraction and global_position.distance_to(current_attraction.global_position) < 20.0:
		print("arrived")
		start_visiting()
		
func start_visiting():
	is_visiting = true
	velocity = Vector2.ZERO
	print("Visiting attraction:", current_attraction.name)

	await get_tree().create_timer(2.0).timeout
	print("Done visiting:", current_attraction.name)

	#current_attraction = null
	is_visiting = false
	_pick_and_go_to_next_attraction()

	
func _pick_and_go_to_next_attraction() -> void:
	var all := get_tree().get_nodes_in_group("attractions")
	if all.is_empty():
		print("no attractions")
		return

	# Avoid picking the same one twice in a row if possible
	var candidates := []
	for a in all:
		if a != current_attraction:
			candidates.append(a)

	var choice = all[randi() % all.size()] if candidates.is_empty() else candidates[randi() % candidates.size()]
	visit_attraction(choice)




	
