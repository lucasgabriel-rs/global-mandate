class_name LawEngine
extends RefCounted
## Executes an article's code without touching anything in the game: returns the list of effects, which is only
## applied if the execution ends well. There is no way to run arbitrary code: the engine only knows the
## instructions below, has a step limit and never reads anything outside the snapshot ("view") it receives.
##
## Aggregate mode: the subject is a group of "count" million people with the average values. A condition
## on the citizen holds for the fraction of the group where it is true, and each branch runs with that fraction's weight.
## Individual mode (simulator): the subject is one person, and every condition is worth 0 or 1.

const MAX_STEPS := 4000
const MAX_REPEAT := 200
const EACH_MEAN_SHARES := {"citizens": 1.0, "properties": 0.45, "companies": 0.03}

var view := {}
var individual := false
var tracing := false
var vars := {}
var effects: Array = []
var trace: Array = []
var error := ""
var waiting := {}

var _weight := 1.0
var _frames: Array = []
var _loops: Array = []
var _steps := 0


## state: continuation of a "wait" block. Without it, the article starts from the beginning.
func run(code: Array, state := {}) -> Dictionary:
	var pc := 0
	if not state.is_empty():
		pc = int(state.pc)
		_weight = float(state.weight)
		_frames = state.frames.duplicate(true)
		_loops = state.loops.duplicate(true)
	while pc < code.size() and error == "":
		_steps += 1
		if _steps > MAX_STEPS:
			error = tr("Limite de %d passos: a norma foi interrompida.") % MAX_STEPS
			break
		var ins: Array = code[pc]
		match ins[0]:
			"end":
				pc = code.size()
			"branch":
				var share := clampf(_number(ins[1]), 0.0, 1.0)
				_frames.append({"w": _weight, "s": share, "else": ins[2], "end": ins[3]})
				if tracing:
					_note(tr("Condição: %s") % _share_text(share))
				if share > 0.0:
					_weight *= share
					pc += 1
				else:
					_weight *= 1.0 - share
					pc = int(ins[2])
			"else":
				var frame: Dictionary = _frames[-1]
				if float(frame.s) < 1.0:
					_weight = float(frame.w) * (1.0 - float(frame.s))
					pc = int(frame.else)
				else:
					pc = int(frame.end)
			"end_if":
				_weight = float(_frames.pop_back().w)
				pc += 1
			"while":
				# A repetition has no partial weight: it continues while it holds for the majority.
				pc = pc + 1 if _number(ins[1]) >= 0.5 else int(ins[2])
			"jump":
				pc = int(ins[1])
			"repeat":
				var times := int(_number(ins[1]))
				if times < 0 or times > MAX_REPEAT:
					error = tr("Repetição fora do limite: %d vezes.") % times
					break
				if times == 0:
					pc = int(ins[2])
				else:
					_loops.append({"left": times - 1, "head": pc + 1, "exit": ins[2], "count": view.get("count", 1.0)})
					pc += 1
			"each":
				pc = _start_each(ins, pc)
			"next":
				var loop: Dictionary = _loops[-1]
				if int(loop.left) > 0:
					loop.left = int(loop.left) - 1
					if loop.has("units"):
						_enter_unit(loop.units[loop.units.size() - 1 - int(loop.left)])
					pc = int(loop.head)
				else:
					_leave_loop()
					pc += 1
			"break":
				for i in int(ins[2]):
					_weight = float(_frames.pop_back().w)
				if int(ins[1]) < 0:
					_leave_loop()
					pc = -int(ins[1])
				else:
					pc = int(ins[1])
			"set":
				var value: Variant = _eval(ins[2])
				if tracing:
					_note("%s = %s" % [ins[1], _show(value)])
				vars[ins[1]] = value
				pc += 1
			"wait":
				var days := int(_number(ins[1]))
				if tracing:
					_note(tr("Aguarda %d dias.") % days)
				waiting = {"days": days, "pc": pc + 1, "weight": _weight, "frames": _frames, "loops": _loops}
				pc = code.size()
			"act":
				_act(ins[1], ins[2], int(ins[3]))
				pc += 1
			_:
				error = tr("Instrução desconhecida: %s.") % ins[0]
	return {"ok": error == "", "error": error, "effects": effects if error == "" else [], "trace": trace, "vars": vars, "waiting": waiting, "steps": _steps}


func _start_each(ins: Array, pc: int) -> int:
	var kind: String = ins[1][1]
	var units: Array = view.get("unit_shares", {}).keys() if kind == "units" else []
	if kind == "units":
		if units.is_empty():
			return int(ins[2])
		_loops.append({"left": units.size() - 1, "head": pc + 1, "exit": ins[2], "count": view.get("count", 1.0), "units": units})
		_enter_unit(units[0])
		return pc + 1
	# In aggregate, "for each" is a single pass over the whole group: the values are already averages.
	var count: float = view.get("count", 1.0)
	_loops.append({"left": 0, "head": pc + 1, "exit": ins[2], "count": count})
	if not individual:
		view.count = count * float(EACH_MEAN_SHARES.get(kind, 1.0))
	return pc + 1


