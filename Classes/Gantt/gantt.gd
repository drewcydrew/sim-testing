extends Control
class_name BasicGantt

# Auto-centering options
@export var auto_follow_now: bool = false # keep 'now' centered in view
@export var follow_window_seconds: float = 60.0 # width of sliding window

@export var auto_fit_domain_live: bool = true # fit domain to all bars each frame
@export var fit_padding_seconds: float = 2.0 # padding when auto-fitting
@export var recalc_hz: float = 10.0 # limit re-centering to avoid thrash

@export var tooltip_scene: PackedScene


# ── Time domain & horizontal zoom (works with a parent ScrollContainer) ───────
@export var domain_min: float = 0.0
@export var domain_max: float = 100.0
@export var pixels_per_unit: float = 10.0 # horizontal zoom
@export var auto_grow_domain: bool = false # expand as events arrive

# ── Layout ────────────────────────────────────────────────────────────────────
@export var row_height: float = 18.0
@export var row_gap: float = 6.0
@export var left_margin: float = 0.0 # keeps working as before
@export var right_margin: float = 0.0
@export var top_margin: float = 100.0
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
@export var row_label_font_size: int = 0 # 0 = use theme default

# ── Zoom/Pan controls ─────────────────────────────────────────────────────────
@export var zoom_min: float = 0.01
@export var zoom_max: float = 100.0
@export var zoom_sensitivity: float = 0.1


@export var grow_open_events: bool = true

@export var display_type: String = ""

# ── Time Axis / Tick Marks ───────────────────────────────────────────────────
@export var show_time_axis: bool = true
@export var tick_interval_seconds: float = 10.0 # spacing between vertical ticks
@export var major_tick_every: int = 6 # e.g. every 6 minor ticks = major tick (1 min when interval=10s)
@export var tick_color: Color = Color(0.5, 0.5, 0.5, 0.4)
@export var major_tick_color: Color = Color(0.8, 0.8, 0.8, 0.7)
@export var tick_width: float = 1.0
@export var major_tick_width: float = 2.0

@export var show_time_labels: bool = true
@export var time_label_font: Font
@export var time_label_font_size: int = 14
@export var time_label_color: Color = Color(0.9, 0.9, 0.9, 1)

@export var time_axis_height: float = 30.0


var _tap_tooltip: Control = null

const _DISPLAY_DAY_START_SEC: int = 9 * 3600

var _open_by_key: Dictionary = {}

# Debug
@export var debug_log: bool = false

var _accum: float = 0.0


# Stored events (typed)
# Each: { label: String, start: float, end: float, row: int, color: Color }
var _events: Array[Dictionary] = []
var _max_row: int = -1

# Map row-key (e.g. traveller name) -> numeric row index
var _row_key_to_index: Dictionary = {}
var _row_index_to_key: Array[String] = [] # index -> key (for drawing labels)


func _plot_width_available() -> float:
	# Width inside the plot area (node width minus gutter/margins)
	var w := size.x - (left_margin + right_margin + _gutter_width())
	return max(1.0, w)

func _fit_scale_to_viewport() -> void:
	# Use the ScrollContainer's viewport width if we're inside one;
	# fall back to our own size otherwise.
	var viewport_width: float = size.x
	var p := get_parent()
	if p is ScrollContainer:
		viewport_width = (p as ScrollContainer).size.x

	# Match the same plot area logic as _draw_time_axis
	var x0: float = row_label_gutter_width + left_margin
	var x1: float = viewport_width - right_margin
	var usable_w: float = max(1.0, x1 - x0)

	# Time span we want to see
	var span: float = max(0.001, domain_max - domain_min)

	# Pixels per unit so that [domain_min .. domain_max] fills the plot width
	var target_ppu: float = usable_w / span

	# Clamp to zoom limits
	pixels_per_unit = clamp(target_ppu, zoom_min, zoom_max)

	_update_content_metrics()


func _effective_end(ev: Dictionary) -> float:
	var e_raw := float(ev.get("end", NAN))
	var is_open: bool = grow_open_events and ev.get("open", false) and not is_finite(e_raw)
	return _now() if is_open else e_raw

func _fit_domain_from_events(pad: float) -> void:
	if _events.is_empty():
		return

	var hi: float = - INF
	for ev in _events:
		var e: float = _effective_end(ev)
		if is_finite(e):
			hi = max(hi, e)

	if hi == -INF:
		return

	# Left edge stays fixed (usually 0). Only extend the right edge.
	domain_max = max(domain_max, hi + pad)

	# Just update scrollable size; DO NOT change pixels_per_unit here.
	_update_content_metrics()


