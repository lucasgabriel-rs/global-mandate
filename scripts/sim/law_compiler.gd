class_name LawCompiler
extends RefCounted
## Turns the blocks into instructions: reads the structure, verifies, generates an intermediate form and, from it,
## the flat code that the engine executes. The interface never runs the blocks directly.

const MAX_BLOCKS := 400
const NUMERIC := ["num", "money", "pct", "days"]
const COMPARE := {"op_eq": "==", "op_ne": "!=", "op_gt": ">", "op_lt": "<", "op_ge": ">=", "op_le": "<="}
const MATH := {"m_add": "+", "m_sub": "-", "m_mul": "*", "m_div": "/"}
const SUBJECT := {"sb_age": "age", "sb_money": "money", "sb_income": "income", "sb_value": "value", "sb_tx": "tx"}
const LOOPS := ["fl_while", "fl_repeat", "fl_foreach"]

var _errors: Array = []
var _warnings: Array = []
var _rank := 100
var _context := {}
var _program := {}
var _defined := {}
var _var_articles := {}
var _article := 0


## context: {"rank": norm hierarchy, "norms": {number: true}, "units": {id: true}, "institutions": {name: true}}.
static func compile(program: Dictionary, context := {}) -> Dictionary:
	return LawCompiler.new()._run(program, context)


func _run(program: Dictionary, context: Dictionary) -> Dictionary:
	_program = program
	_context = context
	_rank = int(context.get("rank", 100))
	var articles := _read()
	_check_program(articles)
	var ir := []
	var code := {}
	if _errors.is_empty():
		for a: Dictionary in articles:
			if a.repealed:
				continue
			var body := _ir_list(a.blocks.slice(1))
			ir.append({"article": a.number, "event": a.blocks[0].type, "fields": _event_fields(a.blocks[0]), "body": body})
		code = _generate(ir)
	return {
		"ok": _errors.is_empty(), "errors": _errors, "warnings": _warnings, "ir": ir, "code": code,
		"position": position_of(program), "text": LawProgram.legal_text(program),
	}


# --- Stage 1: reading ------------------------------------------------------------------

func _read() -> Array:
	var articles := []
	var number := 0
	for stack: Dictionary in _program.get("stacks", []):
		number += 1
		articles.append({"number": number, "blocks": stack.get("blocks", []), "repealed": stack.get("repealed", false)})
	return articles


func _err(block: Variant, text: String) -> void:
	_errors.append({"block": int(block.id) if block is Dictionary else -1, "text": text})


func _warn(block: Variant, text: String) -> void:
	_warnings.append({"block": int(block.id) if block is Dictionary else -1, "text": text})


# --- Stage 2: verification --------------------------------------------------------------

func _check_program(articles: Array) -> void:
	var active := articles.filter(func(a): return not a.repealed)
	if active.is_empty():
		_err(null, tr("A norma não tem nenhum artigo: coloque um bloco de evento na área de programação."))
		return
	var count := LawProgram.all_blocks(_program).size()
	if count > MAX_BLOCKS:
		_err(null, tr("A norma tem %d blocos; o limite é %d.") % [count, MAX_BLOCKS])
	# Variables defined in any article persist between executions.
	for block: Dictionary in LawProgram.all_blocks(_program):
		if block.type == "var_set":
			_defined[String(block.fields.get("name", ""))] = true
	for a: Dictionary in active:
		LawProgram.walk(a.blocks, func(b):
			if b.type == "var_set":
				_var_articles.get_or_add(String(b.fields.get("name", "")), {})[a.number] = true)
	for a: Dictionary in active:
		_article = a.number
		var first: Dictionary = a.blocks[0]
		var def := LawCatalog.get_def(first.type)
		if def.is_empty():
			_err(first, tr("Art. %d: evento inexistente (%s).") % [a.number, first.type])
			continue
		if def.kind != "event":
			_err(first, tr("Art. %d: bloco solto. Todo artigo precisa começar com um evento.") % a.number)
		_check_block_fields(first)
		_check_rank(first)
		var set_here := {}
		_check_list(a.blocks.slice(1), 0, set_here)
		if a.blocks.size() == 1:
			_warn(first, tr("Art. %d: o evento não dispara nenhuma ação.") % a.number)


