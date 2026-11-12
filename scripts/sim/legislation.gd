class_name Legislation
extends RefCounted
## Norms of the player's country: documents, versions, procedure, Constitution, execution and audit.
## Everything is a plain dictionary, saved with the match. Only the player's country has norms.

const MAX_AUDIT := 1500
const MAX_FAILURES := 3
const MAX_AI_PENDING := 3
const AI_PROPOSAL_CHANCE := 0.25
const TACIT_SANCTION_DAYS := 15
## Share of the tax that actually comes in: the rest is evasion.
const COMPLIANCE := 0.88
const EXPORT_DIR := "user://legislacao/"
const EXPORT_FORMAT := 1

# i18n-begin
const STATE_DRAFT := "Em elaboração"
const STATE_PROCESS := "Em tramitação"
const STATE_APPROVED := "Aprovada"
const STATE_AWAITING := "Aguardando publicação"
const STATE_PUBLISHED := "Publicada"
const STATE_IN_FORCE := "Em vigor"
const STATE_SUSPENDED := "Suspensa"
const STATE_REVOKED := "Revogada"
const STATE_EXPIRED := "Expirada"
const STATE_INVALID := "Declarada inválida"
const STATE_REJECTED := "Rejeitada"
# i18n-end

## vote: none, simple, absolute or qualified. needs: roles that may submit.
# i18n-begin
const NORM_TYPES := {
	"constituicao": {"label": "Constituição", "short": "CF", "rank": 100, "organ": "Assembleia Constituinte", "vote": "qualified", "sanction": false, "needs": []},
	"emenda": {"label": "Emenda constitucional", "short": "EC", "rank": 90, "organ": "Parlamento", "vote": "amendment", "sanction": false, "needs": ["head", "opposition"]},
	"plebiscito": {"label": "Plebiscito", "short": "Pleb.", "rank": 60, "organ": "Parlamento", "vote": "simple", "sanction": false, "needs": ["head", "opposition"]},
	"complementar": {"label": "Lei complementar", "short": "LC", "rank": 70, "organ": "Parlamento", "vote": "absolute", "sanction": true, "needs": ["head", "opposition"]},
	"ordinaria": {"label": "Lei ordinária", "short": "Lei", "rank": 60, "organ": "Parlamento", "vote": "simple", "sanction": true, "needs": ["head", "opposition"]},
	"decreto_autonomo": {"label": "Decreto autônomo", "short": "DA", "rank": 45, "organ": "Chefe de governo", "vote": "none", "sanction": false, "needs": ["head"]},
	"decreto": {"label": "Decreto", "short": "Dec.", "rank": 40, "organ": "Chefe de governo", "vote": "none", "sanction": false, "needs": ["head"]},
	"resolucao": {"label": "Resolução", "short": "Res.", "rank": 35, "organ": "Parlamento", "vote": "simple", "sanction": false, "needs": ["head", "opposition"]},
	"regulamento": {"label": "Regulamento", "short": "Reg.", "rank": 30, "organ": "Ministério", "vote": "none", "sanction": false, "needs": ["head"]},
	"portaria": {"label": "Portaria", "short": "Port.", "rank": 20, "organ": "Ministério", "vote": "none", "sanction": false, "needs": ["head"]},
}
# i18n-end
## Days each stage takes after the previous one: parliament needs time to deliberate.
const STEP_DAYS := {
	"present": 2, "admissibility": 7, "constitutional": 7, "discussion": 21, "vote": 3, "vote_upper": 21, "interval": 0,
	"plebiscite": 30, "quorum": 1, "sanction": 5, "override": 14, "promulgate": 2, "publish": 1, "sign": 1, "apply": 0,
}
## Weight of each block in the voter's opinion, besides the distance from their ideas.
const POPULARITY_WEIGHTS := {
	"ec_charge": -0.08, "ec_fee": -0.04, "ec_contribution": -0.08, "ac_obligation": -0.08, "ac_fine": -0.03, "ac_benefit": 0.1, "ec_exempt": 0.05, "ec_cap": 0.04,
	"ec_minwage": 0.08, "ec_subsidy": 0.02, "ec_spend": 0.03, "rg_grant": 0.06, "rg_remove": -0.12, "rg_restrict": -0.1, "rg_duty": -0.05, "rg_penalty": -0.03, "rg_exception": 0.02,
}
## A popular law gives the government approval when it takes effect; an unpopular one takes it away.
const POPULARITY_APPROVAL := 0.05
const POLL_MARGIN_POPULARITY := 3.0
const POLL_MARGIN_SUPPORT := 0.04
## Vote negotiation: price by the weight of the caucus and chance by the distance between the party and the proposal.
const DEAL_BASE_PRICE := 0.1
const DEAL_SEAT_PRICE := 1.2
const DEAL_GENEROUS_BONUS := 0.25
const DEAL_POST_BONUS := 0.2
const TAX_FIELDS := ["tax_income", "tax_consumption", "tax_corporate", "tariff"]
# i18n-begin
const STEP_LABELS := {
	"present": "Apresentação", "admissibility": "Admissibilidade", "constitutional": "Análise constitucional", "discussion": "Discussão",
	"vote": "Votação", "vote_upper": "Votação na segunda casa", "vote_2": "Segunda votação", "interval": "Intervalo entre votações",
	"quorum": "Verificação do quórum", "sanction": "Sanção", "override": "Veto em análise", "promulgate": "Promulgação",
	"plebiscite": "Plebiscito", "publish": "Publicação", "sign": "Assinatura", "apply": "Atualização da Constituição",
}
# i18n-end
# i18n-begin
const ACTIONS := {
	"create": "Criar normas", "edit": "Editar propostas", "present": "Apresentar projetos", "analyze": "Analisar propostas",
	"vote": "Participar de votações", "approve": "Aprovar normas", "veto": "Exercer veto", "promulgate": "Promulgar normas",
	"publish": "Publicar normas", "revoke": "Revogar normas", "admin": "Administrar o sistema legislativo",
}
# i18n-end
# i18n-begin
const ROLE_LABELS := {"head": "Chefe de governo", "opposition": "Líder da oposição", "parliament": "Parlamento", "court": "Corte constitucional"}
# i18n-end
const ROLE_ACTIONS := {
	"head": ["create", "edit", "present", "veto", "promulgate", "publish", "revoke", "admin"],
	"opposition": ["create", "edit", "present"],
	"parliament": ["analyze", "vote", "approve", "promulgate"],
	"court": ["analyze"],
}
const PROTECTED_RIGHTS := ["expressao", "voto", "associacao", "propriedade"]
## Weight of each right in approval and stability. Authoritarians gain stability by restricting.
const RIGHT_APPROVAL := 0.006
const RIGHT_STABILITY := 0.004
# i18n-begin
const AMENDMENT_OPS := {"alter": "Alteração", "add": "Acréscimo", "suppress": "Supressão", "replace": "Substituição"}
# i18n-end
# i18n-begin
const ADD_KINDS := {"artigo": "Artigo", "paragrafo": "Parágrafo", "inciso": "Inciso", "transitoria": "Disposição transitória"}
# i18n-end

var iso := ""
var norms := {}
var next_id := 2
var constitution := {}
var standing := {"rights": {}, "minwage": {}, "posts": {}, "institutions": {}, "subsidies": {}, "spends": {}, "duties": {}, "restrictions": {}, "requirements": {}, "exceptions": {}, "penalties": {}, "deadlines": {}, "exemptions": {}, "caps": {}, "budget_locks": {}, "ministry_ops": {}, "codes": {}}
var licenses := {}
var registry := {"registered": 0.0, "status": {}}
var obligations: Array = []
var pending: Array = []
var variables := {}
var audit: Array = []
var fired := {}
## Only for old tests of the Divisions tab: new units take effect right away.
static var skip_unit_approval := false
var next_ministry_seq := 1
var failures := {}
var revenue_ring: Array = []
var spend_ring: Array = []
var last_war := false
var rng_state := 0
var rng_seed := 0
## Goes up with every change, so the interface knows when to redraw.
var revision := 0
var _rng := RandomNumberGenerator.new()
## The world, so the compiler can look up the country's companies (privatize and nationalize).
var _world: WeakRef


func setup(world: GameWorld) -> void:
	var c := world.player
	iso = c.iso
	_world = weakref(world)
	_rng.seed = hash("legislacao" + c.iso)
	constitution = _seed_constitution(c, world.politics.data_of(c.iso))
	norms = {}
	norms[1] = {
		"id": 1, "type": "constituicao", "number": 1, "year": world.start_year, "title": tr("Constituição de %s") % c.name,
		"ementa": tr("Estrutura fundamental do Estado."), "author": tr("Assembleia Constituinte"), "organ": tr("Assembleia Constituinte"),
		"dates": {"published": world.date_string(), "in_force": world.date_string()}, "state": STATE_IN_FORCE, "program": LawProgram.empty(),
		"versions": [], "current_v": 0, "votes": [], "process": {}, "history": [],
	}
	_seed_codes(world)
	revision += 1


## Each legal code with an initial text becomes a complementary law in force from the start of the match.
## Without its own Tax Code, the old one stays, made only of tax rates.
func _seed_codes(world: GameWorld) -> void:
	var has_tax := false
	for code: LawCode in LawCodes.all():
		var program := code.seed_program(world, world.player)
		if program.is_empty():
			continue
		var norm := new_norm(world, code.norm_type, "Parlamento")  # i18n
		norm.by_player = false
		norm.title = code.title
		norm.ementa = code.summary
		norm["base_code"] = true
		norm["code"] = code.id
		norm.program = program
		var compiled := LawCompiler.compile(program, compile_context(code.norm_type))
		norm.versions.append(_make_version(world, program, compiled, tr("Texto original")))
		norm.current_v = 0
		norm.state = STATE_IN_FORCE
		norm.dates["published"] = world.date_string()
		norm.dates["in_force"] = world.date_string()
		# The text already applies: what the code keeps in force (brackets, rates...) is recorded right away.
		fire(world, "ev_enact", {"only": norm.id})
		has_tax = has_tax or code.id == "tributario"
	if not has_tax:
		_seed_tax_code(world)


## The norm in force of a code ("tributario", "penal"...), or empty.
func code_norm(id: String) -> Dictionary:
	for norm: Dictionary in norms.values():
		if String(norm.get("code", "")) == id and norm.state == STATE_IN_FORCE:
			return norm
	return {}


## The code of a norm, or that of the norm it amends; "" if it is not a code.
func norm_code_of(norm: Dictionary) -> String:
	if String(norm.get("code", "")) != "":
		return String(norm.code)
	return String(norms.get(int(norm.get("amends", -1)), {}).get("code", ""))


## Draft that amends a code in force (or creates it, if the country does not have one yet), for the block editor.
func start_code_bill(world: GameWorld, id: String) -> Dictionary:
	var target := code_norm(id)
	if not target.is_empty():
		return start_change(world, target)
	var code := LawCodes.get_code(id)
	if code == null:
		return {}
	var norm := new_norm(world, code.norm_type)
	norm.program = code.seed_program(world, world.player)
	if norm.program.is_empty():
		norm.program = LawProgram.empty()
	norm.title = code.title
	norm.ementa = code.summary
	norm["code"] = id
	return norm


## The taxes at the start of the match are already law: changing them is amending or replacing this norm.
func _seed_tax_code(world: GameWorld) -> void:
	# Title, summary and body stay in Portuguese, like those of the codes: the screen translates.
	var norm := new_norm(world, "ordinaria", "Parlamento")  # i18n
	norm.by_player = false
	norm.title = "Código Tributário"  # i18n
	norm.ementa = "Define as alíquotas de renda, consumo, empresas e importação."  # i18n
	norm["base_code"] = true
	norm.program = tax_program(world)
	var compiled := LawCompiler.compile(norm.program, compile_context("ordinaria"))
	norm.versions.append(_make_version(world, norm.program, compiled, tr("Texto original")))
	norm.current_v = 0
	norm.state = STATE_IN_FORCE
	norm.dates["published"] = world.date_string()
	norm.dates["in_force"] = world.date_string()


## Program with the tax rates in force: starting point of any change to taxes.
func tax_program(world: GameWorld) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	for field: String in TAX_FIELDS:
		var block := LawProgram.new_block(program, "ec_rate")
		block.fields.field = field
		block.fields.value = snappedf(float(world.player.get(field)) * 100.0, 0.01)
		stack.blocks.append(block)
	return program


## Draft tax law, to open straight in the block editor.
func start_tax_bill(world: GameWorld) -> Dictionary:
	if not code_norm("tributario").is_empty():
		return start_code_bill(world, "tributario")
	var norm := new_norm(world, "ordinaria")
	norm.program = tax_program(world)
	norm.title = tr("Reforma tributária")
	norm.ementa = tr("Altera as alíquotas dos tributos.")
	return norm


# --- Constitution --------------------------------------------------------------------

func _seed_constitution(c: Country, data: Dictionary) -> Dictionary:
	var rule := Elections.rules(c, data)
	var free := c.dem >= 6.0
	var open := c.dem >= 4.0
	var articles := [
		_article("Art. 1º", "%s é um Estado soberano, organizado em governo, parlamento e tribunais.", "", c.iso, true),  # i18n
		_article("Art. 2º", "Os poderes são independentes e harmônicos entre si." if open else "O chefe de governo dirige o Estado e responde por todos os poderes.", "", null, free),  # i18n
		_article("Art. 3º", "São garantidos os direitos: {v}.", "rights", PROTECTED_RIGHTS.duplicate() if free else (["propriedade"] if not open else ["voto", "propriedade"]), free),  # i18n
		_article("Art. 4º", "O mandato do chefe de governo terá duração de {v} anos.", "mandate", 4, false),  # i18n
		_article("Art. 5º", "O parlamento terá duas casas: {v}.", "bicameral", free and c.pop >= 50.0, false),  # i18n
		_article("Art. 6º", "O chefe de governo poderá vetar projetos aprovados: {v}.", "veto", open, false),  # i18n
		_article("Art. 7º", "O veto só cai com {v}% dos votos do parlamento.", "override_pct", 50, false),  # i18n
		_article("Art. 8º", "O chefe de governo poderá editar decreto autônomo: {v}.", "autonomous_decree", not free, false),  # i18n
		_article("Art. 9º", "A corte constitucional controla a validade das normas: {v}.", "judicial_review", open, false),  # i18n
		_article("Art. 10.", "A oposição poderá apresentar projetos: {v}.", "opposition_present", open, false),  # i18n
		_article("Art. 11.", "Emendas exigem apoio inicial de {v}% dos assentos.", "amend_proposers", 33 if free else 20, false),  # i18n
		_article("Art. 12.", "Emendas exigem {v}% dos votos do parlamento.", "amend_quorum", 60, false),  # i18n
		_article("Art. 13.", "Emendas passam por {v} votações.", "amend_votes", 2 if free else 1, false),  # i18n
		_article("Art. 14.", "Entre as votações de uma emenda haverá intervalo de {v} dias.", "amend_interval", 10 if free else 0, false),  # i18n
		_article("Art. 15.", "A Constituição não será emendada em tempo de guerra: {v}.", "amend_no_war", free, false),  # i18n
		_article("Art. 16.", "Tramitarão ao mesmo tempo, no máximo, {v} emendas.", "amend_max", 2, false),  # i18n
		_article("Art. 17.", "O banco central é independente do governo: {v}.", "cb_independent", c.cb_independent, false),  # i18n
		_article("Art. 18.", "O parlamento é eleito pelo sistema: {v}.", "electoral_system", String(rule.system), false),  # i18n
		_article("Art. 19.", "O regime de governo é: {v}.", "head_system", String(rule.head), false),  # i18n
		_article("Art. 20.", "Partidos abaixo de {v}% dos votos não entram por lista.", "threshold", roundi(float(rule.threshold) * 100.0), false),  # i18n
	]
	return {
		"articles": articles, "next_article": 100, "version": 0, "next_emenda": 1,
		"versions": [{"n": 0, "emenda": 0, "date": tr("Texto original"), "articles": articles.duplicate(true), "changes": [], "approvers": tr("Assembleia Constituinte"), "votes": []}],
	}


