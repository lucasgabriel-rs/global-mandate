class_name AmendmentEditor
extends ColorRect
## Editor de emendas: escolhe o dispositivo, a operação e compara com o texto em vigor.

const ARTICLE_ROW := preload("res://scenes/ui/legislation/article_row.tscn")
const OP_ROW := preload("res://scenes/ui/legislation/op_row.tscn")
const CHECK_ROW := preload("res://scenes/ui/legislation/check_row.tscn")

var main: Node
var world: GameWorld
var leg: Legislation
var norm := {}
var _article := {}
var _rights := {}

@onready var _op: OptionButton = %op_pick
@onready var _kind: OptionButton = %kind_pick
@onready var _text: TextEdit = %new_text
@onready var _note: Label = %op_note
@onready var _feedback: Label = %feedback


func setup(owner_main: Node, target: Dictionary) -> void:
	main = owner_main
	world = main.world
	leg = world.legislation
	norm = target
	(%title as Label).text = "Emenda constitucional nº %d" % int(norm.number)
	(%doc_name as LineEdit).text = norm.title
	(%doc_ementa as TextEdit).text = norm.ementa
	%doc_name.text_changed.connect(func(t): norm.title = t)
	%doc_ementa.text_changed.connect(func(): norm.ementa = %doc_ementa.text)
	for key: String in Legislation.AMENDMENT_OPS:
		_op.add_item(Legislation.AMENDMENT_OPS[key])
		_op.set_item_metadata(_op.item_count - 1, key)
	_op.item_selected.connect(func(_i): _refresh_form())
	for key: String in Legislation.ADD_KINDS:
		_kind.add_item(Legislation.ADD_KINDS[key])
		_kind.set_item_metadata(_kind.item_count - 1, key)
	%add_op.pressed.connect(_add_op)
	%new_article.pressed.connect(func():
		_article = {}
		_choose_op("add")
		_text.grab_focus())
	%block_article.pressed.connect(func(): main.open_law_editor(norm))
	(%poll as PollBox).setup(world, func(): return {} if norm.ops.is_empty() and norm.program.stacks.is_empty() else norm)
	%save_close.pressed.connect(func(): main.reopen_legislation(0))
	%close.pressed.connect(func(): main.reopen_legislation(0))
	%delete_draft.pressed.connect(func():
		leg.delete_draft(int(norm.id))
		main.reopen_legislation(0))
	%present.pressed.connect(_present)
	_fill_articles()
	_refresh_form()
	_fill_ops()


func _fill_articles() -> void:
	var list: Control = %article_list
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for article: Dictionary in leg.constitution.articles:
		if article.get("suppressed", false):
			continue
		var row: Control = ARTICLE_ROW.instantiate()
		row.name = "article_%d" % abs(int(article.id))
		var select: Button = row.get_node("%select")
		select.text = ("★ " if article.petrea else "") + String(article.text)
		select.tooltip_text = "Cláusula pétrea: não pode ser alterada." if article.petrea else String(article.text)
		select.pressed.connect(func():
			_article = article
			_choose_op("alter"))
		var remove: Button = row.get_node("%delete")
		remove.disabled = article.petrea
		if article.petrea:
			remove.tooltip_text = "Cláusula pétrea: não pode ser excluída."
		remove.pressed.connect(func():
			norm.ops = norm.ops.filter(func(o): return int(o.get("article", 0)) != int(article.id))
			norm.ops.append({"op": "suppress", "article": article.id})
			_fill_ops())
		list.add_child(row)


func _choose_op(key: String) -> void:
	for i in _op.item_count:
		if _op.get_item_metadata(i) == key:
			_op.select(i)
	_refresh_form()


func _selected_op() -> String:
	return _op.get_item_metadata(_op.selected) if _op.selected >= 0 else "alter"


