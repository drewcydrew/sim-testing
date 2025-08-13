extends HBoxContainer

signal sim_speed_changed(value: float)



@export var initial_value: float = 1.0

func _ready() -> void:
	$HSlider.value = initial_value
	_update_label($HSlider.value)
	$HSlider.value_changed.connect(_on_value_changed)

func _on_value_changed(v: float) -> void:
	_update_label(v)
	emit_signal("sim_speed_changed", v)

func _update_label(v: float) -> void:
	if has_node("Label"):
		$Label.text = "Speed: %.2fx" % v
