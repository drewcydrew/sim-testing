extends Control

signal spawn_rate_changed(per_hour: float)
signal auto_spawn_toggled(on: bool)



@export var environment_path: NodePath  # Drag your Environment node here in the editor
@export var slider_min_per_hr: float = 0.0
@export var slider_max_per_hr: float = 120.0
@export var slider_step: float = 1.0

@onready var _slider: HSlider = $HSlider
@onready var _value_label: Label = $ValueLabel
@onready var _toggle: CheckBox = ( $HBox/Toggle if has_node("HBox/Toggle") else null )

var _env: Node = null

func _ready() -> void:
	_slider.value_changed.connect(func(v):
		emit_signal("spawn_rate_changed", max(v, 0.0))
	)
	
	
	_slider.min_value = slider_min_per_hr
	_slider.max_value = slider_max_per_hr
	_slider.step = slider_step

	if environment_path != NodePath():
		_env = get_node(environment_path)

	# Initialise slider from environment if available
	var current := 0.0
	if _env and _env.has_method("get_spawn_rate_per_hour"):
		current = float(_env.get_spawn_rate_per_hour())
	
	
	_slider.value = clamp(current, _slider.min_value, _slider.max_value)
	_update_value_label(_slider.value)
	if _toggle:
		_toggle.button_pressed = current > 0.0
	else:
		_update_value_label(_slider.value)

	_slider.value_changed.connect(_on_slider_changed)
	if _toggle:
		_toggle.toggled.connect(_on_toggle_toggled)

func _on_slider_changed(v: float) -> void:
	_update_value_label(v)
	if not _env:
		return

	# If there's a toggle, follow its state; else 0 => off
	if _toggle:
		if _toggle.button_pressed:
			_env.call_deferred("set_spawn_rate_per_hour", v)
		else:
			_env.call_deferred("set_spawn_rate_per_hour", 0.0)
	else:
		_env.call_deferred("set_spawn_rate_per_hour", v if v > 0.0 else 0.0)

func _on_toggle_toggled(on: bool) -> void:
	if not _env:
		return
	if on:
		_env.call_deferred("set_spawn_rate_per_hour", _slider.value)
	else:
		_env.call_deferred("set_spawn_rate_per_hour", 0.0)

func _update_value_label(v: float) -> void:
	var text := "off" if v == 0.0 else "%d / hr" % int(round(v))
	_value_label.text = text
