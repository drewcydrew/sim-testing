extends Area2D

signal attraction_selected(attraction)

@onready var tooltip: Control = $Tooltip
@export var visit_duration_seconds: float = 120.0

signal visit_requested(traveller: Node)
signal visit_started(traveller: Node)
signal visit_finished(traveller: Node)

@onready var progress_bar: ProgressBar = $ProgressBar


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
	emit_signal("visit_started", traveller)
	print("attraction started")
	await _visit_for_sim_seconds(visit_duration_seconds)
	print("attraction finished")
	emit_signal("visit_finished", traveller)
	
func _run_visit_for_sim_seconds(dur: float) -> void:
	var start_t: float = SimulationClock.now()
	var end_t: float = start_t + max(dur, 0.0)
	while SimulationClock.now() < end_t:
		await get_tree().process_frame

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
