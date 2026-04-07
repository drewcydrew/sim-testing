extends Control
class_name Tooltip

@onready var label: RichTextLabel = $PanelContainer/MarginContainer/RichTextLabel

func set_text(text: String) -> void:
	label.text = text

func show_tooltip(text: String) -> void:
	var nl := text.find("\n")
	if nl >= 0:
		label.text = "[b]%s[/b]%s" % [text.substr(0, nl), text.substr(nl)]
	else:
		label.text = "[b]%s[/b]" % text
	visible = true

func hide_and_free() -> void:
	queue_free()
