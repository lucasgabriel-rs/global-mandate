class_name LawSocket
extends Button
## Field of a block: shows the typed value and accepts a value or condition block plugged in.

var view: LawBlockView
var field := ""
var spec := {}


func setup(owner_view: LawBlockView, field_name: String, field_spec: Dictionary) -> void:
	view = owner_view
	field = field_name
	spec = field_spec
	text = LawProgram.field_text(view.block, field, true) if view.block.fields.has(field) else "?"
	# A condition field is hexagonal, in the shape of the piece that goes in it.
	if spec.t == "bool":
		for state: String in ["normal", "hover", "pressed"]:
			var style := get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.corner_detail = 1
			add_theme_stylebox_override(state, style)
	tooltip_text = tr("Clique para editar. Arraste aqui um bloco compatível.") if spec.t != "bool" else tr("Arraste uma condição para cá.")
	pressed.connect(func():
		if not view.in_library:
			view.editor.select_block(int(view.block.id)))


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if view.in_library or view.editor.read_only or not data is Dictionary or not data.has("law"):
		return false
	if data.kind != "value" and data.kind != "bool":
		return false
	return view.editor.can_plug(data, int(view.block.id), spec)


func _drop_data(_at: Vector2, data: Variant) -> void:
	view.editor.drop(data, {"kind": "plug", "id": int(view.block.id), "field": field})
