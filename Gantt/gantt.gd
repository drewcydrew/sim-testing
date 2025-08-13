extends Control
class_name BasicGantt

# Minimal Gantt: accepts completed events and draws rectangles.
# Strongly typed to avoid Variant inference errors in Godot 4.
#
# API:
#   set_time_window(start_time: float, end_time: float)
#   record_event(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0))





# Typed inner class for events (avoids Variant dictionaries)
class Event:
	var row: int
	var label: String
	var start: float
	var end: float
	var color: Color

@export var left_margin: float = 80.0
@export var top_margin: float = 24.0
@export var row_height: float = 18.0
@export var row_gap: float = 6.0
@export var background_color: Color = Color(0.12, 0.12, 0.14)
@export var default_bar_color: Color = Color(0.50, 0.80, 1.00, 1.0)
@export var text_color: Color = Color(0.92, 0.92, 0.96, 0.95)

var _start_time: float = 0.0
var _end_time: float = 30.0

var _events: Array[Event] = []


func _ready() -> void:
	GanttHub.set_chart(self)

func _exit_tree() -> void:
	# avoid dangling reference if scene is closed
	if GanttHub.chart == self:
		GanttHub.clear_chart()

func set_time_window(start_time: float, end_time: float) -> void:
	_start_time = start_time
	_end_time = maxf(end_time, start_time + 0.001)
	queue_redraw()

func record_event(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	if end_time < start_time:
		var tmp: float = start_time
		start_time = end_time
		end_time = tmp
	var ev := Event.new()
	ev.row = max(0, row)
	ev.label = label
	ev.start = start_time
	ev.end = end_time
	ev.color = color
	_events.append(ev)
	queue_redraw()

func clear() -> void:
	_events.clear()
	queue_redraw()

func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, size), background_color)

	var visible_span: float = _end_time - _start_time
	if visible_span <= 0.0:
		return

	var content_x0: float = left_margin
	var content_x1: float = size.x - 8.0
	var content_w: float = maxf(1.0, content_x1 - content_x0)

	# Draw events
	var max_row: int = 0
	for ev: Event in _events:
		max_row = max(max_row, ev.row)
		var x1: float = content_x0 + content_w * ((ev.start - _start_time) / visible_span)
		var x2: float = content_x0 + content_w * ((ev.end   - _start_time) / visible_span)
		if x2 <= content_x0 or x1 >= content_x1:
			continue # fully outside
		x1 = clampf(x1, content_x0, content_x1)
		x2 = clampf(x2, content_x0, content_x1)

		var y: float = _row_to_y(ev.row)
		var rect: Rect2 = Rect2(Vector2(x1, y + 2.0), Vector2(maxf(1.0, x2 - x1), row_height - 4.0))
		draw_rect(rect, ev.color)

		# Label (only if it fits)
		var font := get_theme_default_font()
		var fs: int = get_theme_default_font_size()
		if ev.label != "" and font:
			var text_size: Vector2 = font.get_string_size(ev.label, fs)
			if text_size.x + 8.0 <= rect.size.x:
				draw_string(font, rect.position + Vector2(4.0, row_height * 0.7), ev.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0,0,0,0.8))

	# Row labels (very simple: "Row N")
	var font2 := get_theme_default_font()
	var fs2: int = get_theme_default_font_size()
	for r in range(max_row + 1):
		draw_string(font2, Vector2(8.0, _row_to_y(r) + row_height * 0.7), "Row %d" % r, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs2, text_color)

func _row_to_y(row_index: int) -> float:
	return top_margin + float(row_index) * (row_height + row_gap)

func _get_minimum_size() -> Vector2:
	var max_row: int = 0
	for ev: Event in _events:
		max_row = max(max_row, ev.row)
	var h: float = top_margin + float(max_row + 1) * (row_height + row_gap) + 8.0
	return Vector2(320.0, h)
