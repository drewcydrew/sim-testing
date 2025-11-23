extends Area2D

signal attraction_selected(attraction)

@export var tooltip_scene: PackedScene
@export var visit_duration_seconds: float = 120.0
@export var capacity: int = 2
@export var attractionName: String = "Whirly Dirvy"
@export var sprite_texture: Texture2D

signal visit_requested(traveller: Node)
signal visit_started(traveller: Node)
signal visit_finished(traveller: Node)

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var queueIndicator: HBoxContainer = $QueueIndicator
@onready var activeIndicator: HBoxContainer = $ActiveIndicator
@onready var tap_button: TouchScreenButton = $TapButton   # NEW
@onready var sprite_node: Sprite2D = $Sprite2D

var queue: Array[Node] = []
var active: Array[Node] = [] 

var _pumping: bool = false
var _epoch: int = 0   # increments on reset to cancel in-flight awaits

var tooltip_instance: Control = null   # shared Tooltip scene instance


func _clear_container_children(c: Node) -> void:
	if c == null:
		return
	for child in c.get_children():
		child.queue_free()


func clear_all() -> void:
	_epoch += 1

	queue.clear()
	active.clear()
	_pumping = false

	_clear_container_children(queueIndicator)
	_clear_container_children(activeIndicator)

	progress_bar.visible = false
	progress_bar.value = 0.0

	_hide_tooltip()


func _ready():
	print("initialised")
	
	# Apply the per-instance sprite, if set
	if sprite_node and sprite_texture:
		sprite_node.texture = sprite_texture

	# Hover (mouse only)
	connect("area_entered", _on_mouse_entered)
	connect("area_exited", _on_mouse_exited)
	connect("visit_requested", _on_visit_requested)
	
	# NEW: tap button (mouse + touch)
	if tap_button:
		tap_button.pressed.connect(_on_tap_button_pressed)

	if typeof(GanttHub) != TYPE_NIL and GanttHub.has_signal("events_reset"):
		if not GanttHub.is_connected("events_reset", Callable(self, "_on_events_reset")):
			GanttHub.connect("events_reset", Callable(self, "_on_events_reset"))


func _on_events_reset() -> void:
	print("CLEARING ATTRACTIN")
	clear_all()


# OLD click-on-Area2D is no longer needed if we rely on TouchScreenButton:
# func _input_event(viewport, event, shape_idx):
# 	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
# 		print("emitting signal")
# 		emit_signal("attraction_selected", self)


func _on_tap_button_pressed() -> void:
	# This is called on mouse click (with emulate_touch_from_mouse) and on real touch
	print("TapButton pressed on attraction: ", attractionName)
	emit_signal("attraction_selected", self)

	# Toggle tooltip on tap
	if tooltip_instance != null and is_instance_valid(tooltip_instance):
		_hide_tooltip()
	else:
		_show_tooltip()


func _on_visit_requested(traveller: Node) -> void:
	if active.has(traveller) or queue.has(traveller):
		return
	queue.append(traveller)
	var rect = ColorRect.new()
	rect.color = Color(0.2, 0.8, 1.0)  # cyan color
	rect.custom_minimum_size = Vector2(10, 10)
	queueIndicator.add_child(rect)

	_pump_queue()
	
func _emit_visit_started(traveller: Node) -> void:
	emit_signal("visit_started", traveller)


func _pump_queue() -> void:
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
		call_deferred("_emit_visit_started", next)

		# Move one indicator block from queueIndicator → activeIndicator
		#if queueIndicator.get_child_count() > 0:
		#	queueIndicator.get_child(0).queue_free()

		_sync_indicators()
		var rect := ColorRect.new()
		rect.color = Color(0.2, 0.4, 1.0)  # darker blue for active riders
		rect.custom_minimum_size = Vector2(10, 10)
		activeIndicator.add_child(rect)

	# Kick off a single session for this batch
	_serve_batch(my_epoch)
	