# ── Row key helpers ───────────────────────────────────────────────────────────

func _get_row_index_for(key: String) -> int:
	if _row_key_to_index.has(key):
		return _row_key_to_index[key]
	# Allocate a new row
	_max_row += 1
	var idx := _max_row
	_row_key_to_index[key] = idx
	_row_index_to_key.append(key)
	_update_content_metrics() # content height may grow
	queue_redraw()
	return idx

func record_event_by_key(label: String, start_time: float, end_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	var row := _get_row_index_for(row_key)
	if debug_log:
		print("recording to row ", row, " (", row_key, ")")
	record_event(label, start_time, end_time, row, color)

# ── Node lifecycle ────────────────────────────────────────────────────────────

# Handlers (very small)
func _on_hub_event_recorded(ev: Dictionary) -> void:
	var ev_type := String(ev.get("type", ""))
	if not _type_matches(ev_type):
		return
	if ev.has("row_key"):
		record_event_by_key(ev.label, float(ev.start_time), float(ev.end_time), ev.row_key, ev.color)
	elif ev.has("row"):
		record_event(ev.label, float(ev.start_time), float(ev.end_time), int(ev.row), ev.color)

func _on_hub_event_opened(row_key: String, payload: Dictionary) -> void:
	var ev_type := String(payload.get("type", ""))
	if not _type_matches(ev_type):
		return
	open_event_by_key(payload.label, float(payload.start_time), row_key, payload.color)

func _on_hub_event_finished(row_key: String, end_time: float) -> void:
	# Safe: only matching-type opens were created locally, so this is a no-op otherwise.
	finish_event_by_key(row_key, float(end_time))

		
func _norm(s: String) -> String:
	return String(s).strip_edges().to_lower()

func _type_matches(t: String) -> bool:
	var want := _norm(display_type)
	if want == "" or want == "all":
		return true
	return _norm(t) == want

func _row_key_from_open_map_key(k: String) -> String:
	var sep := "::"
	if typeof(GanttHub) != TYPE_NIL and GanttHub.has_variable("_TYPE_SEP"):
		sep = String(GanttHub._TYPE_SEP)
	var parts := String(k).split(sep, false, 1)
	return String(parts[1]) if parts.size() == 2 else String(k)


func _ready() -> void:
	size = Vector2(1600, 600)
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(Callable(self , "_on_resized"))
	_update_content_metrics()
	# Register with hub (optional)
	#if typeof(GanttHub) != TYPE_NIL:
	#	GanttHub.set_chart(self)
		
		# 1) Closed events
	if typeof(GanttHub) != TYPE_NIL and GanttHub.has_method("get_all_events"):
		for ev in GanttHub.get_all_events():
			var ev_type := String(ev.get("type", ""))
			if not _type_matches(ev_type):
				continue
			if ev.has("row_key"):
				record_event_by_key(ev.label, ev.start_time, ev.end_time, ev.row_key, ev.color)
			elif ev.has("row"):
				record_event(ev.label, ev.start_time, ev.end_time, int(ev.row), ev.color)

	# 2) Open events
	if typeof(GanttHub) != TYPE_NIL and GanttHub.has_method("get_open_events"):
		var open_map := GanttHub.get_open_events()
		for k in open_map.keys():
			var o: Dictionary = open_map[k]
			var ev_type := String(o.get("type", ""))
			if not _type_matches(ev_type):
				continue
			var rk := String(o.get("row_key", ""))
			if rk == "":
				rk = _row_key_from_open_map_key(String(k))
			open_event_by_key(o.label, float(o.start_time), rk, o.color)


		# 3) Subscribe to live updates
		if not GanttHub.is_connected("event_recorded", Callable(self , "_on_hub_event_recorded")):
			GanttHub.connect("event_recorded", Callable(self , "_on_hub_event_recorded"))
		if not GanttHub.is_connected("event_opened", Callable(self , "_on_hub_event_opened")):
			GanttHub.connect("event_opened", Callable(self , "_on_hub_event_opened"))
		if not GanttHub.is_connected("event_finished", Callable(self , "_on_hub_event_finished")):
			GanttHub.connect("event_finished", Callable(self , "_on_hub_event_finished"))
		if GanttHub.has_signal("events_reset") and not GanttHub.is_connected("events_reset", Callable(self , "_on_hub_events_reset")):
			GanttHub.connect("events_reset", Callable(self , "_on_hub_events_reset"))


func _now() -> float:
	# Use a sim clock if you have one; otherwise wall-clock seconds
	if typeof(SimulationClock) != TYPE_NIL and SimulationClock.has_method("now"):
		return float(SimulationClock.now())
	return float(Time.get_ticks_msec()) / 1000.0

		
func _process(delta: float) -> void:
	_accum += delta
	var needs_redraw := false

	# 1) Sliding window that follows 'now'
	if auto_follow_now:
		var half: float = max(0.001, follow_window_seconds * 0.5)
		var now := _now()
		var new_min: float = now - half
		var new_max: float = now + half
		# only update a few times per second to avoid layout thrash
		if _accum >= (1.0 / max(1.0, recalc_hz)):
			_accum = 0.0
			if new_min != domain_min or new_max != domain_max:
				domain_min = new_min
				domain_max = new_max
				_update_content_metrics()
				needs_redraw = true

	# 2) Otherwise, optional auto-fit so [0 .. now] fills the view
	elif auto_fit_domain_live and _accum >= (1.0 / max(1.0, recalc_hz)):
		_accum = 0.0
		_fit_domain_to_now(fit_padding_seconds)
		needs_redraw = true


	# 3) Legacy growth (keeps right edge moving when growing open events)
	if auto_grow_domain and not auto_follow_now:
		# Only repaint/follow time if we actually have open events.
		if not _open_by_key.is_empty():
			var now := _now()
			if now > domain_max:
				domain_max = now
				_update_content_metrics()
				needs_redraw = true

	if needs_redraw:
		queue_redraw()

	
func _on_hub_events_reset() -> void:
	# Restore the initial viewport and wipe all local state
	clear() # will now also clear open events


func _exit_tree() -> void:
	if typeof(GanttHub) != TYPE_NIL and GanttHub.chart == self:
		GanttHub.clear_chart()

# ── Public API (call these from your game code) ───────────────────────────────

func open_event_by_key(label: String, start_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0), type: String = "TEST") -> void:
	var row := _get_row_index_for(row_key)
	var s: float = start_time
	_events.append({
		"label": label,
		"start": s,
		"end": INF, # sentinel: draw up to now
		"row": row,
		"color": color,
		"open": true,
		"type": type
	})
	_open_by_key[row_key] = _events.size() - 1
	_max_row = max(_max_row, row)
	if auto_grow_domain and s > domain_max:
		domain_max = s
	_update_content_metrics()
	queue_redraw()

