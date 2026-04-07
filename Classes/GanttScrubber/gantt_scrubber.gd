extends Control
class_name GanttScrubber

## A draggable timeline scrubber that sits inside a BasicGantt control.
## Drag the centre thumb to pan; drag the left/right handles to zoom.

# ── Visual style ─────────────────────────────────────────────────────────────
@export var track_color: Color = Color(0.12, 0.12, 0.18, 0.90)
@export var thumb_color: Color = Color(0.30, 0.50, 0.80, 0.70)
@export var handle_color: Color = Color(0.55, 0.75, 1.0, 1.0)
@export var now_marker_color: Color = Color(1.0, 0.85, 0.3, 0.90)
@export var border_color: Color = Color(0.55, 0.75, 1.0, 0.30)

const HANDLE_W: float = 14.0
const MIN_THUMB_W: float = HANDLE_W * 3.0

# ── Internal state ────────────────────────────────────────────────────────────
var _gantt: BasicGantt = null
var _scroll: ScrollContainer = null

enum DragMode {NONE, LEFT_HANDLE, CENTER, RIGHT_HANDLE}

var _drag_mode: DragMode = DragMode.NONE
var _drag_start_x: float = 0.0
var _drag_start_scroll: float = 0.0
var _drag_start_ppu: float = 0.0
var _drag_start_thumb: Rect2 = Rect2()
var _was_auto_fit: bool = false


func _ready() -> void:
	_gantt = get_parent() as BasicGantt
	if _gantt == null:
		push_error("GanttScrubber must be a direct child of BasicGantt")
		return
	_scroll = _gantt.get_parent() as ScrollContainer
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _process(_delta: float) -> void:
	if _gantt == null or _scroll == null:
		return
	# Stay visually fixed in the viewport: track scroll offset and viewport size.
	var new_x := float(_scroll.scroll_horizontal)
	var new_y := float(_scroll.scroll_vertical) + _scroll.size.y - size.y
	var new_w := _scroll.size.x
	if position.x != new_x or position.y != new_y or size.x != new_w:
		position.x = new_x
		position.y = new_y
		size.x = new_w
	queue_redraw()


# ── Thumb geometry ────────────────────────────────────────────────────────────

func _get_thumb_rect() -> Rect2:
	var domain: float = _gantt.domain_max - _gantt.domain_min
	if domain <= 0.0:
		return Rect2(0.0, 0.0, MIN_THUMB_W, size.y)

	var viewport_w: float = _scroll.size.x
	var ppu: float = max(0.001, _gantt.pixels_per_unit)
	var visible_duration: float = viewport_w / ppu
	var visible_start: float = float(_scroll.scroll_horizontal) / ppu

	var tx0: float = (visible_start - _gantt.domain_min) / domain * size.x
	var tx1: float = tx0 + (visible_duration / domain) * size.x

	tx0 = clamp(tx0, 0.0, size.x)
	tx1 = clamp(tx1, 0.0, size.x)

	# Enforce minimum grabbable width
	if tx1 - tx0 < MIN_THUMB_W:
		var center: float = (tx0 + tx1) * 0.5
		tx0 = clamp(center - MIN_THUMB_W * 0.5, 0.0, size.x - MIN_THUMB_W)
		tx1 = tx0 + MIN_THUMB_W

	return Rect2(tx0, 0.0, tx1 - tx0, size.y)


func _get_drag_mode_at(x: float) -> DragMode:
	var thumb: Rect2 = _get_thumb_rect()
	if thumb.size.x <= 0.0:
		return DragMode.NONE
	var tx0: float = thumb.position.x
	var tx1: float = thumb.position.x + thumb.size.x
	if x >= tx0 and x <= tx0 + HANDLE_W:
		return DragMode.LEFT_HANDLE
	if x >= tx1 - HANDLE_W and x <= tx1:
		return DragMode.RIGHT_HANDLE
	if x > tx0 + HANDLE_W and x < tx1 - HANDLE_W:
		return DragMode.CENTER
	return DragMode.NONE


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return

	# Track background
	draw_rect(Rect2(0.0, 0.0, w, h), track_color, true)

	if _gantt == null or _scroll == null:
		return

	var thumb: Rect2 = _get_thumb_rect()

	# Thumb body
	draw_rect(thumb, thumb_color, true)

	# Left handle
	draw_rect(Rect2(thumb.position.x, 0.0, HANDLE_W, h), handle_color, true)

	# Right handle
	draw_rect(Rect2(thumb.position.x + thumb.size.x - HANDLE_W, 0.0, HANDLE_W, h), handle_color, true)

	# Grip lines on left handle (3 vertical lines)
	_draw_grip_lines(thumb.position.x, HANDLE_W, h)

	# Grip lines on right handle
	_draw_grip_lines(thumb.position.x + thumb.size.x - HANDLE_W, HANDLE_W, h)

	# Thumb outline
	draw_rect(thumb, border_color, false, 1.5)

	# "Now" time marker
	var domain: float = _gantt.domain_max - _gantt.domain_min
	if domain > 0.0:
		var now_t: float = _gantt._now() - _gantt.domain_min
		if now_t >= 0.0:
			var now_x: float = (now_t / domain) * w
			if now_x >= 0.0 and now_x <= w:
				draw_line(Vector2(now_x, 0.0), Vector2(now_x, h), now_marker_color, 2.0)


