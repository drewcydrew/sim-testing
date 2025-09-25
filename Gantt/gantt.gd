extends Control
class_name BasicGantt

# ── Time domain & horizontal zoom (works with a parent ScrollContainer) ───────
@export var domain_min: float = 0.0
@export var domain_max: float = 50.0
@export var pixels_per_unit: float = 10.0            # horizontal zoom
@export var auto_grow_domain: bool = true            # expand as events arrive

# ── Layout ────────────────────────────────────────────────────────────────────
@export var row_height: float = 18.0
@export var row_gap: float = 6.0
@export var left_margin: float = 0.0                 # keeps working as before
@export var right_margin: float = 0.0
@export var top_margin: float = 0.0
@export var bottom_margin: float = 0.0

# Labels **inside bars**
@export var show_labels: bool = false
@export var label_color: Color = Color(1, 1, 1, 1)
@export var label_pad_left: float = 6.0
@export var label_pad_right: float = 6.0

# ── Row-label gutter (traveller names on the left) ────────────────────────────
@export var show_row_labels: bool = true
@export var row_label_gutter_width: float = 120.0
@export var row_label_pad_left: float = 8.0
@export var row_label_color: Color = Color(0.92, 0.92, 0.92, 1.0)
@export var row_label_font: Font
@export var row_label_font_size: int = 0            # 0 = use theme default

# Debug
@export var debug_log: bool = false

# Stored events (typed)
# Each: { label: String, start: float, end: float, row: int, color: Color }
var _events: Array[Dictionary] = []
var _max_row: int = -1

# Map row-key (e.g. traveller name) -> numeric row index
var _row_key_to_index: Dictionary = {}
var _row_index_to_key: Array[String] = []  # index -> key (for drawing labels)

# ── Row key helpers ───────────────────────────────────────────────────────────

func _get_row_index_for(key: String) -> int:
	if _row_key_to_index.has(key):
		return _row_key_to_index[key]
	# Allocate a new row
	_max_row += 1
	var idx := _max_row
	_row_key_to_index[key] = idx
	_row_index_to_key.append(key)
	_update_content_metrics()  # content height may grow
	queue_redraw()
	return idx

