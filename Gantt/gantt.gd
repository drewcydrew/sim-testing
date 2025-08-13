extends Control
class_name BasicGantt

# Minimal, node-based Gantt:
# - set_time_window(start, end)
# - record_event(label, start, end, row?, color?)
# Creates GanttBar nodes and positions/sizes them based on the time window.

# Layout
@export var left_margin: float = 80.0
@export var right_margin: float = 16.0
@export var top_margin: float = 24.0
@export var bottom_margin: float = 24.0
@export var row_height: float = 18.0
@export var row_gap: float = 6.0

# Bar prefab (adjust path as needed)
@export var bar_scene: PackedScene = preload("res://GanttBar/GanttBar.tscn")
@export var _plot: Control

# Time window
var _start_time: float = 0.0
var _end_time: float = 30.0

# Runtime
var _bar_nodes: Array[Dictionary] = []  # {bar, start, end, row, label, color}

func _ready() -> void:
	if typeof(GanttHub) != TYPE_NIL:
		GanttHub.set_chart(self)
	resized.connect(_relayout_bars)

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

	# Create/attach bar node
	var bar: Control = bar_scene.instantiate()
	_plot.add_child(bar)
	if bar.has_method("set_data"):
		bar.call("set_data", label, s, e, row, color)

	# Track for layout
	_bar_nodes.append({
		"bar": bar,
		"start": s,
		"end": e,
		"row": row,
		"label": label,
		"color": color
	})

	# Expand time window as events arrive (optional but handy)
	if _bar_nodes.size() == 1:
		_start_time = s
		_end_time = maxf(e, s + 0.001)
	else:
		_start_time = min(_start_time, s)
		_end_time = max(_end_time, e)

	_relayout_bars()

func clear() -> void:
	for d in _bar_nodes:
		if is_instance_valid(d.bar):
			d.bar.queue_free()
	_bar_nodes.clear()

# --- Layout helpers -----------------------------------------------------------

func _map_time_to_x(t: float, plot: Rect2) -> float:
	if _end_time <= _start_time:
		return plot.position.x
	var u: float = (t - _start_time) / (_end_time - _start_time)
	return plot.position.x + clamp(u, 0.0, 1.0) * plot.size.x

func _relayout_bars() -> void:
	if _bar_nodes.is_empty():
		return

	var x0: float = left_margin
	var x1: float = size.x - right_margin
	var y0: float = top_margin
	var plot_w: float = max(1.0, x1 - x0)
	var plot_h: float = max(1.0, size.y - top_margin - bottom_margin)
	var plot_rect := Rect2(Vector2(x0, y0), Vector2(plot_w, plot_h))

	for d in _bar_nodes:
		var bar: Control = d.bar
		var s: float = d.start
		var e: float = d.end
		var row: int = d.row

		var px_start: float = _map_time_to_x(s, plot_rect)
		var px_end: float = _map_time_to_x(e, plot_rect)
		var w: float = max(1.0, px_end - px_start)
		var row_y: float = y0 + float(row) * (row_height + row_gap)

		bar.position = Vector2(px_start, row_y)
		bar.size = Vector2(w, row_height)
