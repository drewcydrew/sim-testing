extends Control
class_name Tooltip

@onready var label: RichTextLabel = $PanelContainer/MarginContainer/RichTextLabel

func set_text(text: String) -> void:
	label.text = text

func show_tooltip(text: String) -> void:
	set_text(text)
	visible = true

func hide_and_free() -> void:
	queue_free()
