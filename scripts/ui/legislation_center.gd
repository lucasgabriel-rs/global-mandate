class_name LegislationCenter
extends MarginContainer
## Gerenciador de normas. A primeira aba junta o que se usa sempre: os códigos, os projetos em tramitação,
## as normas em vigor e, por último, a lei avulsa com todos os blocos. Depois vêm Constituição, instituições,
## auditoria e tratados.

const CODE_CARD := preload("res://scenes/ui/legislation/code_card.tscn")
const NORM_ROW := preload("res://scenes/ui/legislation/norm_row.tscn")
const PROCESS_ROW := preload("res://scenes/ui/legislation/process_row.tscn")
const TREATY_ROW := preload("res://scenes/ui/legislation/treaty_row.tscn")
const STATE_COLORS := {
	Legislation.STATE_DRAFT: Color("8ba2af"), Legislation.STATE_PROCESS: Color("4fb3d9"), Legislation.STATE_APPROVED: Color("4fb3d9"),
	Legislation.STATE_AWAITING: Color("4fb3d9"), Legislation.STATE_PUBLISHED: Color("f2b33d"), Legislation.STATE_IN_FORCE: Color("4cc794"),
	Legislation.STATE_SUSPENDED: Color("f08a4b"), Legislation.STATE_REVOKED: Color("555f66"), Legislation.STATE_EXPIRED: Color("555f66"),
	Legislation.STATE_INVALID: Color("ec5a43"), Legislation.STATE_REJECTED: Color("ec5a43"),
}

var main: Node
var world: GameWorld
var leg: Legislation

@onready var _tabs: TabContainer = %tabs
@onready var _feedback: Label = %feedback


func setup(owner_main: Node, tab := 0, message := "") -> void:
	main = owner_main
	world = main.world
	leg = world.legislation
	_tabs.current_tab = tab
	_feedback.text = message
	(%role_note as Label).text = "Você atua como %s. Fundo de %s: %s." % [Legislation.ROLE_LABELS[leg.role(world)], world.politics.player_party(world).get("short", "seu partido"), UiKit.millions(world.politics.party_fund(world))]
	%close.pressed.connect(func(): main.close_legislation())
	var types: OptionButton = %new_type
	for key: String in Legislation.NORM_TYPES:
		if key != "constituicao" and key != "emenda" and leg.can(world, "present", key):
			types.add_item(Legislation.NORM_TYPES[key].label)
			types.set_item_metadata(types.item_count - 1, key)
			if key == "ordinaria":
				types.select(types.item_count - 1)
	%new_norm.pressed.connect(func(): main.open_law_editor(leg.new_norm(world, types.get_item_metadata(types.selected))))
	var templates: OptionButton = %template_pick
	for template: Dictionary in LawTemplates.all():
		templates.add_item(template.title)
	%new_template.pressed.connect(_use_template)
	(%new_amendment as Button).disabled = not leg.can(world, "present", "emenda")
	%new_amendment.pressed.connect(func(): main.open_amendment_editor(leg.new_norm(world, "emenda")))
	var imports: OptionButton = %import_pick
	for file: String in Legislation.export_files():
		imports.add_item(file)
	(%import_norm as Button).disabled = imports.item_count == 0
	%import_norm.pressed.connect(_import)
	var filter: OptionButton = %state_filter
	filter.add_item("Todas")
	for state: String in STATE_COLORS:
		filter.add_item(state)
		if state == Legislation.STATE_IN_FORCE:
			filter.select(filter.item_count - 1)
	filter.item_selected.connect(func(_i): _fill_norms())
	_fill_codes()
	_fill_norms()
	_fill_process()
	_fill_constitution_versions()
	_fill_institutions()
	_fill_treaties()
	var audit_filter: OptionButton = %audit_filter
	audit_filter.add_item("Tudo")
	var kinds := {}
	for entry: Dictionary in leg.audit:
		kinds[entry.kind] = true
	for kind: String in kinds:
		audit_filter.add_item(kind)
	audit_filter.item_selected.connect(func(_i): _fill_audit())
	_fill_audit()


