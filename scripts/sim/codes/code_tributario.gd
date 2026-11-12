class_name CodeTributario
extends LawCode
## Tax Code: Taxes, rates, brackets, exemptions and contributions.
##
## Each block is a provision with a legal rate (income tax by brackets, VAT, corporate tax...). The code converts the
## set in force into the effective burdens the economy uses (`tax_income`, `tax_consumption`,
## `tax_corporate`, as a fraction of GDP, and `tariff`), multiplying each rate by the base it reaches.
## The bases come from the country's average income and starting Gini, stored in the "_ref" item, together with the
## calibration that makes the initial text reproduce exactly the burden the country starts with.
##
## Income and payroll: income tax and pensions. Consumption: consumption taxes, reduced and selective.
## Companies and capital: corporate taxes, Simples, IOF, property taxes, vehicle taxes, inheritance tax and large fortunes.

## Bases as a fraction of GDP.
const PERSONAL_BASE := 0.65
const PAYROLL_BASE := 0.55
const CONSUMPTION_BASE := 0.7
const PROFIT_BASE := 0.14
## Revenue of small companies per unit of profit.
const TURNOVER_PER_PROFIT := 5.0
const IOF_BASE := 0.3
const PROPERTY_BASE := {"iptu": 1.6, "ipva": 0.3}
const INHERITANCE_BASE := 0.05
const WEALTH_GDP := 3.5
const WEALTH_ALPHA := 1.5
## How much of the consumption base each tax reaches.
const CONSUMPTION_COVER := {"iva": 1.0, "icms": 0.5, "ipi": 0.15, "iss": 0.4}
## Share of each group's consumption base with a reduced rate.
const REDUCED_SHARE := {"cesta": 0.12, "saude": 0.06, "educacao": 0.05}
const SELECTIVE_BASE := {"tabaco": 0.008, "alcool": 0.012, "combustivel": 0.035, "acucar": 0.01}
## Tax Authority budget (% of GDP) that keeps evasion at the starting level.
const ENFORCEMENT_REF := 0.2
const SECTOR_KEYS := ["agro", "mineracao", "industria", "construcao", "comercio", "transporte", "financas", "tecnologia", "turismo", "publico"]
## Burden limits, the same as `Legislation._set_policy`.
const LIMITS := {"tax_income": 0.32, "tax_consumption": 0.24, "tax_corporate": 0.16, "tariff": 0.5}
const GROUP_FIELD := {"income": "tax_income", "consumption": "tax_consumption", "corporate": "tax_corporate"}


func _init() -> void:
	id = "tributario"
	title = "Código Tributário"
	ementa = "Tributos, alíquotas, faixas, isenções e contribuições."
	category = {"id": "tributario", "label": "Tributos", "color": Color("4f8f3a")}


