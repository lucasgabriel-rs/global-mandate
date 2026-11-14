class_name Outlook
extends RefCounted
## Economic projections read from the country's state, without changing it: market expectations (in the style of the
## Focus Bulletin) and IMF forecasts. Pure functions; the interface calls them while the window is open.
##
## The market starts from what it sees in the latest data and trusts the central bank in proportion to its credibility.
## The IMF anchors more on fundamentals: trend growth, the inflation target and debt sustainability.

const YEARS := 3


## The starting data, seen `back` months ago (0 = today), taken from the `c.hist` series.
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


## Fraction of the year still to come; the current-year projection is for December.
static func _left(world: GameWorld) -> float:
	return clampf((12.0 - float(world.month)) / 12.0, 0.05, 1.0)


## Inflation at the end of each year: converges to the target faster the more credible the central bank.
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


## Market expectations: inflation, GDP growth, policy rate and exchange rate at the end of each year.
static func market(c: Country, world: GameWorld, back := 0) -> Dictionary:
	var d := inputs(c, back)
	var left := _left(world)
	# Without credibility, the market expects today's inflation to stay; with it, to return to the target.
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
		# Taylor rule: neutral rate, expected inflation and its deviation from the target; the central bank moves gradually.
		var gap_k := c.gap * pow(0.5, float(k) + left)
		var taylor := maxf(c.r_n + infl[k] + 0.5 * (infl[k] - c.pi_target) + 0.5 * gap_k, 0.0)
		if c.peg == 0:
			r = lerpf(r, taylor, 1.0 - pow(0.45, t))
			# Purchasing power parity: the currency loses the inflation differential against the dollar.
			e *= pow(1.0 + infl[k] - us_infl, t)
		else:
			r = lerpf(r, taylor, 1.0 - pow(0.6, t))
		rate.append(r)
		fx.append(e)
	return {"infl": infl, "growth": growth, "rate": rate, "fx": fx}


## IMF forecast: more anchored growth and inflation and the path of public debt (% of GDP).
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
		# The IMF assumes a gradual adjustment: a third of the deficit disappears each year.
		def *= pow(0.67, t)
		b = maxf(b + (def - nominal * b / (1.0 + nominal)) * t, 0.0)
		debt.append(b)
	return {"growth": growth, "infl": infl, "debt": debt}


## The risks the IMF points out in its report on the country, already translated.
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


## Average of the forecasts of all living countries weighted by GDP in dollars (the world economy).
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
