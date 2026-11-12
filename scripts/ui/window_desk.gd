class_name WindowDesk
extends Control
## Mesa das janelas do governo: abre, fecha e põe na frente as janelas flutuantes que são seus filhos.
## Cada janela tem um índice fixo (a ordem dos filhos na cena), o mesmo das antigas abas; `current_tab`
## é a janela da frente, ou -1 se nenhuma está aberta.

signal tab_changed(index: int)

## As janelas abrem no centro da tela; cada janela a mais desce um degrau em cascata.
const CASCADE := Vector2(28, 26)

var current_tab: int:
	get:
		return _front
	set(i):
		open(i)

var _windows: Array[FloatWindow] = []
var _front := -1


func _ready() -> void:
	for child in get_children():
		if child is FloatWindow:
			var w: FloatWindow = child
			var i := _windows.size()
			_windows.append(w)
			w.focused.connect(_on_focused.bind(i))
			w.closed.connect(_on_closed.bind(i))
	resized.connect(func():
		for w in _windows:
			w.fit())


func get_tab_count() -> int:
	return _windows.size()


## O conteúdo da janela (para achar em qual janela um painel mora).
func get_tab_control(i: int) -> Control:
	return _windows[i].content()


func window(i: int) -> FloatWindow:
	return _windows[i]


func is_open(i: int) -> bool:
	return i >= 0 and i < _windows.size() and _windows[i].is_open


func open_count() -> int:
	var n := 0
	for w in _windows:
		n += int(w.is_open)
	return n


func open(i: int, from := Vector2.ZERO) -> void:
	if i < 0 or i >= _windows.size():
		return
	var w := _windows[i]
	if w.locked:
		return
	if from != Vector2.ZERO:
		w.origin = from
	if w.is_open:
		w.raise()
		return
	var step := float(open_count() % 6) - 1.5
	w.open_at(((size - w.size) * 0.5 + CASCADE * step).floor())


func close(i: int) -> void:
	if is_open(i):
		_windows[i].close()


## Clique no dock: abre se está fechada, traz para a frente se está atrás, minimiza se já está na frente.
func toggle(i: int, from := Vector2.ZERO) -> void:
	if is_open(i) and _front == i:
		if from != Vector2.ZERO:
			_windows[i].origin = from
		close(i)
	else:
		open(i, from)


func close_all() -> void:
	for i in _windows.size():
		close(i)


## Índices das janelas abertas, da de trás para a da frente.
func open_windows() -> Array[int]:
	var out: Array[int] = []
	for child in get_children():
		if child is FloatWindow and child.is_open:
			out.append(_windows.find(child))
	return out


func _on_focused(i: int) -> void:
	if _front != i:
		_front = i
		tab_changed.emit(i)


func _on_closed(i: int) -> void:
	if _front != i:
		return
	var rest := open_windows()
	_front = rest[-1] if not rest.is_empty() else -1
	tab_changed.emit(_front)


## Clicar em qualquer ponto de uma janela a traz para a frente, como num sistema de janelas.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var at: Vector2 = event.position
	for k in range(get_child_count() - 1, -1, -1):
		var child := get_child(k)
		if child is FloatWindow and child.is_open and child.get_global_rect().has_point(at):
			if k != get_child_count() - 1:
				child.raise()
			return