func blocks() -> Array:
	var cat := "tributario"
	var law := LawCatalog.RANK_LAW
	return [
		{"id": "tr_irpf_isencao", "cat": cat, "kind": "statement", "text": "IRPF: isenção para rendas de até {limite} por mês", "fields": {"limite": {"t": "money", "d": 500}}, "rank": law, "econ": 0.05, "social": 0.05},
		{"id": "tr_irpf_faixa", "cat": cat, "kind": "statement", "text": "IRPF, faixa {faixa}: renda até {limite} por mês paga {aliquota}%", "fields": {"faixa": {"t": "choice", "of": "tr_faixa", "d": "1"}, "limite": {"t": "money", "d": 1000}, "aliquota": {"t": "pct", "d": 7.5}}, "rank": law},
		{"id": "tr_irpf_topo", "cat": cat, "kind": "statement", "text": "IRPF: acima da última faixa, alíquota de {aliquota}%", "fields": {"aliquota": {"t": "pct", "d": 27.5}}, "rank": law, "econ": -0.05},
		{"id": "tr_prev", "cat": cat, "kind": "statement", "text": "Contribuição previdenciária do {quem}: {aliquota}% do salário", "fields": {"quem": {"t": "choice", "of": "tr_contribuinte", "d": "empregado"}, "aliquota": {"t": "pct", "d": 9}}, "rank": law},
		{"id": "tr_irpj", "cat": cat, "kind": "statement", "text": "IRPJ: {aliquota}% sobre o lucro das empresas", "fields": {"aliquota": {"t": "pct", "d": 15}}, "rank": law},
		{"id": "tr_csll", "cat": cat, "kind": "statement", "text": "CSLL: {aliquota}% sobre o lucro líquido", "fields": {"aliquota": {"t": "pct", "d": 9}}, "rank": law},
		{"id": "tr_simples", "cat": cat, "kind": "statement", "text": "Regime simplificado: empresas com faturamento de até {limite} por ano pagam {aliquota}% do faturamento", "fields": {"limite": {"t": "money", "d": 1000000}, "aliquota": {"t": "pct", "d": 6}}, "rank": law, "econ": 0.15},
		{"id": "tr_isencao_setor", "cat": cat, "kind": "statement", "text": "Isenção de {parcela}% do IRPJ e da CSLL para o setor {setor}", "fields": {"parcela": {"t": "pct", "d": 50}, "setor": {"t": "choice", "of": "tr_setor", "d": "tecnologia"}}, "rank": law, "econ": 0.2},
		{"id": "tr_consumo", "cat": cat, "kind": "statement", "text": "{tributo}: alíquota padrão de {aliquota}%", "fields": {"tributo": {"t": "choice", "of": "tr_consumo", "d": "iva"}, "aliquota": {"t": "pct", "d": 17}}, "rank": law},
		{"id": "tr_reduzida", "cat": cat, "kind": "statement", "text": "Alíquota reduzida de {aliquota}% sobre {grupo}", "fields": {"aliquota": {"t": "pct", "d": 5}, "grupo": {"t": "choice", "of": "tr_grupo", "d": "cesta"}}, "rank": law, "social": 0.05},
		{"id": "tr_seletivo", "cat": cat, "kind": "statement", "text": "Imposto seletivo de {aliquota}% sobre {produto}", "fields": {"aliquota": {"t": "pct", "d": 20}, "produto": {"t": "choice", "of": "tr_produto", "d": "tabaco"}}, "rank": law, "social": -0.05},
		{"id": "tr_importacao", "cat": cat, "kind": "statement", "text": "Imposto de importação geral de {aliquota}%", "fields": {"aliquota": {"t": "pct", "d": 10}}, "rank": law},
		{"id": "tr_iof", "cat": cat, "kind": "statement", "text": "IOF: {aliquota}% sobre crédito, câmbio e seguros", "fields": {"aliquota": {"t": "pct", "d": 0.4}}, "rank": law},
		{"id": "tr_patrimonio", "cat": cat, "kind": "statement", "text": "{tributo}: {aliquota}% ao ano sobre o valor do bem", "fields": {"tributo": {"t": "choice", "of": "tr_patrimonio", "d": "iptu"}, "aliquota": {"t": "pct", "d": 1}}, "rank": law},
		{"id": "tr_heranca", "cat": cat, "kind": "statement", "text": "ITCMD: {aliquota}% sobre heranças e doações", "fields": {"aliquota": {"t": "pct", "d": 4}}, "rank": law, "econ": -0.1},
		{"id": "tr_fortunas", "cat": cat, "kind": "statement", "text": "Imposto sobre grandes fortunas: {aliquota}% ao ano sobre patrimônios acima de {limite}", "fields": {"aliquota": {"t": "pct", "d": 1}, "limite": {"t": "money", "d": 10000000}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": -0.4},
		{"id": "tr_fiscalizacao", "cat": cat, "kind": "statement", "text": "Orçamento da Receita para fiscalização: {verba}% do PIB por ano", "fields": {"verba": {"t": "pct", "d": 0.2}}, "rank": law, "social": -0.05},
	]


func choices() -> Dictionary:
	var sectors := {}
	for i in SECTOR_KEYS.size():
		sectors[SECTOR_KEYS[i]] = Sectors.NAMES[i]
	return {
		"tr_faixa": {"1": "1", "2": "2", "3": "3", "4": "4"},
		"tr_contribuinte": {"empregado": "empregado", "empregador": "empregador"},
		"tr_consumo": {"iva": "IVA", "icms": "ICMS (mercadorias)", "ipi": "IPI (industrializados)", "iss": "ISS (serviços)"},
		"tr_grupo": {"cesta": "a cesta básica", "saude": "saúde", "educacao": "educação"},
		"tr_produto": {"tabaco": "tabaco", "alcool": "bebidas alcoólicas", "combustivel": "combustíveis", "acucar": "bebidas açucaradas"},
		"tr_patrimonio": {"iptu": "IPTU (imóveis)", "ipva": "IPVA (veículos)"},
		"tr_setor": sectors,
	}


# --- Initial text ---------------------------------------------------------------------

## The country starts with a complete code, in round rates, that reproduces the starting burden.
func seed_program(world: GameWorld, c: Country) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	for row: Array in _seed_rows(c, _ref_income(world, c)):
		var block := LawProgram.new_block(program, row[0])
		block.fields.merge(row[1], true)
		stack.blocks.append(block)
	return program


## Lines [block type, fields] of the initial text: a rate template scaled by group.
func _seed_rows(c: Country, m: float) -> Array:
	var income := [
		["tr_irpf_isencao", {"limite": _nice(m)}],
		["tr_irpf_faixa", {"faixa": "1", "limite": _nice(m * 1.5), "aliquota": 7.5}],
		["tr_irpf_faixa", {"faixa": "2", "limite": _nice(m * 2.5), "aliquota": 15.0}],
		["tr_irpf_faixa", {"faixa": "3", "limite": _nice(m * 4.0), "aliquota": 22.5}],
		["tr_irpf_topo", {"aliquota": 27.5}],
		["tr_prev", {"quem": "empregado", "aliquota": 9.0}],
		["tr_prev", {"quem": "empregador", "aliquota": 20.0}],
	]
	var consumption := [
		["tr_consumo", {"tributo": "iva", "aliquota": 17.0}],
		["tr_reduzida", {"grupo": "cesta", "aliquota": 7.0}],
		["tr_reduzida", {"grupo": "saude", "aliquota": 10.0}],
		["tr_reduzida", {"grupo": "educacao", "aliquota": 10.0}],
		["tr_seletivo", {"produto": "tabaco", "aliquota": 60.0}],
		["tr_seletivo", {"produto": "alcool", "aliquota": 25.0}],
		["tr_seletivo", {"produto": "combustivel", "aliquota": 20.0}],
	]
	var corporate := [
		["tr_irpj", {"aliquota": 15.0}],
		["tr_csll", {"aliquota": 9.0}],
		["tr_simples", {"limite": _nice(m * 2000.0), "aliquota": 6.0}],
		["tr_iof", {"aliquota": 0.4}],
		["tr_patrimonio", {"tributo": "iptu", "aliquota": 0.6}],
		["tr_patrimonio", {"tributo": "ipva", "aliquota": 3.0}],
		["tr_heranca", {"aliquota": 4.0}],
	]
	var out := []
	for pair: Array in [[income, c.tax_income, "income"], [consumption, c.tax_consumption, "consumption"], [corporate, c.tax_corporate, "corporate"]]:
		var rows: Array = pair[0]
		var model: float = _effective(_rows_items(rows), c, m, {})[pair[2]]
		var k := float(pair[1]) / model if model > 0.0 else 0.0
		for row: Array in rows:
			if row[1].has("aliquota"):
				var rate := clampf(float(row[1].aliquota) * k, 0.0, 60.0)
				row[1].aliquota = snappedf(rate, 0.5 if rate >= 10.0 else (0.1 if rate >= 1.0 else 0.01))
		out.append_array(rows)
	out.append(["tr_importacao", {"aliquota": snappedf(c.tariff * 100.0, 0.01)}])
	out.append(["tr_fiscalizacao", {"verba": ENFORCEMENT_REF}])
	return out


func _rows_items(rows: Array) -> Dictionary:
	var items := {}
	for row: Array in rows:
		items[_key(row[0], row[1])] = _clean(row[0], row[1])
	return items


## Round value, with two significant figures.
static func _nice(x: float) -> float:
	if x <= 0.0:
		return 0.0
	var step := pow(10.0, floorf(log(x) / log(10.0)) - 1.0)
	return roundf(x / step) * step


# --- Effect of the blocks -----------------------------------------------------------------

func apply(world: GameWorld, leg: Legislation, op: String, values: Dictionary, _weight: float, norm_id: int, prio: float) -> String:
	var c := world.player
	# Law that amends another: the new text already applies through the amended norm, which runs first.
	var norm: Dictionary = leg.norms.get(norm_id, {})
	if int(norm.get("amends", -1)) >= 0 and String(leg.norms.get(int(norm.amends), {}).get("state", "")) == Legislation.STATE_IN_FORCE:
		return ""
	_ensure_ref(world, leg, c)
	leg.stand("tributario:" + _key(op, values), _clean(op, values), norm_id, prio)
	_recompute(world, leg, c)
	return ""


## Item key: one per tax, per bracket, per group, per product...
func _key(op: String, v: Dictionary) -> String:
	match op:
		"tr_irpf_faixa":
			return "irpf_faixa_%s" % String(v.get("faixa", "1"))
		"tr_prev":
			return "prev_%s" % String(v.get("quem", "empregado"))
		"tr_consumo":
			return "consumo_%s" % String(v.get("tributo", "iva"))
		"tr_reduzida":
			return "reduzida_%s" % String(v.get("grupo", "cesta"))
		"tr_seletivo":
			return "seletivo_%s" % String(v.get("produto", "tabaco"))
		"tr_patrimonio":
			return "patrimonio_%s" % String(v.get("tributo", "iptu"))
		"tr_isencao_setor":
			return "isencao_%s" % String(v.get("setor", "agro"))
	return op.trim_prefix("tr_")


## Only the block's numbers and choices, with the type alongside.
func _clean(op: String, v: Dictionary) -> Dictionary:
	var out := {"op": op}
	for k: String in v:
		var value: Variant = v[k]
		out[k] = float(value) if (value is float or value is int) else String(value)
	return out


## Tax items in force, without the internal ones ("_ref").
func _items(leg: Legislation) -> Dictionary:
	var out := {}
	var all := leg.code_standing(id)
	for k: String in all:
		if not k.begins_with("_"):
			out[k] = all[k]
	return out


func _ref(leg: Legislation) -> Dictionary:
	return leg.standing.codes.get("tributario:_ref", {})


## Average monthly income (US$) that measures the brackets: the one from the start, stored; before that, today's.
func _ref_income(world: GameWorld, c: Country) -> float:
	var ref := {}
	if world.legislation:
		ref = _ref(world.legislation)
	if not ref.is_empty():
		return float(ref.m)
	return maxf(c.gdp_pc() * 0.6 / 12.0, 1.0)


## The first time: the reference income, the calibration per group and the indicators of the initial text,
## which are the zero point of the monthly effects. Stays with norm 0, which no repeal erases.
func _ensure_ref(world: GameWorld, leg: Legislation, c: Country) -> void:
	if not _ref(leg).is_empty():
		return
	var m := _ref_income(world, c)
	var seed := _rows_items(_seed_rows(c, m))
	var raw := _effective(seed, c, m, {})
	var calib := {}
	for group: String in GROUP_FIELD:
		var model: float = raw[group]
		calib[group] = float(c.get(GROUP_FIELD[group])) / model if model > 0.0 else 1.0
	var ref := {"m": m, "gini": c.inequality0, "calib": calib, "sig": 0}
	ref["base"] = _stats(seed, c, m, calib)
	ref["start"] = {"tax_income": c.tax_income, "tax_consumption": c.tax_consumption, "tax_corporate": c.tax_corporate}
	leg.stand("tributario:_ref", ref, 0, -1.0)


## Rewrites the burdens with what is in force. A group with no provision stays as it is.
func _recompute(world: GameWorld, leg: Legislation, c: Country) -> void:
	var ref := _ref(leg)
	if ref.is_empty():
		return
	var items := _items(leg)
	ref.sig = hash(items)
	if items.is_empty():
		return
	var eff := _effective(items, c, float(ref.m), ref.calib)
	for group: String in GROUP_FIELD:
		if eff.has_group[group]:
			_set_load(world, GROUP_FIELD[group], float(eff[group]), float(ref.start.get(GROUP_FIELD[group], 0.0)))
	if eff.tariff >= 0.0:
		_set_load(world, "tariff", float(eff.tariff), 0.0)


func _set_load(world: GameWorld, field: String, value: float, start: float) -> void:
	var c := world.player
	var v := clampf(value, 0.0, maxf(float(LIMITS[field]), start))
	if absf(v - float(c.get(field))) > 1e-9:
		Politics._apply_budget_change(c, field, v)


## Effective burdens (fraction of GDP) and what each group has. Without calibration, the model's raw numbers.
func _effective(items: Dictionary, c: Country, m: float, calib: Dictionary) -> Dictionary:
	var has := {"income": false, "consumption": false, "corporate": false}
	var sigma := _sigma(c.inequality0)
	# Income tax: marginal rate per bracket on the income falling in each bracket.
	var irpf := 0.0
	var bands := _bands(items)
	for band: Array in bands:
		irpf += float(band[2]) * 0.01 * (_above(band[0], m, sigma) - _above(band[1], m, sigma))
		has.income = true
	irpf *= PERSONAL_BASE
	var pc := m * 12.0 / 0.6
	var formal := clampf(0.45 + 0.15 * log(maxf(pc, 500.0) / 2000.0), 0.25, 0.95)
	var payroll := 0.0
	for who: String in ["empregado", "empregador"]:
		if items.has("prev_" + who):
			payroll += _rate(items, "prev_" + who) * PAYROLL_BASE * formal
			has.income = true
	# Consumption: the sum of the taxes, lower in groups with a reduced rate, plus the selective one.
	var standard := 0.0
	for t: String in CONSUMPTION_COVER:
		if items.has("consumo_" + t):
			standard += _rate(items, "consumo_" + t) * float(CONSUMPTION_COVER[t])
			has.consumption = true
	var consumption := 0.0
	var reduced_share := 0.0
	for g: String in REDUCED_SHARE:
		if items.has("reduzida_" + g):
			reduced_share += float(REDUCED_SHARE[g])
			consumption += float(REDUCED_SHARE[g]) * minf(_rate(items, "reduzida_" + g), standard)
			has.consumption = true
	consumption = CONSUMPTION_BASE * (consumption + (1.0 - reduced_share) * standard)
	var selective := 0.0
	for p: String in SELECTIVE_BASE:
		if items.has("seletivo_" + p):
			selective += _rate(items, "seletivo_" + p) * float(SELECTIVE_BASE[p])
			has.consumption = true
	consumption += selective
	# Companies and capital.
	var profit_rate := _rate(items, "irpj") + _rate(items, "csll")
	var exempt := 0.0
	for i in SECTOR_KEYS.size():
		var key: String = "isencao_" + SECTOR_KEYS[i]
		if items.has(key) and i < c.sector_share.size():
			exempt += c.sector_share[i] * _rate(items, key)
	var small := 0.0
	var simples := 0.0
	if items.has("simples"):
		small = clampf(0.25 * pow(maxf(float(items.simples.get("limite", 0.0)), 0.0) / maxf(m * 2000.0, 1.0), 0.25), 0.0, 0.6)
		simples = small * PROFIT_BASE * TURNOVER_PER_PROFIT * _rate(items, "simples")
	var corporate := PROFIT_BASE * (1.0 - small) * profit_rate * (1.0 - clampf(exempt, 0.0, 1.0)) + simples
	var wealth := _rate(items, "heranca") * INHERITANCE_BASE
	for t: String in PROPERTY_BASE:
		wealth += _rate(items, "patrimonio_" + t) * float(PROPERTY_BASE[t])
	var fortune := 0.0
	if items.has("fortunas"):
		fortune = _rate(items, "fortunas") * WEALTH_GDP * _wealth_above(float(items.fortunas.get("limite", 0.0)), pc)
	wealth += fortune
	corporate += _rate(items, "iof") * IOF_BASE + wealth
	for k: String in ["irpj", "csll", "simples", "iof", "heranca", "fortunas", "patrimonio_iptu", "patrimonio_ipva"]:
		has.corporate = has.corporate or items.has(k)
	return {
		"income": (irpf + payroll) * float(calib.get("income", 1.0)),
		"consumption": consumption * float(calib.get("consumption", 1.0)),
		"corporate": corporate * float(calib.get("corporate", 1.0)),
		"tariff": _rate(items, "importacao") if items.has("importacao") else -1.0,
		"has_group": has,
		"irpf": irpf, "payroll": payroll, "standard": standard, "selective": selective, "profit_rate": profit_rate,
		"exempt": exempt, "small": small, "wealth": wealth, "fortune": fortune,
		"top": float(bands[-1][2]) * 0.01 if not bands.is_empty() else 0.0,
	}


## Income tax brackets as [from, to, rate], in order; the last goes to infinity.
func _bands(items: Dictionary) -> Array:
	var lo := float(items.get("irpf_isencao", {}).get("limite", 0.0))
	var steps := []
	for n in range(1, 5):
		var f: Dictionary = items.get("irpf_faixa_%d" % n, {})
		if not f.is_empty():
			steps.append([float(f.get("limite", 0.0)), float(f.get("aliquota", 0.0))])
	steps.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for s: Array in steps:
		if s[0] > lo:
			out.append([lo, s[0], s[1]])
			lo = s[0]
	var top: float = items.get("irpf_topo", {}).get("aliquota", out[-1][2] if not out.is_empty() else 0.0)
	if items.has("irpf_topo") or not out.is_empty():
		out.append([lo, INF, top])
	return out


func _rate(items: Dictionary, key: String) -> float:
	var item: Dictionary = items.get(key, {})
	return float(item.get("aliquota", item.get("parcela", 0.0))) * 0.01


## Log-normal income with the country's Gini: share of total income above `a` (E[(y-a)+] / mean).
static func _above(a: float, m: float, sigma: float) -> float:
	if a <= 0.0:
		return 1.0
	if a == INF:
		return 0.0
	var z := log(a / m) / sigma
	var share := 1.0 - _phi(z - sigma * 0.5)
	var people := 1.0 - _phi(z + sigma * 0.5)
	return maxf(share - a / m * people, 0.0)


## Pareto for wealth: share of total wealth above the limit.
static func _wealth_above(limit: float, pc: float) -> float:
	var mean := WEALTH_GDP * pc
	var x_min := mean * (WEALTH_ALPHA - 1.0) / WEALTH_ALPHA
	if limit <= x_min:
		return maxf(1.0 - limit / maxf(mean, 1.0), 0.0)
	return pow(x_min / limit, WEALTH_ALPHA - 1.0) / WEALTH_ALPHA


static func _phi(x: float) -> float:
	# Abramowitz and Stegun 7.1.26.
	var t := 1.0 / (1.0 + 0.3275911 * absf(x) / sqrt(2.0))
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x / 2.0)
	return 0.5 * (1.0 + (y if x >= 0.0 else -y))


## Deviation of the log of income that gives the Gini: G = 2Φ(σ/√2) − 1.
static func _sigma(gini: float) -> float:
	var target := (clampf(gini, 0.1, 0.8) + 1.0) * 0.5
	var lo := 0.0
	var hi := 6.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _phi(mid / sqrt(2.0)) < target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


# --- Indicators and monthly effects -----------------------------------------------------

## What weighs on the effects: burden, progressivity, evasion and what moves investment.
func _stats(items: Dictionary, c: Country, m: float, calib: Dictionary) -> Dictionary:
	var e := _effective(items, c, m, calib)
	var load := float(e.income) + float(e.consumption) + float(e.corporate)
	var avg_irpf := float(e.irpf) / PERSONAL_BASE * float(calib.get("income", 1.0))
	var prog := clampf(float(e.top) - avg_irpf, 0.0, 1.0) + float(e.wealth) * 3.0
	var cesta_rel := 1.0
	if items.has("reduzida_cesta") and float(e.standard) > 0.0:
		cesta_rel = minf(_rate(items, "reduzida_cesta") / float(e.standard), 1.0)
	var regressive := float(e.consumption) * (0.7 + 0.3 * cesta_rel)
	var pressure := maxf(load - 0.3, 0.0) * 0.5 + maxf(float(e.top) - 0.3, 0.0) * 0.25 + maxf(float(e.profit_rate) - 0.3, 0.0) * 0.25
	pressure += maxf(float(e.standard) - 0.2, 0.0) * 0.2 + _rate(items, "fortunas") * 1.5
	var verba := float(items.get("fiscalizacao", {}).get("verba", 0.0))
	var enforcement := verba / ENFORCEMENT_REF
	# Diminishing returns: doubling the Tax Authority does not cut evasion by half.
	var evasion := (0.06 + pressure) / (0.6 + 0.4 * sqrt(clampf(enforcement, 0.0, 4.0)))
	if items.has("simples"):
		evasion *= 0.95
	return {
		"load": load, "prog": prog, "regressive": regressive, "evasion": clampf(evasion, 0.0, 0.5), "verba": verba,
		"iof": _rate(items, "iof"), "profit_rate": e.profit_rate, "exempt": e.exempt, "small": e.small,
		"fortune": _rate(items, "fortunas"), "fuel": _rate(items, "seletivo_combustivel"),
		"isencao": float(items.get("irpf_isencao", {}).get("limite", 0.0)) / maxf(m, 1.0), "cesta_rel": cesta_rel,
	}


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	var ref := _ref(leg)
	if ref.is_empty():
		return {}
	var items := _items(leg)
	if hash(items) != int(ref.sig):
		# Some norm went out of force: the code's text applies again where it ruled.
		_restore(world, leg)
		_recompute(world, leg, c)
		items = _items(leg)
	if items.is_empty():
		return {}
	var m := float(ref.m)
	var now := _stats(items, c, m, ref.calib)
	var base: Dictionary = ref.base
	c.code_stats["carga_tributaria"] = c.tax_total() + c.tariff * c.m_share
	c.code_stats["progressividade"] = float(now.prog)
	c.code_stats["sonegacao"] = float(now.evasion)
	# The Tax Authority costs: only what exceeds the starting budget, which the economy already counts.
	var extra := (float(now.verba) - float(base.verba)) * 0.01 * c.y_usd() / 12.0
	if extra > 0.0:
		Legislation._pay(c, extra)
	elif extra < 0.0:
		Legislation._collect(c, -extra)
	var invest := -(float(now.iof) - float(base.iof)) * 3.0 - (float(now.profit_rate) - float(base.profit_rate)) * 0.3
	invest += float(now.exempt) * 0.1 + (float(now.small) - float(base.small)) * 0.05 - (float(now.fortune) - float(base.fortune)) * 2.0
	var approval := clampf(log(maxf(float(now.isencao), 0.05) / maxf(float(base.isencao), 0.05)) * 0.01, -0.02, 0.02)
	approval += (float(base.cesta_rel) - float(now.cesta_rel)) * 0.01 - (float(now.fuel) - float(base.fuel)) * 0.05
	approval += 0.005 if float(now.fortune) > 0.0 and float(base.fortune) == 0.0 else 0.0
	return {
		"evasion": float(now.evasion) - float(base.evasion),
		"inequality": -(float(now.prog) - float(base.prog)) * 0.2 + (float(now.regressive) - float(base.regressive)) * 0.4,
		"invest": clampf(invest, -0.15, 0.1),
		"approval": approval,
	}


## Reapplies the code's text in force: what another norm overwrote and lost on going out of force comes back.
func _restore(world: GameWorld, leg: Legislation) -> void:
	var norm := leg.code_norm(id)
	if norm.is_empty() or norm.versions.is_empty():
		return
	var prio := leg._priority(norm, {})
	var items := _program_items(leg._current_program(norm))
	for k: String in items:
		leg.stand("tributario:" + k, items[k].duplicate(), int(norm.id), prio)


## Items that a program defines, article by article (the later one prevails).
func _program_items(program: Dictionary) -> Dictionary:
	var items := {}
	for stack: Dictionary in program.get("stacks", []):
		if stack.get("repealed", false) or stack.blocks.is_empty() or stack.blocks[0].type != "ev_enact":
			continue
		for block: Dictionary in stack.blocks:
			if String(block.type).begins_with("tr_") and block.plugs.is_empty():
				items[_key(block.type, block.fields)] = _clean(block.type, block.fields)
	return items


## For the compass and the voter: how much the project changes the burden compared with today's.
func bill_effect(world: GameWorld, leg: Legislation, norm: Dictionary) -> Dictionary:
	var ref := _ref(leg)
	var added := _program_items(norm.get("program", {}))
	if ref.is_empty() or added.is_empty():
		return {}
	var c := world.player
	var items := {}
	var current := _items(leg)
	for k: String in current:
		if int(current[k].get("norm", -1)) != int(norm.get("amends", -2)):
			items[k] = current[k]
	items.merge(added, true)
	var eff := _effective(items, c, float(ref.m), ref.calib)
	var delta := 0.0
	for group: String in GROUP_FIELD:
		var field: String = GROUP_FIELD[group]
		if eff.has_group[group]:
			delta += clampf(float(eff[group]), 0.0, maxf(float(LIMITS[field]), float(ref.start.get(field, 0.0)))) - float(c.get(field))
	if eff.tariff >= 0.0:
		delta += (clampf(float(eff.tariff), 0.0, 0.5) - c.tariff) * clampf(c.m_share, 0.05, 0.5)
	# budget: extra revenue per year, in US$ bn, for the expected effects panel.
	return {"econ": clampf(-delta * 15.0, -1.0, 1.0), "popularity": -delta * 6.0, "budget": delta * c.y_usd()}