func _refresh_form() -> void:
	var op := _selected_op()
	var adding := op == "add"
	(%article_text as Label).text = "Novo dispositivo." if adding else (String(_article.text) if not _article.is_empty() else "Escolha um dispositivo ao lado.")
	# Num artigo com parâmetro, "alteração" muda o valor; "substituição" permite reescrever a redação.
	var is_param: bool = op == "alter" and not _article.is_empty() and String(_article.get("param", "")) != ""
	(_kind.get_parent() as Control).visible = adding
	(%new_petrea as Control).visible = adding
	_text.visible = not is_param and op != "suppress"
	if not adding and not _article.is_empty() and _text.visible:
		_text.text = String(_article.text)
	elif adding:
		_text.text = ""
	var value_row: Control = (%value_edit as Control).get_parent()
	var rights: Control = %rights_box
	value_row.visible = false
	rights.visible = false
	if is_param:
		var value: Variant = _article.value
		if value is Array:
			_fill_rights(value)
			rights.visible = true
		else:
			value_row.visible = true
			(%value_edit as Control).visible = not value is bool and not value is String
			(%value_check as Control).visible = value is bool
			(%value_option as Control).visible = value is String
			if value is String:
				var options: OptionButton = %value_option
				options.clear()
				var choices: Dictionary = Elections.SYSTEMS if String(_article.param) == "electoral_system" else Elections.HEADS
				for key: String in choices:
					options.add_item(choices[key])
					options.set_item_metadata(options.item_count - 1, key)
					if key == value:
						options.select(options.item_count - 1)
			elif value is bool:
				(%value_check as CheckBox).button_pressed = value
			else:
				(%value_edit as LineEdit).text = str(int(value))
	_note.text = ""


func _fill_rights(current: Array) -> void:
	var box: Control = %rights_box
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	_rights = {}
	var all: Dictionary = LawCatalog.CHOICES.right
	for key: String in all:
		var check: CheckBox = CHECK_ROW.instantiate()
		check.text = all[key]
		check.button_pressed = key in current
		box.add_child(check)
		_rights[key] = check


func _add_op() -> void:
	var kind := _selected_op()
	var op := {"op": kind}
	if kind == "add":
		var text := _text.text.strip_edges()
		if text == "":
			_note.text = "Escreva o texto do novo dispositivo."
			return
		op["kind"] = _kind.get_item_metadata(_kind.selected)
		op["text"] = text
		op["petrea"] = (%new_petrea as CheckBox).button_pressed
	else:
		if _article.is_empty():
			_note.text = "Escolha um dispositivo."
			return
		if _article.petrea:
			_note.text = "%s é cláusula pétrea: não pode ser alterado." % _article.label
			return
		op["article"] = _article.id
		if kind != "suppress":
			if kind == "alter" and String(_article.get("param", "")) != "":
				var value: Variant = _article.value
				if value is Array:
					var chosen := []
					for key: String in _rights:
						if (_rights[key] as CheckBox).button_pressed:
							chosen.append(key)
					op["value"] = chosen
				elif value is String:
					var options: OptionButton = %value_option
					op["value"] = options.get_item_metadata(options.selected)
				elif value is bool:
					op["value"] = (%value_check as CheckBox).button_pressed
				else:
					var number := (%value_edit as LineEdit).text.to_int()
					if number < 0:
						_note.text = "O valor não pode ser negativo."
						return
					op["value"] = number
			else:
				var text := _text.text.strip_edges()
				if text == "" or text == String(_article.text):
					_note.text = "Mude o texto do dispositivo."
					return
				op["text"] = text
	norm.ops.append(op)
	_fill_ops()


func _fill_ops() -> void:
	var list: Control = %op_list
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for op: Dictionary in norm.ops:
		var row: Control = OP_ROW.instantiate()
		var shown := leg.preview_op(op)
		(row.get_node("%op_label") as Label).text = Legislation.AMENDMENT_OPS[op.op]
		(row.get_node("%diff") as RichTextLabel).text = Legislation.word_diff(shown.before, shown.after)
		row.get_node("%remove").pressed.connect(func():
			norm.ops.erase(op)
			_fill_ops())
		list.add_child(row)
	if not norm.program.stacks.is_empty():
		var row: Control = OP_ROW.instantiate()
		(row.get_node("%op_label") as Label).text = "Artigos programados com blocos"
		(row.get_node("%diff") as RichTextLabel).text = LawProgram.legal_text(norm.program)
		row.get_node("%remove").pressed.connect(func():
			norm.program = LawProgram.empty()
			_fill_ops())
		list.add_child(row)
	var check: Dictionary = leg.check_amendment(world, norm)
	(%forecast as Label).text = "" if check.ok else String(check.msg)
	(%forecast as Label).add_theme_color_override("font_color", UiKit.RED)
	(%poll as PollBox).refresh()
	(%poll as PollBox).clear_result()


func _present() -> void:
	var r: Dictionary = leg.present(world, norm)
	_feedback.text = r.msg
	_feedback.add_theme_color_override("font_color", UiKit.GREEN if r.ok else UiKit.RED)
	if r.ok:
		main.reopen_legislation(1, r.msg)
