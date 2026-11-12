class_name LawEditor
extends ColorRect
## Legislative editor: library, programming area, block properties and validation.

const BLOCK := preload("res://scenes/ui/legislation/law_block.tscn")
const LIBRARY_HEADING := preload("res://scenes/ui/legislation/library_heading.tscn")
const LIBRARY_GROUP := preload("res://scenes/ui/legislation/library_group.tscn")
const VALIDATION_ROW := preload("res://scenes/ui/legislation/validation_row.tscn")
const FIELD_ROW := preload("res://scenes/ui/legislation/field_row.tscn")

var main: Node
var world: GameWorld
var norm := {}
var read_only := false
var selected_id := -1
var error_blocks: Array = []
var last_compile := {}
## When reading a published version, the program is not the norm's draft.
var _shown_program := {}
var _library_program := LawProgram.empty()
## Code that the norm amends ("tributario"...), or "" for a standalone law.
var code_id := ""

@onready var canvas: LawCanvas = %canvas
@onready var _library: VBoxContainer = %library_list
@onready var _trash: LawTrash = %library_panel
@onready var _validation: VBoxContainer = %validation_list
@onready var _summary: Label = %validation_summary
@onready var _feedback: Label = %feedback
@onready var _props: VBoxContainer = %props_box
@onready var _props_title: Label = %props_title
@onready var _props_empty: Label = %props_empty
@onready var _remove: Button = %remove_block
@onready var _legal: Label = %legal_text
@onready var _doc_type: OptionButton = %doc_type


func setup(owner_main: Node, target: Dictionary, version := -1) -> void:
	main = owner_main
	world = main.world
	norm = target
	code_id = world.legislation.code_of(norm)
	read_only = version >= 0 or norm.state != Legislation.STATE_DRAFT
	_shown_program = norm.versions[version].program if version >= 0 else norm.program
	canvas.editor = self
	_trash.editor = self
	(%simulator as LawSimulator).setup(self)
	(%review as LawReview).setup(self)
	_build_library()
	_fill_document()
	_connect()
	var emenda: bool = norm.type == "emenda"
	(%poll as PollBox).setup(world, func(): return {} if not last_compile.get("ok", false) else _poll_target())
	(%read_only_note as Control).visible = read_only
	for button: Control in [%present, %delete_draft, %save_close]:
		button.visible = not read_only and not emenda
	if emenda:
		(%save_close as Control).visible = not read_only
		(%save_close as Button).text = tr("Voltar à emenda")
	refresh()


func norm_program() -> Dictionary:
	return _shown_program


func _connect() -> void:
	%simulate.pressed.connect(func(): (%simulator as LawSimulator).open())
	%save_close.pressed.connect(close_editor)
	%present.pressed.connect(_on_present)
	%delete_draft.pressed.connect(func():
		world.legislation.delete_draft(int(norm.id))
		main.close_law_screen(self))
	_remove.pressed.connect(func():
		LawProgram.remove_one(_shown_program, selected_id)
		selected_id = -1
		refresh())
	_doc_type.item_selected.connect(func(i: int):
		norm.type = _doc_type.get_item_metadata(i)
		norm.organ = Legislation.NORM_TYPES[norm.type].organ
		refresh())
	%doc_name.text_changed.connect(func(t): norm.title = t)
	%doc_ementa.text_changed.connect(func(): norm.ementa = %doc_ementa.text)
	%doc_vacatio.text_changed.connect(func(t: String): norm.vacatio = maxi(t.to_int(), 0))
	%doc_expires.text_changed.connect(func(t: String): norm.expires = t.strip_edges())


func _input(event: InputEvent) -> void:
	# In reading mode there is no "save": Esc closes. In editing, Esc also saves and closes.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not (%simulator as Control).visible:
		get_viewport().set_input_as_handled()
		if (%review as Control).visible:
			(%review as Control).visible = false
			return
		close_editor()


func close_editor() -> void:
	if norm.type == "emenda" and not read_only:
		main.open_amendment_editor(norm)
	else:
		main.close_law_screen(self)


func _poll_target() -> Dictionary:
	return {"type": norm.type, "program": _shown_program, "by_player": norm.get("by_player", true), "ops": norm.get("ops", [])}


