class_name LawBlockView
extends PanelContainer
## Um bloco na tela. Só desenha e entrega os gestos ao editor: quem muda o programa é o LawEditor.

const BLOCK_PATH := "res://scenes/ui/legislation/law_block.tscn"
const TEXT := preload("res://scenes/ui/legislation/law_text.tscn")
const SOCKET := preload("res://scenes/ui/legislation/law_socket.tscn")
const SLOT := preload("res://scenes/ui/legislation/law_slot.tscn")
const SELECTED_BORDER := Color.WHITE
const ERROR_BORDER := Color("ec5a43")

var editor: LawEditor
var block := {}
## Na biblioteca o bloco é só um molde: arrastar cria uma cópia nova.
var in_library := false
var _head: HBoxContainer


func setup(owner_editor: LawEditor, data: Dictionary, library := false) -> void:
	editor = owner_editor
	block = data
	in_library = library
	_head = get_node("%head")
	var def := LawCatalog.get_def(block.type)
	_paint(def)
	if def.is_empty():
		_add_text("Bloco desconhecido: %s" % block.type)
		return
	for seg: Dictionary in LawCatalog.segments(def):
		if seg.has("text"):
			_add_text(seg.text)
		elif block.plugs.has(seg.field):
			var inner: LawBlockView = load(BLOCK_PATH).instantiate()
			_head.add_child(inner)
			inner.setup(editor, block.plugs[seg.field], library)
		else:
			var socket: LawSocket = SOCKET.instantiate()
			_head.add_child(socket)
			socket.setup(self, seg.field, def.fields[seg.field])
	var col: Control = get_node("%col")
	for slot_name: String in def.get("slots", []):
		var slot: LawSlot = SLOT.instantiate()
		col.add_child(slot)
		slot.setup(self, slot_name)


func _add_text(text: String) -> void:
	var label: Label = TEXT.instantiate()
	label.text = text.strip_edges()
	_head.add_child(label)


func _paint(def: Dictionary) -> void:
	var color: Color = LawCatalog.category(String(def.get("cat", ""))).get("color", Color("555555"))
	var border := Color(0, 0, 0, 0.35)
	if editor and not in_library:
		if int(block.id) in editor.error_blocks:
			border = ERROR_BORDER
		if int(block.id) == editor.selected_id:
			border = SELECTED_BORDER
	var style := UiKit.panel_style(color, border, 4, 5)
	if border != Color(0, 0, 0, 0.35):
		style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not in_library:
		editor.select_block(int(block.id))
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if editor.read_only:
		return null
	var preview: LawBlockView = load(BLOCK_PATH).instantiate()
	preview.editor = editor
	preview.modulate.a = 0.8
	set_drag_preview(preview)
	preview.setup(editor, block, true)
	if in_library:
		return {"law": true, "new": block.type, "kind": LawCatalog.get_def(block.type).kind}
	return {"law": true, "move": int(block.id), "kind": LawCatalog.get_def(block.type).kind}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if in_library or editor.read_only or not data is Dictionary or not data.has("law"):
		return false
	var kind: String = LawCatalog.get_def(block.type).kind
	if kind == "value" or kind == "bool":
		return false
	if data.kind != "statement" and data.kind != "cblock":
		return false
	if kind == "event" and at.y < size.y * 0.5:
		return false
	return editor.can_move_to(data, int(block.id))


func _drop_data(at: Vector2, data: Variant) -> void:
	editor.drop(data, {"kind": "before" if at.y < size.y * 0.5 and LawCatalog.get_def(block.type).kind != "event" else "after", "id": int(block.id)})
