class_name LawSlot
extends HBoxContainer
## A parte de dentro de um bloco de controle, como "Se" ou "Repetir".

const BLOCK_PATH := "res://scenes/ui/legislation/law_block.tscn"

var view: LawBlockView
var slot_name := ""


func setup(owner_view: LawBlockView, name_: String) -> void:
	view = owner_view
	slot_name = name_
	var items: Control = get_node("%items")
	var hint: Label = get_node("%hint")
	var inner: Array = view.block.slots.get(slot_name, [])
	if slot_name == "else":
		hint.text = "caso contrário: solte blocos aqui"
	hint.visible = inner.is_empty()
	for child: Dictionary in inner:
		var block_view: LawBlockView = load(BLOCK_PATH).instantiate()
		block_view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		items.add_child(block_view)
		block_view.setup(view.editor, child, view.in_library)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if view.in_library or view.editor.read_only or not data is Dictionary or not data.has("law"):
		return false
	if data.kind != "statement" and data.kind != "cblock":
		return false
	return view.editor.can_move_to(data, int(view.block.id))


func _drop_data(_at: Vector2, data: Variant) -> void:
	view.editor.drop(data, {"kind": "slot", "id": int(view.block.id), "slot": slot_name})