func _fill_codes() -> void:
	var box: Control = %code_cards
	for code: LawCode in LawCodes.all():
		var card: Control = CODE_CARD.instantiate()
		card.name = "code_%s" % code.id
		var info := leg.code_card(code.id)
		(card.get_node("%swatch") as ColorRect).color = code.category.get("color", Color.GRAY)
		(card.get_node("%code_name") as Label).text = code.title
		var norm: Dictionary = info.norm
		var articles: int = info.articles
		(card.get_node("%articles") as Label).text = ("%s  ·  %d artigo%s" % [leg.norm_label(norm), articles, "" if articles == 1 else "s"]) if not norm.is_empty() else "Ainda não existe: alterar cria o código."
		var status: Label = card.get_node("%status")
		status.text = "%d alteração(ões) em tramitação" % int(info.pending) if int(info.pending) > 0 else ""
		var alter: Button = card.get_node("%alter")
		alter.disabled = not leg.can(world, "present", code.norm_type)
		alter.tooltip_text = code.ementa if not alter.disabled else "%s não pode apresentar %s." % [Legislation.ROLE_LABELS[leg.role(world)], Legislation.NORM_TYPES[code.norm_type].label]
		alter.pressed.connect(_alter_code.bind(code.id))
		var read: Button = card.get_node("%read")
		read.visible = not norm.is_empty()
		read.pressed.connect(func(): main.open_norm(norm))
		box.add_child(card)


func _alter_code(id: String) -> void:
	# Enquanto o Código Tributário não tem texto próprio, alterar é mudar o antigo, feito só de alíquotas.
	var legacy: Dictionary = leg.code_card(id).norm
	var bill := leg.start_change(world, legacy) if leg.code_norm(id).is_empty() and not legacy.is_empty() else leg.start_code_bill(world, id)
	if bill.is_empty():
		return
	main.open_law_editor(bill)


func _use_template() -> void:
	var template: Dictionary = LawTemplates.all()[(%template_pick as OptionButton).selected]
	var type := "ordinaria" if leg.can(world, "present", "ordinaria") else "decreto"
	var norm := leg.new_norm(world, type)
	norm.program = template.build.call()
	norm.title = template.title
	norm.ementa = template.ementa
	main.open_law_editor(norm)


func _import() -> void:
	var picks: OptionButton = %import_pick
	var r: Dictionary = leg.import_norm(world, picks.get_item_text(picks.selected))
	_feedback.text = r.msg
	_feedback.add_theme_color_override("font_color", UiKit.GREEN if r.ok else UiKit.RED)
	_fill_norms()


func _fill_norms() -> void:
	var box: Control = %norm_rows
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var filter: OptionButton = %state_filter
	var state := "" if filter.selected <= 0 else filter.get_item_text(filter.selected)
	var list := leg.list_norms(state)
	(%norm_count as Label).text = "%d norma(s)" % list.size()
	(%norms_title as Label).text = "Normas em vigor" if state == Legislation.STATE_IN_FORCE else ("Todas as normas" if state == "" else "Normas: %s" % state.to_lower())
	for norm: Dictionary in list:
		var row: Control = NORM_ROW.instantiate()
		(row.get_node("%state_chip") as ColorRect).color = STATE_COLORS.get(norm.state, Color.GRAY)
		var open: Button = row.get_node("%open")
		open.name = "norm_%d" % int(norm.id)
		open.text = "%s  ·  %s" % [leg.norm_label(norm), norm.title if norm.title != "" else "(sem título)"]
		open.tooltip_text = String(norm.ementa)
		open.pressed.connect(func(): main.open_norm(norm))
		(row.get_node("%state") as Label).text = norm.state
		box.add_child(row)