func finish_event_by_key(row_key: String, end_time: float) -> void:
	if not _open_by_key.has(row_key):
		return
	var idx: int = _open_by_key[row_key]
	if idx < 0 or idx >= _events.size():
		_open_by_key.erase(row_key)
		return
	var ev: Dictionary = _events[idx]
	ev["end"] = max(end_time, float(ev.get("start", end_time)))
	ev["open"] = false
	_events[idx] = ev
	_open_by_key.erase(row_key)
	if auto_grow_domain and ev["end"] > domain_max:
		domain_max = ev["end"]
	_update_content_metrics()
	queue_redraw()


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
		domain_max = max(domain_max, e)


	_update_content_metrics()
	queue_redraw()
	
func zoom_in(factor: float = 1.2) -> void:
	var new_zoom = pixels_per_unit * factor
	pixels_per_unit = clamp(new_zoom, zoom_min, zoom_max)
	_update_content_metrics()
	queue_redraw()

func zoom_out(factor: float = 1.2) -> void:
	var new_zoom = pixels_per_unit / factor
	pixels_per_unit = clamp(new_zoom, zoom_min, zoom_max)
	_update_content_metrics()
	queue_redraw()

func clear():
	_events.clear()
	_open_by_key.clear()
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
	#domain_min = lo - pad_units
	domain_min = 0 - pad_units
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
	var font := get_theme_default_font()
	var font_size: int = int(get_theme_default_font_size())

	# Draw row labels in the left gutter (even when there are no events)
	if show_row_labels and _row_index_to_key.size() > 0:
		_draw_row_labels(plot)
		
	if show_time_axis:
		_draw_time_axis()

	# If there are no events, we're done (labels may still be visible)
	#if (_events.is_empty()) or (span <= 0.):
	#	return

	for ev: Dictionary in _events:
		var s: float = ev["start"]
		#var e: float = ev["end"]
		var e_raw: float = float(ev["end"])
		var is_open: bool = grow_open_events and ev.get("open", false) and is_finite(e_raw) == false
		var e: float = _now() if is_open else e_raw
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
		draw_line(Vector2(sep_x, 0.0), Vector2(sep_x, size.y), row_label_color * Color(1, 1, 1, 0.35), 1.0)


