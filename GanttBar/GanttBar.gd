extends Control
class_name GanttBar

signal hovered(bar: GanttBar, inside: bool)

@export var label_text: String = "Task"
@export var start_time: float = 0.0
@export var end_time: float = 1.0
@export var row_index: int = 0
@export var bar_color: Color = Color(0.50, 0.80, 1.00, 1.0)

@export var popup_on_hover: bool = true
@export var popup_offset: Vector2 = Vector2(0, -8)

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label
@onready var _popup: PopupPanel = $HoverPopup
@onready var _pop_title: Label = $HoverPopup/Margin/VBox/Title
@onready var _pop_body: Label  = $HoverPopup/Margin/VBox/Body

var _base_color: Color

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

	_base_color = bar_color
	_label.text = label_text
	_apply_style(_base_color)
	_refresh_popup_content()

func set_data(label: String, start_t: float, end_t: float, row: int, color: Color) -> void:
	label_text = label
	start_time = start_t
	end_time = end_t
	row_index = row
	bar_color = color
	_base_color = color

	if is_inside_tree():
		_label.text = label_text
		_apply_style(_base_color)
		_refresh_popup_content()

func set_label_text(t: String) -> void:
	label_text = t
	if is_inside_tree():
		_label.text = label_text
		_refresh_popup_content()

func set_bar_color(c: Color) -> void:
	bar_color = c
	_base_color = c
	if is_inside_tree():
		_apply_style(_base_color)

func _apply_style(c: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = c
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)

# Placeholder content for now; we’ll wire richer info later.
func _refresh_popup_content() -> void:
	_pop_title.text = label_text
	_pop_body.text = "Start: %.2f\nEnd: %.2f\nDuration: %.2fs" % [
		start_time, end_time, max(0.0, end_time - start_time)
	]

func _show_popup() -> void:
	if _popup == null:
		return
	_refresh_popup_content()
	# Position the popup above the bar, clamped to the window
	var win := get_window()
	var screen_size: Vector2 = win.size
	var global_origin: Vector2 = get_global_transform_with_canvas().origin
	var desired: Vector2 = global_origin + Vector2(size.x * 0.5, 0) + popup_offset
	desired.x -= _popup.size.x * 0.5
	desired.y -= _popup.size.y + 8.0
	desired.x = clampf(desired.x, 0.0, screen_size.x - _popup.size.x)
	desired.y = maxf(0.0, desired.y)
	_popup.position = desired.round()
	_popup.popup()

func _hide_popup() -> void:
	if _popup and _popup.visible:
		_popup.hide()
		
		


func _on_panel_mouse_entered() -> void:
	emit_signal("hovered", self, true)
	# subtle hover highlight
	_apply_style(_base_color.lightened(0.10))
	if popup_on_hover:
		_show_popup()


func _on_panel_mouse_exited() -> void:
	emit_signal("hovered", self, false)
	_apply_style(_base_color)
	_hide_popup()