func _enter_unit(unit: Variant) -> void:
	var loop: Dictionary = _loops[-1]
	view.count = float(loop.count) * float(view.unit_shares[unit])
	vars["unidade"] = unit
	if tracing:
		_note(tr("Para a unidade %s") % unit)


func _leave_loop() -> void:
	view.count = _loops.pop_back().count


func _note(text: String) -> void:
	trace.append(text)


static func _share_text(share: float) -> String:
	if share >= 1.0:
		return "verdadeira"
	if share <= 0.0:
		return "falsa"
	return TranslationServer.translate("vale para %s do grupo") % UiKit.pct(share)


static func _show(value: Variant) -> String:
	if value is float or value is int:
		return UiKit.num(float(value), 2)
	return str(value)


# --- Expressions --------------------------------------------------------------------------

func _number(expr: Array) -> float:
	var value: Variant = _eval(expr)
	if value is float or value is int:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	if value == null:
		error = tr("Variável sem valor.")
		return 0.0
	error = tr("Tipos incompatíveis: \"%s\" não é um número.") % value
	return 0.0


func _eval(expr: Array) -> Variant:
	match expr[0]:
		"lit":
			return expr[1]
		"subject":
			return float(view.subject.get(expr[1], 0.0))
		"game":
			return float(view.game.get(expr[1], 0.0))
		"var":
			if not vars.has(expr[1]):
				error = tr("Variável não inicializada: %s.") % expr[1]
				return 0.0
			return vars[expr[1]]
		"math":
			var a := _number(expr[2])
			var b := _number(expr[3])
			var out := 0.0
			match expr[1]:
				"+": out = a + b
				"-": out = a - b
				"*": out = a * b
				"/":
					if is_zero_approx(b):
						error = tr("Divisão por zero.")
						return 0.0
					out = a / b
			if tracing:
				_note("%s %s %s = %s" % [_show(a), expr[1], _show(b), _show(out)])
			return out
		"pct":
			var rate := _number(expr[1])
			var base := _number(expr[2])
			var out := base * rate / 100.0
			if tracing:
				_note(tr("Valor tributável: %s moedas") % _show(base))
				_note(tr("Alíquota: %s%%") % _show(rate))
				_note(tr("Calculado: %s moedas") % _show(out))
			return out
		"cmp":
			return _compare(expr)
		"between":
			var subject := _subject_share(expr[1], ">=", _number(expr[2]))
			if subject >= 0.0:
				var above := _subject_share(expr[1], ">", _number(expr[3]))
				return clampf(subject - above, 0.0, 1.0)
			var v := _number(expr[1])
			return 1.0 if v >= _number(expr[2]) and v <= _number(expr[3]) else 0.0
		"and":
			return _number(expr[1]) * _number(expr[2])
		"or":
			var a := _number(expr[1])
			var b := _number(expr[2])
			return 1.0 - (1.0 - a) * (1.0 - b)
		"not":
			return 1.0 - _number(expr[1])
		"profession":
			if individual:
				return 1.0 if view.subject.get("profession", "") == expr[1] else 0.0
			return float(view.get("professions", {}).get(expr[1], 0.0))
		"territory":
			if int(expr[1]) < 0:
				return 1.0
			if individual:
				return 1.0 if int(view.subject.get("unit", -1)) == int(expr[1]) else 0.0
			return float(view.get("unit_shares", {}).get(int(expr[1]), 0.0))
		"has_money":
			var amount := _number(expr[1])
			return _dist_share("money", ">=", amount)
		"owner":
			if individual:
				return 1.0 if view.subject.get("owner", true) else 0.0
			return float(view.get("owner_share", 0.45))
		"license":
			if individual:
				return 1.0 if view.subject.get("licenses", []).has(expr[1]) else 0.0
			return float(view.get("licenses", {}).get(expr[1], 0.0))
		"period":
			var today: String = view.get("date", "")
			return 1.0 if today >= String(expr[1]) and today <= String(expr[2]) else 0.0
		"institution":
			return 1.0 if view.get("institutions", {}).has(expr[1]) else 0.0
		"norm":
			return 1.0 if view.get("norms_in_force", {}).has(int(expr[1])) else 0.0
	error = tr("Expressão desconhecida: %s.") % expr[0]
	return 0.0


