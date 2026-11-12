class_name CodeTrabalhista
extends LawCode
## Labor Code: Minimum wage, working hours, vacation, unions, strikes and pensions.
##
## Each month's effect is measured against the code's original text (the first version of the norm): the country
## starts as the game was calibrated, and only what the player changes weighs. The minimum wage writes to
## `standing.minwage`, the same place as the advanced block, and its effect lives in `Legislation._update_macro`.

## Block → item stored in `standing.codes` ("trabalhista:item"). Strikes have one item per sector.
const ITEMS := {
	"tb_minwage": "salario_minimo", "tb_hours": "jornada", "tb_overtime": "horas_extras", "tb_vacation": "ferias",
	"tb_13th": "decimo_terceiro", "tb_fgts": "fgts", "tb_severance": "indenizacao", "tb_unemp_ins": "seguro_desemprego",
	"tb_parental": "licencas", "tb_unions": "sindicatos", "tb_outsourcing": "terceirizacao", "tb_gig": "aplicativos",
	"tb_min_age": "idade_minima", "tb_retirement": "aposentadoria", "tb_pension_cap": "teto_previdencia",
}
const STRIKE_SECTORS := ["privado", "publico", "essencial"]


func _init() -> void:
	id = "trabalhista"
	title = "Código Trabalhista"
	ementa = "Salário mínimo, jornada, férias, sindicatos, greve e previdência."
	category = {"id": "trabalhista", "label": "Trabalho", "color": Color("3a7fb0")}


