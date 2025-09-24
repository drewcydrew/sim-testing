extends Control
class_name BasicGantt

# --- Fixed x-domain -----------------------------------------------------------
const AXIS_MIN: float = 0.0
const AXIS_MAX: float = 50.0

# --- Vertical layout (inside host) -------------------------------------------
@export var row_height: float = 18.0
@export var row_gap: float = 6.0

# --- Bar prefab & container ---------------------------------------------------
@export var bar_scene: PackedScene = preload("res://GanttBar/GanttBar.tscn")
@export var _plot: Control  # can be any Control; may be a Container

# Internal host where bars are added (always a non-Container Control)
var _host: Control

# API-compat only (not used for x mapping)
var _start_time: float = 0.0
var _end_time: float = 30.0

# Each entry: {bar: Control, start: float, end: float, row: int, label: String, color: Color}
var _bar_nodes: Array[Dictionary] = []

func _ready() -> void:
	_init_plot_host()
	if typeof(GanttHub) != TYPE_NIL:
		GanttHub.set_chart(self)
	resized.connect(Callable(self, "_relayout_bars"))

func _exit_tree() -> void:
	if typeof(GanttHub) != TYPE_NIL and GanttHub.chart == self:
		GanttHub.clear_chart()

# --- Public API ---------------------------------------------------------------

func set_time_window(start_time: float, end_time: float) -> void:
	_start_time = start_time
	_end_time = maxf(end_time, start_time + 0.001)
	_relayout_bars()

func record_event(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	var s: float = min(start_time, end_time)
	var e: float = max(start_time, end_time)

	var bar: Control = bar_scene.instantiate()
	_prepare_bar_for_manual_layout(bar)
	_host.add_child(bar)

	if bar.has_method("set_data"):
		bar.call("set_data", label, s, e, row, color)

	_bar_nodes.append({
		"bar": bar,
		"start": s,
		"end": e,
		"row": row,
		"label": label,
		"color": color
	})

	_relayout_bars()

func clear() -> void:
	for d in _bar_nodes:
		var bar: Control = (d.get("bar") as Control)
		if is_instance_valid(bar):
			bar.queue_free()
	_bar_nodes.clear()

# --- Internal helpers ---------------------------------------------------------

func _init_plot_host() -> void:
	# Fallback if not assigned
	if _plot == null:
		_plot = self

	# If _plot is a Container, create a manual-layout child to host bars.
	if _plot is Container:
		push_warning("BasicGantt: _plot is a Container; adding a manual 'PlotHost' to avoid layout overrides.")
		_host = Control.new()
		_host.name = "PlotHost"
		_host.set_anchors_preset(Control.PRESET_FULL_RECT)
		_plot.add_child(_host)
	else:
		_host = _plot

func _prepare_bar_for_manual_layout(bar: Control) -> void:
	# Top-left anchored, fully manual placement
	bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 0.0
	bar.anchor_bottom = 0.0

	# No automatic stretching
	bar.size_flags_horizontal = 0
	bar.size_flags_vertical = 0
	bar.custom_minimum_size = Vector2.ZERO
	bar.pivot_offset = Vector2.ZERO
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

# Linear map from domain value -> host-local pixels (float, no rounding)
func _map_time_to_px(value: float, plot_width: float) -> float:
	var span: float = AXIS_MAX - AXIS_MIN
	if span <= 0.0:
		return 0.0
	var u: float = (value - AXIS_MIN) / span
	return clamp(u, 0.0, 1.0) * plot_width

func _relayout_bars() -> void:
	if _bar_nodes.is_empty() or _host == null:
		return

	var plot_w: float = max(1.0, _host.size.x)
	var plot_h: float = max(1.0, _host.size.y)

	for d in _bar_nodes:
		var bar: ColorRect = (d["bar"] as ColorRect)
		var s: float = d["start"]
		var e: float = d["end"]
		var row: int = int(d["row"])

		# Fully out of range -> hide
		if e <= AXIS_MIN or s >= AXIS_MAX:
			#bar.visible = false
			continue
		#bar.visible = true

		# Clip to domain
		var s_clip: float = max(s, AXIS_MIN)
		var e_clip: float = min(e, AXIS_MAX)

		# Independent mapping (no sequencing, no rounding)
		var x0: float = _map_time_to_px(s_clip, plot_w)
		var x1: float = _map_time_to_px(e_clip, plot_w)
		#var w: float = max(1.0, x1 - x0)

		# Vertical placement per row inside host
		var row_y: float = float(row) * (row_height + row_gap)
		if row_y + row_height > plot_h:
			bar.visible = false
			continue

		bar.size = Vector2(1, row_height)
		bar.position = Vector2(x0, row_y)   # host-local
		
