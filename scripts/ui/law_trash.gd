class_name LawTrash
extends PanelContainer
## O painel da biblioteca também apaga: soltar um bloco da área de programação aqui o remove.

var editor: LawEditor


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return editor != null and not editor.read_only and data is Dictionary and data.has("law") and data.has("move")


func _drop_data(_at: Vector2, data: Variant) -> void:
	editor.drop(data, {"kind": "trash"})