func _fill_document() -> void:
	var leg: Legislation = world.legislation
	(%doc_number as Label).text = tr("%s  ·  autor: %s  ·  %s") % [leg.norm_label(norm), norm.author, tr(norm.state)]
	(%doc_title as Label).text = tr("Editor legislativo") if not read_only else tr("Programação de %s") % leg.norm_label(norm)
	var code := LawCodes.get_code(code_id)
	var badge: Label = %code_badge
	badge.visible = code != null
	if code:
		(%doc_title as Label).text = tr(code.title) if read_only else tr("Alterar: %s") % tr(code.title)
		badge.text = tr("%s · blocos de %s") % [tr(Legislation.NORM_TYPES[norm.type].label), tr(code.category.label).to_lower()]
	for key: String in Legislation.NORM_TYPES:
		if key == "constituicao" or (key == "emenda" and norm.type != "emenda"):
			continue
		if norm.type == "emenda" and key != "emenda":
			continue
		if read_only or leg.can(world, "present", key):
			_doc_type.add_item(tr(Legislation.NORM_TYPES[key].label))
			_doc_type.set_item_metadata(_doc_type.item_count - 1, key)
			if key == norm.type:
				_doc_type.select(_doc_type.item_count - 1)
	# Titles of the codes and templates stay in Portuguese in the norm: the field shows the translation.
	(%doc_name as LineEdit).text = tr(norm.title)
	(%doc_ementa as TextEdit).text = tr(norm.ementa)
	(%doc_vacatio as LineEdit).text = str(int(norm.get("vacatio", 0)))
	(%doc_expires as LineEdit).text = String(norm.get("expires", ""))
	for field: Control in [%doc_name, %doc_vacatio, %doc_expires]:
		(field as LineEdit).editable = not read_only
	(%doc_ementa as TextEdit).editable = not read_only
	_doc_type.disabled = read_only or norm.type == "emenda" or int(norm.get("amends", -1)) >= 0 or not norm.get("revokes", {}).is_empty()


## Palette. Standalone law: the blocks of the codes and, in an open group, the advanced ones. Code norm: only the
## code's category and the events; the other codes and the advanced ones stay collapsed, one click away.
func _build_library() -> void:
	var cats := LawCatalog.categories()
	var others: Control = null
	var advanced: Control = _library_group(tr("Avançado"), tr("Blocos genéricos para regras próprias: condições, cálculos, variáveis e ações administrativas."), code_id == "")
	for cat: Dictionary in cats:
		var mine: bool = String(cat.get("code", "")) == code_id or (code_id != "" and cat.id == "events")
		var target: Control = _library
		if code_id != "" and not mine:
			if cat.has("code"):
				if others == null:
					others = _library_group(tr("Outros códigos"), tr("Blocos de outras áreas. Prefira alterar o código de cada área."), false)
				target = others.get_node("%items")
			else:
				target = advanced.get_node("%items")
		elif cat.get("advanced", false) and not mine:
			target = advanced.get_node("%items")
		var blocks := LawCatalog.in_category(cat.id)
		var heading: Label = LIBRARY_HEADING.instantiate()
		heading.name = "cat_%s" % cat.id
		heading.text = tr(cat.label).to_upper()
		target.add_child(heading)
		if blocks.is_empty():
			var empty: Label = LIBRARY_HEADING.instantiate()
			empty.name = "empty_%s" % cat.id
			empty.text = tr("Os blocos desta área ainda não foram feitos.")
			target.add_child(empty)
		for def: Dictionary in blocks:
			var view: LawBlockView = BLOCK.instantiate()
			view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			target.add_child(view)
			view.setup(self, LawProgram.new_block(_library_program, def.id), true)
	if others:
		_library.move_child(others, -1)
	_library.move_child(advanced, -1)


func _library_group(title: String, hint: String, open: bool) -> Control:
	var group: Control = LIBRARY_GROUP.instantiate()
	group.name = "group_%s" % title.to_lower().replace(" ", "_")
	_library.add_child(group)
	var toggle: Button = group.get_node("%toggle")
	var items: Control = group.get_node("%items")
	(group.get_node("%hint") as Label).text = hint
	var show := func(on: bool):
		items.visible = on
		toggle.text = ("▾ " if on else "▸ ") + title
	toggle.button_pressed = open
	show.call(open)
	toggle.toggled.connect(show)
	return group


## The collapsed palette group that has the block, so the test opens it before dragging.
func library_group_of(view: Control) -> Control:
	var node := view.get_parent()
	while node and node != _library:
		if node.has_node("%toggle"):
			return node
		node = node.get_parent()
	return null


func refresh() -> void:
	canvas.rebuild()
	_show_props()
	_compile_now()