# Tooltips for hovered bars
#func _get_tooltip(at_position: Vector2) -> String:
#	var ev := _find_event_at(at_position)
#	if ev.is_empty():
#		return ""
#	return _format_event_tooltip(ev)

func _gui_input(event: InputEvent) -> void:
	# Mouse click (desktop)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(event.position)
		accept_event()
		return

	# Touch (mobile / tablet)
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
		accept_event()
		return


func _hide_tap_tooltip() -> void:
	if _tap_tooltip != null and is_instance_valid(_tap_tooltip):
		_tap_tooltip.queue_free()
		_tap_tooltip = null


func _show_tap_tooltip(text: String, local_pos: Vector2) -> void:
	# Make sure any existing tooltip is removed first
	_hide_tap_tooltip()

	if tooltip_scene == null:
		push_warning("BasicGantt has no tooltip_scene assigned.")
		return

	# Instantiate the shared tooltip scene
	_tap_tooltip = tooltip_scene.instantiate() as Control
	add_child(_tap_tooltip)

	# Populate text using the tooltip API
	if _tap_tooltip.has_method("show_tooltip"):
		_tap_tooltip.call("show_tooltip", text)
	elif _tap_tooltip.has_method("set_text"):
		_tap_tooltip.call("set_text", text)

	# If your tooltip script doesn't auto-show, ensure it's visible
	_tap_tooltip.visible = true

	# Let it compute its minimum size, so we can clamp correctly
	_tap_tooltip.reset_size()
	var tooltip_size: Vector2 = _tap_tooltip.get_combined_minimum_size()

	# Offset a little so we don’t cover the exact tap point
	var x: float = local_pos.x + 8.0
	var y: float = local_pos.y + 8.0

	# Clamp so it stays inside the chart control
	x = clamp(x, 0.0, max(0.0, size.x - tooltip_size.x))
	y = clamp(y, 0.0, max(0.0, size.y - tooltip_size.y))

	_tap_tooltip.position = Vector2(x, y)

	# Optional: avoid the tooltip eating later clicks
	_tap_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _handle_tap(local_pos: Vector2) -> void:
	var ev := _find_event_at(local_pos)

	# No bar under this tap → hide tooltip if visible
	if ev.is_empty():
		_hide_tap_tooltip()
		return

	var text := _format_event_tooltip(ev)
	_show_tap_tooltip(text, local_pos)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _gutter_width() -> float:
	return row_label_gutter_width if show_row_labels else 0.0

func _plot_rect() -> Rect2:
	# The content (and thus scrollable width/height) is determined by domain span and rows.
	var x0: float = left_margin + _gutter_width() # reserve gutter without mutating left_margin
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
	var content_w: float = left_margin + _gutter_width() + right_margin \
		+ max(1.0, (domain_max - domain_min) * pixels_per_unit)

	var content_h: float = top_margin \
		+ max(1.0, _content_rows_height()) \
		+ time_axis_height \
		+ bottom_margin

	custom_minimum_size = Vector2(content_w, content_h)


func _on_zoom_in_pressed() -> void:
	zoom_in(2)


func _on_zoom_out_pressed() -> void:
	zoom_out(2)
	
	## ───────────────────────── CSV Export ─────────────────────────

# Public helper in case other code wants the raw list
func get_events() -> Array[Dictionary]:
	# Return a shallow copy so callers can't mutate our internal array directly
	return _events.duplicate()

# Button: open save dialog, or fall back to a default user:// path
func _on_export_csv_pressed() -> void:
	var default_name := "gantt_export_%s.csv" % Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var dlg := get_node_or_null("SaveDialog")
	if dlg:
		dlg.current_file = default_name
		dlg.popup_centered()
	else:
		# Fallback: auto-save to user://
		var path := "user://%s" % default_name
		var ok := export_csv(path)
		if ok:
			if debug_log:
				print("Gantt CSV exported to ", path)
		else:
			push_warning("Failed to export CSV to %s" % path)