func _fill_process() -> void:
	var box: Control = %process_rows
	var list := leg.in_process()
	(%process_empty as Control).visible = list.is_empty()
	(%process_count as Label).text = "%d projeto(s)" % list.size() if not list.is_empty() else ""
	for norm: Dictionary in list:
		var row: Control = PROCESS_ROW.instantiate()
		row.name = "process_%d" % int(norm.id)
		(row.get_node("%name_label") as Label).text = "%s  ·  %s" % [leg.norm_label(norm), norm.title]
		var process: Dictionary = norm.process
		var waiting: bool = process.get("waiting_player", false)
		(row.get_node("%step_label") as Label).text = "Aguardando sua sanção" if waiting else String(norm.state)
		(row.get_node("%track") as ProcessTrack).setup(world, norm)
		var last: String = process.log[-1].result if not process.log.is_empty() else ""
		(row.get_node("%forecast") as Label).text = "Último passo: %s" % last if last != "" else ""
		row.get_node("%open").pressed.connect(func(): main.open_norm(norm))
		var deal: Button = row.get_node("%negotiate")
		deal.visible = leg.can_negotiate(norm)
		deal.pressed.connect(func(): main.open_negotiation(norm))
		var yes: Button = row.get_node("%sanction")
		var no: Button = row.get_node("%veto")
		yes.visible = waiting
		no.visible = waiting
		yes.pressed.connect(_sanction.bind(norm, true))
		no.pressed.connect(_sanction.bind(norm, false))
		box.add_child(row)
		(row.get_node("%poll") as PollBox).setup(world, func(): return norm)


func _fill_treaties() -> void:
	var box: Control = %treaty_rows
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for t: Dictionary in world.treaties.of_country(leg.iso):
		var row: Control = TREATY_ROW.instantiate()
		var others: int = t.parties.size() - 1
		(row.get_node("%title") as Label).text = "%s  ·  %s, assinado em %s%s" % [t.title, Treaties.TYPES[t.type].label, t.signed, "" if others <= 1 else "  ·  %d outros países" % others]
		(row.get_node("%state") as Label).text = t.state
		var out: Button = row.get_node("%denounce")
		out.visible = t.state == Treaties.STATE_FORCE and world.in_office
		out.pressed.connect(func():
			var r: Dictionary = world.treaties.denounce(world, int(t.id))
			_feedback.text = r.msg
			_fill_treaties())
		box.add_child(row)


func _sanction(norm: Dictionary, approve: bool) -> void:
	var r: Dictionary = leg.sanction(world, norm, approve)
	main.reopen_legislation(0, r.msg)


# --- Constituição --------------------------------------------------------------------

func _fill_constitution_versions() -> void:
	var pick: OptionButton = %version_pick
	var other: OptionButton = %compare_pick
	other.add_item("Sem comparação")
	other.set_item_metadata(0, -1)
	var versions: Array = leg.constitution.versions
	for v: Dictionary in versions:
		var label := "Versão %d (%s)" % [int(v.n), "original" if int(v.n) == 0 else "emenda nº %d" % int(v.emenda)]
		pick.add_item(label)
		pick.set_item_metadata(pick.item_count - 1, int(v.n))
		other.add_item(label)
		other.set_item_metadata(other.item_count - 1, int(v.n))
	pick.select(versions.size() - 1)
	pick.item_selected.connect(func(_i): _show_constitution())
	other.item_selected.connect(func(_i): _show_constitution())
	_show_constitution()
	var lines := []
	for v: Dictionary in versions:
		if int(v.n) == 0:
			continue
		lines.append("[color=#f2b33d]Emenda nº %d[/color]  ·  versão %d  ·  %s  ·  %s" % [int(v.emenda), int(v.n), v.date, v.approvers])
		for change: Dictionary in v.changes:
			lines.append("%s: %s" % [change.label, Legislation.word_diff(change.before, change.after)])
		lines.append("")
	(%amend_history as RichTextLabel).text = "\n".join(lines) if not lines.is_empty() else "Nenhuma emenda até agora."


func _show_constitution() -> void:
	var pick: OptionButton = %version_pick
	var other: OptionButton = %compare_pick
	var version := leg.constitution_version(pick.get_item_metadata(pick.selected))
	var base_id: int = other.get_item_metadata(other.selected) if other.selected >= 0 else -1
	var lines := []
	var previous := {}
	if base_id >= 0:
		for a: Dictionary in leg.constitution_version(base_id).articles:
			previous[int(a.id)] = a.text
	for a: Dictionary in version.articles:
		var mark := " [color=#8ba2af](cláusula pétrea)[/color]" if a.get("petrea", false) else ""
		var text: String = a.text
		if base_id >= 0:
			text = Legislation.word_diff(String(previous.get(int(a.id), "")), a.text)
		lines.append(text + mark)
	(%constitution_text as RichTextLabel).text = "\n\n".join(lines)


