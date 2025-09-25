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
@export var text_left_padding: float = 6.0
@export var text_right_padding: float = 6.0
@export var text_color: Color = Color.WHITE

@onready var _rect: ColorRect = $Panel
@onready var _label: Label = $Panel/Label
@onready var _popup: PopupPanel = $HoverPopup
@onready var _pop_title: Label = $HoverPopup/Margin/VBox/Title
@onready var _pop_body: Label  = $HoverPopup/Margin/VBox/Body

var _base_color: Color

func _ready() -> void:
	# Root should fully control geometry; children should not capture mouse.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Fill the node with the color rect & label.
	if is_instance_valid(_rect):
		#_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_instance_valid(_label):
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.offset_left = text_left_padding
		_label.offset_right = -text_right_padding
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.clip_text = true
		_label.add_theme_color_override("font_color", text_color)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Initial data → UI
	_base_color = bar_color
	_apply_color(_base_color)
	_label.text = label_text
	_refresh_tooltips()

	# Connect hover on the root (children won’t block due to IGNORE)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# --- Public API ---------------------------------------------------------------

func set_data(label: String, start_t: float, end_t: float, row: int, color: Color) -> void:
	label_text = label
	start_time = start_t
	end_time = end_t
	row_index = row
	_base_color = color
	bar_color = color

	if is_instance_valid(_label):
		_label.text = label_text
	_apply_color(_base_color)
	_refresh_tooltips()

func set_label_text(t: String) -> void:
	label_text = t
	if is_instance_valid(_label):
		_label.text = label_text
	_refresh_tooltips()

func set_bar_color(c: Color) -> void:
	_base_color = c
	bar_color = c
	_apply_color(_base_color)

# The Gantt calls this to position/size the bar rectangle reliably.
func apply_rect(pos: Vector2, sz: Vector2) -> void:
	position = pos
	size = sz
	
	print ("Setting rectangle size to", sz)
	# Children are anchored to FULL_RECT, so they resize automatically.

# --- Internals ----------------------------------------------------------------

func _apply_color(c: Color) -> void:
	if is_instance_valid(_rect):
		_rect.color = c

func _refresh_tooltips() -> void:
	# Built-in tooltip (for platform-native tooltip behaviors)
	tooltip_text = "%s\nStart: %.2f  End: %.2f\nDuration: %.2fs" % [
		label_text, start_time, end_time, max(0.0, end_time - start_time)
	]
	# Custom popup content
	if is_instance_valid(_pop_title):
		_pop_title.text = label_text
	if is_instance_valid(_pop_body):
		_pop_body.text = "Start: %.2f\nEnd: %.2f\nDuration: %.2fs" % [
			start_time, end_time, max(0.0, end_time - start_time)
		]

func _show_popup() -> void:
	if not is_instance_valid(_popup):
		return
	_refresh_tooltips()

	# Position the popup above the bar, clamped to the window.
	var win := get_window()
	if win == null:
		return
	var screen_size: Vector2 = win.size
	var global_origin: Vector2 = get_global_transform_with_canvas().origin
	var desired: Vector2 = global_origin + Vector2(size.x * 0.5, 0.0) + popup_offset
	desired.x -= _popup.size.x * 0.5
	desired.y -= _popup.size.y + 8.0
	desired.x = clampf(desired.x, 0.0, screen_size.x - _popup.size.x)
	desired.y = maxf(0.0, desired.y)
	_popup.position = desired.round()
	_popup.popup()

func _hide_popup() -> void:
	if is_instance_valid(_popup) and _popup.visible:
		_popup.hide()

# --- Hover handling -----------------------------------------------------------

func _on_mouse_entered() -> void:
	emit_signal("hovered", self, true)
	_apply_color(_base_color.lightened(0.10))
	if popup_on_hover:
		_show_popup()

func _on_mouse_exited() -> void:
	emit_signal("hovered", self, false)
	_apply_color(_base_color)
	_hide_popup()