func _check_list(blocks: Array, loops: int, set_here: Dictionary) -> void:
	var dead := false
	for block: Dictionary in blocks:
		if dead:
			_warn(block, tr("Este bloco nunca será executado: há um encerramento antes dele."))
			dead = false
		var def := LawCatalog.get_def(block.type)
		if def.is_empty():
			_err(block, tr("Bloco inexistente: %s.") % block.type)
			continue
		if def.kind == "event":
			_err(block, tr("Um evento só pode iniciar um artigo."))
			continue
		if def.kind == "value" or def.kind == "bool":
			_err(block, tr("Conexão inválida: \"%s\" é um valor e precisa entrar em um campo.") % LawProgram.block_text(block, true))
			continue
		_check_rank(block)
		_check_block_fields(block, set_here)
		if block.type == "var_set":
			set_here[String(block.fields.get("name", ""))] = true
		if block.type == "fl_break" and loops == 0:
			_err(block, tr("Fluxo inválido: \"Interromper\" só funciona dentro de uma repetição."))
		if block.type == "fl_end" or block.type == "fl_break":
			dead = true
		if block.type == "fl_while":
			_check_loop(block)
		for slot: String in block.slots:
			if block.slots[slot].is_empty():
				_warn(block, tr("\"%s\" tem uma parte vazia.") % LawProgram.block_text(block, true))
			_check_list(block.slots[slot], loops + (1 if block.type in LOOPS else 0), set_here.duplicate())


func _check_loop(block: Dictionary) -> void:
	var cond: Variant = block.plugs.get("cond")
	if cond == null:
		return
	if not _has_variable(cond) and not _contains_type(block.slots.get("do", []), "fl_wait"):
		_warn(block, tr("Esta repetição pode não terminar. O motor interrompe depois de %d passos.") % LawEngine.MAX_STEPS)


func _has_variable(block: Dictionary) -> bool:
	var found := [false]
	LawProgram.walk([block], func(b): if b.type == "var_get": found[0] = true)
	return found[0]


func _contains_type(blocks: Array, type: String) -> bool:
	var found := [false]
	LawProgram.walk(blocks, func(b): if b.type == type: found[0] = true)
	return found[0]


func _check_rank(block: Dictionary) -> void:
	var def := LawCatalog.get_def(block.type)
	if int(def.get("rank", 0)) > _rank:
		_err(block, tr("Ação não autorizada: \"%s\" exige uma norma de hierarquia maior.") % LawProgram.block_text(block, true))


func _check_block_fields(block: Dictionary, set_here := {}) -> void:
	var def := LawCatalog.get_def(block.type)
	var specs: Dictionary = def.get("fields", {})
	for key: String in specs:
		var spec: Dictionary = specs[key]
		if block.plugs.has(key):
			var plug: Dictionary = block.plugs[key]
			var pdef := LawCatalog.get_def(plug.type)
			if pdef.is_empty():
				_err(plug, tr("Bloco inexistente: %s.") % plug.type)
				continue
			if not LawProgram.accepts(spec, plug):
				_err(plug, tr("Tipos incompatíveis: \"%s\" não serve para este campo.") % LawProgram.block_text(plug, true))
				continue
			_check_rank(plug)
			_check_block_fields(plug, set_here)
			continue
		if not block.fields.has(key):
			if block.type not in ["fl_if", "fl_ifelse", "fl_while", "op_and", "op_or", "op_not"]:
				_err(block, tr("Parâmetro ausente em \"%s\".") % LawProgram.block_text(block, true))
			continue
		_check_literal(block, key, spec, block.fields[key])
	_check_block_logic(block, set_here)