func _article(label: String, template: String, param: String, value: Variant, petrea: bool) -> Dictionary:
	var a := {"id": 0, "label": label, "template": template, "param": param, "value": value, "petrea": petrea, "kind": "artigo"}
	a.id = hash(label)
	a["text"] = article_text(a)
	return a


## The stored text stays in Portuguese; with localized, it comes out in the game's language (for the screen).
static func article_text(a: Dictionary, localized := false) -> String:
	var template: String = a.get("template", "")
	var label: String = a.label
	if localized:
		template = TranslationServer.translate(template)
		label = TranslationServer.translate(label)
	if String(a.get("param", "")) == "":
		# Art. 1: the value is the country code, so the name comes out in the right language.
		if a.get("value") is String and "%s" in template:
			var country := GameData.country_name_pt(a.value)
			return template % (TranslationServer.translate(country) if localized else country)
		return template
	var value := _value_text(a.value, localized)
	return "%s %s" % [label, template.replace("{v}", value)] if not template.begins_with(label) else template.replace("{v}", value)


static func _value_text(value: Variant, localized := false) -> String:
	if value is String:
		return Lang.tr_if(String(Elections.SYSTEMS.get(value, Elections.HEADS.get(value, value))), localized)
	if value is bool:
		return Lang.tr_if("sim", localized) if value else Lang.tr_if("não", localized)
	if value is Array:
		var names := []
		for r: String in value:
			names.append(Lang.tr_if(String(LawCatalog.CHOICES.right.get(r, r)), localized))
		return ", ".join(names) if not names.is_empty() else Lang.tr_if("nenhum", localized)
	return str(int(value)) if value is float or value is int else str(value)


func param(key: String, fallback: Variant = null) -> Variant:
	for a: Dictionary in constitution.get("articles", []):
		if a.get("param", "") == key:
			if not a.get("suppressed", false):
				return a.value
			# A suppressed power or right ceases to exist; a suppressed number goes back to the default.
			if a.value is bool:
				return false
			return [] if a.value is Array else fallback
	return fallback


func mandate_years() -> float:
	return float(param("mandate", 4))


func article_by_id(id: int) -> Dictionary:
	for a: Dictionary in constitution.articles:
		if int(a.id) == id:
			return a
	return {}


## Word-by-word comparison, in BBCode: what left in struck-through red and what came in green.
static func word_diff(before: String, after: String) -> String:
	var a := before.split(" ", false)
	var b := after.split(" ", false)
	var table := []
	for i in a.size() + 1:
		var row := PackedInt32Array()
		row.resize(b.size() + 1)
		table.append(row)
	for i in range(a.size() - 1, -1, -1):
		for j in range(b.size() - 1, -1, -1):
			table[i][j] = table[i + 1][j + 1] + 1 if a[i] == b[j] else maxi(table[i + 1][j], table[i][j + 1])
	var out := []
	var i := 0
	var j := 0
	while i < a.size() or j < b.size():
		if i < a.size() and j < b.size() and a[i] == b[j]:
			out.append(a[i])
			i += 1
			j += 1
		elif j < b.size() and (i >= a.size() or table[i][j + 1] >= table[i + 1][j]):
			out.append("[color=#4cc794]%s[/color]" % b[j])
			j += 1
		else:
			out.append("[color=#ec5a43][s]%s[/s][/color]" % a[i])
			i += 1
	return " ".join(out)


# --- Permissions ------------------------------------------------------------------------

func role(world: GameWorld) -> String:
	return "head" if world.in_office else "opposition"


func can(world: GameWorld, action: String, type := "") -> bool:
	var who := role(world)
	if not action in ROLE_ACTIONS[who]:
		return false
	if type == "" or not NORM_TYPES.has(type):
		return true
	if action == "present":
		if not who in NORM_TYPES[type].needs:
			return false
		if who == "opposition" and not param("opposition_present", true):
			return false
		if type == "decreto_autonomo" and not param("autonomous_decree", false):
			return false
	return true


## Who can do what, according to the Constitution in force. The Institutions screen shows this table.
func permission_table() -> Dictionary:
	var out := {}
	for who: String in ROLE_ACTIONS:
		var row := {}
		for action: String in ACTIONS:
			row[action] = action in ROLE_ACTIONS[who]
		out[who] = row
	if not param("veto", true):
		out.head.veto = false
	if not param("opposition_present", true):
		out.opposition.present = false
	if not param("judicial_review", true):
		out.court.analyze = false
	return out


# --- Norm maintenance ---------------------------------------------------------------

func new_norm(world: GameWorld, type: String, author := "") -> Dictionary:
	var norm := {
		"id": next_id, "type": type, "number": next_id, "year": world.year, "title": "", "ementa": "",
		"author": author if author != "" else String(world.leader.get("name", tr("Jogador"))), "by_player": author == "",
		"organ": String(NORM_TYPES[type].organ), "dates": {}, "state": STATE_DRAFT, "program": LawProgram.empty(), "vacatio": 0, "expires": "",
		"versions": [], "current_v": -1, "votes": [], "process": {}, "history": [], "amends": -1, "revokes": {}, "ops": [],
	}
	next_id += 1
	norms[norm.id] = norm
	_log(world, norm, "Criação", "", norm.title, tr("Rascunho criado"), norm.author)  # i18n
	revision += 1
	return norm


func delete_draft(id: int) -> void:
	if norms.has(id) and norms[id].state == STATE_DRAFT:
		norms.erase(id)
		revision += 1


func norm_label(norm: Dictionary) -> String:
	return tr("%s nº %d/%d") % [tr(NORM_TYPES[norm.type].short), int(norm.number), int(norm.year)]


func list_norms(state_filter := "") -> Array:
	var out := norms.values().filter(func(n): return state_filter == "" or n.state == state_filter)
	out.sort_custom(func(a, b): return int(a.id) > int(b.id))
	return out


func in_process() -> Array:
	return norms.values().filter(func(n): return n.state == STATE_PROCESS or n.state == STATE_APPROVED or n.state == STATE_AWAITING or n.state == STATE_PUBLISHED)


func compile_context(type: String) -> Dictionary:
	var numbers := {}
	for id: int in norms:
		numbers[id] = true
	var institutions := {}
	for key: String in standing.institutions:
		institutions[key] = true
	var ministries := {}
	for op: Dictionary in ministry_ops():
		if op.op != "abolish":
			ministries[String(op.get("name", ""))] = true
	for p: Dictionary in Politics.PORTFOLIOS:
		ministries[String(p.label)] = true
	var context := {"rank": int(NORM_TYPES[type].rank), "norms": numbers, "institutions": institutions, "ministries": ministries}
	var world: GameWorld = _world.get_ref() if _world else null
	if world:
		context["companies"] = world.corporate.state_shares(iso)
	return context


func compile_norm(norm: Dictionary) -> Dictionary:
	var result := LawCompiler.compile(norm.program, compile_context(norm.type))
	result.warnings.append_array(find_conflicts(norm))
	return result


## Clashes with other norms in force. They only warn: priority decides at execution time.
func find_conflicts(norm: Dictionary) -> Array:
	var mine := _claims(norm.program)
	var out := []
	for other: Dictionary in norms.values():
		if other.id == norm.id or other.state != STATE_IN_FORCE or other.id == norm.get("amends", -1) or other.get("base_code", false):
			continue
		var theirs := _claims(_current_program(other))
		for key: String in mine:
			if theirs.has(key):
				var low: bool = int(NORM_TYPES[other.type].rank) > int(NORM_TYPES[norm.type].rank)
				out.append({"block": -1, "text": tr("Conflito com %s sobre %s: %s.") % [norm_label(other), theirs[key], tr("a outra norma prevalece por ter hierarquia maior") if low else tr("vale a hierarquia, a especialidade e a data de vigência")]})
	# Right protected by the Constitution.
	for block: Dictionary in LawProgram.all_blocks(norm.program):
		if block.type in ["rg_remove", "dr_suspend"] and block.fields.get("right") in param("rights", []):
			out.append({"block": int(block.id), "text": tr("A Constituição garante esse direito: a corte pode declarar a norma inválida.")})
	return out


func _claims(program: Dictionary) -> Dictionary:
	var out := {}
	for b: Dictionary in LawProgram.all_blocks(program):
		match b.type:
			"ec_rate", "ec_budget", "ac_param":
				out[String(b.fields.get("field"))] = LawProgram.block_text(b)
			"ec_minwage":
				out["minwage"] = tr("salário mínimo")
			"rg_grant", "rg_remove", "dr_right", "dr_suspend":
				out["right:" + String(b.fields.get("right"))] = tr("o direito %s") % LawProgram.field_text(b, "right")
	return out


func _current_program(norm: Dictionary) -> Dictionary:
	if norm.versions.is_empty():
		return norm.program
	return norm.versions[int(norm.current_v)].program


## Priority: hierarchy, then specialty (how many conditions), then the most recent effective date.
func _priority(norm: Dictionary, article: Dictionary) -> float:
	return float(NORM_TYPES[norm.type].rank) * 1e7 + float(article.get("conditions", 0)) * 1e5 + float(norm.get("force_day", 0))


# --- Procedure --------------------------------------------------------------------------

func _steps_for(norm: Dictionary) -> Array:
	var def: Dictionary = NORM_TYPES[norm.type]
	if norm.has("payload"):
		var quick := ["present", "discussion", "vote"]
		if param("bicameral", false):
			quick.append("vote_upper")
		if norm.get("plebiscite", false):
			quick.append("plebiscite")
		quick.append("publish")
		return quick
	if norm.type == "emenda":
		var out := ["present", "admissibility"]
		if param("judicial_review", true):
			out.append("constitutional")
		out.append_array(["discussion", "vote"])
		if int(param("amend_votes", 1)) >= 2:
			out.append_array(["interval", "vote_2"])
		out.append_array(["quorum", "promulgate", "publish", "apply"])
		return out
	if def.vote == "none":
		var out := ["sign"]
		if norm.type == "decreto_autonomo" and param("judicial_review", true):
			out.append("constitutional")
		out.append("publish")
		return out
	var out := ["present", "admissibility"]
	if param("judicial_review", true):
		out.append("constitutional")
	out.append_array(["discussion", "vote"])
	if param("bicameral", false) and def.rank >= 60:
		out.append("vote_upper")
	if norm.type == "plebiscito":
		out.append("plebiscite")
	if def.sanction and param("veto", true):
		out.append("sanction")
	out.append_array(["promulgate" if norm.type == "complementar" or not def.sanction else "publish"])
	if out[-1] == "promulgate":
		out.append("publish")
	return out


## Sends the norm to procedure, after compiling. A draft with an error does not leave the editor.
func present(world: GameWorld, norm: Dictionary) -> Dictionary:
	if not can(world, "present", norm.type):
		return {"ok": false, "msg": tr("%s não pode apresentar %s.") % [tr(ROLE_LABELS[role(world)]), tr(NORM_TYPES[norm.type].label)]}
	if String(norm.title).strip_edges() == "" or String(norm.ementa).strip_edges() == "":
		return {"ok": false, "msg": tr("Preencha o título e a ementa da norma.")}
	if norm.type == "emenda":
		var check := check_amendment(world, norm)
		if not check.ok:
			return check
		if not norm.program.stacks.is_empty() and not compile_norm(norm).ok:
			return {"ok": false, "msg": tr("Os blocos da emenda têm erros: corrija antes de apresentar.")}
	else:
		var compiled := compile_norm(norm)
		if not compiled.ok:
			return {"ok": false, "msg": tr("A norma tem %d erro(s): corrija antes de apresentar.") % compiled.errors.size()}
	var position := position_for(world, norm)
	norm["position"] = position
	norm["popularity"] = popularity_of(world, norm)
	norm.state = STATE_PROCESS
	norm.dates["presented"] = world.date_string()
	norm.process = {"steps": _steps_for(norm), "at": 0, "due": world.day_index + _days_of("present"), "log": []}
	_log(world, norm, "Apresentação", "", norm_label(norm), tr("Entrou em tramitação"), norm.author)  # i18n
	world.emit_news(tr("%s: %s entra em tramitação.") % [norm_label(norm), norm.title], "politica", world.player)
	revision += 1
	return {"ok": true, "msg": tr("%s apresentada.") % norm_label(norm)}


## Finished project or budget: no blocks, but the same rite in parliament.
func present_payload(world: GameWorld, payload: Dictionary, title: String, ementa: String, position: Dictionary, plebiscite := false) -> Dictionary:
	var norm := new_norm(world, "ordinaria")
	norm["payload"] = payload
	norm["plebiscite"] = plebiscite
	norm.title = title
	norm.ementa = ementa
	norm["position"] = position
	norm["popularity"] = popularity_of(world, norm)
	norm.state = STATE_PROCESS
	norm.dates["presented"] = world.date_string()
	norm.process = {"steps": _steps_for(norm), "at": 0, "due": world.day_index + _days_of("present"), "log": []}
	_log(world, norm, "Apresentação", "", norm_label(norm), tr("Entrou em tramitação"), norm.author)  # i18n
	world.emit_news(tr("%s: %s vai ao parlamento.") % [norm_label(norm), title], "politica", world.player)
	revision += 1
	return {"ok": true, "pending": true, "norm": norm, "msg": tr("%s foi ao parlamento: o rito leva cerca de %d dias.") % [title, _total_days(norm)]}


## In a democratic country, a new unit goes through parliament and a plebiscite. The outline was already validated.
func units_need_approval(world: GameWorld) -> bool:
	return not skip_unit_approval and world.player.dem >= Politics.FREE_PARLIAMENT_DEM


func present_unit(world: GameWorld, payload: Dictionary, title: String) -> Dictionary:
	return present_payload(world, payload, title, tr("Criação de unidade: vale se o parlamento e o plebiscito aprovarem."), {"econ": 0.0, "social": 0.0}, true)


func _total_days(norm: Dictionary) -> int:
	var total := 0
	for step: String in norm.process.steps:
		total += _days_of(step)
	return total


## Whoever was in government loses the projects they left: the new government does not defend them.
func drop_government_bills(world: GameWorld) -> void:
	for norm: Dictionary in in_process():
		if norm.has("payload"):
			_fail(world, norm, STATE_REJECTED, tr("arquivado com a queda do governo."))