# Called by FileDialog when the user picks a file
func _on_save_dialog_file_selected(path: String) -> void:
	var ok := export_csv(path)
	if ok:
		if debug_log:
			print("Gantt CSV exported to ", path)
	else:
		push_warning("Failed to export CSV to %s" % path)


# Core export function. Returns true on success.
func export_csv(path: String) -> bool:
	# Header
	var header := [
		"row_key",
		"row_index",
		"label",
		"start",
		"end",
		"duration",
		"color_rgba"
	]

	var lines: Array[String] = []
	lines.append(_csv_join(header))

	# Rows
	for e in _events:
		var row_index: int = int(e.get("row", -1))
		var row_key: String = ""
		if row_index >= 0 and row_index < _row_index_to_key.size():
			row_key = _row_index_to_key[row_index]

		var label: String = str(e.get("label", ""))
		var start := float(e.get("start", 0.0))
		var end := _effective_end(e) # <-- resolve INF/open to now
		#var end := float(e.get("end", start))
		var duration := end - start
		var color: Color = e.get("color", Color.WHITE)
		var color_hex := color.to_html(true) # RGBA, e.g. #RRGGBBAA

		var row := [
			row_key,
			str(row_index),
			label,
			_stringify_num(start),
			_stringify_num(end),
			_stringify_num(duration),
			color_hex
		]
		lines.append(_csv_join(row))

	# Write
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_string("\n".join(lines) + "\n")
	fa.close()
	return true

# ---- CSV helpers ----
# Basic CSV quoting: wrap fields in quotes, double any inner quotes.
func _csv_escape(s: String) -> String:
	return '"' + s.replace('"', '""') + '"'

func _csv_join(fields: Array) -> String:
	var out: Array[String] = []
	for f in fields:
		var txt := str(f)
		# Always quote to be safe (commas, newlines, etc.)
		out.append(_csv_escape(txt))
	return _join(out, ",")

# Keep numeric output tidy (avoid scientific notation, ensure decimals when needed)
func _stringify_num(x: float) -> String:
	# Use a fixed precision that suits your time units.
	# Adjust decimals if you prefer fewer/more (e.g., 3 decimals).
	return String.num(x, 4)

func _join(parts: Array[String], sep: String) -> String:
	var s := ""
	var first := true
	for p in parts:
		if first:
			first = false
		else:
			s += sep
		s += p
	return s

