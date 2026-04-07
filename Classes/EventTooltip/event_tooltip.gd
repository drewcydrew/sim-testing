extends Control
class_name GanttEntityTooltip

## Row key to follow – e.g. traveller_name
@export var row_key: String = ""

## Optional type filter, same semantics as BasicGantt.display_type
## "" or "all" = show all types; otherwise match (case-insensitive) on ev.type
@export var display_type: String = ""

## Path to the RichTextLabel that will display the text
@export var label_path: NodePath = "PanelContainer/MarginContainer/VBoxContainer/RichTextLabel"

var _label: RichTextLabel = null
@onready var _heatmap_btn: Button = $PanelContainer/MarginContainer/VBoxContainer/HeatmapToggleButton

# Closed events for this entity: { label, start_time, end_time, color, row_key, type }
var _closed_events: Array[Dictionary] = []

# Currently open event: { label, start_time, end_time(=-1 for open), color, row_key, type }
var _open_event: Dictionary = {}

var _rebuild_dirty: bool = true


func _ready() -> void:
	_label = get_node_or_null(label_path)

	_closed_events.clear()
	_open_event.clear()

	# Initial load from GanttHub
	_load_initial_events_for_row()

	# Subscribe to live updates from GanttHub (autoload singleton)
	if typeof(GanttHub) != TYPE_NIL:
		if not GanttHub.is_connected("event_recorded", Callable(self , "_on_hub_event_recorded")):
			GanttHub.connect("event_recorded", Callable(self , "_on_hub_event_recorded"))
		if not GanttHub.is_connected("event_opened", Callable(self , "_on_hub_event_opened")):
			GanttHub.connect("event_opened", Callable(self , "_on_hub_event_opened"))
		if not GanttHub.is_connected("event_finished", Callable(self , "_on_hub_event_finished")):
			GanttHub.connect("event_finished", Callable(self , "_on_hub_event_finished"))
		if GanttHub.has_signal("events_reset") and not GanttHub.is_connected("events_reset", Callable(self , "_on_hub_events_reset")):
			GanttHub.connect("events_reset", Callable(self , "_on_hub_events_reset"))

	_rebuild_dirty = true
	set_process(true)
	_refresh_text()


## Allow the traveller to set / change the row key after instantiation
func set_row_key(key: String) -> void:
	row_key = key
	_load_initial_events_for_row()
	_rebuild_dirty = true
	_refresh_text()


# ───────────────────── Hub bootstrap ─────────────────────────────

func _load_initial_events_for_row() -> void:
	_closed_events.clear()
	_open_event.clear()

	if typeof(GanttHub) == TYPE_NIL:
		return
	if row_key == "":
		return

	# 1) Closed events via get_events_for
	if GanttHub.has_method("get_events_for"):
		var arr: Array = GanttHub.get_events_for(row_key)
		for e in arr:
			var ev: Dictionary = e
			var ev_type: String = String(ev.get("type", ""))
			if _type_matches(ev_type):
				_closed_events.append(ev)

	# 2) Open events via get_open_events (map: row_key -> dict)
	if GanttHub.has_method("get_open_events"):
		var open_map: Dictionary = GanttHub.get_open_events()
		if open_map.has(row_key):
			var o_any = open_map[row_key]
			var o: Dictionary = o_any
			var ev_type2: String = String(o.get("type", ""))
			if _type_matches(ev_type2):
				_open_event = {
					"label": o.get("label", ""),
					"start_time": float(o.get("start_time", 0.0)),
					"end_time": - 1.0, # sentinel for open
					"color": o.get("color", Color.WHITE),
					"type": o.get("type", ""),
					"row_key": row_key
				}
			else:
				_open_event.clear()


# ───────────────────── Hub signal handlers ───────────────────────

func _on_hub_event_recorded(ev: Dictionary) -> void:
	# Closed event was recorded globally (finish_named or record_named)
	var ev_type: String = String(ev.get("type", ""))
	if not _type_matches(ev_type):
		return

	var rk: String = String(ev.get("row_key", ""))
	if rk != row_key:
		return

	# If this matches the current open event, clear the open one.
	if not _open_event.is_empty():
		var open_label: String = String(_open_event.get("label", ""))
		var open_start: float = float(_open_event.get("start_time", 0.0))
		var ev_label: String = String(ev.get("label", ""))
		var ev_start: float = float(ev.get("start_time", 0.0))
		if open_label == ev_label and abs(open_start - ev_start) < 0.0001:
			_open_event.clear()

	_closed_events.append(ev)
	_rebuild_dirty = true


