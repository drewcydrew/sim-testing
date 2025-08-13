# res://Gantt/GanttHub.gd
extends Node

var chart: Node = null  # BasicGantt or anything with record_event()

func set_chart(c: Node) -> void:
	chart = c

func clear_chart() -> void:
	chart = null

func record(label: String, start_time: float, end_time: float, row: int = 0, color: Color = Color(0.5, 0.8, 1.0, 1.0)) -> void:
	if chart and chart.has_method("record_event"):
		chart.record_event(label, start_time, end_time, row, color)
