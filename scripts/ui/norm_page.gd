class_name NormPage
extends ColorRect
## Public consultation of a norm: data, consolidated text by version, votes and history.

var main: Node
var world: GameWorld
var leg: Legislation
var norm := {}

@onready var _feedback: Label = %feedback
@onready var _version: OptionButton = %version_pick


func setup(owner_main: Node, target: Dictionary) -> void:
	main = owner_main
	world = main.world
	leg = world.legislation
	norm = target
	(%title as Label).text = "%s  ·  %s" % [leg.norm_label(norm), tr(norm.title)]
	(%state as Label).text = tr(norm.state)
	%close.pressed.connect(func(): main.reopen_legislation(0))
	_fill_document()
	_fill_versions()
	_fill_votes()
	_fill_history()
	_fill_actions()


func _fill_document() -> void:
	var dates: Dictionary = norm.dates
	var lines := [
		tr("[color=#8ba2af]Tipo:[/color] %s") % tr(Legislation.NORM_TYPES[norm.type].label),
		tr("[color=#8ba2af]Número e ano:[/color] %d/%d") % [int(norm.number), int(norm.year)],
		tr("[color=#8ba2af]Autor:[/color] %s") % norm.author,
		tr("[color=#8ba2af]Órgão responsável:[/color] %s") % tr(norm.organ),
		tr("[color=#8ba2af]Ementa:[/color] %s") % tr(norm.ementa),
		tr("[color=#8ba2af]Apresentação:[/color] %s  ·  [color=#8ba2af]Aprovação:[/color] %s") % [dates.get("presented", "—"), dates.get("approved", "—")],
		tr("[color=#8ba2af]Promulgação:[/color] %s  ·  [color=#8ba2af]Publicação:[/color] %s") % [dates.get("promulgated", "—"), dates.get("published", "—")],
		tr("[color=#8ba2af]Entrada em vigor:[/color] %s  ·  [color=#8ba2af]Situação:[/color] %s") % [dates.get("in_force", "—"), tr(norm.state)],
	]
	if String(norm.get("expires", "")) != "":
		lines.append(tr("[color=#8ba2af]Vale até:[/color] %s") % norm.expires)
	(%doc_text as RichTextLabel).text = "\n".join(lines)


func _fill_versions() -> void:
	if norm.type == "constituicao":
		_version.add_item(tr("Texto em vigor"))
		(%law_text as RichTextLabel).text = "\n\n".join(leg.constitution.articles.map(func(a): return Legislation.article_text(a, true)))
		return
	var versions: Array = norm.versions
	if versions.is_empty():
		_version.add_item(tr("Rascunho"))
		(%law_text as RichTextLabel).text = LawProgram.legal_text(norm.program, true) if norm.type != "emenda" else _ops_text()
		return
	for i in versions.size():
		_version.add_item(tr("Versão %d: %s (%s)") % [i + 1, tr(versions[i].change), versions[i].date])
	_version.select(int(norm.current_v))
	_version.item_selected.connect(_show_version)
	_show_version(int(norm.current_v))


func _ops_text() -> String:
	var lines := []
	for op: Dictionary in norm.get("ops", []):
		var shown := leg.preview_op(op, true)
		lines.append("%s: %s" % [tr(Legislation.AMENDMENT_OPS[op.op]), Legislation.word_diff(shown.before, shown.after)])
	return "\n\n".join(lines)


func _show_version(index: int) -> void:
	var text := _version_text(norm.versions[index])
	if index > 0:
		text = Legislation.word_diff(_version_text(norm.versions[index - 1]), text).replace("\n", " ")
	(%law_text as RichTextLabel).text = text


## The text stored in the version stays in Portuguese; the program, when there is one, is shown in the game's language.
func _version_text(version: Dictionary) -> String:
	var program: Dictionary = version.get("program", {})
	if norm.type != "emenda" and not program.get("stacks", []).is_empty():
		return LawProgram.legal_text(program, true)
	return String(version.text)


func _fill_votes() -> void:
	var lines := []
	for vote: Dictionary in norm.votes:
		lines.append(tr("[color=#f2b33d]%s[/color]  %s  ·  %d a %d (precisava de %d)  %s") % [tr(vote.get("house", "Plenário")), vote.get("date", ""), int(vote.yes), int(vote.no), int(vote.needed), tr("aprovado") if vote.get("passed", false) else tr("rejeitado")])
		var parties := []
		for row: Dictionary in vote.get("tally", []):
			parties.append("%s %d/%d" % [row.party, int(row.yes), int(row.no)])
		lines.append("  ".join(parties))
	(%votes_text as RichTextLabel).text = "\n".join(lines) if not lines.is_empty() else tr("Sem votação.")