func _draw_time_axis() -> void:
	if pixels_per_unit <= 0.0:
		return

	var width: float = size.x
	var height: float = size.y

	# Render area offset (don’t draw in the row label gutter)
	var x0: float = row_label_gutter_width + left_margin
	var x1: float = width - right_margin
	var usable_w: float = x1 - x0
	if usable_w <= 0.0:
		return

	var time_span: float = domain_max - domain_min
	if time_span <= 0.0:
		return

	# ---- Font + approximate label width (for overlap avoidance) ----
	var font: Font = time_label_font
	if font == null:
		font = get_theme_default_font()

	var fs: int = time_label_font_size
	if fs <= 0:
		fs = get_theme_default_font_size()

	# Approximate width of a typical time label like "09:30"
	var sample_text: String = "09:30"
	var label_size: Vector2 = font.get_string_size(sample_text, fs)
	var label_px_width: float = label_size.x

	# How many pixels we want between labels to avoid overlap
	var min_label_gap_px: float = label_px_width * 1.6

	# Convert that into an "ideal" time step in seconds (before snapping to a nice value)
	var ideal_step_sec: float = min_label_gap_px / pixels_per_unit
	if ideal_step_sec <= 0.0:
		ideal_step_sec = 60.0

	# ---- Choose a "nice" step size (in seconds) close to ideal ----
	var nice_steps: Array[float] = [
		60.0, # 1 min
		120.0, # 2 min
		300.0, # 5 min
		600.0, # 10 min
		900.0, # 15 min
		1800.0, # 30 min
		3600.0, # 1 hour
		7200.0 # 2 hours
	]

	var step_sec: float = nice_steps[nice_steps.size() - 1]
	for s in nice_steps:
		if s >= ideal_step_sec:
			step_sec = s
			break

	# Optional horizontal axis line across the bottom of the chart area
	draw_line(
		Vector2(x0, height - bottom_margin),
		Vector2(x1, height - bottom_margin),
		Color(1, 1, 1, 0.4),
		1.5
	)

	# First & last tick indices within the current time domain
	var tick_start: int = int(floor(domain_min / step_sec))
	var tick_end: int = int(ceil(domain_max / step_sec))

	for i in range(tick_start, tick_end + 1):
		var t: float = float(i) * step_sec

		# Convert time → x coordinate
		var x: float = x0 + (t - domain_min) * pixels_per_unit
		if x < x0 or x > x1:
			continue

		# Convert simulation seconds to a time of day, starting at 9:00 AM
		var base_seconds: int = 9 * 3600 # 9:00 AM
		var total_sec: int = base_seconds + int(t)
		var hours: int = int(total_sec / 3600) % 24
		var minutes: int = int((total_sec % 3600) / 60)

		# Major tick at the top of the hour (e.g. 10:00, 11:00, ...)
		var is_major: bool = (minutes == 0)

		var col: Color = major_tick_color if is_major else tick_color
		var w: float = major_tick_width if is_major else tick_width

		# Full-height vertical tick line
		draw_line(
			Vector2(x, top_margin),
			Vector2(x, height - bottom_margin),
			col,
			w
		)

		if show_time_labels:
			var label: String = "%02d:%02d" % [hours, minutes]

			var ext: Vector2 = font.get_string_size(label, fs)
			var lx: float = x - (ext.x * 0.5)

			# Font metrics
			var fh: float = font.get_height(fs)
			var ascent: float = font.get_ascent(fs)

			# Bottom baseline: a few pixels above the bottom margin (as before)
			var baseline_bottom_y: float = height - bottom_margin - 4.0

			# Top baseline: center the label vertically inside [0 .. top_margin]
			# so it sits in the header band above the first row of bars.
			var baseline_top_y: float = (top_margin - fh) * 0.5 + ascent

			# Bottom label
			draw_string(
				font,
				Vector2(lx, baseline_bottom_y),
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				fs,
				time_label_color
			)

			# Top label (mirrored, in the top margin band)
			draw_string(
				font,
				Vector2(lx, baseline_top_y),
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				fs,
				time_label_color
			)


func _fit_domain_to_now(pad: float) -> void:
	var now: float = _now()
	if not is_finite(now):
		return

	# Always show from 0 to "now + pad"
	domain_min = 0.0
	domain_max = max(now + pad, 1.0)

	# Pick a zoom so [0 .. domain_max] fits the available width
	_fit_scale_to_viewport()


func _find_event_at(at_position: Vector2) -> Dictionary:
	var plot: Rect2 = _plot_rect()
	var scale: float = pixels_per_unit

	for ev: Dictionary in _events:
		var s: float = ev["start"]
		var e: float = _effective_end(ev)
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

		var r: Rect2 = Rect2(
			Vector2(float(x0_px), float(y_px)),
			Vector2(float(x1_px - x0_px), float(h_px))
		)

		if r.has_point(at_position):
			return ev

	return {} # empty dictionary = no hit


func _format_sim_time_ampm(sim_sec: float) -> String:
	var total: int = _DISPLAY_DAY_START_SEC + int(sim_sec)
	var hours: int = int(total / 3600) % 24
	var minutes: int = int((total % 3600) / 60)
	var seconds: int = total % 60
	var is_am: bool = hours < 12
	var h12: int = hours % 12
	if h12 == 0:
		h12 = 12
	var meridiem: String = "AM" if is_am else "PM"
	return "%d:%02d:%02d %s" % [h12, minutes, seconds, meridiem]


func _format_duration(dur_sec: float) -> String:
	var s: int = int(dur_sec)
	var h: int = s / 3600
	var m: int = (s % 3600) / 60
	var sec: int = s % 60
	if h > 0:
		return "%dh %02dm %02ds" % [h, m, sec]
	if m > 0:
		return "%dm %02ds" % [m, sec]
	return "%ds" % sec


func _format_event_tooltip(ev: Dictionary) -> String:
	var s: float = float(ev.get("start", 0.0))
	var e: float = _effective_end(ev)
	var dur: float = max(0.0, e - s)
	var label: String = str(ev.get("label", ""))
	return "%s\nStart: %s   End: %s\nDuration: %s" % [
		label,
		_format_sim_time_ampm(s),
		_format_sim_time_ampm(e),
		_format_duration(dur)
	]