func _days_of(step: String) -> int:
	if step == "interval":
		return int(param("amend_interval", 0))
	if step == "vote_2":
		return int(STEP_DAYS.vote)
	return int(STEP_DAYS.get(step, 1))


func step_day(world: GameWorld) -> void:
	if world.player == null or iso == "":
		return
	for norm: Dictionary in norms.values():
		_advance_norm(world, norm)
	_check_expiry(world)
	_run_pending(world)
	_run_due_obligations(world)
	_fire_dates(world)
	var at_war := world.diplomacy.in_war(world.player.idx)
	if at_war and not last_war:
		fire(world, "ev_war")
	last_war = at_war


func _advance_norm(world: GameWorld, norm: Dictionary) -> void:
	var state: String = norm.state
	if state == STATE_PROCESS or state == STATE_APPROVED or state == STATE_AWAITING:
		var process: Dictionary = norm.process
		if world.day_index < int(process.due) or process.get("waiting_player", false) and world.day_index < int(process.get("tacit", 0)):
			return
		if process.get("waiting_player", false):
			process.erase("waiting_player")
			_record_step(world, norm, "sanction", tr("Sanção tácita: o prazo acabou sem veto."), ROLE_LABELS.head)
			_next_step(world, norm)
			return
		_run_step(world, norm)
	elif state == STATE_PUBLISHED and world.day_index >= int(norm.get("force_due", 0)):
		_enter_force(world, norm)


func _record_step(world: GameWorld, norm: Dictionary, step: String, result: String, who: String) -> void:
	norm.process.log.append({"step": step, "label": STEP_LABELS.get(step, step), "result": result, "by": who, "date": world.date_string()})
	_log(world, norm, STEP_LABELS.get(step, step), "", "", result, who)
	revision += 1


func _next_step(world: GameWorld, norm: Dictionary) -> void:
	var process: Dictionary = norm.process
	process.at = int(process.at) + 1
	if int(process.at) >= process.steps.size():
		return
	process.due = world.day_index + _days_of(process.steps[int(process.at)])


func _fail(world: GameWorld, norm: Dictionary, state: String, why: String) -> void:
	norm.state = state
	if norm.get("payload", {}).get("kind", "") == "treaty":
		world.treaties.on_player_ratification(world, int(norm.payload.treaty), false)
	world.emit_news("%s: %s" % [norm_label(norm), why], "politica", world.player)
	revision += 1


func _run_step(world: GameWorld, norm: Dictionary) -> void:
	var process: Dictionary = norm.process
	var step: String = process.steps[int(process.at)]
	match step:
		"present":
			_record_step(world, norm, step, tr("Protocolada em %s.") % tr(norm.organ), tr("Mesa do parlamento"))
		"sign":
			_record_step(world, norm, step, tr("Assinada por %s.") % norm.author, tr(norm.organ))
		"admissibility":
			var why := _admissibility(world, norm)
			if why != "":
				_record_step(world, norm, step, tr("Inadmitida: %s") % why, tr("Comissão de Justiça"))
				_fail(world, norm, STATE_REJECTED, tr("inadmitida. %s") % why)
				return
			_record_step(world, norm, step, tr("Admitida."), tr("Comissão de Justiça"))
		"constitutional":
			var problem := _court_problem(norm)
			if problem != "" and _court_acts(world):
				_record_step(world, norm, step, tr("Inconstitucional: %s") % problem, ROLE_LABELS.court)
				_fail(world, norm, STATE_INVALID, tr("declarada inválida pela corte. %s") % problem)
				return
			_record_step(world, norm, step, tr("Sem impedimento.") if problem == "" else tr("Dúvida arquivada: %s") % problem, ROLE_LABELS.court)
		"discussion":
			_record_step(world, norm, step, tr("Debate encerrado."), tr("Parlamento"))
		"vote", "vote_2", "vote_upper":
			var result := roll_call(world, norm, step == "vote_upper", _required_share(norm))
			result["step"] = step
			result["date"] = world.date_string()
			norm.votes.append(result)
			var text := tr("%d a %d (precisava de %d).") % [int(result.yes), int(result.no), int(result.needed)]
			if not result.passed:
				_record_step(world, norm, step, tr("Rejeitada por %s") % text, tr("Parlamento"))
				_fail(world, norm, STATE_REJECTED, tr("rejeitada por %s") % text)
				return
			_record_step(world, norm, step, tr("Aprovada por %s") % text, tr("Parlamento"))
			norm.dates["approved"] = world.date_string()
		"plebiscite":
			var result := _hold_plebiscite(world, norm)
			var plebiscite_text := tr("Sim %d%%, não %d%%, com %d%% de comparecimento.") % [roundi(float(result.yes) * 100.0), roundi((1.0 - float(result.yes)) * 100.0), roundi(float(result.turnout) * 100.0)]
			if float(result.yes) <= 0.5:
				_record_step(world, norm, step, tr("Rejeitado nas urnas. %s") % plebiscite_text, tr("Eleitorado"))
				_fail(world, norm, STATE_REJECTED, tr("rejeitado em plebiscito. %s") % plebiscite_text)
				return
			_record_step(world, norm, step, tr("Aprovado nas urnas. %s") % plebiscite_text, tr("Eleitorado"))
			world.emit_news(tr("%s: aprovado em plebiscito. %s") % [norm_label(norm), plebiscite_text], "politica", world.player)
		"interval":
			_record_step(world, norm, step, tr("Intervalo cumprido."), tr("Mesa do parlamento"))
		"quorum":
			var last: Dictionary = norm.votes[-1]
			if int(last.yes) < ceili(float(last.total) * float(param("amend_quorum", 60)) / 100.0):
				_record_step(world, norm, step, tr("Quórum insuficiente."), tr("Mesa do parlamento"))
				_fail(world, norm, STATE_REJECTED, tr("sem o quórum qualificado."))
				return
			_record_step(world, norm, step, tr("Quórum qualificado alcançado."), tr("Mesa do parlamento"))
			norm.state = STATE_APPROVED
		"sanction":
			norm.state = STATE_APPROVED
			if _run_sanction(world, norm):
				return
		"override":
			var result := roll_call(world, norm, false, float(param("override_pct", 50)) / 100.0, true)
			result["step"] = step
			result["date"] = world.date_string()
			norm.votes.append(result)
			if not result.passed:
				_record_step(world, norm, step, tr("Veto mantido: %d de %d votos.") % [int(result.yes), int(result.needed)], tr("Parlamento"))
				_fail(world, norm, STATE_REJECTED, tr("o veto foi mantido."))
				return
			_record_step(world, norm, step, tr("Veto derrubado por %d votos.") % int(result.yes), tr("Parlamento"))
		"promulgate":
			norm.dates["promulgated"] = world.date_string()
			_record_step(world, norm, step, tr("Promulgada."), tr("Presidência do parlamento") if norm.type == "emenda" else ROLE_LABELS.head)
			norm.state = STATE_AWAITING
		"publish":
			_publish(world, norm)
			if norm.type != "emenda":
				return
		"apply":
			_apply_amendment(world, norm)
			return
	_next_step(world, norm)


## true: the sanction stayed with the player or became a veto, so the next stage does not advance now.
func _run_sanction(world: GameWorld, norm: Dictionary) -> bool:
	if world.in_office:
		if norm.get("by_player", false):
			_record_step(world, norm, "sanction", tr("Sancionada pelo autor."), ROLE_LABELS.head)
			return false
		norm.process["waiting_player"] = true
		norm.process["tacit"] = world.day_index + TACIT_SANCTION_DAYS
		world.emit_news(tr("%s aprovada: você tem %d dias para sancionar ou vetar.") % [norm_label(norm), TACIT_SANCTION_DAYS], "politica", world.player)
		revision += 1
		return true
	var ruling: Dictionary = world.politics.ruling_party(iso)
	var veto: bool = Politics.distance(ruling, norm.position) > Politics.COALITION_REBEL_DISTANCE * 0.7
	if veto:
		_record_step(world, norm, "sanction", tr("Vetada pelo governo."), String(world.politics.leader_of(iso).get("name", ROLE_LABELS.head)))
		_insert_override(world, norm)
		return true
	_record_step(world, norm, "sanction", tr("Sancionada pelo governo."), String(world.politics.leader_of(iso).get("name", ROLE_LABELS.head)))
	return false


func _insert_override(world: GameWorld, norm: Dictionary) -> void:
	var process: Dictionary = norm.process
	process.steps.insert(int(process.at) + 1, "override")
	_next_step(world, norm)


## The player in government decides on a project that is not theirs.
func sanction(world: GameWorld, norm: Dictionary, approve: bool) -> Dictionary:
	if not norm.process.get("waiting_player", false):
		return {"ok": false, "msg": tr("Esse projeto não aguarda sanção.")}
	if not can(world, "veto"):
		return {"ok": false, "msg": tr("Só o chefe de governo sanciona ou veta.")}
	norm.process.erase("waiting_player")
	var who: String = String(world.leader.get("name", ROLE_LABELS.head))
	if approve:
		_record_step(world, norm, "sanction", tr("Sancionada."), who)
		_next_step(world, norm)
		return {"ok": true, "msg": tr("%s sancionada.") % norm_label(norm)}
	_record_step(world, norm, "sanction", tr("Vetada."), who)
	_insert_override(world, norm)
	return {"ok": true, "msg": tr("%s vetada: o parlamento pode derrubar o veto.") % norm_label(norm)}


func _required_share(norm: Dictionary) -> float:
	if float(norm.get("payload", {}).get("share", 0.0)) > 0.0:
		return float(norm.payload.share)
	match String(NORM_TYPES[norm.type].vote):
		"simple": return 0.41
		"absolute": return 0.0
		"qualified": return 0.6
		"amendment": return float(param("amend_quorum", 60)) / 100.0
	return 0.0


## Decision factors: ideology, discipline of those who govern, popularity and state of the accounts.
func _party_votes_yes(world: GameWorld, party: Dictionary, norm: Dictionary, against_veto: bool) -> bool:
	var data: Dictionary = world.politics.data_of(iso)
	var position: Dictionary = norm.position
	var deals: Dictionary = norm.get("deals", {})
	if deals.has(str(party.id)):
		return deals[str(party.id)]
	var limit := Politics.OPPOSITION_SUPPORT_DISTANCE
	var by_player: bool = norm.get("by_player", false)
	var government_bill: bool = world.in_office if by_player else int(norm.get("author_party", -1)) in data.coalition
	var in_gov: bool = party.id in data.coalition
	if int(party.id) == int(data.player_party) and by_player:
		return true
	if int(party.id) == int(norm.get("author_party", -1)):
		return true
	if government_bill and in_gov and not against_veto:
		limit = Politics.COALITION_REBEL_DISTANCE
	elif not government_bill and in_gov:
		limit = Politics.OPPOSITION_SUPPORT_DISTANCE * 0.7
	limit += (world.player.approval - 0.46) * 0.5 if in_gov else -(world.player.approval - 0.46) * 0.3
	if float(position.econ) < 0.0 and world.player.debt_ratio > world.player.debt_tol:
		limit -= 0.15
	return Politics.distance(party, position) <= limit


func roll_call(world: GameWorld, norm: Dictionary, upper := false, share := 0.0, against_veto := false) -> Dictionary:
	var data: Dictionary = world.politics.data_of(iso)
	var parties: Array = Politics.upper_house(data) if upper else data.parties
	var total: int = Politics._count_seats(parties)
	var yes := 0
	var tally := []
	for party: Dictionary in parties:
		var seats: int = party.seats
		if seats == 0:
			continue
		var rebels := roundi(seats * _rng.randf_range(0.0, 0.08))
		var party_yes: int = seats - rebels if _party_votes_yes(world, party, norm, against_veto) else rebels
		yes += party_yes
		tally.append({"party": party.short, "yes": party_yes, "no": seats - party_yes})
	var needed: int = ceili(float(total) * share) if share > 0.0 else total / 2 + 1
	return {"passed": yes >= needed, "yes": yes, "no": total - yes, "needed": needed, "total": total, "tally": tally, "house": tr("Senado") if upper else (tr("Câmara") if param("bicameral", false) else tr("Parlamento"))}


# --- Vote negotiation ----------------------------------------------------------------

## Is there still a vote ahead? Only then is it worth negotiating.
func can_negotiate(norm: Dictionary) -> bool:
	if not norm.state in [STATE_PROCESS, STATE_APPROVED] or norm.process.is_empty():
		return false
	for step: String in norm.process.steps.slice(int(norm.process.at)):
		if step in ["vote", "vote_2", "vote_upper", "override"]:
			return true
	return false


func deal_price(world: GameWorld, party: Dictionary, generous: bool) -> float:
	var total := maxf(float(world.politics.data_of(iso).seats_total), 1.0)
	var price: float = world.politics.fund_unit(world) * (DEAL_BASE_PRICE + DEAL_SEAT_PRICE * float(party.seats) / total)
	return price * (2.0 if generous else 1.0)


## Chance of the party accepting. Whoever already tends to vote that way accepts easily; turning a vote is harder,
## the more so the further the proposal is from what the party defends.
func deal_chance(world: GameWorld, norm: Dictionary, party: Dictionary, want_yes: bool, bonus: float) -> float:
	var position := position_for(world, norm)
	var gap := Politics.distance(party, position)
	var probe := {"position": position, "by_player": norm.get("by_player", false), "author_party": norm.get("author_party", -1)}
	if _party_votes_yes(world, party, probe, false) == want_yes:
		return 0.95
	var resistance := gap if want_yes else maxf(1.5 - gap, 0.0)
	return clampf(0.75 - resistance * 0.4 + bonus, 0.05, 0.95)


## Asks a caucus for its vote in exchange for fund money. Refusal costs nothing, but ends the conversation
## with that party about this proposal. The player's own caucus follows the guidance for free.
func negotiate(world: GameWorld, norm: Dictionary, party_id: int, want_yes: bool, generous := false) -> Dictionary:
	if not can_negotiate(norm):
		return {"ok": false, "msg": tr("Não há mais votação a negociar nesta proposta.")}
	var data: Dictionary = world.politics.data_of(iso)
	var party: Dictionary = Politics._find(data, party_id)
	if party.is_empty():
		return {"ok": false, "msg": tr("Esse partido não existe.")}
	var who: String = String(world.leader.get("name", tr("Jogador")))
	var deals: Dictionary = norm.get_or_add("deals", {})
	if party_id == int(data.player_party):
		deals[str(party_id)] = want_yes
		revision += 1
		return {"ok": true, "accepted": true, "msg": tr("Sua bancada foi orientada a votar %s.") % (tr("a favor") if want_yes else tr("contra"))}
	var asked: Dictionary = norm.get_or_add("asked", {})
	if asked.has(str(party_id)):
		return {"ok": false, "msg": tr("%s já deu a resposta sobre esta proposta.") % party.short}
	var price := deal_price(world, party, generous)
	var fund: float = world.politics.party_fund(world)
	if fund < price:
		return {"ok": false, "msg": tr("O acordo custa %s, e o fundo tem %s.") % [UiKit.millions(price), UiKit.millions(fund)]}
	asked[str(party_id)] = true
	var chance := deal_chance(world, norm, party, want_yes, DEAL_GENEROUS_BONUS if generous else 0.0)
	if _rng.randf() >= chance:
		_log(world, norm, "Negociação", "", "", tr("%s recusou votar %s") % [party.short, tr("a favor") if want_yes else tr("contra")], who)  # i18n
		revision += 1
		return {"ok": true, "accepted": false, "msg": tr("%s recusou. Nada foi pago.") % party.short}
	var mine: Dictionary = world.politics.player_party(world)
	mine.funds = float(mine.funds) - price
	deals[str(party_id)] = want_yes
	_log(world, norm, "Negociação", "", "", tr("%s fechou voto %s por %s") % [party.short, tr("a favor") if want_yes else tr("contra"), UiKit.millions(price)], who)  # i18n
	revision += 1
	return {"ok": true, "accepted": true, "msg": tr("%s vai votar %s. Pago: %s.") % [party.short, tr("a favor") if want_yes else tr("contra"), UiKit.millions(price)]}