func blocks() -> Array:
	var cat: String = category.id
	var law := LawCatalog.RANK_LAW
	return [
		{"id": "tb_minwage", "cat": cat, "kind": "statement", "text": "Salário mínimo de {amount} por mês", "fields": {"amount": {"t": "money", "d": 300}}, "rank": law, "econ": -0.45, "social": 0.05},
		{"id": "tb_hours", "cat": cat, "kind": "statement", "text": "Jornada máxima de {hours} horas por semana", "fields": {"hours": {"t": "num", "d": 44}}, "rank": law, "econ": -0.2},
		{"id": "tb_overtime", "cat": cat, "kind": "statement", "text": "Hora extra paga com adicional de {pct}%", "fields": {"pct": {"t": "pct", "d": 50}}, "rank": law, "econ": -0.15},
		{"id": "tb_vacation", "cat": cat, "kind": "statement", "text": "Férias anuais remuneradas de {days} dias", "fields": {"days": {"t": "days", "d": 30}}, "rank": law, "econ": -0.15},
		{"id": "tb_13th", "cat": cat, "kind": "statement", "text": "Décimo terceiro salário obrigatório: {on}", "fields": {"on": {"t": "bool", "d": true}}, "rank": law, "econ": -0.2},
		{"id": "tb_fgts", "cat": cat, "kind": "statement", "text": "Fundo de garantia com depósito de {deposit}% do salário ao mês e multa de {fine}% do saldo na demissão sem justa causa", "fields": {"deposit": {"t": "pct", "d": 8}, "fine": {"t": "pct", "d": 40}}, "rank": law, "econ": -0.25},
		{"id": "tb_severance", "cat": cat, "kind": "statement", "text": "Indenização de {weeks} semanas de salário por ano trabalhado na demissão sem justa causa", "fields": {"weeks": {"t": "num", "d": 2}}, "rank": law, "econ": -0.2},
		{"id": "tb_unemp_ins", "cat": cat, "kind": "statement", "text": "Seguro-desemprego por {months} meses, pagando {pct}% do último salário", "fields": {"months": {"t": "num", "d": 5}, "pct": {"t": "pct", "d": 60}}, "rank": law, "econ": -0.3, "social": 0.05},
		{"id": "tb_parental", "cat": cat, "kind": "statement", "text": "Licença-maternidade de {maternity} dias e licença-paternidade de {paternity} dias", "fields": {"maternity": {"t": "days", "d": 120}, "paternity": {"t": "days", "d": 5}}, "rank": law, "econ": -0.15, "social": 0.1},
		{"id": "tb_unions", "cat": cat, "kind": "statement", "text": "Sindicalização {mode}", "fields": {"mode": {"t": "choice", "of": "tb_union_mode", "d": "livre"}}, "rank": law, "social": 0.1},
		{"id": "tb_strike", "cat": cat, "kind": "statement", "text": "Greve em {sector}: {mode}", "fields": {"sector": {"t": "choice", "of": "tb_strike_sector", "d": "privado"}, "mode": {"t": "choice", "of": "tb_strike_mode", "d": "pleno"}}, "rank": law, "social": 0.2},
		{"id": "tb_outsourcing", "cat": cat, "kind": "statement", "text": "Terceirização {mode}", "fields": {"mode": {"t": "choice", "of": "tb_outsourcing_mode", "d": "meio"}}, "rank": law, "econ": 0.2},
		{"id": "tb_gig", "cat": cat, "kind": "statement", "text": "Quem trabalha por aplicativo é {mode}", "fields": {"mode": {"t": "choice", "of": "tb_gig_mode", "d": "autonomo"}}, "rank": law, "econ": 0.1},
		{"id": "tb_min_age", "cat": cat, "kind": "statement", "text": "Idade mínima para trabalhar de {age} anos, ou {apprentice} como aprendiz", "fields": {"age": {"t": "num", "d": 16}, "apprentice": {"t": "num", "d": 14}}, "rank": law, "social": 0.1},
		{"id": "tb_retirement", "cat": cat, "kind": "statement", "text": "Aposentadoria aos {men} anos (homens) e {women} anos (mulheres), com {years} anos de contribuição", "fields": {"men": {"t": "num", "d": 65}, "women": {"t": "num", "d": 62}, "years": {"t": "num", "d": 15}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.2},
		{"id": "tb_pension_cap", "cat": cat, "kind": "statement", "text": "Teto do benefício previdenciário de {amount} por mês", "fields": {"amount": {"t": "money", "d": 1500}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.15},
	]


func choices() -> Dictionary:
	return {
		"tb_union_mode": {"obrigatoria": "obrigatória, com contribuição de todos", "livre": "livre", "proibida": "proibida"},
		"tb_strike_sector": {"privado": "o setor privado", "publico": "o serviço público", "essencial": "os serviços essenciais"},
		"tb_strike_mode": {"pleno": "permitida", "minimo": "permitida com serviço mínimo", "proibida": "proibida"},
		"tb_outsourcing_mode": {"total": "permitida em qualquer atividade", "meio": "permitida só em atividades-meio", "proibida": "proibida"},
		"tb_gig_mode": {"autonomo": "autônomo, sem vínculo", "hibrido": "autônomo com contribuição e seguro", "empregado": "empregado com carteira"},
	}


## How rich the country is, from 0 (US$ 1 thousand per person) to 1 (US$ 60 thousand).
static func wealth(c: Country) -> float:
	return clampf(log(maxf(c.gdp_pc(), 1.0) / 1000.0) / log(60.0), 0.0, 1.0)


## The values the country starts with: protections grow with income; closed regimes control unions and strikes.
func _defaults(c: Country) -> Dictionary:
	var f := wealth(c)
	var lam := c.region == "LAM"
	var eur := c.region == "EUR"
	var men := roundi(58.0 + 9.0 * f)
	var out := {
		"salario_minimo": {"amount": snappedf(c.gdp_pc() * 0.025, 10.0)},
		"jornada": {"hours": 40 if f > 0.6 else (44 if f > 0.3 else 48)},
		"horas_extras": {"pct": 50},
		"ferias": {"days": 30 if lam or eur else roundi(10.0 + 12.0 * f)},
		"decimo_terceiro": {"on": lam or c.iso in ["PRT", "ITA", "ESP", "GRC", "PHL", "AUT", "DEU"]},
		"fgts": {"deposit": 0, "fine": 0},
		"indenizacao": {"weeks": 3 if eur else (2 if c.dem >= 4.0 else 1)},
		"seguro_desemprego": {"months": 0 if f < 0.2 else roundi(2.0 + 8.0 * f), "pct": 60},
		"licencas": {"maternity": roundi(60.0 + 100.0 * f), "paternity": roundi(14.0 * f)},
		"sindicatos": {"mode": "livre" if c.dem >= 4.0 else "obrigatoria"},
		"terceirizacao": {"mode": "total" if f > 0.5 else "meio"},
		"aplicativos": {"mode": "hibrido" if eur and f > 0.6 else "autonomo"},
		"idade_minima": {"age": 16 if f > 0.4 else 14, "apprentice": 14 if f > 0.4 else 12},
		"aposentadoria": {"men": men, "women": men - (5 if lam or f < 0.6 else 0), "years": roundi(15.0 + 15.0 * f)},
		"teto_previdencia": {"amount": snappedf(c.gdp_pc() * 0.18, 10.0)},
	}
	if c.dem >= 6.0:
		out["greve_privado"] = {"sector": "privado", "mode": "pleno"}
		out["greve_publico"] = {"sector": "publico", "mode": "minimo"}
		out["greve_essencial"] = {"sector": "essencial", "mode": "minimo"}
	elif c.dem >= 4.0:
		out["greve_privado"] = {"sector": "privado", "mode": "pleno"}
		out["greve_publico"] = {"sector": "publico", "mode": "minimo"}
		out["greve_essencial"] = {"sector": "essencial", "mode": "proibida"}
	else:
		for s: String in STRIKE_SECTORS:
			out["greve_" + s] = {"sector": s, "mode": "proibida"}
	match c.iso:
		"BRA":
			out.fgts = {"deposit": 8, "fine": 40}
			out.indenizacao = {"weeks": 0}
			out.licencas = {"maternity": 120, "paternity": 5}
			out.seguro_desemprego = {"months": 5, "pct": 80}
			out.aposentadoria = {"men": 65, "women": 62, "years": 15}
		"USA":
			out.ferias = {"days": 0}
			out.licencas = {"maternity": 0, "paternity": 0}
			out.indenizacao = {"weeks": 0}
			out.seguro_desemprego = {"months": 6, "pct": 45}
			out.jornada = {"hours": 40}
	return out


func _item(op: String, values: Dictionary) -> String:
	if op == "tb_strike":
		return "greve_" + String(values.get("sector", "privado"))
	return String(ITEMS.get(op, ""))


func seed_program(_world: GameWorld, c: Country) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	var values := _defaults(c)
	for op: String in ITEMS:
		_put(program, stack, op, values[ITEMS[op]])
	for s: String in STRIKE_SECTORS:
		_put(program, stack, "tb_strike", values["greve_" + s])
	return program


func _put(program: Dictionary, stack: Dictionary, op: String, fields: Dictionary) -> void:
	var block := LawProgram.new_block(program, op)
	for key: String in fields:
		block.fields[key] = fields[key]
	stack.blocks.append(block)


func apply(_world: GameWorld, leg: Legislation, op: String, values: Dictionary, weight: float, norm_id: int, prio: float) -> String:
	var item := _item(op, values)
	if item == "" or weight <= 0.0:
		return ""
	if op == "tb_minwage":
		# The same place as the advanced block: whoever has the higher priority takes the slot, and the effect does not add twice.
		leg._stand("minwage", "valor", {"value": float(values.amount)}, norm_id, prio)
		return tr("salário mínimo de US$ %d") % roundi(float(values.amount))
	leg.stand(id + ":" + item, values.duplicate(), norm_id, prio)
	return ""


# --- Monthly effect -----------------------------------------------------------------------

## The values of a program (the code's original version, for example), by item.
func _read_program(program: Dictionary) -> Dictionary:
	var out := {}
	for block: Dictionary in LawProgram.all_blocks(program):
		var item := _item(String(block.type), block.fields)
		if item != "":
			out[item] = block.fields
	return out


## Base: the code's original text. Current: what is in force; what is missing, the base applies.
func _base_and_current(world: GameWorld, c: Country, leg: Legislation) -> Array:
	var norm := leg.code_norm(id)
	var held := leg.code_standing(id)
	if held.is_empty() and not norm.is_empty():
		# The code seeded at the start of the match never fired "on taking effect": it fires now, once.
		leg.fire(world, "ev_enact", {"only": int(norm.id)})
		held = leg.code_standing(id)
	if norm.is_empty() and held.is_empty():
		return []
	var base := _defaults(c)
	if not norm.is_empty() and not norm.versions.is_empty():
		base.merge(_read_program(norm.versions[0].program), true)
	var current := base.duplicate()
	current.merge(held, true)
	var wage: Dictionary = leg.standing.minwage.get("valor", {})
	current["salario_minimo"] = {"amount": float(wage.get("value", 0.0))}
	return [base, current]


## Labor market rigidity, from 0 (everything free) to 1 (everything protected).
static func rigidity(v: Dictionary) -> float:
	var r := 0.0
	r += clampf((48.0 - float(v.jornada.hours)) / 16.0, -0.2, 1.0) * 0.12
	r += clampf(float(v.horas_extras.pct) / 100.0, 0.0, 2.0) * 0.05
	r += clampf(float(v.ferias.days) / 30.0, 0.0, 2.0) * 0.06
	r += 0.04 if bool(v.decimo_terceiro.on) else 0.0
	r += clampf(float(v.fgts.deposit) / 10.0, 0.0, 2.0) * 0.05 + clampf(float(v.fgts.fine) / 50.0, 0.0, 2.0) * 0.05
	r += clampf(float(v.indenizacao.weeks) / 4.0, 0.0, 3.0) * 0.08
	r += clampf(float(v.seguro_desemprego.months) * float(v.seguro_desemprego.pct) / 100.0 / 6.0, 0.0, 3.0) * 0.08
	r += clampf(float(v.licencas.maternity) / 180.0 + float(v.licencas.paternity) / 60.0, 0.0, 3.0) * 0.05
	r += {"obrigatoria": 0.1, "livre": 0.04, "proibida": 0.0}.get(String(v.sindicatos.mode), 0.04)
	r += {"total": 0.0, "meio": 0.05, "proibida": 0.1}.get(String(v.terceirizacao.mode), 0.05)
	r += {"autonomo": 0.0, "hibrido": 0.03, "empregado": 0.07}.get(String(v.aplicativos.mode), 0.0)
	for s: String in STRIKE_SECTORS:
		r += {"pleno": 0.03, "minimo": 0.015, "proibida": 0.0}.get(String(v.get("greve_" + s, {}).get("mode", "minimo")), 0.015)
	return clampf(r, 0.0, 1.0)


## Share of the elderly with a benefit: long contribution, informality and gig work with no bond leave people out.
static func pension_coverage(c: Country, v: Dictionary) -> float:
	var cover := 0.25 + 0.65 * wealth(c) - (float(v.aposentadoria.years) - 15.0) * 0.012
	cover += {"autonomo": -0.03, "hibrido": 0.0, "empregado": 0.03}.get(String(v.aplicativos.mode), 0.0)
	return clampf(cover, 0.05, 0.98)


## Pension deficit, in % of GDP: years of benefit paid against years of contribution.
static func pension_deficit(c: Country, v: Dictionary) -> float:
	# Life expectancy of those who reach 60, not at birth.
	var life := 72.0 + 12.0 * wealth(c)
	var age := (float(v.aposentadoria.men) + float(v.aposentadoria.women)) / 2.0
	var paid := maxf(life - age, 3.0)
	var cap_ratio := float(v.teto_previdencia.amount) * 12.0 / maxf(c.gdp_pc(), 1.0)
	var generosity := clampf(0.6 + 0.2 * cap_ratio, 0.6, 1.4)
	return pension_coverage(c, v) * (paid * 0.55 * generosity - (age - 20.0) * 0.12)


## What a set of values does to the country, in levels; the month uses the difference from the base.
func _effects(c: Country, v: Dictionary) -> Dictionary:
	var r := rigidity(v)
	var free := c.dem >= 4.0
	var e := {"unemp": r * 0.05, "invest": -r * 0.08, "inequality": -r * 0.03, "approval": r * (0.04 if free else 0.02), "stability": 0.0, "labor": 0.0, "evasion": 0.0}
	var age := (float(v.aposentadoria.men) + float(v.aposentadoria.women)) / 2.0
	e.labor = age * 0.004 + float(v.aposentadoria.years) * 0.001 - float(v.idade_minima.age) * 0.002 + float(v.jornada.hours) * 0.002 - float(v.ferias.days) * 0.0003
	# Retiring early pleases; working earlier does not.
	e.approval += -age * 0.002 - maxf(16.0 - float(v.idade_minima.age), 0.0) * 0.002
	var wage_ratio := float(v.salario_minimo.amount) * 12.0 / maxf(c.gdp_pc() * 0.6, 1.0)
	e.inequality += -minf(wage_ratio, 1.5) * 0.01
	# A minimum far above productivity pushes people into informality.
	e.evasion += maxf(wage_ratio - 0.8, 0.0) * 0.03 + r * 0.02
	for s: String in STRIKE_SECTORS:
		if String(v.get("greve_" + s, {}).get("mode", "minimo")) == "proibida" and free:
			# A banned strike does not disappear: it becomes a wildcat strike and protest.
			e.stability -= 0.008
			e.approval -= 0.004
	match String(v.sindicatos.mode):
		"proibida":
			e.stability -= 0.015 if free else 0.004
			e.approval -= 0.01 if free else 0.0
			e.invest += 0.01
		"obrigatoria":
			e.stability -= 0.003
	return e


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	var pair := _base_and_current(world, c, leg)
	if pair.is_empty():
		return {}
	var base: Dictionary = pair[0]
	var now: Dictionary = pair[1]
	if float(now.salario_minimo.amount) <= 0.0:
		now.salario_minimo = base.salario_minimo
	var e_now := _effects(c, now)
	var e_base := _effects(c, base)
	var out := {}
	for key: String in e_now:
		out[key] = float(e_now[key]) - float(e_base[key])
	var deficit := pension_deficit(c, now)
	# A pension more or less expensive than the original comes out of the Treasury every month.
	var extra := (deficit - pension_deficit(c, base)) / 100.0 * c.y_usd() / 12.0
	if extra > 0.0:
		Legislation._pay(c, extra)
	elif extra < 0.0:
		Legislation._collect(c, -extra)
	c.code_stats["cobertura_previdencia"] = pension_coverage(c, now)
	c.code_stats["deficit_previdencia"] = deficit
	c.code_stats["rigidez_trabalho"] = rigidity(now)
	return out
