extends Node

var chart: Node = null
const MAX_FALLBACK_ROWS: int = 1024

# ── NEW: global event store ─────────────────────────────────────
# Closed events: each dict has {label, start_time, end_time, color, row_key?, row?}
var _events: Array[Dictionary] = []
# Open events (by row_key): row_key -> {label, start_time, color}
var _open_by_key := {}

# ── NEW: signals so any number of charts can subscribe ─────────
signal event_recorded(event: Dictionary)            # fired for closed events
signal event_opened(row_key: String, payload: Dictionary)  # payload: {label, start_time, color}
signal event_finished(row_key: String, end_time: float)
signal events_reset()  

func set_chart(c: Node) -> void:
	chart = c

func clear_chart() -> void:
	chart = null

# ── NEW: read APIs for charts to bootstrap ─────────────────────
func get_all_events() -> Array[Dictionary]:
	# return a shallow copy to avoid external mutation
	return _events.duplicate()

func get_open_events() -> Dictionary:
	return _open_by_key.duplicate()

# ── Existing numeric record; now also stored globally ──────────
func record(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	var ev := {
		"label": label,
		"start_time": start_time,
		"end_time": end_time,
		"color": color,
		"row": row
	}
	_events.append(ev)
	emit_signal("event_recorded", ev)
	if chart and chart.has_method("record_event"):
		chart.record_event(label, start_time, end_time, row, color)

func record_named(label: String, start_time: float, end_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0),type: String = "TEST") -> void:
	# store closed event globally
	var ev := {
		"label": label,
		"start_time": start_time,
		"end_time": end_time,
		"color": color,
		"row_key": row_key,
		"type": type
	}
	_events.append(ev)
	emit_signal("event_recorded", ev)

	# forward to a bound chart if present
	if chart:
		if chart.has_method("record_event_by_key"):
			chart.record_event_by_key(label, start_time, end_time, row_key, color)
		elif chart.has_method("record_event"):
			var hashed: int = int(hash(row_key))
			var row: int = int(abs(hashed) % MAX_FALLBACK_ROWS)
			chart.record_event(label, start_time, end_time, row, color)

# Read API (unchanged signature)
func get_events_for(row_key: String, up_to_time: float = INF) -> Array[Dictionary]:
	# If the chart provides a richer implementation, use it;
	# otherwise read from the global list.
	if chart and chart.has_method("get_events_by_row_key"):
		return chart.get_events_by_row_key(row_key, up_to_time)

	var out: Array[Dictionary] = []
	for ev in _events:
		if ev.has("row_key") and ev.row_key == row_key:
			if up_to_time == INF or float(ev.end_time) <= up_to_time:
				out.append(ev)
	return out

func start_named(label: String, start_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0), type: String = "TEST") -> void:
	# store open state globally
	_open_by_key[row_key] = {
		"label": label,
		"start_time": start_time,
		"color": color,
		"type": type
	}
	emit_signal("event_opened", row_key, _open_by_key[row_key])

	# forward to chart if available
	if chart and chart.has_method("open_event_by_key"):
		chart.open_event_by_key(label, start_time, row_key, color, type)
	else:
		# optional: immediate record (no growth) for legacy-only charts
		record_named(label, start_time, start_time, row_key, color, type)
		
func reset_all() -> void:
	_events.clear()
	_open_by_key.clear()
	emit_signal("events_reset")


func finish_named(row_key: String, end_time: float) -> void:
	# close globally (if we had a matching open)
	if _open_by_key.has(row_key):
		var opened : Dictionary= _open_by_key[row_key]
		_open_by_key.erase(row_key)

		var ev := {
			"label": opened.label,
			"start_time": float(opened.start_time),
			"end_time": end_time,
			"color": opened.color,
			"type": opened.type,
			"row_key": row_key
		}
		_events.append(ev)
		emit_signal("event_recorded", ev)

	# always emit finished (even if we didn’t know about an open)
	emit_signal("event_finished", row_key, end_time)

	# forward to chart if available
	if chart and chart.has_method("finish_event_by_key"):
		chart.finish_event_by_key(row_key, end_time)