func _check_literal(block: Dictionary, key: String, spec: Dictionary, value: Variant) -> void:
	match spec.t:
		"text", "var", "ref":
			if String(value).strip_edges() == "":
				_err(block, tr("Parâmetro ausente: preencha o texto em \"%s\".") % LawProgram.block_text(block, true))
		"date":
			if not LawEngine.valid_date(String(value)):
				_err(block, tr("Data inválida (%s). Use o formato aaaa-mm-dd.") % value)
		"choice":
			if not LawCatalog.choice_list(spec.of).has(value):
				_err(block, tr("Opção inexistente: %s.") % value)
		"money", "days":
			if not (value is float or value is int):
				_err(block, tr("Tipos incompatíveis: era esperado um número em \"%s\".") % key)
			elif float(value) < 0.0:
				_err(block, tr("Operação impossível: valor negativo em \"%s\".") % LawProgram.block_text(block, true))
		"pct":
			if not (value is float or value is int):
				_err(block, tr("Tipos incompatíveis: era esperado um número em \"%s\".") % key)
			elif float(value) < 0.0 or float(value) > 100.0:
				_err(block, tr("Operação impossível: porcentagem fora de 0 a 100."))
		"num":
			if not (value is float or value is int):
				_err(block, tr("Tipos incompatíveis: era esperado um número em \"%s\".") % key)
		"ministry":
			if String(value) == "":
				_err(block, tr("Parâmetro ausente: escolha o ministério em \"%s\".") % LawProgram.block_text(block, true))
			elif _context.has("ministries") and not _context.ministries.has(String(value)) and not _will_create(String(value)):
				_err(block, tr("Referência inexistente: não há ministério \"%s\".") % value)
		"company":
			if String(value) == "":
				_err(block, tr("Parâmetro ausente: escolha a empresa em \"%s\".") % LawProgram.block_text(block, true))
			elif _context.has("companies") and not _context.companies.has(String(value)):
				_err(block, tr("Referência inexistente: não há empresa \"%s\" no país.") % value)
		"unit":
			if int(value) >= 0 and _context.has("units") and not _context.units.has(int(value)):
				_err(block, tr("Referência inexistente: essa unidade do território não existe mais."))


func _literal_number(block: Dictionary, key: String) -> Variant:
	if block.plugs.has(key) or not block.fields.has(key):
		return null
	var value: Variant = block.fields[key]
	return float(value) if value is float or value is int else null


func _check_block_logic(block: Dictionary, set_here: Dictionary) -> void:
	match block.type:
		"m_div":
			var divisor: Variant = _literal_number(block, "b")
			if divisor != null and is_zero_approx(divisor):
				_err(block, tr("Operação impossível: divisão por zero."))
		"fl_repeat":
			var times: Variant = _literal_number(block, "times")
			if times != null and (times < 1.0 or times > LawEngine.MAX_REPEAT):
				_err(block, tr("Operação impossível: repetir de 1 a %d vezes.") % LawEngine.MAX_REPEAT)
		"op_between":
			var lo: Variant = _literal_number(block, "lo")
			var hi: Variant = _literal_number(block, "hi")
			if lo != null and hi != null and lo > hi:
				_err(block, tr("Condição contraditória: o intervalo começa depois de terminar."))
		"cd_period":
			if String(block.fields.get("from", "")) > String(block.fields.get("to", "")):
				_err(block, tr("Condição contraditória: o período começa depois de terminar."))
		"op_and":
			_check_contradiction(block)
		"var_get", "var_change":
			var name_ := String(block.fields.get("name", ""))
			if not _defined.has(name_):
				_err(block, tr("Variável não inicializada: \"%s\" nunca é definida nesta norma.") % name_)
			elif not set_here.has(name_) and _var_articles.get(name_, {}).keys() == [_article]:
				_err(block, tr("Variável não inicializada: \"%s\" é usada antes de ser definida.") % name_)
		"ec_privatize":
			var name_ := String(block.fields.get("company", ""))
			if _context.has("companies") and _context.companies.has(name_) and float(_context.companies[name_]) <= 0.0:
				_err(block, tr("Operação impossível: o Estado não tem participação em %s.") % name_)
		"ec_nationalize":
			var name_ := String(block.fields.get("company", ""))
			var share: Variant = _literal_number(block, "stake")
			if share != null and _context.has("companies") and _context.companies.has(name_) and float(_context.companies[name_]) * 100.0 >= share - 0.1:
				_warn(block, tr("O Estado já tem %d%% de %s: nada a comprar.") % [int(roundf(float(_context.companies[name_]) * 100.0)), name_])
		"cd_norm":
			if _context.has("norms") and not _context.norms.has(int(block.fields.get("norm", -1))):
				_err(block, tr("Referência inexistente: não há norma nº %s.") % block.fields.get("norm", ""))
		"cd_institution":
			if _context.has("institutions") and not _context.institutions.has(String(block.fields.get("institution", ""))) and not _creates_institution(String(block.fields.get("institution", ""))):
				_warn(block, tr("A instituição \"%s\" ainda não existe.") % block.fields.get("institution", ""))
		"fl_if", "fl_ifelse", "fl_while":
			if not block.plugs.has("cond"):
				_err(block, tr("Parâmetro ausente: encaixe uma condição em \"%s\".") % LawProgram.block_text(block, true))
		"op_or", "op_not":
			if not block.plugs.has("a") or (block.type == "op_or" and not block.plugs.has("b")):
				_err(block, tr("Parâmetro ausente: encaixe as condições do operador."))