## Offers entry into the government in exchange for the vote in favor. No cost to the fund, but the party starts demanding
## ministries like any ally.
func offer_post(world: GameWorld, norm: Dictionary, party_id: int) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": tr("Na oposição, você não tem cargos a oferecer.")}
	if not can_negotiate(norm):
		return {"ok": false, "msg": tr("Não há mais votação a negociar nesta proposta.")}
	var data: Dictionary = world.politics.data_of(iso)
	var party: Dictionary = Politics._find(data, party_id)
	if party.is_empty() or party_id in data.coalition:
		return {"ok": false, "msg": tr("Esse partido já está no governo.")}
	var asked: Dictionary = norm.get_or_add("asked", {})
	if asked.has(str(party_id)):
		return {"ok": false, "msg": tr("%s já deu a resposta sobre esta proposta.") % party.short}
	asked[str(party_id)] = true
	var who: String = String(world.leader.get("name", tr("Jogador")))
	if Politics.distance(Politics._find(data, data.ruling), party) > Politics.COALITION_MAX_DISTANCE or _rng.randf() >= deal_chance(world, norm, party, true, DEAL_POST_BONUS):
		_log(world, norm, "Negociação", "", "", tr("%s recusou entrar no governo") % party.short, who)  # i18n
		revision += 1
		return {"ok": true, "accepted": false, "msg": tr("%s recusou entrar no governo.") % party.short}
	data.coalition.append(party_id)
	norm.get_or_add("deals", {})[str(party_id)] = true
	world.politics.revision += 1
	_log(world, norm, "Negociação", "", "", tr("%s entrou no governo e votará a favor") % party.short, who)  # i18n
	revision += 1
	return {"ok": true, "accepted": true, "msg": tr("%s entra no governo e vota a favor. Lembre de dar um ministério ao novo aliado.") % party.short}


# --- Conversation with party leaders -----------------------------------------------------
# Informal request, no money: the party leader weighs ideas, affinity with your party and the
# law's popularity. The answer becomes a vote agreement (norm.deals), the same one the paid negotiation uses.

const CHAT_MIN_CHANCE := 0.03
const CHAT_MAX_CHANCE := 0.95


## How the party would vote today, with no agreement closed.
func chat_stance(world: GameWorld, norm: Dictionary, party: Dictionary) -> bool:
	var probe := {"position": norm.get("position", position_for(world, norm)), "by_player": norm.get("by_player", false), "author_party": norm.get("author_party", -1)}
	return _party_votes_yes(world, party, probe, false)


## How much the party weighs each thing when deciding to hear the request. Returns {chance, aff, pop, gap, aligned}.
func chat_factors(world: GameWorld, norm: Dictionary, party: Dictionary, want_yes: bool, bonus := 0.0) -> Dictionary:
	var aligned := chat_stance(world, norm, party) == want_yes
	var mine: Dictionary = world.politics.player_party(world)
	var aff := clampf(1.0 - Politics.distance(party, mine) / 2.8, 0.0, 1.0)
	var pop := popularity_of(world, norm)
	var gap := Politics.distance(party, norm.get("position", position_for(world, norm)))
	var chance := 0.95
	if not aligned:
		var pop_term := (pop - 0.5) * (0.6 if want_yes else -0.6)
		chance = deal_chance(world, norm, party, want_yes, 0.0) * 0.8 + pop_term + (aff - 0.5) * 0.3 + bonus + counterpart_bonus(world, norm, party, want_yes)
	return {"chance": clampf(chance, CHAT_MIN_CHANCE, CHAT_MAX_CHANCE), "aff": aff, "pop": pop, "gap": gap, "aligned": aligned}


## EXTENSION POINT: counterparts the player offers along with the request (posts, favors, party
## funds). Returns an addition to the request's chance. Today there is no counterpart: 0.
func counterpart_bonus(_world: GameWorld, _norm: Dictionary, _party: Dictionary, _want_yes: bool) -> float:
	return 0.0


func chat_closed(norm: Dictionary, party_id: int) -> bool:
	return norm.get("chat_asked", {}).has(str(party_id)) or norm.get("deals", {}).has(str(party_id)) or norm.get("asked", {}).has(str(party_id))


## Asks the party leader to support (want_yes) or vote against the law. Each party answers once per law.
## Returns {ok, accepted, msg, chance, aff, pop, gap, aligned}.
func chat_request(world: GameWorld, norm: Dictionary, party_id: int, want_yes: bool, bonus := 0.0) -> Dictionary:
	if not can_negotiate(norm):
		return {"ok": false, "msg": tr("Não há mais votação a negociar nesta proposta.")}
	var data: Dictionary = world.politics.data_of(iso)
	var party: Dictionary = Politics._find(data, party_id)
	if party.is_empty() or party_id == int(data.player_party):
		return {"ok": false, "msg": tr("Esse partido não existe.")}
	if chat_closed(norm, party_id):
		return {"ok": false, "msg": tr("%s já deu a resposta sobre esta proposta.") % party.short}
	var f := chat_factors(world, norm, party, want_yes, bonus)
	f["ok"] = true
	norm.get_or_add("chat_asked", {})[str(party_id)] = true
	var who: String = String(world.leader.get("name", tr("Jogador")))
	var word: String = tr("a favor") if want_yes else tr("contra")
	if _rng.randf() >= float(f.chance):
		_log(world, norm, "Conversa", "", "", tr("%s recusou votar %s") % [party.short, word], who)  # i18n
		revision += 1
		f["accepted"] = false
		f["msg"] = tr("%s recusou votar %s.") % [party.short, word]
		return f
	norm.get_or_add("deals", {})[str(party_id)] = want_yes
	_log(world, norm, "Conversa", "", "", tr("%s combinou votar %s") % [party.short, word], who)  # i18n
	revision += 1
	f["accepted"] = true
	f["msg"] = tr("%s vai votar %s.") % [party.short, word]
	return f


## Where the norm falls on the compass. Taxes count for what they change: cutting pulls right, raising pulls left.
func position_for(world: GameWorld, norm: Dictionary) -> Dictionary:
	if not norm.get("position", {}).is_empty():
		return norm.position
	var base := LawCompiler.position_of(norm.get("program", LawProgram.empty()))
	if norm.type == "emenda":
		base.social = clampf(float(base.social) + float(_amendment_position(norm).social), -1.0, 1.0)
		return base
	var adds := 0.0
	var change := change_of(norm)
	var blocks: Array = change.added
	var seen := 0
	if int(norm.get("amends", -1)) >= 0:
		# Amendment: what changes counts, not the whole text the draft copies.
		base = {"econ": 0.0, "social": 0.0}
		for pair: Array in [[change.added, 1.0], [change.removed, -1.0]]:
			for block: Dictionary in pair[0]:
				var def := LawCatalog.get_def(block.type)
				base.econ = float(base.econ) + float(def.get("econ", 0.0)) * pair[1]
				base.social = float(base.social) + float(def.get("social", 0.0)) * pair[1]
				if def.has("econ") or def.has("social"):
					seen += 1
		var scale := 1.0 / maxf(sqrt(float(seen)), 1.0)
		base.econ = clampf(float(base.econ) * scale, -1.0, 1.0)
		base.social = clampf(float(base.social) * scale, -1.0, 1.0)
		seen = 0
	for block: Dictionary in blocks:
		var def := LawCatalog.get_def(block.type)
		if def.has("econ") or def.has("social"):
			seen += 1
		if block.type == "ec_rate" and not block.plugs.has("value"):
			var delta := float(block.fields.get("value", 0.0)) / 100.0 - float(world.player.get(String(block.fields.get("field"))))
			adds += 0.3 - delta * 30.0
	base.econ = clampf(float(base.econ) + adds / maxf(sqrt(float(seen)), 1.0) + float(_code_effect(world, norm).get("econ", 0.0)), -1.0, 1.0)
	return base


## What the codes say about the project ("econ", "popularity"), for those that know how to measure the change it makes.
func _code_effect(world: GameWorld, norm: Dictionary) -> Dictionary:
	var out := {"econ": 0.0, "popularity": 0.0}
	for code: LawCode in LawCodes.all():
		if code.has_method("bill_effect"):
			var got: Dictionary = code.call("bill_effect", world, self, norm)
			for key: String in out:
				out[key] += float(got.get(key, 0.0))
	return out


## What the electorate thinks, from 0 to 1: the distance from the majority's ideas, what the norm takes from or gives to
## everyone's pocket and the mood about the government.
func popularity_of(world: GameWorld, norm: Dictionary) -> float:
	var c := world.player
	var data: Dictionary = world.politics.data_of(iso)
	var median := {"econ": 0.0, "social": 0.0}
	for party: Dictionary in data.parties:
		median.econ = float(median.econ) + float(party.econ) * float(party.support)
		median.social = float(median.social) + float(party.social) * float(party.support)
	var score := 0.56 - Politics.distance(position_for(world, norm), median) * 0.25
	var change := change_of(norm)
	for block: Dictionary in change.removed:
		score -= _popularity_weight(block.type)
	for block: Dictionary in change.added:
		score += _popularity_weight(block.type)
		if block.type == "ec_rate" and not block.plugs.has("value"):
			score -= (float(block.fields.get("value", 0.0)) / 100.0 - float(c.get(String(block.fields.get("field"))))) * 6.0
		elif block.type == "ec_budget" and not block.plugs.has("value"):
			score += (float(block.fields.get("value", 0.0)) / 100.0 - float(c.get(String(block.fields.get("field"))))) * 4.0
	score += float(_code_effect(world, norm).get("popularity", 0.0))
	var payload: Dictionary = norm.get("payload", {})
	if payload.get("kind", "") in ["new_unit", "split_unit"]:
		# Creating a unit usually pleases the region, and the rest of the country does not object much.
		score += 0.08
	if payload.get("kind", "") == "bill":
		score += float(Politics.bill(payload.id).get("approval", 0.0)) * 5.0
	for op: Dictionary in norm.get("ops", []):
		if String(article_by_id(int(op.get("article", 0))).get("param", "")) == "mandate":
			score -= 0.15
	score += (c.approval - 0.46) * 0.25
	return clampf(score, 0.03, 0.97)


## Weight of a block in the voter's opinion: from the table, or the "pop" of a code's block.
static func _popularity_weight(type: String) -> float:
	if POPULARITY_WEIGHTS.has(type):
		return float(POPULARITY_WEIGHTS[type])
	return float(LawCatalog.get_def(type).get("pop", 0.0))


## What the norm adds and removes. New norm: everything is an addition. Amendment: compares with the version in force
## of the target, block by block, by type and values.
func change_of(norm: Dictionary) -> Dictionary:
	var mine := LawProgram.all_blocks(norm.get("program", LawProgram.empty()))
	var target: Dictionary = norms.get(int(norm.get("amends", -1)), {})
	if target.is_empty() or target.get("versions", []).is_empty():
		return {"added": mine, "removed": []}
	var theirs := LawProgram.all_blocks(_current_program(target))
	var pool := {}
	for block: Dictionary in theirs:
		pool.get_or_add(_block_key(block), []).append(block)
	var added := []
	for block: Dictionary in mine:
		var key := _block_key(block)
		if pool.has(key) and not pool[key].is_empty():
			pool[key].pop_back()
		else:
			added.append(block)
	var removed := []
	for key: String in pool:
		removed.append_array(pool[key])
	return {"added": added, "removed": removed}


static func _block_key(block: Dictionary) -> String:
	var plugs := {}
	for key: String in block.plugs:
		plugs[key] = _block_key(block.plugs[key])
	return "%s|%s|%s" % [block.type, var_to_str(block.fields), var_to_str(plugs)]


## Estimate of votes in a house, not counting dissidents. The paid poll uses this.
func _estimate_house(world: GameWorld, parties: Array, probe: Dictionary) -> Dictionary:
	var yes := 0
	var rows := []
	var total := 0
	for party: Dictionary in parties:
		var seats: int = party.seats
		if seats == 0:
			continue
		total += seats
		var favor := _party_votes_yes(world, party, probe, false)
		if favor:
			yes += seats
		rows.append("%s (%d): %s" % [party.short, seats, tr("a favor") if favor else tr("contra")])
	return {"yes": yes, "total": total, "rows": rows}


## Poll paid for with the party fund. kind: poll_support (support by house) or poll_popularity (electorate).
func poll(world: GameWorld, kind: String, norm: Dictionary) -> Dictionary:
	var paid: Dictionary = world.politics.spend_fund(world, kind)
	if not paid.ok:
		return paid
	var probe := {"position": position_for(world, norm), "by_player": norm.get("by_player", true), "deals": norm.get("deals", {}), "author_party": norm.get("author_party", -1)}
	var lines := []
	if kind == "poll_support":
		var share := _required_share(norm)
		for house: Dictionary in world.politics.houses(world):
			var estimate := _estimate_house(world, house.parties, probe)
			var total: int = estimate.total
			var margin := maxi(ceili(float(total) * POLL_MARGIN_SUPPORT), 1)
			var seen := clampi(int(estimate.yes) + _rng.randi_range(-margin, margin), 0, total)
			var needed: int = ceili(float(total) * share) if share > 0.0 else total / 2 + 1
			lines.append(tr("%s: cerca de %d de %d votos (margem de %d), precisa de %d. %s") % [house.name, seen, total, margin, needed, tr("Deve passar.") if seen >= needed else tr("Deve cair.")])
			lines.append("  ".join(estimate.rows))
	else:
		var seen := clampf(popularity_of(world, norm) * 100.0 + _rng.randf_range(-POLL_MARGIN_POPULARITY, POLL_MARGIN_POPULARITY), 0.0, 100.0)
		var mood := tr("A maioria aprova.") if seen >= 55.0 else (tr("A maioria rejeita.") if seen <= 45.0 else tr("O eleitorado está dividido."))
		lines.append(tr("Favoráveis: %d%% (margem de %d pontos). %s") % [roundi(seen), int(POLL_MARGIN_POPULARITY), mood])
	revision += 1
	return {"ok": true, "msg": "", "text": "\n".join(lines)}


## Poll target for a finished project, with no norm created yet.
func bill_probe(id: String) -> Dictionary:
	var b := Politics.bill(id)
	return {"type": "ordinaria", "payload": {"kind": "bill", "id": id, "share": float(b.get("share", 0.0))}, "position": {"econ": b.econ, "social": b.social}, "by_player": true}


# --- Queries for the screen ---------------------------------------------------------------

