class_name FloatWindow
extends PanelContainer
## Janela flutuante, como a de um aplicativo: arrasta pela barra de título, redimensiona pelo canto,
## fecha pelo botão vermelho e minimiza pelo amarelo. O conteúdo vai como filho direto da instância
## na cena que a usa; ao ficar pronta, a janela o põe dentro do corpo.

signal closed
signal focused

const MIN_SIZE := Vector2(320, 220)
const ANIM_TIME := 0.16

@export var title := "Janela":
	set(v):
		title = v
		if is_node_ready():
			_title_label.text = v
@export var icon: Texture2D:
	set(v):
		icon = v
		if is_node_ready():
			_icon_rect.texture = v
@export var default_size := Vector2(460, 600)

var is_open := false
## De onde a janela sai e para onde volta ao minimizar (o ícone do dock), em coordenadas globais.
var origin := Vector2.ZERO
var _dragging := false
var _resizing := false
var _grab := Vector2.ZERO
var _tween: Tween

@onready var _title_bar: Control = %title_bar
@onready var _title_label: Label = %title_label
@onready var _icon_rect: TextureRect = %title_icon
@onready var _body: MarginContainer = %body
@onready var _grip: Control = %grip


func _ready() -> void:
	var own := [%Moldura]
	for child in get_children():
		if child not in own:
			child.reparent(_body, false)
	_title_label.text = title
	_icon_rect.texture = icon
	size = default_size
	visible = false
	%close.pressed.connect(close)
	%minimize.pressed.connect(close)
	%maximize.pressed.connect(_toggle_tall)
	_title_bar.gui_input.connect(_on_title_input)
	_grip.gui_input.connect(_on_grip_input)


## O conteúdo que a janela mostra (o primeiro filho do corpo).
func content() -> Control:
	return _body.get_child(0) if _body.get_child_count() > 0 else null


func open_at(pos: Vector2) -> void:
	if is_open:
		raise()
		return
	is_open = true
	visible = true
	position = pos
	_clamp()
	_animate(true)
	raise()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_dragging = false
	_resizing = false
	_animate(false)
	closed.emit()


func raise() -> void:
	move_to_front()
	focused.emit()


## Encaixa a janela dentro da área do pai depois de mudar o tamanho da tela.
func fit() -> void:
	if is_open:
		_clamp()


func _animate(opening: bool) -> void:
	if _tween:
		_tween.kill()
	pivot_offset = size * 0.5
	if origin != Vector2.ZERO:
		pivot_offset = (origin - global_position).clamp(Vector2.ZERO, size)
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if opening:
		scale = Vector2(0.6, 0.6)
		modulate.a = 0.0
		_tween.tween_property(self, "scale", Vector2.ONE, ANIM_TIME)
		_tween.tween_property(self, "modulate:a", 1.0, ANIM_TIME * 0.8)
	else:
		_tween.tween_property(self, "scale", Vector2(0.6, 0.6), ANIM_TIME).set_ease(Tween.EASE_IN)
		_tween.tween_property(self, "modulate:a", 0.0, ANIM_TIME).set_ease(Tween.EASE_IN)
		_tween.chain().tween_callback(func():
			if not is_open:
				visible = false
				scale = Vector2.ONE)


## O botão verde estica a janela até a altura toda da área, ou volta ao tamanho padrão.
func _toggle_tall() -> void:
	var area := _area()
	if size.y >= area.size.y - 2.0:
		size = default_size
	else:
		position.y = area.position.y
		size = Vector2(size.x, area.size.y)
	_clamp()


func _area() -> Rect2:
	var p := get_parent() as Control
	return Rect2(Vector2.ZERO, p.size) if p else Rect2(Vector2.ZERO, get_viewport_rect().size)


func _clamp() -> void:
	var area := _area()
	size = size.clamp(MIN_SIZE, area.size.max(MIN_SIZE))
	position = position.clamp(area.position, area.end - size)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_grab = get_global_mouse_position() - global_position
		if event.pressed:
			raise()
			if event.double_click:
				_toggle_tall()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _grab
		_clamp()


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		_grab = size - get_global_mouse_position()
		if event.pressed:
			raise()
	elif event is InputEventMouseMotion and _resizing:
		size = get_global_mouse_position() + _grab
		_clamp()