func record_event_by_key(label: String, start_time: float, end_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	var row := _get_row_index_for(row_key)
	if debug_log:
		print("recording to row ", row, " (", row_key, ")")
	record_event(label, start_time, end_time, row, color)

# ── Node lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(Callable(self, "_on_resized"))
	_update_content_metrics()
	# Register with hub (optional)
	if typeof(GanttHub) != TYPE_NIL:
		GanttHub.set_chart(self)

func _exit_tree() -> void:
	if typeof(GanttHub) != TYPE_NIL and GanttHub.chart == self:
		GanttHub.clear_chart()

# ── Public API (call these from your game code) ───────────────────────────────

func record_event(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	var s: float = min(start_time, end_time)
	var e: float = max(start_time, end_time)
	if e <= s:
		return

	_events.append({
		"label": label,
		"start": s,
		"end": e,
		"row": row,
		"color": color
	})
	_max_row = max(_max_row, row)

	if auto_grow_domain:
		if _events.size() == 1:
			domain_min = s
			domain_max = maxf(e, s + 0.001)
		else:
			domain_min = min(domain_min, s)
			domain_max = max(domain_max, e)

	_update_content_metrics()
	queue_redraw()

func clear():
	_events.clear()
	_max_row = -1
	_row_key_to_index.clear()
	_row_index_to_key.clear()
	_update_content_metrics()
	queue_redraw()

# Keep for compatibility; sets visible domain explicitly
func set_time_window(start_time: float, end_time: float) -> void:
	domain_min = start_time
	domain_max = maxf(end_time, start_time + 0.001)
	_update_content_metrics()
	queue_redraw()

func set_axis(min_v: float, max_v: float) -> void:
	domain_min = min_v
	domain_max = maxf(max_v, min_v + 0.001)
	_update_content_metrics()
	queue_redraw()

# Renamed to avoid colliding with Control.set_scale(Vector2)
func set_pixels_per_unit(px_per_unit: float) -> void:
	pixels_per_unit = max(0.01, px_per_unit)
	_update_content_metrics()
	queue_redraw()

func set_zoom(px_per_unit: float) -> void:
	set_pixels_per_unit(px_per_unit)

func set_auto_grow(v: bool) -> void:
	auto_grow_domain = v

func fit_domain(pad_units: float = 0.0) -> void:
	if _events.is_empty():
		return
	var lo: float = _events[0]["start"]
	var hi: float = _events[0]["end"]
	for ev: Dictionary in _events:
		lo = min(lo, ev["start"])
		hi = max(hi, ev["end"])
	domain_min = lo - pad_units
	domain_max = hi + pad_units
	_update_content_metrics()
	queue_redraw()

# ── Drawing ───────────────────────────────────────────────────────────────────

func _on_resized() -> void:
	queue_redraw()

func _draw() -> void:
	var plot: Rect2 = _plot_rect()
	var span: float = domain_max - domain_min
	var scale: float = pixels_per_unit

	# Draw row labels in the left gutter (even when there are no events)
	if show_row_labels and _row_index_to_key.size() > 0:
		_draw_row_labels(plot)

	# If there are no events, we're done (labels may still be visible)
	if _events.is_empty():
		return

	if span <= 0.0:
		return

	var font := get_theme_default_font()
	var font_size: int = int(get_theme_default_font_size())

	for ev: Dictionary in _events:
		var s: float = ev["start"]
		var e: float = ev["end"]
		var row: int = int(ev["row"])
		var col: Color = ev["color"]
		var inside_label: String = ev["label"]

		if e <= s:
			continue

		# Clip to visible domain
		var s_clip: float = max(s, domain_min)
		var e_clip: float = min(e, domain_max)
		if e_clip <= s_clip:
			continue

		# Map to integer pixels in *plot* space
		var x0_px: int = int(floor(plot.position.x + (s_clip - domain_min) * scale))
		var x1_px: int = int(floor(plot.position.x + (e_clip - domain_min) * scale))
		if x1_px <= x0_px:
			x1_px = x0_px + 1
		var w_px: int = x1_px - x0_px

		var y_px: int = int(floor(plot.position.y + float(row) * (row_height + row_gap)))
		var h_px: int = max(1, int(floor(row_height)))

		var bar_rect: Rect2 = Rect2(Vector2(float(x0_px), float(y_px)), Vector2(float(w_px), float(h_px)))
		draw_rect(bar_rect, col, true)

		# Optional label inside the bar
		if show_labels and font != null:
			var baseline_y: float = bar_rect.position.y + (bar_rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
			var text_pos: Vector2 = Vector2(bar_rect.position.x + label_pad_left, baseline_y)
			draw_string(font, text_pos, inside_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, label_color)

		if debug_log:
			print("'", inside_label, "' s=", s_clip, " e=", e_clip, " rect=", bar_rect)

# Draw traveller names in the gutter
func _draw_row_labels(plot: Rect2) -> void:
	var fnt := row_label_font
	var fsize: int = row_label_font_size
	if fnt == null:
		fnt = get_theme_default_font()
	if fsize <= 0:
		fsize = int(get_theme_default_font_size())
	if fnt == null or fsize <= 0:
		return

	var fh: float = fnt.get_height(fsize)
	var ascent: float = fnt.get_ascent(fsize)

	# Gutter left edge is the node's local left; we reserve [left_margin .. left_margin+gutter)
	var gutter_left_x: float = left_margin
	var text_x: float = gutter_left_x + row_label_pad_left

	for i in range(_row_index_to_key.size()):
		var key := _row_index_to_key[i]
		var row_top: float = plot.position.y + float(i) * (row_height + row_gap)
		var baseline_y: float = row_top + (row_height - fh) * 0.5 + ascent
		draw_string(fnt, Vector2(text_x, baseline_y), key, HORIZONTAL_ALIGNMENT_LEFT, row_label_gutter_width - row_label_pad_left, fsize, row_label_color)

	# Optional separator line between gutter and plot
	var sep_x: float = left_margin + _gutter_width() - 1.0
	if sep_x > 0.0:
		draw_line(Vector2(sep_x, 0.0), Vector2(sep_x, size.y), row_label_color * Color(1,1,1,0.35), 1.0)


# Tooltips for hovered bars
func _get_tooltip(at_position: Vector2) -> String:
	var plot: Rect2 = _plot_rect()
	var scale: float = pixels_per_unit

	for ev: Dictionary in _events:
		var s: float = ev["start"]
		var e: float = ev["end"]
		var row: int = int(ev["row"])
		if e <= s:
			continue

		var s_clip: float = max(s, domain_min)
		var e_clip: float = min(e, domain_max)
		if e_clip <= s_clip:
			continue

		var x0_px: int = int(floor(plot.position.x + (s_clip - domain_min) * scale))
		var x1_px: int = int(floor(plot.position.x + (e_clip - domain_min) * scale))
		if x1_px <= x0_px:
			x1_px = x0_px + 1
		var y_px: int = int(floor(plot.position.y + float(row) * (row_height + row_gap)))
		var h_px: int = int(floor(row_height))

		var r: Rect2 = Rect2(Vector2(float(x0_px), float(y_px)), Vector2(float(x1_px - x0_px), float(h_px)))
		if r.has_point(at_position):
			var dur: float = max(0.0, e - s)
			return "%s\nStart: %.3f  End: %.3f\nDuration: %.3fs" % [ev["label"], s, e, dur]
	return ""

# ── Helpers ───────────────────────────────────────────────────────────────────

func _gutter_width() -> float:
	return row_label_gutter_width if show_row_labels else 0.0

func _plot_rect() -> Rect2:
	# The content (and thus scrollable width/height) is determined by domain span and rows.
	var x0: float = left_margin + _gutter_width()    # reserve gutter without mutating left_margin
	var y0: float = top_margin
	var content_w: float = max(1.0, (domain_max - domain_min) * pixels_per_unit)
	var content_h: float = max(1.0, _content_rows_height())
	return Rect2(Vector2(x0, y0), Vector2(content_w, content_h))

func _content_rows_height() -> float:
	if _max_row < 0:
		return 0.0
	var rows_total: float = float(_max_row + 1)
	return rows_total * row_height + max(0.0, rows_total - 1.0) * row_gap

func _update_content_metrics() -> void:
	# Set the size the ScrollContainer will use for scrollbars.
	var content_w: float = left_margin + _gutter_width() + right_margin + max(1.0, (domain_max - domain_min) * pixels_per_unit)
	var content_h: float = top_margin + bottom_margin + max(1.0, _content_rows_height())
	custom_minimum_size = Vector2(content_w, content_h)
