class_name LawBlockView
extends PanelContainer
## A block on screen. It only draws and hands the gestures to the editor: whoever changes the program is LawEditor.

const BLOCK_PATH := "res://scenes/ui/legislation/law_block.tscn"
const TEXT := preload("res://scenes/ui/legislation/law_text.tscn")
const SOCKET := preload("res://scenes/ui/legislation/law_socket.tscn")
const SLOT := preload("res://scenes/ui/legislation/law_slot.tscn")
const SELECTED_BORDER := Color.WHITE
const ERROR_BORDER := Color("ec5a43")
## Fit of the pieces: where the tooth starts, width, depth and slant of the sides.
const NOTCH_X := 12.0
const NOTCH_W := 20.0
const NOTCH_D := 5.0
const NOTCH_SLOPE := 4.0
const HAT := 10.0
const PIECE_RADIUS := 11

var editor: LawEditor
var block := {}
## In the library the block is only a template: dragging creates a new copy.
var in_library := false
var _head: HBoxContainer
var _color := Color("555555")
var _kind := "statement"
var _border := Color(0, 0, 0, 0)


func setup(owner_editor: LawEditor, data: Dictionary, library := false) -> void:
	editor = owner_editor
	block = data
	in_library = library
	_head = get_node("%head")
	# The mouth of the control blocks depends on where the column puts each part: redraws when it settles.
	var parts: Container = get_node("%col")
	if not parts.sort_children.is_connected(queue_redraw):
		parts.sort_children.connect(queue_redraw)
		resized.connect(queue_redraw)
	var def := LawCatalog.get_def(block.type)
	_paint(def)
	if def.is_empty():
		_add_text(tr("Bloco desconhecido: %s") % block.type)
		return
	for seg: Dictionary in LawCatalog.segments(def, true):
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
	_color = LawCatalog.category(String(def.get("cat", ""))).get("color", Color("555555"))
	_kind = String(def.get("kind", "statement"))
	_border = Color(0, 0, 0, 0)
	if editor and not in_library:
		if int(block.id) in editor.error_blocks:
			_border = ERROR_BORDER
		if int(block.id) == editor.selected_id:
			_border = SELECTED_BORDER
	# Values are round pieces; conditions, hexagonal. Statements draw themselves, with a fit.
	if _kind == "value" or _kind == "bool":
		var style := UiKit.panel_style(_color, _border if _border.a > 0.0 else _color.darkened(0.3), PIECE_RADIUS, 5)
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		style.corner_detail = 1 if _kind == "bool" else 8
		if _border.a > 0.0:
			style.set_border_width_all(2)
		add_theme_stylebox_override("panel", style)
	queue_redraw()


## Jigsaw piece: bevel on top to receive the previous block, tooth below for the next one.
## Control blocks have the mouth open to the right, where the statements inside go in.
func _draw() -> void:
	if _kind == "value" or _kind == "bool":
		return
	var w := size.x
	var h := size.y
	var col: Control = get_node("%col")
	var mouths := []
	for child in col.get_children():
		if child is LawSlot:
			var items: Control = child.get_node("%items")
			mouths.append(Rect2(col.position + child.position + items.position, Vector2(w, child.size.y)))
	var top := 0.0
	var first := true
	for mouth: Rect2 in mouths:
		_band(Rect2(0, top, w, mouth.position.y - top), first, mouth.position.x)
		draw_rect(Rect2(0, mouth.position.y, mouth.position.x, mouth.size.y), _color)
		top = mouth.end.y
		first = false
	_band(Rect2(0, top, w, h - top), first, 0.0)
	if _border.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), _border, false, 2.0)


## A strip of the block. `top_notch`: the top strip receives the previous block's tooth (the event is the
## top of the stack and has a hat). `inner_x` > 0: the strip has a mouth below, and the tooth goes into it.
func _band(r: Rect2, top_notch: bool, inner_x: float) -> void:
	if r.size.y <= 0.0:
		return
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var pts := PackedVector2Array()
	if top_notch and _kind == "event":
		pts.append_array([Vector2(x0, y0 + HAT), Vector2(x0 + 6, y0 + 3), Vector2(x0 + 18, y0), Vector2(x1 - 4, y0), Vector2(x1, y0 + 4)])
	elif top_notch:
		pts.append_array([Vector2(x0, y0), Vector2(x0 + NOTCH_X, y0), Vector2(x0 + NOTCH_X + NOTCH_SLOPE, y0 + NOTCH_D), Vector2(x0 + NOTCH_X + NOTCH_W - NOTCH_SLOPE, y0 + NOTCH_D), Vector2(x0 + NOTCH_X + NOTCH_W, y0), Vector2(x1, y0)])
	else:
		pts.append_array([Vector2(x0, y0), Vector2(x1, y0)])
	pts.append(Vector2(x1, y1))
	# Tooth below: in the mouth of the control block, or for the next block in the stack.
	var tx := inner_x + NOTCH_X if inner_x > 0.0 else x0 + NOTCH_X
	pts.append_array([Vector2(tx + NOTCH_W, y1), Vector2(tx + NOTCH_W - NOTCH_SLOPE, y1 + NOTCH_D), Vector2(tx + NOTCH_SLOPE, y1 + NOTCH_D), Vector2(tx, y1)])
	pts.append(Vector2(x0, y1))
	draw_colored_polygon(pts, _color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), _color.darkened(0.35), 1.0)


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