func _draw_grip_lines(handle_x: float, hw: float, h: float) -> void:
	var mid_x: float = handle_x + hw * 0.5
	var line_h: float = h * 0.45
	var y0: float = (h - line_h) * 0.5
	var y1: float = y0 + line_h
	var grip_color: Color = Color(1.0, 1.0, 1.0, 0.45)
	for i: int in range(3):
		var gx: float = mid_x + float(i - 1) * 3.5
		draw_line(Vector2(gx, y0), Vector2(gx, y1), grip_color, 1.5)


# ── Drag logic ────────────────────────────────────────────────────────────────

func _begin_drag(x: float, mode: DragMode) -> void:
	_drag_mode = mode
	_drag_start_x = x
	_drag_start_scroll = float(_scroll.scroll_horizontal)
	_drag_start_ppu = _gantt.pixels_per_unit
	_drag_start_thumb = _get_thumb_rect()
	_was_auto_fit = _gantt.auto_fit_domain_live
	_gantt.auto_fit_domain_live = false


func _end_drag() -> void:
	if _drag_mode == DragMode.NONE:
		return
	_drag_mode = DragMode.NONE
	_gantt.auto_fit_domain_live = _was_auto_fit


func _do_drag(x: float) -> void:
	if _drag_mode == DragMode.NONE or _gantt == null or _scroll == null:
		return

	var delta_x: float = x - _drag_start_x
	var domain: float = _gantt.domain_max - _gantt.domain_min
	if domain <= 0.0 or size.x <= 0.0:
		return

	var viewport_w: float = _scroll.size.x

	match _drag_mode:
		DragMode.CENTER:
			var delta_t: float = (delta_x / size.x) * domain
			var new_scroll: float = _drag_start_scroll + delta_t * _gantt.pixels_per_unit
			var max_scroll: float = max(0.0, _gantt.custom_minimum_size.x - viewport_w)
			_scroll.scroll_horizontal = int(clamp(new_scroll, 0.0, max_scroll))

		DragMode.LEFT_HANDLE:
			# Left edge moves; visible end stays fixed.
			var new_tx0: float = clamp(
				_drag_start_thumb.position.x + delta_x,
				0.0,
				_drag_start_thumb.position.x + _drag_start_thumb.size.x - MIN_THUMB_W
			)
			var new_visible_start: float = _gantt.domain_min + (new_tx0 / size.x) * domain
			var fixed_visible_end: float = (_drag_start_scroll + viewport_w) / _drag_start_ppu
			var new_duration: float = fixed_visible_end - new_visible_start
			if new_duration <= 0.0:
				return
			var new_ppu: float = clamp(viewport_w / new_duration, _gantt.zoom_min, _gantt.zoom_max)
			_gantt.set_pixels_per_unit(new_ppu)
			var new_scroll: float = max(0.0, new_visible_start * new_ppu)
			var max_scroll: float = max(0.0, _gantt.custom_minimum_size.x - viewport_w)
			_scroll.scroll_horizontal = int(clamp(new_scroll, 0.0, max_scroll))

		DragMode.RIGHT_HANDLE:
			# Right edge moves; visible start stays fixed.
			var tx1_start: float = _drag_start_thumb.position.x + _drag_start_thumb.size.x
			var new_tx1: float = clamp(
				tx1_start + delta_x,
				_drag_start_thumb.position.x + MIN_THUMB_W,
				size.x
			)
			var new_visible_end: float = _gantt.domain_min + (new_tx1 / size.x) * domain
			var fixed_visible_start: float = _drag_start_scroll / _drag_start_ppu
			var new_duration: float = new_visible_end - fixed_visible_start
			if new_duration <= 0.0:
				return
			var new_ppu: float = clamp(viewport_w / new_duration, _gantt.zoom_min, _gantt.zoom_max)
			_gantt.set_pixels_per_unit(new_ppu)
			var new_scroll: float = max(0.0, fixed_visible_start * new_ppu)
			var max_scroll: float = max(0.0, _gantt.custom_minimum_size.x - viewport_w)
			_scroll.scroll_horizontal = int(clamp(new_scroll, 0.0, max_scroll))


# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mode := _get_drag_mode_at(event.position.x)
			if mode != DragMode.NONE:
				_begin_drag(event.position.x, mode)
				accept_event()
		else:
			if _drag_mode != DragMode.NONE:
				_end_drag()
				accept_event()

	elif event is InputEventMouseMotion:
		if _drag_mode != DragMode.NONE:
			_do_drag(event.position.x)
			accept_event()

	elif event is InputEventScreenTouch:
		if event.pressed:
			var mode := _get_drag_mode_at(event.position.x)
			if mode != DragMode.NONE:
				_begin_drag(event.position.x, mode)
				accept_event()
		else:
			if _drag_mode != DragMode.NONE:
				_end_drag()
				accept_event()

	elif event is InputEventScreenDrag:
		if _drag_mode != DragMode.NONE:
			_do_drag(event.position.x)
			accept_event()