## Phases of the procedure in plain language, each joining stages of the rite.
# i18n-begin
const PHASES := [
	{"id": "comissao", "label": "Comissão", "steps": ["present", "admissibility", "constitutional"]},
	{"id": "plenario", "label": "Plenário", "steps": ["discussion", "vote", "interval", "vote_2", "quorum"]},
	{"id": "outra_casa", "label": "Outra casa", "steps": ["vote_upper"]},
	{"id": "plebiscito", "label": "Plebiscito", "steps": ["plebiscite"]},
	{"id": "sancao", "label": "Sanção", "steps": ["sign", "sanction", "override"]},
	{"id": "publicacao", "label": "Publicação", "steps": ["promulgate", "publish", "apply"]},
	{"id": "vigencia", "label": "Vigência", "steps": []},
]
# i18n-end
## Social groups of the compass, for the expected reaction to a proposal.
# i18n-begin
const SOCIAL_GROUPS := [
	{"label": "Trabalhadores", "econ": -0.6, "social": 0.1},
	{"label": "Empresários", "econ": 0.7, "social": 0.1},
	{"label": "Classe média", "econ": 0.2, "social": 0.3},
	{"label": "Religiosos", "econ": 0.1, "social": -0.6},
	{"label": "Jovens", "econ": -0.2, "social": 0.7},
	{"label": "Aposentados", "econ": -0.3, "social": -0.3},
]
# i18n-end
# i18n-begin
const VOTE_WORDS := {"none": "sem votação", "simple": "maioria simples", "absolute": "maioria absoluta", "qualified": "maioria qualificada", "amendment": "quórum de emenda"}
# i18n-end


## The code of a norm: its own, that of the norm it amends, or "".
func code_of(norm: Dictionary) -> String:
	if String(norm.get("code", "")) != "":
		return String(norm.code)
	var target: Dictionary = norms.get(int(norm.get("amends", -1)), {})
	if String(target.get("code", "")) != "":
		return String(target.code)
	# The old Tax Code, made only of tax rates, is still the tax code.
	if target.get("base_code", false) and String(target.get("title", "")) == "Código Tributário":
		return "tributario"
	return ""


## Card of a code for the legislative center: the norm in force, if any, and how many articles it has.
func code_card(id: String) -> Dictionary:
	var norm := code_norm(id)
	if norm.is_empty() and id == "tributario":
		for other: Dictionary in norms.values():
			if other.get("base_code", false) and other.state == STATE_IN_FORCE and String(other.get("code", "")) == "" and String(other.title) == "Código Tributário":
				norm = other
	var articles := 0
	var blocks := 0
	if not norm.is_empty():
		for stack: Dictionary in _current_program(norm).stacks:
			if not stack.get("repealed", false):
				articles += 1
				blocks += stack.blocks.size()
	var pending := 0
	for other: Dictionary in in_process():
		if code_of(other) == id:
			pending += 1
	return {"norm": norm, "articles": articles, "blocks": blocks, "pending": pending}


## One line that explains the rite of the norm type, with the votes it needs.
func type_rule_text(world: GameWorld, type: String) -> String:
	var def: Dictionary = NORM_TYPES[type]
	if def.vote == "none":
		return tr("%s: assinada por %s, sem votação no parlamento.") % [tr(def.label), tr(def.organ).to_lower()]
	var share := _required_share({"type": type})
	var houses := []
	for house: Dictionary in world.politics.houses(world):
		var total: int = house.total
		var needed: int = ceili(float(total) * share) if share > 0.0 else total / 2 + 1
		houses.append(tr("%d de %d votos %s") % [needed, total, tr("na %s") % house.name if world.politics.houses(world).size() > 1 else tr("no Parlamento")])
	var text := tr("%s exige %s: %s.") % [tr(def.label), tr(VOTE_WORDS[def.vote]), tr(" e ").join(houses)]
	if def.sanction and param("veto", true):
		text += tr(" Depois vai à sanção, e o chefe de governo pode vetar.")
	return text


## Step-by-step procedure: [{label, state (done, current, todo, failed), days, detail}].
## Draft: the path the norm will follow, everything still to do.
func process_track(world: GameWorld, norm: Dictionary) -> Array:
	var process: Dictionary = norm.get("process", {})
	var steps: Array = process.get("steps", _steps_for(norm))
	var at: int = int(process.get("at", -1)) if not process.is_empty() else -1
	var failed: bool = norm.state in [STATE_REJECTED, STATE_INVALID]
	var finished: bool = norm.state in [STATE_PUBLISHED, STATE_IN_FORCE, STATE_SUSPENDED, STATE_REVOKED, STATE_EXPIRED]
	var out := []
	for phase: Dictionary in PHASES:
		var mine := []
		for i in steps.size():
			if steps[i] in phase.steps:
				mine.append(i)
		if mine.is_empty() and phase.id != "vigencia":
			continue
		var entry := {"label": tr(phase.label), "state": "todo", "days": 0, "detail": ""}
		if phase.id == "vigencia":
			entry.days = int(norm.get("vacatio", 0))
			if norm.state == STATE_PUBLISHED:
				entry.state = "current"
				entry.days = maxi(int(norm.get("force_due", world.day_index)) - world.day_index, 0)
				entry.detail = tr("Publicada, aguardando a vigência")
			elif norm.state == STATE_IN_FORCE:
				entry.state = "done"
				entry.detail = tr("Em vigor desde %s") % String(norm.dates.get("in_force", ""))
			out.append(entry)
			continue
		for i: int in mine:
			entry.days += _days_of(steps[i])
		if finished or (at >= 0 and at > int(mine[-1])):
			entry.state = "done"
			entry.days = 0
		elif at >= 0 and at >= int(mine[0]):
			entry.state = "failed" if failed else "current"
			var step: String = steps[at]
			entry.detail = tr(STEP_LABELS.get(step, step))
			var left: int = (int(process.get("tacit", 0)) if process.get("waiting_player", false) else int(process.get("due", 0))) - world.day_index
			entry.days = maxi(left, 0)
			for i: int in mine:
				if i > at:
					entry.days += _days_of(steps[i])
			if process.get("waiting_player", false):
				entry.detail = tr("Aguardando sua sanção")
		out.append(entry)
	if failed and not out.any(func(e): return e.state == "failed"):
		for entry: Dictionary in out:
			if entry.state == "todo":
				entry.state = "failed"
				break
	return out


## Days left until the norm takes effect, adding up the phases still to do.
func days_to_force(world: GameWorld, norm: Dictionary) -> int:
	var total := 0
	for entry: Dictionary in process_track(world, norm):
		if entry.state in ["current", "todo"]:
			total += int(entry.days)
	return total


## Chance of passing the remaining votes, from 0 to 1, not counting agreements still to be made. -1: there is no vote.
## It is a rough and free estimate; the paid poll shows the count by party.
func pass_chance(world: GameWorld, norm: Dictionary) -> float:
	var process: Dictionary = norm.get("process", {})
	var steps: Array = process.get("steps", _steps_for(norm))
	var at: int = maxi(int(process.get("at", 0)), 0)
	var probe := {"type": norm.type, "position": position_for(world, norm), "by_player": norm.get("by_player", true), "deals": norm.get("deals", {}), "author_party": norm.get("author_party", -1), "payload": norm.get("payload", {})}
	var share := _required_share(probe)
	var data: Dictionary = world.politics.data_of(iso)
	var chance := 1.0
	var any := false
	var houses_seen := {}
	for i in range(at, steps.size()):
		var step: String = steps[i]
		if not step in ["vote", "vote_2", "vote_upper", "plebiscite"]:
			continue
		any = true
		if step == "plebiscite":
			chance *= 1.0 / (1.0 + exp(-(popularity_of(world, norm) - 0.5) / 0.07 * 1.7))
			continue
		var upper := step == "vote_upper"
		if houses_seen.has(upper):
			continue
		houses_seen[upper] = true
		var estimate := _estimate_house(world, Politics.upper_house(data) if upper else data.parties, probe)
		var total := maxf(float(estimate.total), 1.0)
		var needed: float = ceilf(total * share) if share > 0.0 else floorf(total / 2.0) + 1.0
		var expected := float(estimate.yes) * 0.96 + (total - float(estimate.yes)) * 0.04
		chance *= 1.0 / (1.0 + exp(-(expected - needed) / (total * 0.02) * 1.7))
	if not any:
		return -1.0
	if "constitutional" in steps.slice(at) and _court_problem(norm) != "":
		chance *= 0.35
	return clampf(chance, 0.0, 1.0)


## Word for the chance: the player reads "likely", not 0.73.
static func chance_word(chance: float) -> String:
	if chance < 0.0:
		return TranslationServer.translate("sem votação")
	if chance >= 0.85:
		return TranslationServer.translate("muito provável")
	if chance >= 0.6:
		return TranslationServer.translate("provável")
	if chance >= 0.4:
		return "incerta"
	if chance >= 0.15:
		return TranslationServer.translate("difícil")
	return TranslationServer.translate("muito difícil")


## Expected effect of a proposal, for the panel before sending: approval, budget, groups and parties.
func expected_effects(world: GameWorld, norm: Dictionary) -> Dictionary:
	var c := world.player
	var popularity := popularity_of(world, norm)
	var position := position_for(world, norm)
	var change := change_of(norm)
	var yusd := c.y_usd()
	var budget := 0.0
	var unknown := 0
	for pair: Array in [[change.added, 1.0], [change.removed, -1.0]]:
		for block: Dictionary in pair[0]:
			var f: Dictionary = block.fields
			var sign: float = pair[1]
			match String(block.type):
				"ec_rate":
					if sign > 0.0 and not block.plugs.has("value"):
						budget += (float(f.get("value", 0.0)) / 100.0 - float(c.get(String(f.get("field"))))) * yusd
				"ec_budget":
					if sign > 0.0 and not block.plugs.has("value"):
						budget -= (float(f.get("value", 0.0)) / 100.0 - float(c.get(String(f.get("field"))))) * yusd
				"ec_spend", "ec_subsidy":
					budget -= float(f.get("amount", 0.0)) * sign
				"ac_institution":
					budget -= float(f.get("cost", 0.0)) * sign
				"ac_post":
					budget -= float(f.get("posts", 0.0)) * float(f.get("salary", 0.0)) / 1e9 * sign
				_:
					var def := LawCatalog.get_def(block.type)
					if LawCodes.owner_of(String(block.type)) != null and (def.has("econ") or def.has("social")):
						unknown += 1
	# Codes that know how to estimate their own revenue (the Tax code) come in with their calculation.
	var code_id := String(norm.get("code", norm_code_of(norm)))
	var code := LawCodes.get_code(code_id)
	if code != null and code.has_method("bill_effect"):
		var got: Dictionary = code.call("bill_effect", world, self, norm)
		if got.has("budget"):
			budget += float(got.budget)
			unknown = 0
	var groups := []
	for g: Dictionary in SOCIAL_GROUPS:
		var score := clampf(0.8 - Politics.distance(position, g) * 0.45 + (popularity - 0.5) * 0.5, 0.0, 1.0)
		groups.append({"label": tr(g.label), "score": score, "mood": tr("a favor") if score >= 0.58 else (tr("contra") if score <= 0.42 else tr("dividido"))})
	var parties := []
	var probe := {"position": position, "by_player": norm.get("by_player", true), "deals": norm.get("deals", {}), "author_party": norm.get("author_party", -1)}
	for party: Dictionary in world.politics.data_of(iso).parties:
		if int(party.seats) <= 0:
			continue
		var favor := _party_votes_yes(world, party, probe, false)
		parties.append({"short": party.short, "name": party.get("name", party.short), "seats": int(party.seats), "favor": favor, "color": party.get("color", Color.GRAY)})
	parties.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	return {
		"popularity": popularity, "approval": (popularity - 0.5) * POPULARITY_APPROVAL, "budget": budget, "budget_share": budget / maxf(yusd, 0.001),
		"unknown_budget": unknown, "groups": groups, "parties": parties, "position": position, "chance": pass_chance(world, norm),
		"days": days_to_force(world, norm), "added": change.added.size(), "removed": change.removed.size(),
	}


## Names that already exist for a reference field ("tax", "license", "institution", "duty"), in force or
## created in the program itself. The field still accepts a new name when the block creates something.
func known_names(kind: String, program := {}) -> Array:
	var names := []
	var add := func(n: Variant):
		var text := String(n).strip_edges()
		if text != "" and not text in names:
			names.append(text)
	var creators: Dictionary = {"tax": ["ec_charge", "ec_fee", "ec_contribution"], "license": ["ac_issue_license"], "institution": ["ac_institution"], "duty": ["rg_duty"]}
	var sources := norms.values().filter(func(n): return n.state == STATE_IN_FORCE).map(func(n): return _current_program(n))
	if not program.is_empty():
		sources.append(program)
	for source: Dictionary in sources:
		for block: Dictionary in LawProgram.all_blocks(source):
			if block.type in creators.get(kind, []):
				add.call(block.fields.get("name", block.fields.get("license", "")))
	match kind:
		"license":
			for key: String in licenses:
				add.call(key)
		"institution":
			for key: String in standing.institutions:
				add.call(key)
		"duty":
			for key: String in standing.duties:
				add.call(key)
	names.sort()
	return names


func _admissibility(world: GameWorld, norm: Dictionary) -> String:
	if norm.type == "emenda":
		var check := check_amendment(world, norm, true)
		return "" if check.ok else String(check.msg)
	var compiled := compile_norm(norm)
	return "" if compiled.ok else tr("a programação tem erros.")


## Each voter weighs the proposal's popularity, with the uncertainty of a real campaign. A closed regime
## organizes the vote to give the result it wants.
func _hold_plebiscite(world: GameWorld, norm: Dictionary) -> Dictionary:
	var c := world.player
	var yes := popularity_of(world, norm) + _rng.randf_range(-0.07, 0.07)
	if c.dem < Politics.FREE_PARLIAMENT_DEM:
		yes = maxf(yes, 0.6) + _rng.randf_range(0.05, 0.3)
	var result := {"yes": clampf(yes, 0.02, 0.98), "turnout": clampf(0.45 + c.stability * 0.3 + _rng.randf_range(-0.05, 0.05), 0.2, 0.95), "date": world.date_string()}
	norm["plebiscite_result"] = result
	return result


## What the court challenges. Empty: nothing.
func _court_problem(norm: Dictionary) -> String:
	if norm.type == "emenda":
		return ""
	for block: Dictionary in LawProgram.all_blocks(norm.program):
		if block.type in ["rg_remove", "dr_suspend"] and block.fields.get("right") in param("rights", []):
			return tr("remove um direito garantido no Art. 3º.")
		if block.type == "ec_rate" and float(block.fields.get("value", 0.0)) > 35.0:
			return tr("tributo com efeito de confisco.")
	if not norm.get("revokes", {}).is_empty():
		var target: Dictionary = norms.get(int(norm.revokes.id), {})
		if not target.is_empty() and int(NORM_TYPES[target.type].rank) > int(NORM_TYPES[norm.type].rank):
			return tr("norma inferior não revoga norma superior.")
	return ""


## The more democratic the country, the more the court actually acts.
func _court_acts(world: GameWorld) -> bool:
	return _rng.randf() < clampf(world.player.dem / 8.0, 0.1, 1.0)