func _compile_now() -> void:
	var leg: Legislation = world.legislation
	var probe := {"program": _shown_program, "type": norm.type, "id": norm.id, "amends": norm.get("amends", -1)}
	last_compile = leg.compile_norm(probe)
	error_blocks = last_compile.errors.map(func(e): return int(e.block))
	for child in _validation.get_children():
		_validation.remove_child(child)
		child.queue_free()
	for entry: Dictionary in last_compile.errors:
		_add_validation(entry, true)
	for entry: Dictionary in last_compile.warnings:
		_add_validation(entry, false)
	if last_compile.errors.is_empty() and last_compile.warnings.is_empty():
		_summary.text = tr("Nenhum problema encontrado.")
		_summary.add_theme_color_override("font_color", UiKit.GREEN)
	else:
		_summary.text = tr("%d erro(s), %d aviso(s)") % [last_compile.errors.size(), last_compile.warnings.size()]
		_summary.add_theme_color_override("font_color", UiKit.RED if not last_compile.errors.is_empty() else UiKit.ACCENT)
	_legal.text = LawProgram.legal_text(_shown_program, true)
	(%present as Button).disabled = not last_compile.ok
	(%poll as PollBox).refresh()
	(%poll as PollBox).clear_result()
	# Blocks with an error get a red outline on the next draw.
	canvas.rebuild()


func _add_validation(entry: Dictionary, is_error: bool) -> void:
	var row: Button = VALIDATION_ROW.instantiate()
	row.text = (tr("Erro: ") if is_error else tr("Aviso: ")) + String(entry.text)
	row.tooltip_text = String(entry.text)
	row.add_theme_color_override("font_color", UiKit.RED if is_error else UiKit.ACCENT)
	if int(entry.block) >= 0:
		row.pressed.connect(select_block.bind(int(entry.block)))
	_validation.add_child(row)


## Submitting first opens the expected effects panel; the button there is what sends.
func _on_present() -> void:
	if String(norm.title).strip_edges() == "" or String(norm.ementa).strip_edges() == "":
		_feedback.text = tr("Preencha o título e a ementa da norma.")
		_feedback.add_theme_color_override("font_color", UiKit.RED)
		return
	(%review as LawReview).open()


func send() -> void:
	var r: Dictionary = world.legislation.present(world, norm)
	_feedback.text = r.msg
	_feedback.add_theme_color_override("font_color", UiKit.GREEN if r.ok else UiKit.RED)
	if r.ok:
		main.close_law_screen(self, r.msg)
	else:
		(%review as LawReview).show_error(r.msg)


# --- Selection and properties ------------------------------------------------------------

func select_block(id: int) -> void:
	if id == selected_id:
		return
	selected_id = id
	canvas.rebuild()
	_show_props()


func _show_props() -> void:
	for child in _props.get_children():
		_props.remove_child(child)
		child.queue_free()
	var where := LawProgram.locate(_shown_program, selected_id) if selected_id >= 0 else {}
	_props_empty.visible = where.is_empty()
	_props_title.visible = not where.is_empty()
	_remove.visible = not where.is_empty() and not read_only
	if where.is_empty():
		selected_id = -1
		return
	var block: Dictionary = where.block
	var def := LawCatalog.get_def(block.type)
	_props_title.text = LawProgram.block_text(block, true)
	for key: String in def.get("fields", {}):
		_props.add_child(_field_row(block, key, def.fields[key]))