func _compare(expr: Array) -> Variant:
	var op: String = expr[1]
	if op == "==" or op == "!=":
		var a: Variant = _eval(expr[2])
		var b: Variant = _eval(expr[3])
		var same: bool = is_equal_approx(float(a), float(b)) if (a is float or a is int) and (b is float or b is int) else a == b
		return 1.0 if same == (op == "==") else 0.0
	var share := _subject_share(expr[2], op, _number(expr[3]))
	if share >= 0.0:
		return share
	var left := _number(expr[2])
	var right := _number(expr[3])
	match op:
		">": return 1.0 if left > right else 0.0
		"<": return 1.0 if left < right else 0.0
		">=": return 1.0 if left >= right else 0.0
		"<=": return 1.0 if left <= right else 0.0
	return 0.0


## If the comparison is about citizen data, in aggregate it is worth the group's fraction. -1: not the case.
func _subject_share(expr: Array, op: String, limit: float) -> float:
	if individual or expr[0] != "subject":
		return -1.0
	return _dist_share(expr[1], op, limit)


func _dist_share(field: String, op: String, limit: float) -> float:
	var mean: float = float(view.subject.get(field, 0.0))
	if individual:
		match op:
			">=": return 1.0 if mean >= limit else 0.0
			">": return 1.0 if mean > limit else 0.0
			"<": return 1.0 if mean < limit else 0.0
			"<=": return 1.0 if mean <= limit else 0.0
	var above := above_share(field, mean, limit, float(view.get("inequality", 0.38)))
	return above if op == ">=" or op == ">" else 1.0 - above


## Part of the group above the limit. Age: triangular pyramid from 0 to 2.5 averages. Money and
## income: lognormal distribution, with the dispersion coming from the country's inequality index.
static func above_share(field: String, mean: float, limit: float, inequality: float) -> float:
	if mean <= 0.0:
		return 0.0
	if field == "age":
		var top := mean * 2.5
		var x := clampf(limit / top, 0.0, 1.0)
		return (1.0 - x) * (1.0 - x)
	if limit <= 0.0:
		return 1.0
	var sigma := clampf(inequality * 2.4, 0.3, 1.6)
	var mu := log(mean) - sigma * sigma * 0.5
	var z := (log(limit) - mu) / sigma
	return 1.0 - _normal_cdf(z)


static func _normal_cdf(z: float) -> float:
	# Logistic approximation of the standard normal, enough to split a group.
	return 1.0 / (1.0 + exp(-1.702 * z))


# --- Actions ------------------------------------------------------------------------------

func _act(op: String, args: Dictionary, block: int) -> void:
	var values := {}
	for key: String in args:
		values[key] = _eval(args[key])
		if error != "":
			return
	var count: float = float(view.get("count", 1.0))
	var effect := {"op": op, "values": values, "weight": _weight, "count": count, "block": block}
	# The tax respects the exemption and limit in force.
	if op in ["ec_charge", "ec_fee"]:
		var name_ := String(values.get("name", ""))
		var amount := maxf(float(values.get("amount", 0.0)), 0.0)
		var cap: Variant = view.get("caps", {}).get(name_)
		if cap != null:
			amount = minf(amount, float(cap))
		amount *= 1.0 - clampf(float(view.get("exemptions", {}).get(name_, 0.0)), 0.0, 1.0)
		values["amount"] = amount
	elif op == "ec_contribution":
		values["amount"] = float(view.subject.get("income", 0.0)) / 12.0 * float(values.get("rate", 0.0)) / 100.0
	effects.append(effect)
	if tracing:
		_note(_describe(op, values, count))


func _describe(op: String, values: Dictionary, count: float) -> String:
	var amount := float(values.get("amount", 0.0))
	var scale := _weight * count
	match op:
		"ac_obligation":
			return tr("Obrigação tributária criada: %s moedas, vence em %d dias.") % [_show(amount * scale), int(values.get("days", 0))]
		"ac_fine":
			return tr("Multa aplicada: %s moedas.") % _show(amount * scale)
		"ac_benefit":
			return tr("Benefício concedido: %s moedas.") % _show(amount * scale)
		"ec_charge", "ec_fee", "ec_contribution":
			return tr("%s cobrado: %s moedas.") % [values.get("name", tr("Tributo")), _show(amount * scale)]
	var def := LawCatalog.get_def(op)
	return tr("Executado: %s.") % tr(def.get("text", op)).format(_plain(values), "{_}")


static func _plain(values: Dictionary) -> Dictionary:
	var out := {}
	for key: String in values:
		out[key] = _show(values[key])
	return out


static func valid_date(text: String) -> bool:
	var parts := text.split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var month := int(parts[1])
	var day := int(parts[2])
	return int(parts[0]) >= 1900 and month >= 1 and month <= 12 and day >= 1 and day <= 31