func _fill_history() -> void:
	var lines := []
	for step: Dictionary in norm.process.get("log", []):
		lines.append("[color=#8ba2af]%s[/color]  [color=#4fb3d9]%s[/color]  %s: %s" % [step.date, tr(step.label), tr(step.by), step.result])
	for entry: Dictionary in leg.audit:
		if int(entry.norm) == int(norm.id) and entry.kind != "Execução" and not entry.kind in Legislation.STEP_LABELS.values():
			lines.append("[color=#8ba2af]%s[/color]  [color=#f2b33d]%s[/color]  %s: %s" % [entry.date, tr(entry.kind), entry.who, entry.result])
	(%history_text as RichTextLabel).text = "\n".join(lines) if not lines.is_empty() else tr("Sem registros.")


func _fill_actions() -> void:
	var draft: bool = norm.state == Legislation.STATE_DRAFT
	var in_force: bool = norm.state == Legislation.STATE_IN_FORCE
	var regular: bool = norm.type != "constituicao" and norm.type != "emenda" and not norm.has("payload")
	var has_program: bool = regular and (not norm.versions.is_empty() and not norm.versions[0].program.stacks.is_empty() or draft)
	(%edit_draft as Control).visible = draft
	%edit_draft.pressed.connect(func():
		if norm.type == "emenda":
			main.open_amendment_editor(norm)
		else:
			main.open_law_editor(norm))
	(%view_program as Control).visible = has_program and not draft
	%view_program.pressed.connect(func(): main.open_law_editor(norm, _version.selected))
	(%change as Control).visible = in_force and has_program and leg.can(world, "present", norm.type)
	%change.pressed.connect(func(): main.open_law_editor(leg.start_change(world, norm)))
	var can_revoke: bool = in_force and regular and leg.can(world, "present", norm.type)
	for node: Control in [%revoke, %revoke_articles]:
		node.visible = can_revoke
	%revoke.pressed.connect(_propose_revocation)
	var low: bool = int(Legislation.NORM_TYPES[norm.type].rank) < 60
	(%suspend as Button).visible = regular and low and leg.can(world, "admin") and (in_force or norm.state == Legislation.STATE_SUSPENDED)
	(%suspend as Button).text = tr("Reativar") if norm.state == Legislation.STATE_SUSPENDED else tr("Suspender")
	%suspend.pressed.connect(func():
		var r: Dictionary = leg.suspend(world, norm, norm.state == Legislation.STATE_IN_FORCE)
		main.open_norm(norm, r.msg))
	(%export as Control).visible = regular and has_program
	%export.pressed.connect(func():
		var path: String = leg.export_norm(norm)
		_feedback.text = tr("Exportada para %s") % ProjectSettings.globalize_path(path) if path != "" else tr("Não foi possível exportar."))
	(%negotiate as Control).visible = leg.can_negotiate(norm)
	%negotiate.pressed.connect(func(): main.open_negotiation(norm))
	var waiting: bool = norm.process.get("waiting_player", false)
	for node: Control in [%sanction, %veto]:
		node.visible = waiting
	%sanction.pressed.connect(func():
		var r: Dictionary = leg.sanction(world, norm, true)
		main.open_norm(norm, r.msg))
	%veto.pressed.connect(func():
		var r: Dictionary = leg.sanction(world, norm, false)
		main.open_norm(norm, r.msg))


func _propose_revocation() -> void:
	var articles := []
	var total: int = _program_stacks()
	for piece: String in (%revoke_articles as LineEdit).text.split(",", false):
		var number := piece.strip_edges().to_int()
		if number < 1 or number > total:
			_feedback.text = tr("A norma tem %d artigo(s).") % total
			_feedback.add_theme_color_override("font_color", UiKit.RED)
			return
		articles.append(number)
	var revocation: Dictionary = leg.start_revocation(world, norm, articles)
	var r: Dictionary = leg.present(world, revocation)
	if r.ok:
		main.reopen_legislation(0, r.msg)
	else:
		leg.delete_draft(int(revocation.id))
		_feedback.text = r.msg
		_feedback.add_theme_color_override("font_color", UiKit.RED)


func _program_stacks() -> int:
	return norm.versions[int(norm.current_v)].program.stacks.size() if not norm.versions.is_empty() else 0