func _field_row(block: Dictionary, key: String, spec: Dictionary) -> Control:
	var row: Control = FIELD_ROW.instantiate()
	(row.get_node("%label") as Label).text = key.capitalize() if not FIELD_NAMES.has(key) else tr(FIELD_NAMES[key])
	if spec.get("t", "") == "ref":
		(row.get_node("%label") as Label).text = tr(REF_LABELS.get(String(spec.get("of", "")), tr("Nome")))
	var edit: LineEdit = row.get_node("%edit")
	var option: OptionButton = row.get_node("%option")
	var check: CheckBox = row.get_node("%check")
	var plugged: Control = row.get_node("%Encaixe")
	edit.visible = false
	option.visible = false
	check.visible = false
	plugged.visible = false
	edit.editable = not read_only
	option.disabled = read_only
	check.disabled = read_only
	if block.plugs.has(key):
		plugged.visible = true
		(row.get_node("%plugged") as Label).text = LawProgram.block_text(block.plugs[key], true)
		var unplug: Button = row.get_node("%unplug")
		unplug.visible = not read_only
		unplug.pressed.connect(func():
			block.plugs.erase(key)
			refresh())
		return row
	match spec.t:
		"choice":
			option.visible = true
			var choices: Dictionary = LawCatalog.choice_list(spec.of)
			for value: String in choices:
				option.add_item(tr(choices[value]))
				option.set_item_metadata(option.item_count - 1, value)
				if value == block.fields.get(key):
					option.select(option.item_count - 1)
			option.item_selected.connect(func(i: int):
				block.fields[key] = option.get_item_metadata(i)
				_after_edit())
		"ministry":
			option.visible = true
			var names := []
			for portfolio: Dictionary in world.politics.portfolios(world):
				names.append(String(portfolio.label))
			for b: Dictionary in LawProgram.all_blocks(_shown_program):
				if b.type in ["ad_min_create", "ad_min_merge"] and not String(b.fields.get("name", "")) in names:
					names.append(String(b.fields.get("name", "")))
			option.add_item(tr("Escolha o ministério"))
			option.set_item_metadata(0, "")
			for label: String in names:
				option.add_item(tr(label))
				option.set_item_metadata(option.item_count - 1, label)
				if label == String(block.fields.get(key, "")):
					option.select(option.item_count - 1)
			option.item_selected.connect(func(i: int):
				block.fields[key] = option.get_item_metadata(i)
				_after_edit())
		"ref":
			_ref_field(block, key, spec, option, edit)
		"company":
			option.visible = true
			option.add_item(tr("Escolha a empresa"))
			option.set_item_metadata(0, "")
			var listing: Array = world.corporate.companies_of(world.legislation.iso).duplicate()
			listing.sort_custom(func(a, b): return float(a.value) > float(b.value))
			for co: Dictionary in listing:
				var label := String(co.name)
				if float(co.state) > 0.0:
					label += tr(" (Estado: %d%%)") % int(roundf(float(co.state) * 100.0))
				option.add_item(label)
				option.set_item_metadata(option.item_count - 1, String(co.name))
				if String(co.name) == String(block.fields.get(key, "")):
					option.select(option.item_count - 1)
			option.item_selected.connect(func(i: int):
				block.fields[key] = option.get_item_metadata(i)
				_after_edit())
		"unit":
			option.visible = true
			option.add_item(tr("Qualquer parte do país"))
			option.set_item_metadata(0, -1)
			for id: int in world.subdivisions.roots_of(world.legislation.iso):
				option.add_item(world.subdivisions.units[id].name)
				option.set_item_metadata(option.item_count - 1, id)
				if id == int(block.fields.get(key, -1)):
					option.select(option.item_count - 1)
			option.item_selected.connect(func(i: int):
				block.fields[key] = option.get_item_metadata(i)
				_after_edit())
		"bool":
			if not block.fields.has(key) and not spec.has("d"):
				plugged.visible = true
				(row.get_node("%plugged") as Label).text = tr("Arraste uma condição para este campo.")
				(row.get_node("%unplug") as Control).visible = false
			else:
				check.visible = true
				check.button_pressed = block.fields.get(key, false)
				check.toggled.connect(func(on: bool):
					block.fields[key] = on
					_after_edit())
		_:
			edit.visible = true
			edit.text = _edit_text(block.fields.get(key, ""))
			edit.text_changed.connect(func(t: String):
				block.fields[key] = _parse(t, String(spec.t))
				_after_edit(false))
			edit.focus_exited.connect(_after_edit)
	return row


## List of what already exists (taxes, licenses, institutions, duties). "Outro nome" (another name) opens the free text, only
## to name something that this norm creates.
func _ref_field(block: Dictionary, key: String, spec: Dictionary, option: OptionButton, edit: LineEdit) -> void:
	option.visible = true
	var names := world.legislation.known_names(String(spec.get("of", "")), _shown_program)
	var current := String(block.fields.get(key, ""))
	if current != "" and not current in names:
		names.append(current)
	for label: String in names:
		option.add_item(label)
		option.set_item_metadata(option.item_count - 1, label)
		if label == current:
			option.select(option.item_count - 1)
	option.add_item(tr(REF_NEW))
	option.set_item_metadata(option.item_count - 1, "")
	edit.placeholder_text = tr("Nome do que esta norma cria")
	edit.text = current
	edit.text_changed.connect(func(t: String):
		block.fields[key] = t.strip_edges()
		_after_edit(false))
	edit.focus_exited.connect(_after_edit)
	option.item_selected.connect(func(i: int):
		var value := String(option.get_item_metadata(i))
		edit.visible = value == ""
		if value != "":
			block.fields[key] = value
			edit.text = value
			_after_edit()
		else:
			edit.grab_focus())