func _publish(world: GameWorld, norm: Dictionary) -> void:
	norm.dates["published"] = world.date_string()
	_record_step(world, norm, "publish", tr("Publicada no diário oficial."), tr("Imprensa Oficial"))
	if norm.type == "emenda":
		return
	if norm.has("payload"):
		norm.versions.append({"program": LawProgram.empty(), "text": tr("Art. 1º %s") % norm.ementa, "code": {}, "position": norm.position, "date": world.date_string(), "change": tr("Texto original"), "hash": hash(var_to_str(LawProgram.empty()))})
		norm.current_v = 0
		_enter_force(world, norm)
		return
	var compiled := LawCompiler.compile(norm.program, compile_context(norm.type))
	if not compiled.ok:
		_fail(world, norm, STATE_INVALID, tr("a programação deixou de ser válida."))
		return
	norm.versions.append(_make_version(world, norm.program, compiled, tr("Texto original")))
	norm.current_v = norm.versions.size() - 1
	norm.state = STATE_PUBLISHED
	norm.force_due = world.day_index + int(norm.get("vacatio", 0))
	revision += 1
	if int(norm.vacatio) == 0:
		_enter_force(world, norm)


func _make_version(world: GameWorld, program: Dictionary, compiled: Dictionary, change: String) -> Dictionary:
	var frozen: Dictionary = program.duplicate(true)
	return {"program": frozen, "text": compiled.text, "code": compiled.code, "position": compiled.position, "date": world.date_string(), "change": change, "hash": hash(var_to_str(frozen))}


func _enter_force(world: GameWorld, norm: Dictionary) -> void:
	norm.dates["in_force"] = world.date_string()
	norm.state = STATE_IN_FORCE
	norm["force_day"] = world.day_index
	_log(world, norm, "Entrada em vigor", "", STATE_IN_FORCE, tr("Em vigor"), norm.organ)  # i18n
	world.emit_news(tr("%s entra em vigor: %s.") % [norm_label(norm), norm.title], "politica", world.player)
	_apply_payload(world, norm)
	_popular_effect(world, norm)
	if int(norm.get("amends", -1)) >= 0:
		_apply_change(world, norm)
	if not norm.get("revokes", {}).is_empty():
		_apply_revocation(world, norm)
	fire(world, "ev_enact", {"only": norm.id})
	revision += 1


func _apply_payload(world: GameWorld, norm: Dictionary) -> void:
	var payload: Dictionary = norm.get("payload", {})
	match payload.get("kind", ""):
		"bill":
			world.politics.apply_bill(world, Politics.bill(payload.id))
		"treaty":
			world.treaties.on_player_ratification(world, int(payload.treaty), true)
		"new_unit":
			var c := world.player
			var made: Dictionary = world.subdivisions.create_unit(payload.points, int(payload.type), int(payload.parent), world.territories.territory_of(c, world), c.region, c.iso)
			world.emit_news((tr("%s vira realidade.") % world.subdivisions.units[made.id].name) if made.ok else String(made.msg), "politica", c)
			world.refresh_map = true
		"split_unit":
			var made: Dictionary = {"ok": false, "msg": tr("A unidade não existe mais.")}
			if world.subdivisions.units.has(int(payload.unit)):
				made = world.subdivisions.split_unit(int(payload.unit), payload.points, world.player.region)
			world.emit_news((tr("%s se separa e vira unidade própria.") % world.subdivisions.units[made.id].name) if made.ok else String(made.msg), "politica", world.player)
			world.refresh_map = true


## The government reaps the voter's reaction when the norm starts to apply. The opposition does not govern: nothing changes.
func _popular_effect(world: GameWorld, norm: Dictionary) -> void:
	if norm.get("base_code", false):
		return
	var score: float = norm.get("popularity", popularity_of(world, norm))
	world.player.approval = clampf(world.player.approval + (score - 0.5) * POPULARITY_APPROVAL, 0.02, 0.95)


## The amendment becomes a new version of the original norm, which stays in force. The old one is kept.
func _apply_change(world: GameWorld, norm: Dictionary) -> void:
	var target: Dictionary = norms.get(int(norm.amends), {})
	if target.is_empty() or target.state != STATE_IN_FORCE:
		return
	var compiled := LawCompiler.compile(norm.program, compile_context(target.type))
	if not compiled.ok:
		return
	var before: String = target.versions[int(target.current_v)].text if not target.versions.is_empty() else ""
	target.versions.append(_make_version(world, norm.program, compiled, tr("Alterada por %s") % norm_label(norm)))
	target.current_v = target.versions.size() - 1
	_purge_norm(target.id)
	_log(world, target, "Alteração", before, compiled.text, tr("Nova versão %d") % int(target.current_v), norm.author)  # i18n
	fire(world, "ev_enact", {"only": target.id})


func _apply_revocation(world: GameWorld, norm: Dictionary) -> void:
	var target: Dictionary = norms.get(int(norm.revokes.id), {})
	if target.is_empty():
		return
	var articles: Array = norm.revokes.get("articles", [])
	if articles.is_empty():
		revoke_now(world, target, tr("Revogada por %s") % norm_label(norm), norm.author)
		return
	var program: Dictionary = _current_program(target).duplicate(true)
	for number: int in articles:
		if number >= 1 and number <= program.stacks.size():
			program.stacks[number - 1].repealed = true
	var compiled := LawCompiler.compile(program, compile_context(target.type))
	var before: String = target.versions[int(target.current_v)].text
	target.versions.append(_make_version(world, program, compiled, tr("Revogação parcial por %s") % norm_label(norm)))
	target.current_v = target.versions.size() - 1
	_purge_norm(target.id)
	_log(world, target, "Revogação parcial", before, compiled.text, tr("Artigos %s") % str(articles), norm.author)  # i18n


func revoke_now(world: GameWorld, target: Dictionary, why: String, who: String) -> void:
	var before: String = target.state
	target.state = STATE_REVOKED
	_purge_norm(target.id)
	pending = pending.filter(func(p): return int(p.norm) != int(target.id))
	_log(world, target, "Revogação", before, STATE_REVOKED, why, who)  # i18n
	world.emit_news(tr("%s revogada.") % norm_label(target), "politica", world.player)
	revision += 1


## Creates the project that amends a norm in force: copies the current version into a new draft.
func start_change(world: GameWorld, target: Dictionary) -> Dictionary:
	var norm := new_norm(world, target.type)
	norm.program = _current_program(target).duplicate(true)
	norm.amends = target.id
	norm.title = tr("Altera %s") % norm_label(target)
	norm.ementa = tr("Altera %s: %s.") % [norm_label(target), tr(target.title)]
	return norm


func start_revocation(world: GameWorld, target: Dictionary, articles: Array) -> Dictionary:
	var norm := new_norm(world, target.type)
	norm.revokes = {"id": target.id, "articles": articles}
	var block := LawProgram.new_block(norm.program, "ev_enact")
	LawProgram.add_stack(norm.program, block, Vector2(20, 20))
	norm.title = tr("Revoga %s") % norm_label(target)
	norm.ementa = (tr("Revoga os artigos %s de %s.") % [str(articles), norm_label(target)]) if not articles.is_empty() else tr("Revoga %s.") % norm_label(target)
	return norm


func suspend(world: GameWorld, norm: Dictionary, on: bool) -> Dictionary:
	if not can(world, "admin"):
		return {"ok": false, "msg": tr("Só o chefe de governo suspende normas.")}
	if int(NORM_TYPES[norm.type].rank) >= 60:
		return {"ok": false, "msg": tr("Só norma de hierarquia igual ou a corte suspende uma lei.")}
	var before: String = norm.state
	norm.state = STATE_SUSPENDED if on else STATE_IN_FORCE
	if on:
		_purge_norm(norm.id)
	_log(world, norm, "Suspensão" if on else "Reativação", before, norm.state, "", String(world.leader.get("name", "")))  # i18n
	revision += 1
	return {"ok": true, "msg": "%s: %s." % [norm_label(norm), norm.state]}


func _check_expiry(world: GameWorld) -> void:
	var today := _today(world)
	for norm: Dictionary in norms.values():
		if norm.state == STATE_IN_FORCE and String(norm.get("expires", "")) != "" and today > String(norm.expires):
			norm.state = STATE_EXPIRED
			_purge_norm(norm.id)
			_log(world, norm, "Expiração", STATE_IN_FORCE, STATE_EXPIRED, tr("Prazo de vigência terminou"), tr("Sistema"))  # i18n
			world.emit_news(tr("%s expirou.") % norm_label(norm), "politica", world.player)
			revision += 1


static func _today(world: GameWorld) -> String:
	return "%04d-%02d-%02d" % [world.year, world.month + 1, world.day]


# --- Constitutional amendments -----------------------------------------------------------

## ops: [{"op": "alter", "article": id, "text": new, "value": new parameter}, {"op": "add", "kind": "artigo", "text": ...}].
func check_amendment(world: GameWorld, norm: Dictionary, in_process_now := false) -> Dictionary:
	var ops: Array = norm.get("ops", [])
	if ops.is_empty() and norm.program.stacks.is_empty():
		return {"ok": false, "msg": tr("A emenda não muda nenhum dispositivo.")}
	if param("amend_no_war", false) and world.diplomacy.in_war(world.player.idx):
		return {"ok": false, "msg": tr("A Constituição proíbe emendas em tempo de guerra.")}
	var open_now := in_process().filter(func(n): return n.type == "emenda" and n.id != norm.id).size()
	if open_now >= int(param("amend_max", 2)):
		return {"ok": false, "msg": tr("Já tramitam %d emendas, o máximo permitido.") % open_now}
	for op: Dictionary in ops:
		if op.op == "add":
			continue
		var article := article_by_id(int(op.article))
		if article.is_empty():
			return {"ok": false, "msg": tr("Esse dispositivo não existe mais.")}
		if article.petrea:
			return {"ok": false, "msg": tr("%s é cláusula pétrea e não pode ser alterado.") % article.label}
	var data: Dictionary = world.politics.data_of(iso)
	var backers: int = world.politics.government_seats(iso) if not norm.get("by_player", false) or world.in_office else int(world.politics.player_party(world).get("seats", 0))
	var needed := ceili(float(data.seats_total) * float(param("amend_proposers", 33)) / 100.0)
	if backers < needed:
		return {"ok": false, "msg": tr("A emenda precisa do apoio inicial de %d assentos; você tem %d.") % [needed, backers]}
	return {"ok": true, "msg": ""}


## Changing the Constitution has a political cost: concentrating power pulls toward the authoritarian side.
func _amendment_position(norm: Dictionary) -> Dictionary:
	var social := 0.0
	for op: Dictionary in norm.get("ops", []):
		var article := article_by_id(int(op.get("article", 0)))
		match String(article.get("param", "")):
			"veto", "autonomous_decree":
				social += -0.4 if op.get("value", false) else 0.3
			"judicial_review":
				social += 0.4 if op.get("value", false) else -0.6
			"mandate":
				social += -0.3 if float(op.get("value", 4)) > float(article.value) else 0.1
			"rights":
				social += 0.4 if (op.get("value", []) as Array).size() > (article.value as Array).size() else -0.6
	return {"econ": 0.0, "social": clampf(social, -1.0, 1.0)}


## New text of a provision after the operation: serves for the comparison and for the promulgation.
## With localized, texts stored in Portuguese come out in the game's language (for the screen).
func preview_op(op: Dictionary, localized := false) -> Dictionary:
	if op.op == "add":
		return {"before": "", "after": "%s %s" % [_next_label(String(op.get("kind", "artigo"))), op.get("text", "")]}
	var article := article_by_id(int(op.article))
	var before: String = article_text(article, true) if localized and not article.is_empty() else article.get("text", "")
	if op.op == "suppress":
		return {"before": before, "after": ""}
	if String(article.get("param", "")) != "" and op.has("value"):
		var probe: Dictionary = article.duplicate()
		probe.value = op.value
		return {"before": before, "after": article_text(probe, localized)}
	return {"before": before, "after": String(op.get("text", before))}


func _next_label(kind: String) -> String:
	var used := 0
	for a: Dictionary in constitution.articles:
		if a.get("kind", "") == kind:
			used += 1
	match kind:
		"paragrafo": return "§ %dº" % (used + 1)
		"inciso": return tr("Inciso %d.") % (used + 1)
		"transitoria": return tr("ADT %dº") % (used + 1)
	return tr("Art. %d.") % (used + 1)


## Only here does the Constitution change: after promulgation, generating a new version and keeping the previous one.
func _apply_amendment(world: GameWorld, norm: Dictionary) -> void:
	var changes := []
	for op: Dictionary in norm.ops:
		var shown := preview_op(op)
		changes.append({"op": op.op, "label": AMENDMENT_OPS[op.op], "before": shown.before, "after": shown.after})
		match op.op:
			"add":
				var added := {"id": int(constitution.next_article), "label": _next_label(String(op.get("kind", "artigo"))), "template": "", "param": "", "value": null, "petrea": op.get("petrea", false), "kind": op.get("kind", "artigo")}
				constitution.next_article = int(constitution.next_article) + 1
				added["text"] = shown.after
				constitution.articles.append(added)
			"suppress":
				var gone := article_by_id(int(op.article))
				gone["suppressed"] = true
				gone["text"] = tr("%s (Suprimido.)") % gone.label
				_repeal_block_article(world, gone)
			_:
				var article := article_by_id(int(op.article))
				if String(article.get("param", "")) != "" and op.has("value"):
					article.value = op.value
				elif op.has("text"):
					# Free text in an article with a parameter: the value stays, and the new wording applies from now on.
					article.template = String(op.text)
				article.text = shown.after
	_sync_central_bank(world)
	var compiled := {}
	if not norm.program.stacks.is_empty():
		compiled = LawCompiler.compile(norm.program, compile_context("emenda"))
		for i in norm.program.stacks.size():
			var one := {"stacks": [norm.program.stacks[i]]}
			var label := _next_label("artigo")
			var text := "%s %s" % [label, LawProgram.legal_text(one).trim_prefix("Art. 1º ")]
			constitution.articles.append({"id": int(constitution.next_article), "label": label, "template": "", "param": "", "value": null, "petrea": false, "kind": "artigo", "text": text, "program_norm": int(norm.id), "stack": i})
			constitution.next_article = int(constitution.next_article) + 1
			changes.append({"op": "add", "label": AMENDMENT_OPS.add, "before": "", "after": text})
	var last: Dictionary = norm.votes[-1] if not norm.votes.is_empty() else {}
	constitution.version = int(constitution.version) + 1
	constitution.next_emenda = int(constitution.next_emenda) + 1
	constitution.versions.append({
		"n": constitution.version, "emenda": norm.number, "date": world.date_string(), "articles": constitution.articles.duplicate(true),
		"changes": changes, "approvers": tr("%d votos em %d") % [int(last.get("yes", 0)), int(last.get("total", 0))], "votes": norm.votes.duplicate(true),
	})
	norm.versions.append({"program": norm.program.duplicate(true), "text": "\n".join(changes.map(func(ch): return "%s: %s" % [ch.label, ch.after if ch.after != "" else ch.before])), "code": compiled.get("code", {}), "position": norm.get("position", {}), "date": world.date_string(), "change": tr("Texto promulgado"), "hash": 0})
	norm.current_v = 0
	norm.state = STATE_IN_FORCE
	norm["force_day"] = world.day_index
	norm.dates["in_force"] = world.date_string()
	_record_step(world, norm, "apply", tr("Constituição atualizada para a versão %d.") % int(constitution.version), tr("Presidência do parlamento"))
	world.emit_news(tr("%s promulgada: a Constituição mudou.") % norm_label(norm), "politica", world.player)
	_popular_effect(world, norm)
	fire(world, "ev_enact", {"only": norm.id})
	revision += 1


