class_name ChatBubble
extends HBoxContainer
## Message bubble: the player's on the right, the other side's on the left.

const MAX_TEXT_WIDTH := 400.0

@export var style_me: StyleBox
@export var style_them: StyleBox

@onready var _bubble: PanelContainer = %bubble
@onready var _text: Label = %text
@onready var _time: Label = %time
@onready var _left: Control = %left
@onready var _right: Control = %right


func setup(message: Dictionary) -> void:
	var me: bool = message.get("me", false)
	_text.text = String(message.text)
	_time.text = String(message.get("date", ""))
	_bubble.add_theme_stylebox_override("panel", style_me if me else style_them)
	# The text fits the bubble: width of what was written, up to the limit.
	var font := _text.get_theme_font("font")
	var wide := font.get_multiline_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _text.get_theme_font_size("font_size")).x
	_text.custom_minimum_size.x = clampf(wide + 4.0, 90.0, MAX_TEXT_WIDTH)
	var ok: Variant = message.get("ok", null)
	if not me and ok != null:
		_text.add_theme_color_override("font_color", UiKit.GREEN if ok else UiKit.RED)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL if me else Control.SIZE_FILL
	_right.size_flags_horizontal = Control.SIZE_FILL if me else Control.SIZE_EXPAND_FILL