func _on_hub_event_opened(ev_row_key: String, payload: Dictionary) -> void:
	if ev_row_key != row_key:
		return

	var ev_type: String = String(payload.get("type", ""))
	if not _type_matches(ev_type):
		return

	_open_event = {
		"label": payload.get("label", ""),
		"start_time": float(payload.get("start_time", 0.0)),
		"end_time": - 1.0,
		"color": payload.get("color", Color.WHITE),
		"type": payload.get("type", ""),
		"row_key": ev_row_key
	}
	_rebuild_dirty = true


func _on_hub_event_finished(ev_row_key: String, end_time: float) -> void:
	# We don't *need* this to build the history, because event_recorded
	# already carries the finished event, but we can update the open
	# entry's end_time if we still have it.
	if ev_row_key != row_key:
		return

	if not _open_event.is_empty():
		_open_event["end_time"] = float(end_time)

	_rebuild_dirty = true


func _on_hub_events_reset() -> void:
	_closed_events.clear()
	_open_event.clear()
	_rebuild_dirty = true
	_refresh_text()


# ───────────────────── Process: live updating ────────────────────

func _process(delta: float) -> void:
	# If there's an open event, we want durations / end marker to tick
	if not _open_event.is_empty():
		_rebuild_dirty = true

	if _rebuild_dirty:
		_refresh_text()
		_rebuild_dirty = false


# ───────────────────── Rendering text ────────────────────────────

func _refresh_text() -> void:
	if _label == null:
		return

	# Always refresh from GanttHub so we see the latest open/closed state
	_load_initial_events_for_row()

	var name: String = row_key if row_key != "" else "Entity"

	if _closed_events.is_empty() and _open_event.is_empty():
		_label.text = "%s\nNo events yet" % name
		return

	var lines: Array[String] = []
	lines.append("%s" % name)

	# ── Current event: ONLY show if there is an open event ─────────
	lines.append("Current event")
	if _open_event.is_empty():
		lines.append("None")
	else:
		lines.append(_format_event_line(_open_event, true))

	# ── Previous events: all closed events, newest first ───────────
	var has_previous: bool = false
	for i in range(_closed_events.size() - 1, -1, -1):
		var ev: Dictionary = _closed_events[i]

		if _is_zero_duration_event(ev):
			continue

		if not has_previous:
			lines.append("")
			lines.append("Previous events")
			has_previous = true

		lines.append(_format_event_line(ev, false))

	_label.text = "\n".join(lines)


func _format_event_line(ev: Dictionary, is_current: bool) -> String:
	var label: String = String(ev.get("label", ""))
	var s: float = float(ev.get("start_time", 0.0))
	var e: float = float(ev.get("end_time", -1.0))

	var prefix: String = "• "
	if is_current:
		prefix = "→ "

	var time_str: String = _format_time_range(s, e)
	return "%s%s %s" % [prefix, label, time_str]


func _format_time_range(s: float, e: float) -> String:
	if e < 0.0:
		var now: float = _now()
		var dur: float = max(0.0, now - s)
		return "(%.3f → %.3f, %.3fs, ongoing)" % [s, now, dur]
	else:
		var dur2: float = max(0.0, e - s)
		return "(%.3f → %.3f, %.3fs)" % [s, e, dur2]


func _is_zero_duration_event(ev: Dictionary) -> bool:
	var s: float = float(ev.get("start_time", 0.0))
	var e: float = float(ev.get("end_time", -1.0))
	if e < 0.0:
		return false
	return abs(e - s) < 0.0001


# ───────────────────── Matching & time helpers ───────────────────

func _norm(s: String) -> String:
	return String(s).strip_edges().to_lower()


func _type_matches(t: String) -> bool:
	var want: String = _norm(display_type)
	if want == "" or want == "all":
		return true
	return _norm(t) == want


func _now() -> float:
	if typeof(SimulationClock) != TYPE_NIL and SimulationClock.has_method("now"):
		return float(SimulationClock.now())
	return float(Time.get_ticks_msec()) / 1000.0


func _on_heatmap_toggle_pressed() -> void:
	var traveller: Node = get_parent()
	if traveller == null or not traveller.has_method("toggle_trail"):
		return
	traveller.toggle_trail()
	if is_instance_valid(_heatmap_btn):
		_heatmap_btn.text = "Hide path heatmap" if traveller._trail_visible else "Show path heatmap"
