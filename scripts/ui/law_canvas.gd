class_name LawCanvas
extends Control
## Área de programação. Cada pilha é um artigo, posicionada onde o jogador a soltou.

const STACK := preload("res://scenes/ui/legislation/law_stack.tscn")
const BLOCK := preload("res://scenes/ui/legislation/law_block.tscn")
const MARGIN := 300.0
const MIN_SIZE := Vector2(900, 500)

var editor: LawEditor
## Arrastar o fundo move a área, como numa mesa.
var _panning := false


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var number := 0
	for stack: Dictionary in editor.norm_program().stacks:
		number += 1
		var view: Control = STACK.instantiate()
		add_child(view)
		var at := Vector2(float(stack.pos[0]), float(stack.pos[1]))
		view.position = at
		# O tamanho da pilha só existe depois do layout: a área se ajusta quando ela muda.
		view.resized.connect(_fit)
		var repealed: bool = stack.get("repealed", false)
		(view.get_node("%article") as Label).text = tr("Art. %dº%s") % [number, tr(" (revogado)") if repealed else ""]
		if repealed:
			view.modulate.a = 0.45
		var list: Control = view.get_node("%blocks")
		for block: Dictionary in stack.blocks:
			var block_view: LawBlockView = BLOCK.instantiate()
			# Cada peça tem a largura do próprio texto, como num quebra-cabeça.
			block_view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			list.add_child(block_view)
			block_view.setup(editor, block)
	_fit()


## A área cobre todas as pilhas inteiras, com folga para arrastar mais blocos para baixo e para o lado.
func _fit() -> void:
	var far := MIN_SIZE
	for child in get_children():
		if child is Control and not child.is_queued_for_deletion():
			far = far.max(child.position + child.size + Vector2(MARGIN, MARGIN))
	custom_minimum_size = far


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_panning = event.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _panning else Control.CURSOR_ARROW
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			editor.select_block(-1)
		accept_event()
	elif event is InputEventMouseMotion and _panning:
		var scroll := get_parent() as ScrollContainer
		if scroll:
			scroll.scroll_horizontal -= int(event.relative.x)
			scroll.scroll_vertical -= int(event.relative.y)
		accept_event()


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return editor != null and not editor.read_only and data is Dictionary and data.has("law")


func _drop_data(at: Vector2, data: Variant) -> void:
	editor.drop(data, {"kind": "canvas", "pos": at})
