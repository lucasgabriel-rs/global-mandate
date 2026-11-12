class_name LawSimulator
extends PanelContainer
## Tests the norm with a fictional citizen. Nothing here changes the match.

var editor: LawEditor
var _previous := ""

@onready var _event: OptionButton = %sim_event
@onready var _profession: OptionButton = %sim_profession


func setup(owner_editor: LawEditor) -> void:
	editor = owner_editor
	%sim_close.pressed.connect(func(): visible = false)
	%sim_run.pressed.connect(run)
	var professions: Dictionary = LawCatalog.CHOICES.profession
	for key: String in professions:
		_profession.add_item(professions[key])
		_profession.set_item_metadata(_profession.item_count - 1, key)
	_profession.select(2)
	var unit: OptionButton = %sim_unit
	unit.add_item(tr("Outro lugar"))
	unit.set_item_metadata(0, -1)
	var world := editor.world
	for id: int in world.subdivisions.roots_of(world.legislation.iso):
		unit.add_item(world.subdivisions.units[id].name)
		unit.set_item_metadata(unit.item_count - 1, id)


func open() -> void:
	_event.clear()
	_event.add_item(tr("Todos os artigos"))
	_event.set_item_metadata(0, "")
	var seen := {}
	for stack: Dictionary in editor.norm_program().stacks:
		var type: String = stack.blocks[0].type
		var def := LawCatalog.get_def(type)
		if def.get("kind", "") == "event" and not seen.has(type):
			seen[type] = true
			_event.add_item(tr(def.text).replace("{age}", "N").replace("{date}", tr("certa data")))
			_event.set_item_metadata(_event.item_count - 1, type)
	visible = true


static func _value(field: LineEdit) -> float:
	return field.text.replace(",", ".").to_float()


func citizen() -> Dictionary:
	var licenses := []
	for piece: String in (%sim_licenses as LineEdit).text.split(",", false):
		licenses.append(piece.strip_edges())
	return {
		"age": _value(%sim_age), "money": _value(%sim_money), "income": _value(%sim_income), "value": _value(%sim_value), "tx": _value(%sim_tx),
		"profession": _profession.get_item_metadata(_profession.selected), "unit": (%sim_unit as OptionButton).get_item_metadata((%sim_unit as OptionButton).selected),
		"owner": (%sim_owner as CheckBox).button_pressed, "licenses": licenses,
	}


func run() -> void:
	var economy := {"inflation": _value(%sim_inflation), "unemployment": _value(%sim_unemployment), "debt": _value(%sim_debt)}
	var event: String = _event.get_item_metadata(_event.selected) if _event.selected >= 0 else ""
	var result: Dictionary = editor.world.legislation.simulate(editor.world, editor.norm_program(), editor.norm.type, event, citizen(), economy)
	var lines := []
	if not result.errors.is_empty():
		lines.append("[color=#ec5a43]%s[/color]" % result.error)
		for e: Dictionary in result.errors:
			lines.append("• %s" % e.text)
	for line: String in result.trace:
		lines.append(("[color=#ec5a43]%s[/color]" % line) if line.begins_with("ERRO") else (("[color=#f2b33d]%s[/color]" % line) if line.begins_with("Art.") else line))
	if result.errors.is_empty():
		lines.append("")
		lines.append(tr("[color=#4cc794]%d ação(ões) simulada(s). Nada foi cobrado de verdade.[/color]") % result.get("effects", []).size())
	var text := "\n".join(lines)
	(%sim_previous as RichTextLabel).text = _previous
	(%sim_result as RichTextLabel).text = text
	_previous = text
