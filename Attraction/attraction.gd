extends Area2D

signal attraction_selected(attraction)

@onready var tooltip: Control = $Tooltip
@export var visit_duration_seconds: float = 120.0
@export var capacity: int = 1

signal visit_requested(traveller: Node)
signal visit_started(traveller: Node)
signal visit_finished(traveller: Node)

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var queueIndicator: HBoxContainer = $QueueIndicator

var queue: Array[Node] = []
var active: Array[Node] = [] 


func _ready():
	print("initialised")
	connect("area_entered",_on_mouse_entered)
	connect("area_exited",_on_mouse_exited)
	connect("visit_requested", _on_visit_requested)


func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("emitting signal")
		emit_signal("attraction_selected", self)
		


func _on_visit_requested(traveller: Node) -> void:
	#emit_signal("visit_started", traveller)
	#print("attraction started")
	
	if active.has(traveller) or queue.has(traveller):
		return
	queue.append(traveller)
	var rect = ColorRect.new()
	rect.color = Color(0.2, 0.8, 1.0)  # cyan color
	rect.custom_minimum_size = Vector2(10, 10)
	queueIndicator.add_child(rect)

	_pump_queue()

func _pump_queue() -> void:
	# Start as many as we have capacity for
	while active.size() < capacity and queue.size() > 0:
		var next := queue.pop_front() as Node
		if not is_instance_valid(next):
			continue
		active.append(next)
		emit_signal("visit_started", next)
		# fire-and-forget the service task (don’t block the loop)
		_serve_one(next)

func _serve_one(traveller: Node) -> void:
	# Show progress only for single-slot attractions (shared bar)
	var show_progress := (capacity == 1)
	queueIndicator.get_child(0).queue_free()
	await _visit_for_sim_seconds(get_visit_duration())

	emit_signal("visit_finished", traveller)
	active.erase(traveller)

	# Clean up progress bar in single-slot case
	if capacity == 1 and active.is_empty():
		progress_bar.visible = false
		progress_bar.value = 0

	# Start next in line if any
	_pump_queue()




	#await _visit_for_sim_seconds(visit_duration_seconds)
	#print("attraction finished")
	#emit_signal("visit_finished", traveller)
	

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




func _on_mouse_entered() -> void:
	print("Entered")
	tooltip.visible = true


func _on_mouse_exited() -> void:
	print("Exited")
	tooltip.visible = false
	
	
func get_visit_duration() -> float:
	# e.g., vary by traveller, queue length, time of day, etc.
	return visit_duration_seconds
