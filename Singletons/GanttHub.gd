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
		print ("recording event for: ", row_key)
		chart.record_event_by_key(label, start_time, end_time, row_key, color)
	else:
		# Deterministic numeric fallback if the chart doesn’t support keys yet
		# NOTE: use the global hash() and cast to int to keep types stable.
		var hashed: int = int(hash(row_key))
		var row: int = int(abs(hashed) % MAX_FALLBACK_ROWS)
		chart.record_event(label, start_time, end_time, row, color)