func _will_create(name_: String) -> bool:
	for b: Dictionary in LawProgram.all_blocks(_program):
		if b.type in ["ad_min_create", "ad_min_merge"] and String(b.fields.get("name", "")) == name_:
			return true
	return false


func _creates_institution(name_: String) -> bool:
	for b: Dictionary in LawProgram.all_blocks(_program):
		if b.type == "ac_institution" and String(b.fields.get("name", "")) == name_:
			return true
	return false


## "A and not A", "x > 5 and x < 3": never true.
func _check_contradiction(block: Dictionary) -> void:
	var a: Variant = block.plugs.get("a")
	var b: Variant = block.plugs.get("b")
	if a == null or b == null:
		_err(block, tr("Parâmetro ausente: encaixe as duas condições do operador E."))
		return
	if b.type == "op_not" and b.plugs.has("a") and _same(a, b.plugs.a):
		_err(block, tr("Condição contraditória: \"%s\" nunca é verdadeira.") % LawProgram.block_text(block, true))
	elif a.type == "op_not" and a.plugs.has("a") and _same(a.plugs.a, b):
		_err(block, tr("Condição contraditória: \"%s\" nunca é verdadeira.") % LawProgram.block_text(block, true))
	if a.type in COMPARE and b.type in COMPARE and a.plugs.has("a") and b.plugs.has("a") and _same(a.plugs.a, b.plugs.a):
		var av: Variant = _literal_number(a, "b")
		var bv: Variant = _literal_number(b, "b")
		if av != null and bv != null:
			var low_a: bool = a.type in ["op_gt", "op_ge"]
			var low_b: bool = b.type in ["op_gt", "op_ge"]
			var high_a: bool = a.type in ["op_lt", "op_le"]
			var high_b: bool = b.type in ["op_lt", "op_le"]
			if (low_a and high_b and av >= bv) or (high_a and low_b and bv >= av):
				_err(block, tr("Condição contraditória: \"%s\" nunca é verdadeira.") % LawProgram.block_text(block, true))


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return LawProgram.block_text(a) == LawProgram.block_text(b)


# --- Stage 3: intermediate form --------------------------------------------------------

func _event_fields(block: Dictionary) -> Dictionary:
	return block.fields.duplicate()


func _ir_list(blocks: Array) -> Array:
	var out := []
	for block: Dictionary in blocks:
		out.append(_ir_statement(block))
	return out


func _ir_statement(block: Dictionary) -> Dictionary:
	var node := {"op": block.type, "block": int(block.id)}
	var args := {}
	for key: String in LawCatalog.get_def(block.type).get("fields", {}):
		args[key] = _ir_field(block, key)
	node["args"] = args
	for slot: String in block.slots:
		node[slot] = _ir_list(block.slots[slot])
	return node


func _ir_field(block: Dictionary, key: String) -> Array:
	if block.plugs.has(key):
		return _ir_expr(block.plugs[key])
	return ["lit", block.fields.get(key)]