# i18n-begin
const REF_NEW := "Outro nome…"
# i18n-end
# i18n-begin
const REF_LABELS := {"tax": "Tributo", "license": "Licença", "institution": "Instituição", "duty": "Obrigação"}
# i18n-end

# i18n-begin
const FIELD_NAMES := {
	"amount": "Valor", "days": "Dias", "name": "Nome", "rate": "Alíquota (%)", "base": "Base", "value": "Valor", "field": "Campo", "age": "Idade",
	"date": "Data (aaaa-mm-dd)", "from": "De (aaaa-mm-dd)", "to": "Até (aaaa-mm-dd)", "license": "Licença", "institution": "Instituição", "norm": "Número da norma",
	"a": "Primeiro valor", "b": "Segundo valor", "lo": "Mínimo", "hi": "Máximo", "times": "Vezes", "set": "Cada", "status": "Situação", "posts": "Vagas", "salary": "Salário anual",
	"cost": "Custo anual (bilhões)", "purpose": "Finalidade", "share": "Parte isenta (%)", "max": "Limite por pessoa", "sector": "Setor", "right": "Direito", "cond": "Condição",
	"vtype": "Tipo da variável", "profession": "Profissão", "unit": "Território", "area": "Área",
	"company": "Empresa", "stake": "Participação (%)",
	"scope": "Para quem", "duty": "Dever", "months": "Duração (meses)", "who": "Quem serve", "outlet": "Meio", "level": "Rigor", "service": "Serviço",
}
# i18n-end


static func _edit_text(value: Variant) -> String:
	if value is float or value is int:
		return str(value) if Lang.english_numbers else str(value).replace(".", ",")
	return str(value)


static func _parse(text: String, type: String) -> Variant:
	var clean := text.strip_edges().replace(",", ".")
	if type == "text" or type == "date" or type == "var" or type == "ref":
		return text.strip_edges()
	if clean.is_valid_float():
		return clean.to_float()
	return text.strip_edges() if type == "any" else 0.0 if clean == "" else text.strip_edges()


## The properties panel is not rebuilt here, so the field being edited does not lose focus.
func _after_edit(_redraw := true) -> void:
	_compile_now()


# --- Arrastar e soltar --------------------------------------------------------------------

func can_move_to(data: Dictionary, target_id: int) -> bool:
	if not data.has("move"):
		return true
	if int(data.move) == target_id:
		return false
	var where := LawProgram.locate(_shown_program, int(data.move))
	return where.is_empty() or not LawProgram.contains(where.block, target_id)


func can_plug(data: Dictionary, target_id: int, spec: Dictionary) -> bool:
	if not can_move_to(data, target_id):
		return false
	var probe := {"type": data.new if data.has("new") else LawProgram.locate(_shown_program, int(data.move)).block.type}
	return LawProgram.accepts(spec, probe)


## The only place that changes the shape of the program. where.kind: canvas, after, before, slot, plug or trash.
func drop(data: Dictionary, where: Dictionary) -> void:
	if read_only:
		return
	if where.kind == "trash":
		if data.has("move"):
			LawProgram.detach(_shown_program, int(data.move))
			selected_id = -1
		_refresh_later()
		return
	var blocks := []
	if data.has("new"):
		blocks = [LawProgram.new_block(_shown_program, data.new)]
	else:
		blocks = LawProgram.detach(_shown_program, int(data.move))
	if blocks.is_empty():
		return
	match where.kind:
		"canvas":
			var stack := LawProgram.add_stack(_shown_program, blocks[0], where.pos)
			stack.blocks.append_array(blocks.slice(1))
		"after":
			LawProgram.insert_near(_shown_program, int(where.id), blocks, false)
		"before":
			LawProgram.insert_near(_shown_program, int(where.id), blocks, true)
		"slot":
			LawProgram.insert_in_slot(_shown_program, int(where.id), where.slot, blocks)
		"plug":
			LawProgram.plug(_shown_program, int(where.id), where.field, blocks[0])
	selected_id = int(blocks[0].id)
	_refresh_later()


func _refresh_later() -> void:
	refresh.call_deferred()
