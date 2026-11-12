class_name LawTrash
extends PanelContainer
## The library panel also deletes: dropping a block from the programming area here removes it.

var editor: LawEditor


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return editor != null and not editor.read_only and data is Dictionary and data.has("law") and data.has("move")


func _drop_data(_at: Vector2, data: Variant) -> void:
	editor.drop(data, {"kind": "trash"})