func _ir_expr(block: Dictionary) -> Array:
	var type: String = block.type
	if SUBJECT.has(type):
		return ["subject", SUBJECT[type]]
	if COMPARE.has(type):
		return ["cmp", COMPARE[type], _ir_field(block, "a"), _ir_field(block, "b")]
	if MATH.has(type):
		return ["math", MATH[type], _ir_field(block, "a"), _ir_field(block, "b")]
	match type:
		"gm_value": return ["game", block.fields.get("field")]
		"var_get": return ["var", block.fields.get("name")]
		"m_pct", "ec_calc": return ["pct", _ir_field(block, "rate"), _ir_field(block, "base")]
		"op_and": return ["and", _ir_field(block, "a"), _ir_field(block, "b")]
		"op_or": return ["or", _ir_field(block, "a"), _ir_field(block, "b")]
		"op_not": return ["not", _ir_field(block, "a")]
		"op_between": return ["between", _ir_field(block, "a"), _ir_field(block, "lo"), _ir_field(block, "hi")]
		"cd_profession": return ["profession", block.fields.get("profession")]
		"cd_territory": return ["territory", int(block.fields.get("unit", -1))]
		"cd_money": return ["has_money", _ir_field(block, "amount")]
		"cd_owner": return ["owner"]
		"cd_license": return ["license", block.fields.get("license")]
		"cd_period": return ["period", block.fields.get("from"), block.fields.get("to")]
		"cd_institution": return ["institution", block.fields.get("institution")]
		"cd_norm": return ["norm", int(block.fields.get("norm", -1))]
	return ["lit", 0.0]


# --- Stage 4: flat code -------------------------------------------------------------

func _generate(ir: Array) -> Dictionary:
	var out := {}
	for article: Dictionary in ir:
		var list := []
		_emit_list(article.body, list, [])
		list.append(["end"])
		out[article.article] = {"event": article.event, "fields": article.fields, "code": list, "conditions": _count_conditions(article.body)}
	return out


func _count_conditions(body: Array) -> int:
	var total := 0
	for node: Dictionary in body:
		if node.op in ["fl_if", "fl_ifelse"]:
			total += 1
		total += _count_conditions(node.get("do", [])) + _count_conditions(node.get("else", []))
	return total


## breaks receives the "break" instructions of the current repetition; ifs counts the open "if" blocks inside it.
func _emit_list(nodes: Array, list: Array, breaks: Array, ifs := 0) -> void:
	for node: Dictionary in nodes:
		match node.op:
			"fl_if", "fl_ifelse":
				var branch := ["branch", node.args.cond, -1, -1]
				list.append(branch)
				_emit_list(node.get("do", []), list, breaks, ifs + 1)
				list.append(["else"])
				branch[2] = list.size()
				_emit_list(node.get("else", []), list, breaks, ifs + 1)
				branch[3] = list.size()
				list.append(["end_if"])
			"fl_while":
				var head := list.size()
				var loop := ["while", node.args.cond, -1]
				list.append(loop)
				var inner := []
				_emit_list(node.get("do", []), list, inner)
				list.append(["jump", head])
				loop[2] = list.size()
				for b: Array in inner:
					b[1] = list.size()
			"fl_repeat", "fl_foreach":
				var loop := ["repeat" if node.op == "fl_repeat" else "each", node.args.times if node.op == "fl_repeat" else node.args.set, -1]
				list.append(loop)
				var inner := []
				_emit_list(node.get("do", []), list, inner)
				list.append(["next"])
				loop[2] = list.size()
				for b: Array in inner:
					b[1] = -list.size()
			"fl_wait":
				list.append(["wait", node.args.days])
			"fl_break":
				var b := ["break", 0, ifs]
				list.append(b)
				breaks.append(b)
			"fl_end":
				list.append(["end"])
			"var_set", "var_change":
				list.append(["set", node.args.name[1], node.args.value])
			_:
				list.append(["act", node.op, node.args, node.block])


# --- Political position -------------------------------------------------------------------

## Where the norm falls on the compass: each block pulls to one side, like the budget weights.
static func position_of(program: Dictionary) -> Dictionary:
	var econ := 0.0
	var social := 0.0
	var seen := 0
	for block: Dictionary in LawProgram.all_blocks(program):
		var def := LawCatalog.get_def(block.type)
		if def.has("econ") or def.has("social"):
			econ += float(def.get("econ", 0.0))
			social += float(def.get("social", 0.0))
			seen += 1
	var scale := 1.0 / maxf(sqrt(float(seen)), 1.0)
	return {"econ": clampf(econ * scale, -1.0, 1.0), "social": clampf(social * scale, -1.0, 1.0)}
