# res://SimClock.gd
extends Node
class_name SimClock

signal rate_changed(rate: float)
signal time_reset(t: float)

var _t: float = 0.0  # simulation time in seconds

func _process(delta: float) -> void:
	# delta here is already scaled by Engine.time_scale
	_t += delta

func now() -> float:
	return _t

func set_rate(rate: float) -> void:
	var r: float = max(rate, 0.0)
	Engine.time_scale = r
	emit_signal("rate_changed", r)

func reset(to_time: float = 0.0) -> void:
	_t = max(0.0, to_time)
	emit_signal("time_reset", _t)

# Optional: manual stepping when paused (Engine.time_scale==0)
func step(seconds: float) -> void:
	if seconds > 0.0:
		_t += seconds