func _serve_batch(my_epoch: int) -> void:
	# One Gantt event per session, not per traveller
	GanttHub.start_named(
		"Serving",
		SimulationClock.now(),
		attractionName,
		Color8(52, 152, 219),
		"ATTRACTION"
	)

	# Run the session timer
	await _visit_for_sim_seconds(get_visit_duration())

	# If we've been reset in the meantime, bail out without touching state
	if my_epoch != _epoch:
		return

	GanttHub.finish_named(attractionName, SimulationClock.now())

	# Mark all active travellers as finished for this session
	for traveller in active:
		if is_instance_valid(traveller):
			emit_signal("visit_finished", traveller)

	active.clear()

	# Clear all active indicators
	_clear_container_children(activeIndicator)

	# Progress bar is controlled by _visit_for_sim_seconds,
	# but making sure it's hidden/zeroed doesn't hurt:
	progress_bar.visible = false
	progress_bar.value = 0
	
	_sync_indicators()

	# If there are more people in the queue, start the next session
	_pump_queue()




func _serve_one(traveller: Node) -> void:
	var my_epoch := _epoch

	if queueIndicator.get_child_count() > 0:
		queueIndicator.get_child(0).queue_free()

	var rect := ColorRect.new()
	rect.color = Color(0.2, 0.4, 1.0)
	rect.custom_minimum_size = Vector2(10, 10)
	activeIndicator.add_child(rect)

	GanttHub.start_named(
		"Serving",
		SimulationClock.now(),
		attractionName,
		Color8(52, 152, 219),
		"ATTRACTION"
	)

	await _visit_for_sim_seconds(get_visit_duration())

	if my_epoch != _epoch:
		return

	GanttHub.finish_named(attractionName, SimulationClock.now())

	emit_signal("visit_finished", traveller)
	active.erase(traveller)

	if is_instance_valid(rect) and rect.get_parent() == activeIndicator:
		rect.queue_free()
	elif activeIndicator.get_child_count() > 0:
		activeIndicator.get_child(0).queue_free()

	if capacity == 1 and active.is_empty():
		progress_bar.visible = false
		progress_bar.value = 0

	_pump_queue()


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


# --- Tooltip helpers -------------------------------------------------

func _build_tooltip_text() -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % attractionName)
	lines.append("[i]Capacity:[/i] %d" % capacity)
	lines.append("[i]Visit duration:[/i] %.1fs" % visit_duration_seconds)
	lines.append("[i]Queue size:[/i] %d" % queue.size())
	lines.append("[i]Active riders:[/i] %d" % active.size())
	return "\n".join(lines)


func _show_tooltip() -> void:
	if tooltip_scene == null:
		push_warning("Attraction has no tooltip_scene assigned.")
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
	if tooltip_instance.has_method("set_row_key"):
		tooltip_instance.call("set_row_key", attractionName)
	else:
		push_warning("Tooltip scene has no set_row_key() method.")
	

func _sync_indicators() -> void:
	# Rebuild queueIndicator from `queue`
	_clear_container_children(queueIndicator)
	for i in range(queue.size()):
		var rect := ColorRect.new()
		rect.color = Color(0.2, 0.8, 1.0)  # cyan for waiting
		rect.custom_minimum_size = Vector2(10, 10)
		queueIndicator.add_child(rect)

	# Rebuild activeIndicator from `active`
	#_clear_container_children(activeIndicator)
	#for i in range(active.size()):
#		var rect := ColorRect.new()
#		rect.color = Color(0.2, 0.4, 1.0)  # darker blue for active
#		rect.custom_minimum_size = Vector2(10, 10)
#		activeIndicator.add_child(rect)




func _hide_tooltip() -> void:
	if tooltip_instance != null and is_instance_valid(tooltip_instance):
		tooltip_instance.queue_free()
		tooltip_instance = null


# Hover still works for mouse, if you want it:
func _on_mouse_entered() -> void:
	print("Entered")
	_show_tooltip()


func _on_mouse_exited() -> void:
	print("Exited")
	_hide_tooltip()
	
	
func get_visit_duration() -> float:
	return visit_duration_seconds
