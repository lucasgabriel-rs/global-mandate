class_name Outlook
extends RefCounted
## Projeções econômicas lidas do estado do país, sem mexer nele: as expectativas do mercado (à moda do
## Boletim Focus) e as previsões do FMI. Funções puras; a interface chama quando a janela está aberta.
##
## O mercado parte do que vê nos últimos dados e confia no banco central na medida da credibilidade dele.
## O FMI ancora mais nos fundamentos: crescimento tendencial, meta de inflação e sustentabilidade da dívida.

const YEARS := 3


## Os dados de partida, vistos `back` meses atrás (0 = hoje), tirados das séries de `c.hist`.
static func inputs(c: Country, back := 0) -> Dictionary:
	return {
		"infl": _at(c, "infl", back, c.pi_yoy),
		"growth": _at(c, "growth", back, c.growth_yoy()),
		"rate": _at(c, "rate", back, c.rate),
		"fx": _at(c, "fx", back, c.e),
		"debt": _at(c, "debt", back, c.debt_ratio),
		"deficit": _at(c, "deficit", back, 0.0),
	}


static func _at(c: Country, key: String, back: int, fallback: float) -> float:
	var s: PackedFloat32Array = c.hist.get(key, PackedFloat32Array())
	if s.is_empty():
		return fallback
	return s[maxi(s.size() - 1 - back, 0)]


## Fração do ano que ainda falta; a projeção do ano corrente é para dezembro.
static func _left(world: GameWorld) -> float:
	return clampf((12.0 - float(world.month)) / 12.0, 0.05, 1.0)


## Inflação ao fim de cada ano: converge para a meta mais rápido quanto mais crível o banco central.
static func _infl_path(c: Country, start: float, left: float, persist: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in YEARS:
		var t := left + float(k)
		out.append(c.pi_target + (start - c.pi_target) * pow(persist, t))
	return out


static func _growth_path(c: Country, start: float, left: float, decay: float, drag: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in YEARS:
		var t := left + float(k)
		out.append(c.g0 - drag + (start - c.g0) * pow(decay, t))
	return out


## Expectativas do mercado: inflação, crescimento do PIB, juro básico e câmbio ao fim de cada ano.
static func market(c: Country, world: GameWorld, back := 0) -> Dictionary:
	var d := inputs(c, back)
	var left := _left(world)
	# Sem credibilidade, o mercado espera que a inflação de hoje fique; com ela, que volte à meta.
	var persist := lerpf(0.8, 0.3, clampf(c.cred, 0.0, 1.0))
	var start_infl := lerpf(float(d.infl), c.pi_e, 0.3)
	var infl := _infl_path(c, start_infl, left, persist)
	var growth := _growth_path(c, float(d.growth), left, 0.55, 0.0)
	var us_infl := world.usa.pi_target + (world.usa.pi_yoy - world.usa.pi_target) * 0.5 if world.usa else 0.02
	var rate := PackedFloat32Array()
	var fx := PackedFloat32Array()
	var r: float = d.rate
	var e: float = d.fx
	for k in YEARS:
		var t := left if k == 0 else 1.0
		# Regra de Taylor: juro neutro, inflação esperada e o desvio dela da meta; o BC anda aos poucos.
		var gap_k := c.gap * pow(0.5, float(k) + left)
		var taylor := maxf(c.r_n + infl[k] + 0.5 * (infl[k] - c.pi_target) + 0.5 * gap_k, 0.0)
		if c.peg == 0:
			r = lerpf(r, taylor, 1.0 - pow(0.45, t))
			# Paridade de poder de compra: a moeda perde o diferencial de inflação em relação ao dólar.
			e *= pow(1.0 + infl[k] - us_infl, t)
		else:
			r = lerpf(r, taylor, 1.0 - pow(0.6, t))
		rate.append(r)
		fx.append(e)
	return {"infl": infl, "growth": growth, "rate": rate, "fx": fx}


## Previsão do FMI: crescimento e inflação mais ancorados e a trajetória da dívida pública (% do PIB).
static func imf(c: Country, world: GameWorld) -> Dictionary:
	var d := inputs(c)
	var left := _left(world)
	var excess := maxf(float(d.debt) - c.debt_tol, 0.0)
	var drag := excess * 0.02 + maxf(0.5 - c.stability, 0.0) * 0.02
	var growth := _growth_path(c, float(d.growth), left, 0.45, drag)
	var infl := _infl_path(c, float(d.infl), left, lerpf(0.65, 0.25, clampf(c.cred, 0.0, 1.0)))
	var debt := PackedFloat32Array()
	var b: float = d.debt
	var def: float = d.deficit
	for k in YEARS:
		var t := left if k == 0 else 1.0
		var nominal := growth[k] + infl[k]
		# O FMI supõe um ajuste gradual: um terço do déficit some a cada ano.
		def *= pow(0.67, t)
		b = maxf(b + (def - nominal * b / (1.0 + nominal)) * t, 0.0)
		debt.append(b)
	return {"growth": growth, "infl": infl, "debt": debt}


## Os riscos que o FMI aponta no relatório sobre o país, já traduzidos.
static func imf_risks(c: Country, f: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var debt: PackedFloat32Array = f.debt
	if debt[YEARS - 1] > c.debt_tol:
		out.append(TranslationServer.translate("A dívida pública segue acima do que o mercado tolera; recomenda-se ajuste fiscal."))
	if debt[YEARS - 1] > debt[0] + 0.02:
		out.append(TranslationServer.translate("A trajetória da dívida é de alta."))
	var infl: PackedFloat32Array = f.infl
	if infl[0] > c.pi_target + 0.03:
		out.append(TranslationServer.translate("A inflação está longe da meta; a política monetária deve seguir apertada."))
	if c.cred < 0.4:
		out.append(TranslationServer.translate("O banco central tem pouca credibilidade, e as expectativas não se ancoram."))
	if c.ca_ratio < -0.04:
		out.append(TranslationServer.translate("O déficit em conta corrente deixa o país vulnerável a uma parada súbita de capitais."))
	if c.unemp > c.unemp_n + 0.03:
		out.append(TranslationServer.translate("O desemprego está bem acima do natural; há espaço para estímulo."))
	if out.is_empty():
		out.append(TranslationServer.translate("Os fundamentos estão em ordem; o FMI não vê riscos imediatos."))
	return out


## Média ponderada pelo PIB em dólares das previsões de todos os países vivos (a economia mundial).
static func imf_world(world: GameWorld) -> Dictionary:
	var g := PackedFloat32Array([0, 0, 0])
	var p := PackedFloat32Array([0, 0, 0])
	var total := 0.0
	for c: Country in world.countries:
		if not c.alive:
			continue
		var wgt := c.y_usd()
		var f := imf(c, world)
		for k in YEARS:
			g[k] += f.growth[k] * wgt
			p[k] += clampf(f.infl[k], -0.1, 1.0) * wgt
		total += wgt
	for k in YEARS:
		g[k] /= maxf(total, 0.001)
		p[k] /= maxf(total, 0.001)
	return {"growth": g, "infl": p}
