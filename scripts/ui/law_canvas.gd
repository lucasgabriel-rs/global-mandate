class_name LawCanvas
extends Control
## Área de programação. Cada pilha é um artigo, posicionada onde o jogador a soltou.

const STACK := preload("res://scenes/ui/legislation/law_stack.tscn")
const BLOCK := preload("res://scenes/ui/legislation/law_block.tscn")
const MARGIN := 300.0

var editor: LawEditor


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var number := 0
	var far := Vector2(900, 500)
	for stack: Dictionary in editor.norm_program().stacks:
		number += 1
		var view: Control = STACK.instantiate()
		add_child(view)
		var at := Vector2(float(stack.pos[0]), float(stack.pos[1]))
		view.position = at
		far = far.max(at + Vector2(MARGIN, MARGIN))
		var repealed: bool = stack.get("repealed", false)
		(view.get_node("%article") as Label).text = "Art. %dº%s" % [number, " (revogado)" if repealed else ""]
		if repealed:
			view.modulate.a = 0.45
		var list: Control = view.get_node("%blocks")
		for block: Dictionary in stack.blocks:
			var block_view: LawBlockView = BLOCK.instantiate()
			list.add_child(block_view)
			block_view.setup(editor, block)
	custom_minimum_size = far


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		editor.select_block(-1)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return editor != null and not editor.read_only and data is Dictionary and data.has("law")


func _drop_data(at: Vector2, data: Variant) -> void:
	editor.drop(data, {"kind": "canvas", "pos": at})