## Central bank independence comes from the Constitution. On gaining it, the bank takes back the rate right away.
func _sync_central_bank(world: GameWorld) -> void:
	var c := world.player
	# The electoral system also lives in the Constitution and applies from the next election.
	var rule := Elections.rules(c, world.politics.data_of(iso))
	rule.system = String(param("electoral_system", rule.system))
	rule.head = String(param("head_system", rule.head))
	rule.threshold = float(param("threshold", 3)) / 100.0
	c.cb_independent = bool(param("cb_independent", false))
	if c.cb_independent:
		c.rate_manual = false


## Suppressing an article programmed with blocks also turns off its programming.
func _repeal_block_article(world: GameWorld, article: Dictionary) -> void:
	if not article.has("program_norm"):
		return
	var source: Dictionary = norms.get(int(article.program_norm), {})
	if source.is_empty() or source.versions.is_empty():
		return
	var program: Dictionary = _current_program(source).duplicate(true)
	program.stacks[int(article.stack)].repealed = true
	var compiled := LawCompiler.compile(program, compile_context("emenda"))
	source.versions.append(_make_version(world, program, compiled, tr("Artigo suprimido por emenda")))
	source.current_v = source.versions.size() - 1
	_purge_norm(source.id)


func constitution_version(n: int) -> Dictionary:
	for v: Dictionary in constitution.versions:
		if int(v.n) == n:
			return v
	return {}


# --- Execution ----------------------------------------------------------------------------

## Fires an event: looks up the norms in force and runs the articles, from lowest priority to highest,
## so the strongest norm is the last to set a value.
func fire(world: GameWorld, event: String, options := {}) -> void:
	if world.player == null or iso == "":
		return
	var runs := []
	for norm: Dictionary in norms.values():
		if norm.state != STATE_IN_FORCE or norm.versions.is_empty():
			continue
		if options.has("only") and int(norm.id) != int(options.only):
			continue
		var code: Dictionary = norm.versions[int(norm.current_v)].code
		for number: Variant in code:
			var article: Dictionary = code[number]
			if article.event == event:
				runs.append({"norm": norm, "number": int(number), "article": article, "priority": _priority(norm, article)})
	if runs.is_empty():
		return
	runs.sort_custom(func(a, b): return float(a.priority) < float(b.priority))
	for run: Dictionary in runs:
		_run_article(world, run.norm, int(run.number), run.article, event)


func _run_article(world: GameWorld, norm: Dictionary, number: int, article: Dictionary, event: String) -> void:
	# Avoids running twice on the same day for the same reason.
	var key := "%d:%d:%d:%s" % [int(norm.id), int(norm.current_v), number, event]
	if int(fired.get(key, -1)) == world.day_index:
		return
	fired[key] = world.day_index
	var engine := LawEngine.new()
	engine.view = build_view(world, event, article.fields)
	engine.vars = variables.get_or_add(int(norm.id), {})
	_finish_run(world, norm, number, event, engine, engine.run(article.code))


func _finish_run(world: GameWorld, norm: Dictionary, number: int, event: String, engine: LawEngine, result: Dictionary) -> void:
	if not result.ok:
		failures[norm.id] = int(failures.get(norm.id, 0)) + 1
		_log(world, norm, "Execução", "", "", tr("Falha no art. %d: %s") % [number, result.error], tr("Motor"), event)  # i18n
		if int(failures[norm.id]) >= MAX_FAILURES:
			norm.state = STATE_SUSPENDED
			_purge_norm(norm.id)
			_log(world, norm, "Suspensão automática", STATE_IN_FORCE, STATE_SUSPENDED, tr("Falhou %d vezes") % MAX_FAILURES, tr("Motor"), event)  # i18n
			world.emit_news(tr("%s foi suspensa: a execução falhou repetidas vezes.") % norm_label(norm), "crise", world.player)
		revision += 1
		return
	var summary := _commit(world, norm, result.effects, engine.view)
	if not result.waiting.is_empty():
		var w: Dictionary = result.waiting
		pending.append({"norm": norm.id, "version": norm.current_v, "number": number, "event": event, "due": world.day_index + int(w.days), "state": {"pc": w.pc, "weight": w.weight, "frames": w.frames, "loops": w.loops}})
	_log(world, norm, "Execução", "", "", tr("Art. %d: %s") % [number, summary if summary != "" else tr("sem efeitos")], tr("Motor"), event)  # i18n


func _run_pending(world: GameWorld) -> void:
	if pending.is_empty():
		return
	for wait: Dictionary in pending.duplicate():
		if world.day_index < int(wait.due):
			continue
		pending.erase(wait)
		var norm: Dictionary = norms.get(int(wait.norm), {})
		if norm.is_empty() or norm.state != STATE_IN_FORCE or int(norm.current_v) != int(wait.version):
			continue
		var article: Dictionary = norm.versions[int(wait.version)].code.get(int(wait.number), {})
		if article.is_empty():
			continue
		var engine := LawEngine.new()
		engine.view = build_view(world, wait.event, article.fields)
		engine.vars = variables.get_or_add(int(norm.id), {})
		_finish_run(world, norm, int(wait.number), wait.event, engine, engine.run(article.code, wait.state))


func _run_due_obligations(world: GameWorld) -> void:
	if obligations.is_empty():
		return
	var total := 0.0
	var keep := []
	for ob: Dictionary in obligations:
		if world.day_index >= int(ob.due):
			total += float(ob.usd)
		else:
			keep.append(ob)
	obligations = keep
	if total > 0.0:
		_collect(world.player, total * COMPLIANCE)
		fire(world, "ev_due", {"due": total})


func _fire_dates(world: GameWorld) -> void:
	var today := _today(world)
	for norm: Dictionary in norms.values():
		if norm.state != STATE_IN_FORCE or norm.versions.is_empty():
			continue
		var code: Dictionary = norm.versions[int(norm.current_v)].code
		for number: Variant in code:
			if code[number].event == "ev_date" and String(code[number].fields.get("date", "")) == today:
				_run_article(world, norm, int(number), code[number], "ev_date")


## Snapshot of the game for the engine: average values of the group that fires the event.
func build_view(world: GameWorld, event: String, fields: Dictionary) -> Dictionary:
	var c := world.player
	var pc := c.gdp_pc()
	var income := pc * 0.6
	var pop: float = c.pop
	var owners := pop * 0.45
	var property: float = c.capital / maxf(c.y, 0.001) * c.y_usd() * 1000.0 / maxf(owners, 0.001)
	var subject := {
		"age": clampf(18.0 + log(maxf(pc, 500.0) / 500.0) * 4.0, 18.0, 45.0), "money": pc * 3.0, "income": income,
		"value": property, "tx": income / 12.0,
	}
	var count := pop
	match event:
		"ev_citizen_enter":
			count = maxf(pop * c.popg / 12.0, pop * 0.0003)
			subject.age = 28.0
		"ev_transaction":
			count = pop
		"ev_property":
			count = owners * 0.005
		"ev_death":
			count = pop * 0.008 / 12.0
			subject.age = 72.0
		"ev_age":
			count = pop / 75.0 / 12.0
			subject.age = float(fields.get("age", 18))
		"ev_company":
			count = pop * 0.003 / 12.0
			subject.value = property * 2.0
		"ev_due":
			count = 1.0
	var game := {
		"gdp": c.y_usd(), "gdp_pc": pc, "growth": c.growth_yoy() * 100.0, "inflation": c.pi_yoy * 100.0, "unemployment": c.unemp * 100.0,
		"debt": c.debt_ratio * 100.0, "approval": c.approval * 100.0, "stability": c.stability * 100.0, "population": pop,
		"reserves": c.reserves, "tension": world.global_tension * 100.0,
	}
	var in_force := {}
	for norm: Dictionary in norms.values():
		if norm.state == STATE_IN_FORCE:
			in_force[int(norm.id)] = true
	var agro := clampf(0.5 - log(maxf(pc, 500.0) / 500.0) * 0.09, 0.02, 0.6)
	var public_ := clampf(c.sp_admin + c.sp_education * 0.8 + c.sp_health * 0.6, 0.04, 0.3)
	var industry := clampf(0.26 - agro * 0.1, 0.1, 0.35)
	var units := {}
	var roots: Array = world.subdivisions.roots_of(iso)
	var area := 0.0
	for id: int in roots:
		area += float(world.subdivisions.units[id].area)
	for id: int in roots:
		units[id] = float(world.subdivisions.units[id].area) / maxf(area, 0.0001)
	return {
		"subject": subject, "count": count, "game": game, "date": _today(world), "inequality": c.inequality, "owner_share": 0.45,
		"professions": {"agro": agro, "industria": industry, "publico": public_, "servicos": maxf(1.0 - agro - industry - public_, 0.0)},
		"unit_shares": units, "licenses": licenses, "institutions": standing.institutions, "norms_in_force": in_force,
		"exemptions": _named_values("exemptions"), "caps": _named_values("caps"),
	}


func _named_values(kind: String) -> Dictionary:
	var out := {}
	for key: String in standing[kind]:
		out[key] = standing[kind][key].value
	return out


static func _collect(c: Country, usd_bi: float) -> void:
	c.law_rev_bucket += usd_bi
	c.law_rev_month += usd_bi


static func _pay(c: Country, usd_bi: float) -> void:
	c.law_spend_bucket += usd_bi
	c.law_spend_month += usd_bi


## Applies the effects of a successful execution. The weight and the group become real money here.
func _commit(world: GameWorld, norm: Dictionary, effects: Array, _view: Dictionary) -> String:
	var c := world.player
	var collected := 0.0
	var paid := 0.0
	var notes := []
	# Cap: an execution does not move more than half of GDP, however absurd the norm is.
	var limit := c.y_usd() * 0.5
	var who := int(norm.id)
	var prio := _priority(norm, {})
	for effect: Dictionary in effects:
		var v: Dictionary = effect.values
		var w: float = effect.weight
		var scale: float = w * float(effect.count) / 1000.0
		var amount := float(v.get("amount", 0.0))
		match effect.op:
			"ac_obligation":
				var usd := minf(amount * scale, limit)
				obligations.append({"norm": who, "usd": usd, "due": world.day_index + int(v.get("days", 30))})
				notes.append(tr("obrigação de %s") % UiKit.money(usd))
			"ac_fine", "ec_charge", "ec_fee", "ec_contribution":
				var usd := minf(amount * scale, limit - collected) * COMPLIANCE
				collected += maxf(usd, 0.0)
				if effect.op == "ac_fine":
					c.approval = clampf(c.approval - minf(usd / maxf(c.y_usd(), 1.0), 0.002), 0.02, 0.95)
			"ac_benefit":
				paid += minf(amount * scale, limit - paid)
			"ac_expense":
				paid += minf(float(v.get("amount", 0.0)) * w, limit - paid)
			"ac_revoke_license":
				licenses[String(v.license)] = float(licenses.get(String(v.license), 0.0)) * (1.0 - w)
			"ac_issue_license":
				var share := float(licenses.get(String(v.license), 0.0))
				licenses[String(v.license)] = minf(share + (1.0 - share) * w * minf(float(effect.count) / maxf(c.pop, 0.001), 1.0), 1.0)
			"ac_register":
				registry.registered = minf(float(registry.registered) + w * float(effect.count), c.pop)
			"ac_status":
				registry.status[String(v.status)] = float(registry.status.get(String(v.status), 0.0)) + w * float(effect.count)
			"ac_post":
				_stand("posts", String(v.name), {"annual": float(v.posts) * float(v.salary) / 1e9}, who, prio)
			"ac_institution":
				_stand("institutions", String(v.name), {"annual": float(v.cost)}, who, prio)
			"ac_param":
				c.set(String(v.field), clampf(float(v.value) / 100.0, 0.0, 1.0))
			"ec_rate":
				_set_policy(world, String(v.field), float(v.value) / 100.0)
			"ec_budget":
				_set_policy(world, String(v.field), float(v.value) / 100.0)
				_stand("budget_locks", String(v.field), {"value": float(world.player.get(String(v.field)))}, who, prio)
			"ec_exempt":
				_stand("exemptions", String(v.name), {"value": float(v.share) / 100.0 * w}, who, prio)
			"ec_cap":
				_stand("caps", String(v.name), {"value": float(v.max)}, who, prio)
			"ad_min_create":
				_ministry_op(world, str(effect.block), {"op": "create", "name": String(v.name), "area": String(v.area)}, who, prio)
			"ad_min_merge":
				_ministry_op(world, str(effect.block), {"op": "merge", "a": String(v.a), "b": String(v.b), "name": String(v.name)}, who, prio)
			"ad_min_abolish":
				_ministry_op(world, str(effect.block), {"op": "abolish", "a": String(v.a)}, who, prio)
			"ec_privatize":
				var note := world.corporate.privatize(world, c, String(v.company), float(v.stake) / 100.0 * clampf(w, 0.0, 1.0))
				if note != "":
					notes.append(note)
			"ec_nationalize":
				var note := world.corporate.nationalize(world, c, String(v.company), float(v.stake) / 100.0)
				if note != "":
					notes.append(note)
			"ec_treasury":
				var usd := minf(float(v.amount) * w, maxf(c.reserves * 0.5, 0.0))
				c.reserves -= usd
				_collect(c, usd)
				notes.append(tr("%s das reservas") % UiKit.money(usd))
			"ec_subsidy":
				_stand("subsidies", String(v.sector), {"annual": float(v.amount) * w, "sector": v.sector}, who, prio)
			"ec_spend":
				_stand("spends", String(v.purpose), {"annual": float(v.amount) * w}, who, prio)
			"ec_minwage":
				_stand("minwage", "valor", {"value": float(v.amount)}, who, prio)
			"rg_grant":
				_stand("rights", String(v.right), {"on": true}, who, prio)
			"rg_remove":
				_stand("rights", String(v.right), {"on": false}, who, prio)
			"rg_duty":
				_stand("duties", String(v.name), {"on": true}, who, prio)
			"rg_deadline":
				_stand("deadlines", String(v.name), {"days": int(v.days)}, who, prio)
			"rg_restrict":
				_stand("restrictions", String(v.name), {"on": true}, who, prio)
			"rg_require":
				_stand("requirements", String(v.name), {"on": true}, who, prio)
			"rg_exception":
				_stand("exceptions", String(v.name), {"on": true}, who, prio)
			"rg_penalty":
				_stand("penalties", String(v.name), {"value": float(v.amount)}, who, prio)
			_:
				var code := LawCodes.owner_of(String(effect.op))
				if code != null:
					var note := code.apply(world, self, String(effect.op), v, w, who, prio)
					if note != "":
						notes.append(note)
	if collected > 0.0:
		_collect(c, collected)
		notes.append(tr("arrecadou %s") % UiKit.money(collected))
	if paid > 0.0:
		_pay(c, paid)
		notes.append(tr("pagou %s") % UiKit.money(paid))
	if notes.is_empty() and not effects.is_empty():
		notes.append(tr("%d ação(ões)") % effects.size())
	return ", ".join(notes)


