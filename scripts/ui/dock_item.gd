class_name DockItem
extends Control
## A dock icon. Opens the desk's `window_index` window, or fires `action` when it is not a window.

signal pressed

@export var label := ""
@export var icon: Texture2D:
	set(v):
		icon = v
		if is_node_ready():
			_icon.texture = v
@export var window_index := -1
@export var action := ""

## Resting size; the dock increases this when the mouse passes nearby.
var base := 48.0
var magnify := 1.0:
	set(v):
		magnify = v
		custom_minimum_size = Vector2(base * v, base * v + 8.0)

@onready var _icon: TextureRect = %icon
@onready var _dot: Control = %dot


func _ready() -> void:
	_icon.texture = icon
	magnify = 1.0
	gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_bounce()
			pressed.emit())


func set_running(on: bool) -> void:
	_dot.visible = on


## The icon's little bounce when clicked.
func _bounce() -> void:
	var t := create_tween().set_trans(Tween.TRANS_QUAD)
	t.tween_property(_icon, "position:y", -14.0, 0.12).set_ease(Tween.EASE_OUT)
	t.tween_property(_icon, "position:y", 0.0, 0.18).set_ease(Tween.EASE_IN)
