extends Node

var chart: Node = null

const MAX_FALLBACK_ROWS: int = 1024

func set_chart(c: Node) -> void:
	chart = c

func clear_chart() -> void:
	chart = null

func record(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	if chart and chart.has_method("record_event"):
		chart.record_event(label, start_time, end_time, row, color)

func record_named(label: String, start_time: float, end_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	if not chart:
		return
	if chart.has_method("record_event_by_key"):
		chart.record_event_by_key(label, start_time, end_time, row_key, color)
	else:
		# Deterministic numeric fallback if the chart doesn’t support keys yet
		# NOTE: use the global hash() and cast to int to keep types stable.
		var hashed: int = int(hash(row_key))
		var row: int = int(abs(hashed) % MAX_FALLBACK_ROWS)
		chart.record_event(label, start_time, end_time, row, color)
		
		
# ── Add to GanttHub.gd ──────────────────────────────────────────────────────
func get_events_for(row_key: String, up_to_time: float = INF) -> Array[Dictionary]:
	if chart and chart.has_method("get_events_by_row_key"):
		return chart.get_events_by_row_key(row_key, up_to_time)
	return []

func start_named(label: String, start_time: float, row_key: String, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	if chart and chart.has_method("open_event_by_key"):
		chart.open_event_by_key(label, start_time, row_key, color)
	else:
		# Fallback: immediate record (won’t grow)
		record_named(label, start_time, start_time, row_key, color)

func finish_named(row_key: String, end_time: float) -> void:
	if chart and chart.has_method("finish_event_by_key"):
		chart.finish_event_by_key(row_key, end_time)