## For the codes: stores the effect of a block in `standing.codes` while the norm is in force.
## The key is usually "code:item" (for example "penal:maioridade").
func stand(key: String, data: Dictionary, norm: int, prio: float) -> void:
	_stand("codes", key, data, norm, prio)


## What a code keeps in force: key → data, only the keys that start with "id:".
func code_standing(id: String) -> Dictionary:
	var out := {}
	for key: String in standing.codes:
		if key.begins_with(id + ":"):
			out[key.trim_prefix(id + ":")] = standing.codes[key]
	return out


## The highest-priority norm takes the slot; a lower-priority one does not overwrite it.
func _stand(kind: String, key: String, data: Dictionary, norm: int, prio: float) -> void:
	var old: Dictionary = standing[kind].get(key, {})
	if not old.is_empty() and float(old.prio) > prio:
		return
	data["norm"] = norm
	data["prio"] = prio
	standing[kind][key] = data
	revision += 1


func _set_policy(world: GameWorld, field: String, value: float) -> void:
	var limits: Array = Politics.BILL_LIMITS.get(field, [0.0, 0.5])
	if field == "tax_consumption":
		limits = [0.0, 0.24]
	elif field == "tax_corporate":
		limits = [0.0, 0.16]
	elif field == "sp_health":
		limits = [0.0, 0.14]
	Politics._apply_budget_change(world.player, field, clampf(value, limits[0], limits[1]))


## A norm that goes out of force stops applying: everything it kept falls along with it.
func _purge_norm(id: int) -> void:
	for kind: String in standing:
		for key: String in standing[kind].keys():
			if int(standing[kind][key].get("norm", -1)) == int(id):
				standing[kind].erase(key)
	revision += 1


## The change in the ministries applies while the norm is in force: once revoked, everything returns to what it was.
func _ministry_op(world: GameWorld, block: String, data: Dictionary, norm: int, prio: float) -> void:
	var key := "%d:%s" % [norm, block]
	if standing.ministry_ops.has(key):
		return
	data["seq"] = next_ministry_seq
	next_ministry_seq += 1
	_stand("ministry_ops", key, data, norm, prio)
	world.politics.sync_cabinet(world)
	var label: String = data.get("name", data.get("a", ""))
	world.emit_news({"create": tr("Criado o ministério %s."), "merge": tr("Ministérios fundidos em %s."), "abolish": tr("Extinto o ministério %s.")}[data.op] % label, "politica", world.player)


func ministry_ops() -> Array:
	var out: Array = standing.get("ministry_ops", {}).values()
	out.sort_custom(func(a, b): return int(a.seq) < int(b.seq))
	return out


## The value that a law in force requires for a budget field. Empty: the government decides alone.
func budget_lock(field: String) -> Dictionary:
	return standing.budget_locks.get(field, {})


func step_month(world: GameWorld) -> void:
	var c := world.player
	if c == null or iso == "":
		return
	# What the law fixes, nobody changes: neither the AI government nor another measure.
	for field: String in standing.budget_locks:
		c.set(field, float(standing.budget_locks[field].value))
	var annual := 0.0
	for kind: String in ["posts", "institutions", "subsidies", "spends"]:
		for key: String in standing[kind]:
			annual += float(standing[kind][key].annual)
	_pay(c, annual / 12.0)
	# Each ministry more or fewer than the usual seven weighs on the accounts.
	var extra: int = world.politics.portfolios(world).size() - Politics.PORTFOLIOS.size()
	var ministry_cost := float(extra) * c.y_usd() * Politics.MINISTRY_COST_SHARE / 12.0
	if ministry_cost >= 0.0:
		_pay(c, ministry_cost)
	else:
		_collect(c, -ministry_cost)
	fire(world, "ev_month")
	fire(world, "ev_citizen_enter")
	fire(world, "ev_transaction")
	fire(world, "ev_property")
	fire(world, "ev_death")
	fire(world, "ev_age")
	fire(world, "ev_company")
	if world.month == 0:
		fire(world, "ev_fiscal")
	_update_macro(c)
	_ai_proposal(world)


## Translates what is in force into pressure on the economy, approval and stability.
func _update_macro(c: Country) -> void:
	revenue_ring.append(c.law_rev_month)
	spend_ring.append(c.law_spend_month)
	c.law_rev_month = 0.0
	c.law_spend_month = 0.0
	if revenue_ring.size() > 12:
		revenue_ring.pop_front()
		spend_ring.pop_front()
	var yusd := maxf(c.y_usd(), 0.001)
	c.law_tax = clampf(_sum(revenue_ring) / yusd, 0.0, 0.4)
	c.law_spend = clampf(_sum(spend_ring) / yusd, 0.0, 0.4)
	var approval := c.law_spend * 0.4
	var stability := 0.0
	var invest := 0.0
	var unemp := 0.0
	var free := c.dem >= 4.0
	var seeded: Array = param("rights", [])
	for key: String in standing.rights:
		var on: bool = standing.rights[key].on
		if on and not key in seeded:
			approval += RIGHT_APPROVAL
			stability += RIGHT_STABILITY
		elif not on and key in seeded:
			approval -= RIGHT_APPROVAL * 2.0
			stability += RIGHT_STABILITY * (-1.0 if free else 0.5)
		if key == "propriedade":
			invest += 0.02 if on else -0.05
	approval -= standing.restrictions.size() * 0.008
	stability += standing.restrictions.size() * (0.002 if free else 0.005)
	approval -= standing.duties.size() * 0.003
	approval += standing.exceptions.size() * 0.001
	stability += minf(standing.institutions.size() * 0.003, 0.03)
	invest -= standing.requirements.size() * 0.006
	for key: String in standing.subsidies:
		invest += float(standing.subsidies[key].annual) / yusd
	if standing.minwage.has("valor"):
		var ratio := float(standing.minwage.valor.value) * 12.0 / maxf(c.gdp_pc() * 0.6, 1.0)
		approval += minf(ratio, 0.8) * 0.02
		unemp = clampf((ratio - 0.6) * 0.05, 0.0, 0.06)
	var extra := {"inequality": 0.0, "labor": 0.0, "tfp": 0.0, "evasion": 0.0}
	var world: GameWorld = _world.get_ref() if _world else null
	if world:
		for code: LawCode in LawCodes.all():
			var got := code.monthly(world, c, self)
			approval += float(got.get("approval", 0.0))
			stability += float(got.get("stability", 0.0))
			invest += float(got.get("invest", 0.0))
			unemp += float(got.get("unemp", 0.0))
			for key: String in extra:
				extra[key] += float(got.get(key, 0.0))
	c.law_approval = clampf(approval, -0.2, 0.2)
	c.law_stability = clampf(stability, -0.15, 0.15)
	c.law_invest = clampf(invest, -0.3, 0.3)
	c.law_unemp = clampf(unemp, -0.03, 0.08)
	c.law_inequality = clampf(extra.inequality, -0.12, 0.12)
	c.law_labor = clampf(extra.labor, -0.1, 0.05)
	c.law_tfp = clampf(extra.tfp, -0.01, 0.01)
	c.law_evasion = clampf(extra.evasion, -0.05, 0.3)


static func _sum(values: Array) -> float:
	var total := 0.0
	for v: float in values:
		total += v
	return total


# --- AI proposals ---------------------------------------------------------------------

## A party other than the player's sometimes presents a project close to its ideas.
func _ai_proposal(world: GameWorld) -> void:
	var c := world.player
	if c.dem < 4.0 or _rng.randf() >= AI_PROPOSAL_CHANCE:
		return
	var open := in_process().filter(func(n): return not n.get("by_player", false)).size()
	if open >= MAX_AI_PENDING:
		return
	var data: Dictionary = world.politics.data_of(iso)
	var authors: Array = data.parties.filter(func(p): return int(p.id) != int(data.player_party) and int(p.seats) > 0 and not p.members.is_empty())
	if authors.is_empty():
		return
	var party: Dictionary = authors[_rng.randi() % authors.size()]
	var taken := {}
	for norm: Dictionary in norms.values():
		# A defeated project only returns to the agenda two years later.
		if (norm.state != STATE_REJECTED and norm.state != STATE_INVALID) or world.year - int(norm.year) < 2:
			taken[norm.title] = true
	var options := []
	for template: Dictionary in LawTemplates.all():
		if not taken.has(template.title):
			options.append([Politics.distance(party, LawCompiler.position_of(template.build.call())), template])
	if options.is_empty():
		return
	options.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var best: Dictionary = options[_rng.randi_range(0, mini(2, options.size() - 1))][1]
	var member: Dictionary = party.members[0]
	var norm := new_norm(world, "ordinaria", "%s (%s)" % [member.name, party.short])
	norm.by_player = false
	norm["author_party"] = party.id
	norm.program = best.build.call()
	norm.title = best.title
	norm.ementa = best.ementa
	present(world, norm)


# --- Registry -----------------------------------------------------------------------------

func _log(world: GameWorld, norm: Dictionary, kind: String, before: String, after: String, result: String, who: String, event := "") -> void:
	audit.append({
		"who": who, "date": world.date_string(), "norm": int(norm.id), "label": norm_label(norm), "kind": kind,
		"before": before, "after": after, "result": result, "event": event,
	})
	if audit.size() > MAX_AUDIT:
		audit = audit.slice(audit.size() - MAX_AUDIT)


# --- Simulator ---------------------------------------------------------------------------

## Runs an article with a fictional person. Nothing goes into the game: the result stays only in the report.
## citizen: {age, money, income, value, tx, profession, unit, owner, licenses}; economy: country values.
func simulate(world: GameWorld, program: Dictionary, type: String, event: String, citizen: Dictionary, economy := {}) -> Dictionary:
	var compiled := LawCompiler.compile(program, compile_context(type))
	if not compiled.ok:
		return {"ok": false, "error": tr("A norma tem erros: corrija antes de simular."), "trace": [], "errors": compiled.errors, "ran": 0}
	var trace := []
	var ran := 0
	var effects := []
	var failure := ""
	for number: Variant in compiled.code:
		var article: Dictionary = compiled.code[number]
		if event != "" and article.event != event:
			continue
		ran += 1
		var engine := LawEngine.new()
		engine.individual = true
		engine.tracing = true
		var view := build_view(world, String(article.event), article.fields)
		view.count = 1.0
		view.subject = citizen.duplicate()
		for key: String in economy:
			view.game[key] = economy[key]
		engine.view = view
		engine.vars = {}
		var result := engine.run(article.code)
		trace.append(tr("Art. %d: %s") % [int(number), tr(LawCatalog.get_def(article.event).text)])
		trace.append_array(result.trace)
		if not result.ok:
			failure = String(result.error)
			trace.append(tr("ERRO: %s") % failure)
		effects.append_array(result.effects)
		if not result.waiting.is_empty():
			trace.append(tr("O restante roda depois da espera."))
	if ran == 0:
		trace.append(tr("Nenhum artigo responde a esse evento."))
	return {"ok": failure == "", "error": failure, "trace": trace, "effects": effects, "ran": ran, "errors": []}


# --- Export and import ---------------------------------------------------------------

func export_norm(norm: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var path := "%s%s_%d_%d.json" % [EXPORT_DIR, String(NORM_TYPES[norm.type].short).replace(".", ""), int(norm.number), int(norm.year)]
	var payload := {"format": EXPORT_FORMAT, "iso": iso, "type": norm.type, "title": norm.title, "ementa": norm.ementa, "program": _current_program(norm)}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return path


static func export_files() -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(EXPORT_DIR):
		return PackedStringArray()
	return DirAccess.get_files_at(EXPORT_DIR)


## Importing brings the norm in as a draft: it still goes through the compiler and the procedure here.
func import_norm(world: GameWorld, file_name: String) -> Dictionary:
	var f := FileAccess.open(EXPORT_DIR + file_name, FileAccess.READ)
	if f == null:
		return {"ok": false, "msg": tr("Arquivo não encontrado.")}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary or int(data.get("format", 0)) != EXPORT_FORMAT or not NORM_TYPES.has(String(data.get("type", ""))) or not data.get("program") is Dictionary:
		return {"ok": false, "msg": tr("Arquivo incompatível.")}
	if String(data.type) in ["constituicao", "emenda"]:
		return {"ok": false, "msg": tr("A Constituição é de cada país e não pode ser importada.")}
	var norm := new_norm(world, String(data.type))
	norm.title = String(data.get("title", ""))
	norm.ementa = String(data.get("ementa", ""))
	norm.program = data.program
	norm.program.next_id = int(norm.program.get("next_id", 1))
	var compiled := compile_norm(norm)
	var note := "" if compiled.ok else tr(" Há %d erro(s) de compatibilidade para corrigir.") % compiled.errors.size()
	return {"ok": true, "norm": norm, "msg": tr("%s importada como rascunho.%s") % [norm_label(norm), note]}


# --- Saving and loading -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"iso": iso, "norms": norms, "next_id": next_id, "constitution": constitution, "standing": standing, "licenses": licenses, "registry": registry,
		"obligations": obligations, "pending": pending, "variables": variables, "audit": audit, "fired": fired, "failures": failures,
		"revenue_ring": revenue_ring, "spend_ring": spend_ring, "last_war": last_war, "next_ministry_seq": next_ministry_seq, "rng_seed": _rng.seed, "rng_state": _rng.state,
	}


func from_dict(d: Dictionary, world: GameWorld) -> void:
	_world = weakref(world)
	for key: String in ["iso", "norms", "next_id", "constitution", "standing", "licenses", "registry", "obligations", "pending", "variables", "audit", "fired", "failures", "revenue_ring", "spend_ring", "last_war"]:
		if d.has(key):
			set(key, d[key])
	standing.get_or_add("budget_locks", {})
	standing.get_or_add("ministry_ops", {})
	standing.get_or_add("codes", {})
	next_ministry_seq = int(d.get("next_ministry_seq", 1))
	# Old saves: the Constitution gains the central bank article, with the situation the country already had.
	if world.player and constitution.has("articles") and not constitution.articles.any(func(a): return a.param == "cb_independent"):
		constitution.articles.append(_article(tr("Art. %d.") % (constitution.articles.size() + 1), tr("O banco central é independente do governo: {v}."), "cb_independent", world.player.cb_independent, false))
	_rng.seed = int(d.get("rng_seed", 1))
	_rng.state = int(d.get("rng_state", 0))
	# A published norm does not change silently: a tampered version in the file suspends the norm.
	for norm: Dictionary in norms.values():
		for version: Dictionary in norm.get("versions", []):
			if int(version.get("hash", 0)) != 0 and int(version.hash) != hash(var_to_str(version.program)):
				if norm.state == STATE_IN_FORCE:
					norm.state = STATE_SUSPENDED
					_purge_norm(norm.id)
				_log(world, norm, "Integridade", "", "", tr("Versão publicada não confere: norma suspensa"), tr("Sistema"))  # i18n
	revision += 1