# --- Instituições e auditoria ------------------------------------------------------------

func _fill_institutions() -> void:
	var rules := []
	for key: String in Legislation.NORM_TYPES:
		var def: Dictionary = Legislation.NORM_TYPES[key]
		var vote: String = {"none": "sem votação", "simple": "maioria simples", "absolute": "maioria absoluta", "qualified": "maioria qualificada", "amendment": "%d%% em %d votação(ões)" % [int(leg.param("amend_quorum", 60)), int(leg.param("amend_votes", 1))]}[def.vote]
		var upper := ", duas casas" if leg.param("bicameral", false) and int(def.rank) >= 60 and def.vote != "none" and key != "emenda" else ""
		var sanction := ", com sanção e veto" if def.sanction and leg.param("veto", true) else ""
		rules.append("[color=#f2b33d]%s[/color] (hierarquia %d): %s, %s%s%s." % [def.label, int(def.rank), def.organ, vote, upper, sanction])
	(%rules_text as RichTextLabel).text = "\n".join(rules)
	var table: Dictionary = leg.permission_table()
	var perms := []
	for who: String in table:
		var allowed := []
		for action: String in Legislation.ACTIONS:
			if table[who][action]:
				allowed.append(Legislation.ACTIONS[action])
		perms.append("[color=#4fb3d9]%s[/color]: %s." % [Legislation.ROLE_LABELS[who], ", ".join(allowed) if not allowed.is_empty() else "nada"])
	(%permissions_text as RichTextLabel).text = "\n".join(perms)
	var standing := []
	var c := world.player
	standing.append("Receita das normas nos últimos 12 meses: %s do PIB. Despesa: %s do PIB." % [UiKit.pct(c.law_tax), UiKit.pct(c.law_spend)])
	standing.append("Efeito na aprovação: %+.1f p.p. Na estabilidade: %+.1f p.p." % [c.law_approval * 100.0, c.law_stability * 100.0])
	var titles := {"rights": "Direitos", "minwage": "Salário mínimo", "posts": "Cargos", "institutions": "Instituições", "subsidies": "Subsídios", "spends": "Despesas permanentes", "duties": "Obrigações", "restrictions": "Restrições", "requirements": "Requisitos", "exemptions": "Isenções", "caps": "Limites de cobrança", "penalties": "Penalidades", "deadlines": "Prazos", "exceptions": "Exceções"}
	for kind: String in titles:
		var names: Array = leg.standing[kind].keys()
		if not names.is_empty():
			standing.append("%s: %s." % [titles[kind], ", ".join(names.map(func(n): return str(n)))])
	if not leg.licenses.is_empty():
		var parts := []
		for key: String in leg.licenses:
			parts.append("%s (%s da população)" % [key, UiKit.pct(float(leg.licenses[key]), 0)])
		standing.append("Licenças: %s." % ", ".join(parts))
	standing.append("Pessoas no cadastro: %s mi. Obrigações a vencer: %d." % [UiKit.num(float(leg.registry.registered), 1), leg.obligations.size()])
	(%registry_text as RichTextLabel).text = "\n".join(standing)


func _fill_audit() -> void:
	var filter: OptionButton = %audit_filter
	var kind := "" if filter.selected <= 0 else filter.get_item_text(filter.selected)
	var lines := []
	for i in range(leg.audit.size() - 1, -1, -1):
		var e: Dictionary = leg.audit[i]
		if kind != "" and e.kind != kind:
			continue
		var detail := String(e.result)
		if String(e.before) != "" or String(e.after) != "":
			detail += "  (antes: %s; depois: %s)" % [String(e.before).left(60), String(e.after).left(60)]
		if String(e.event) != "":
			detail += "  [evento: %s]" % String(LawCatalog.get_def(e.event).get("text", e.event))
		lines.append("[color=#8ba2af]%s[/color]  %s  [color=#f2b33d]%s[/color]  %s: %s" % [e.date, e.who, e.label, e.kind, detail])
		if lines.size() >= 400:
			break
	(%audit_count as Label).text = "%d registro(s) guardado(s)" % leg.audit.size()
	(%audit_text as RichTextLabel).text = "\n".join(lines)
