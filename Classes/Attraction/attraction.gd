extends Area2D

@export var tooltip_scene: PackedScene
@export var visit_duration_seconds: float = 120.0
@export var capacity: int = 2
@export var attractionName: String = "Whirly Dirvy"
@export var sprite_texture: Texture2D

#signal attraction_selected(attraction)
signal visit_requested(traveller: Node)
signal visit_started(traveller: Node)
signal visit_finished(traveller: Node)

@onready var progress_bar: ProgressBar = $ProgressBar
#@onready var queueIndicator: HBoxContainer = $QueueIndicator
#@onready var activeIndicator: HBoxContainer = $ActiveIndicator
@onready var tap_button: TouchScreenButton = $TapButton   # NEW
@onready var sprite_node: Sprite2D = $Sprite2D

@onready var queue_slots_root: Node2D = $QueueSlots
@onready var service_slots_root: Node2D = $ServiceSlots

var queue: Array[Node] = []
var active: Array[Node] = [] 

var _pumping: bool = false
var _epoch: int = 0   # increments on reset to cancel in-flight awaits

var tooltip_instance: Control = null   # shared Tooltip scene instance

var queue_slots: Array[Node2D] = []
var service_slots: Array[Node2D] = []



func _ready():
	print("initialised")
	
	# Apply the per-instance sprite, if set
	sprite_node.texture = sprite_texture

	GanttHub.connect("events_reset", Callable(self, "_clear_all"))
	
	queue_slots = []
	for child in queue_slots_root.get_children():
		if child is Marker2D:
			queue_slots.append(child)

	service_slots = []
	for child in service_slots_root.get_children():
		if child is Marker2D:
			service_slots.append(child)


	# Ensure capacity never exceeds number of service slots
	capacity = min(capacity, service_slots.size())



func _clear_all() -> void:
	#advance time unit
	_epoch += 1

	#clear neccessary flags on attraction
	queue.clear()
	active.clear()
	_pumping = false
	#clear_container_children(queueIndicator)
	#clear_container_children(activeIndicator)
	progress_bar.visible = false
	progress_bar.value = 0.0

	#Optional, hide tooltip
	#hide_tooltip()

func _on_tap_button_pressed() -> void:
	# This is called on mouse click (with emulate_touch_from_mouse) and on real touch
	print("TapButton pressed on attraction: ", attractionName)
	emit_signal("attraction_selected", self)

	# Toggle tooltip on tap
	if tooltip_instance != null and is_instance_valid(tooltip_instance):
		hide_tooltip()
	else:
		show_tooltip()

func _on_visit_requested(traveller: Node) -> void:
	# Check Traveller isn't already in queue
	if active.has(traveller) or queue.has(traveller):
		return

	# Add to queue
	queue.append(traveller)

	# TELEPORT to queue slot (if we have one for this index)
	var idx := queue.size() - 1
	if idx < queue_slots.size():
		var slot := queue_slots[idx]
		if slot != null and traveller is Node2D:
			var t2d := traveller as Node2D
			t2d.global_position = slot.global_position

	# Optional: keep your debug indicator bar UI
	#var rect := ColorRect.new()
	#rect.color = Color(0.2, 0.8, 1.0)  # cyan color
	#rect.custom_minimum_size = Vector2(10, 10)
	#queueIndicator.add_child(rect)

	# Pump queue, will move traveller into active if possible
	pump_queue()


func pump_queue() -> void:
	# Only start a new session if there is NO current session running.
	if active.size() > 0:
		return

	if queue.size() == 0:
		return

	var my_epoch := _epoch

	# Start a new session: move up to `capacity` travellers from queue → active
	while active.size() < capacity and queue.size() > 0:
		var next := queue.pop_front() as Node
		if not is_instance_valid(next):
			continue

		active.append(next)

		# TELEPORT to service slot
		var s_idx := active.size() - 1
		if s_idx < service_slots.size() and next is Node2D:
			var slot := service_slots[s_idx]
			if slot != null:
				var t2d := next as Node2D
				t2d.global_position = slot.global_position

		call_deferred("emit_visit_started", next)

		# Existing visual indicators
		sync_indicators()
		#var rect := ColorRect.new()
		#rect.color = Color(0.2, 0.4, 1.0)  # darker blue for active riders
		#rect.custom_minimum_size = Vector2(10, 10)
		#activeIndicator.add_child(rect)

	# Kick off a single session for this batch
	serve_batch(my_epoch)




func serve_batch(my_epoch: int) -> void:
	# One Gantt event per session, not per traveller
	GanttHub.start_named(
		"Serving",
		SimulationClock.now(),
		attractionName,
		Color8(52, 152, 219),
		"ATTRACTION"
	)

	# Run the session timer
	await visit_for_sim_seconds(get_visit_duration())

	# If we've been reset in the meantime, bail out without touching state
	if my_epoch != _epoch:
		return

	GanttHub.finish_named(attractionName, SimulationClock.now())

	# Mark all active travellers as finished for this session
	for traveller in active:
		if is_instance_valid(traveller):
			emit_visit_finished(traveller)
			emit_signal("visit_finished", traveller)

	active.clear()

	# Clear all active indicators
	#clear_container_children(activeIndicator)

	# Progress bar is controlled by _visit_for_sim_seconds,
	# but making sure it's hidden/zeroed doesn't hurt:
	progress_bar.visible = false
	progress_bar.value = 0
	
	sync_indicators()

	# If there are more people in the queue, start the next session
	pump_queue()

func visit_for_sim_seconds(dur: float) -> void:
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

func sync_indicators() -> void:
	# TELEPORT: re-seat all queued travellers into queue slots
	for i in range(queue.size()):
		if i < queue_slots.size():
			var slot := queue_slots[i]
			var trav := queue[i]
			if is_instance_valid(trav) and trav is Node2D and slot != null:
				var t2d := trav as Node2D
				t2d.global_position = slot.global_position

	# Rebuild queueIndicator from `queue` (debug UI)
	#clear_container_children(queueIndicator)
	#for i in range(queue.size()):
	#	var rect := ColorRect.new()
	#	rect.color = Color(0.2, 0.8, 1.0)  # cyan for waiting
	#	rect.custom_minimum_size = Vector2(10, 10)
	#	queueIndicator.add_child(rect)


func show_tooltip() -> void:
	#Gaurd against missing tooltip scene
	if tooltip_scene == null:
		return

	# Already visible? Just bring to front
	if tooltip_instance != null and is_instance_valid(tooltip_instance):
		tooltip_instance.raise()
		tooltip_instance.visible = true
		return

	# Create fresh instance
	tooltip_instance = tooltip_scene.instantiate() as Control
	add_child(tooltip_instance)

	# Position it above the attraction
	tooltip_instance.position = Vector2(0, -60)
	tooltip_instance.visible = true
	tooltip_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# IMPORTANT: set row_key so it tracks this attraction
	tooltip_instance.call("set_row_key", attractionName)

func hide_tooltip() -> void:
	if tooltip_instance != null and is_instance_valid(tooltip_instance):
		tooltip_instance.queue_free()
		tooltip_instance = null


func clear_container_children(c: Node) -> void:
	if c == null:
		return
	for child in c.get_children():
		child.queue_free()

func get_visit_duration() -> float:
	return visit_duration_seconds
	
func emit_visit_started(traveller: Node) -> void:
	emit_signal("visit_started", traveller)
	
func emit_visit_finished(traveller: Node) -> void:
	emit_signal("visit_finished", traveller)
