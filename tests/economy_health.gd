extends SceneTree
## Economy health in long matches: first-day accounts, reserves, exchange volatility, rating and
## credit, macro news, interest under government, sliders and taxes by law, norms in the fiscal weight and
## plausible series over 15 years.
## Usage: godot --headless --path . --script tests/economy_health.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _fresh(iso := "BRA") -> GameWorld:
	var world := GameWorld.new()
	world.setup(7)
	world.leader = Character.random(world.rng)
	world.set_player(world.by_iso[iso], "normal")
	return world


## Advances without elections or game over: what is measured here is the economy.
func _months(world: GameWorld, n: int) -> void:
	for i in int(n * 30.4167):
		world.player.next_election = world.year_float() + 2.0
		world.over = false
		world.tick_day()
	world.flush_events()


func _monthly_sd(s: PackedFloat32Array) -> float:
	var acc := 0.0
	var n := 0
	for j in range(1, s.size()):
		var r := log(s[j] / s[j - 1])
		acc += r * r
		n += 1
	return sqrt(acc / maxf(n, 1))


func _init() -> void:
	_first_day()
	_long_run()
	_central_bank()
	_budget_and_taxes()
	_law_money()
	_territory()
	print("RESULT: %d failures" % failures)
	quit()


## Before the first monthly step, the Fiscal tab and the rating already have real numbers.
func _first_day() -> void:
	var world := _fresh()
	var bra: Country = world.player
	var usa: Country = world.usa
	_check(bra.revenue > 0.0 and bra.spending > bra.revenue * 0.5, "Brazil's revenue and spending on the first day: %.0f / %.0f" % [bra.revenue, bra.spending])
	var dr := bra.deficit / bra.y_nominal()
	_check(dr > 0.03 and dr < 0.12, "Brazil's deficit on the first day is plausible: %.1f%%" % (dr * 100.0))
	_check(bra.interest > 0.0, "debt interest already counts on the first day")
	_check(usa.rating in ["AAA", "AA"], "the USA's rating on the first day comes from risk, not from the default: %s" % usa.rating)
	var ratings := {}
	for c: Country in world.countries:
		ratings[c.rating] = true
	_check(ratings.size() >= 4, "starting ratings vary between countries: %s" % str(ratings.keys()))
	var nan := 0
	for c: Country in world.countries:
		if is_nan(c.revenue) or is_nan(c.deficit) or is_inf(c.deficit):
			nan += 1
	_check(nan == 0, "no country starts with invalid accounts (%d)" % nan)


func _long_run() -> void:
	var world := _fresh()
	var bra: Country = world.player
	var news := []
	world.news_posted.connect(func(t, _k, c): if c == bra: news.append(t))
	var start := {}
	for c: Country in world.countries:
		start[c.iso] = {"res": c.reserves, "tax": c.tax_total(), "sp": c.spend_total(), "tariff": c.tariff, "y": c.y_usd()}
	var bra_ratings := [bra.rating]
	for m in 180:
		_months(world, 1)
		if bra.rating != bra_ratings.back():
			bra_ratings.append(bra.rating)

	# Reserves: a floating-rate country without capital flight does not burn reserves on an external deficit.
	for iso in ["USA", "AUS", "BRA", "IND", "GBR"]:
		var c: Country = world.by_iso[iso]
		var r0: float = start[iso].res
		_check(c.reserves > r0 * 0.5, "%s keeps reserves over 15 years: %.0f -> %.0f" % [iso, r0, c.reserves])
	_check(world.usa.rating in ["AAA", "AA"], "the USA does not lose its rating for lack of reserves: %s" % world.usa.rating)

	# Exchange: monthly swing in the range of real exchanges (USA ~4-5%, emerging up to ~7%).
	var sds := []
	for iso in ["USA", "DEU", "JPN", "GBR", "FRA", "CAN"]:
		sds.append(_monthly_sd(world.by_iso[iso].hist.get("stock", PackedFloat32Array())))
	var avg_sd: float = sds.reduce(func(a, b): return a + b, 0.0) / sds.size()
	_check(avg_sd < 0.062 and sds.max() < 0.075, "rich exchanges swing %.1f%% a month on average (< 6.2%%; before ~7%%): %s" % [avg_sd * 100.0, str(sds.map(func(x): return snappedf(x * 100.0, 0.1)))])
	var bad_stock := 0
	for c: Country in world.countries:
		if c.alive and (is_nan(c.stock) or c.stock <= 0.0 or is_inf(c.stock)):
			bad_stock += 1
	_check(bad_stock == 0, "exchange indices positive and finite (%d bad)" % bad_stock)

	# The credit rating does not flicker every month, and each change of the player becomes news.
	_check(bra_ratings.size() - 1 <= 8, "Brazil's rating changes few times in 15 years: %s" % str(bra_ratings))
	var rating_news := news.filter(func(t): return String(t).contains("nota de crédito")).size()
	_check(rating_news == bra_ratings.size() - 1, "each rating change of the player makes the news (%d news, %d changes)" % [rating_news, bra_ratings.size() - 1])
	_check(news.any(func(t): return String(t).contains("juro básico")), "central bank decisions show up in the news")

	# Plausible aggregate series.
	var w0 := 0.0
	for iso in start:
		w0 += float(start[iso].y)
	var years := 15.0
	var world_g := pow(world.world_gdp() / w0, 1.0 / years) - 1.0
	_check(world_g > 0.01 and world_g < 0.08, "nominal world GDP in US$ grows %.1f%% a year" % (world_g * 100.0))
	var infl := []
	var growth := []
	var unemp := []
	var debt := []
	var nan := 0
	var sectors_off := 0
	for c: Country in world.countries:
		if not c.alive:
			continue
		infl.append(c.pi_yoy)
		growth.append(c.growth_yoy())
		unemp.append(c.unemp)
		debt.append(c.debt_ratio)
		if is_nan(c.y) or is_nan(c.pi_yoy) or is_nan(c.e) or is_nan(c.debt_ratio) or is_nan(c.reserves):
			nan += 1
		var s := 0.0
		for v in c.sector_out:
			s += v
		if absf(s / c.y - 1.0) > 0.01:
			sectors_off += 1
	infl.sort()
	growth.sort()
	unemp.sort()
	debt.sort()
	var mid := infl.size() / 2
	_check(nan == 0, "no series becomes NaN (%d countries)" % nan)
	_check(sectors_off == 0, "sectors add up to GDP in every country (%d off)" % sectors_off)
	_check(infl[mid] > 0.0 and infl[mid] < 0.08, "median inflation %.1f%%" % (infl[mid] * 100.0))
	_check(growth[mid] > 0.0 and growth[mid] < 0.07, "crescimento mediano %.1f%%" % (growth[mid] * 100.0))
	_check(unemp[mid] > 0.02 and unemp[mid] < 0.15, "desemprego mediano %.1f%%" % (unemp[mid] * 100.0))
	_check(debt[mid] > 0.2 and debt[mid] < 1.5, "median debt %.0f%% of GDP" % (debt[mid] * 100.0))
	var hyper := infl.filter(func(x): return x > 1.0).size()
	_check(hyper <= 3, "few hyperinflations in 15 years: %d" % hyper)

	# The AI moves its own economy.
	var moved := 0
	var ai := 0
	for c: Country in world.countries:
		if c == bra or not c.alive:
			continue
		ai += 1
		var s0: Dictionary = start[c.iso]
		if absf(c.tax_total() - float(s0.tax)) > 0.005 or absf(c.spend_total() - float(s0.sp)) > 0.005 or absf(c.tariff - float(s0.tariff)) > 0.005:
			moved += 1
	_check(moved > ai * 0.5, "the AI adjusts taxes, spending or tariffs in %d of %d countries" % [moved, ai])


## Without an independent central bank, the government can fix the rate; with a Taylor rule, the rate moves on its own.
func _central_bank() -> void:
	var world := _fresh("TUR")
	var tur: Country = world.player
	_check(not tur.cb_independent, "Turkey starts with a subordinate central bank")
	var r0 := tur.rate
	_months(world, 6)
	_check(absf(tur.rate - r0) > 0.01, "by the Taylor rule the Turkish interest rate moves: %.1f%% -> %.1f%%" % [r0 * 100.0, tur.rate * 100.0])
	tur.rate_manual = true
	tur.rate_set = 0.2
	_months(world, 8)
	_check(absf(tur.rate - 0.2) < 0.01, "with the manual rate the rate goes to the government's target: %.1f%%" % (tur.rate * 100.0))
	var said := tur.rate_said
	_check(absf(said - tur.rate) < 0.006, "the new rate is announced in the news (%.1f%%)" % (said * 100.0))


## Budget sliders and rates fixed by law reach the accounts and do not disappear.
func _budget_and_taxes() -> void:
	var base := _fresh()
	var world := _fresh()
	var c: Country = world.player
	_months(base, 1)
	_months(world, 1)
	var r: Dictionary = world.politics.set_budget(world, "sp_infra", c.sp_infra + 0.02)
	_check(r.ok, "the government changes infrastructure spending")
	_months(base, 36)
	_months(world, 36)
	var b: Country = base.player
	var gap := c.spending / c.y_nominal() - b.spending / b.y_nominal()
	_check(gap > 0.012, "three years later the extra spending is still in the accounts: +%.1f pp" % (gap * 100.0))
	_check(c.capital / c.y > b.capital / b.y, "more infrastructure accumulates more capital per unit of GDP")
	var before := c.revenue / c.y_nominal()
	world.legislation._set_policy(world, "tax_income", c.tax_income + 0.03)
	_months(world, 1)
	var after := c.revenue / c.y_nominal()
	_check(after - before > 0.02, "a rate fixed by law enters collection: %.1f%% -> %.1f%% of GDP" % [before * 100.0, after * 100.0])


## The norms' money enters the fiscal weight even when it falls between the closing and the country's fiscal step.
func _law_money() -> void:
	var world := _fresh()
	var c: Country = world.player
	_months(world, 2)
	for m in 12:
		# From day 2 on: after the norms close and (for Brazil) before the fiscal step.
		while world.day != 2:
			world.tick_day()
		Legislation._collect(c, 1.0)
		_months(world, 1)
	var expected := 12.0 / c.y_usd()
	_check(c.law_tax > expected * 0.9, "law_tax counts all the revenue of the norms: %.4f (expected ≥ %.4f)" % [c.law_tax, expected * 0.9])


## Annexing or ceding territory does not show up as growth or recession: the GDP history starts
## counting the new borders.
func _territory() -> void:
	var ax := _fresh("SAU")
	_months(ax, 13)
	var sau: Country = ax.by_iso["SAU"]
	var g_sau := sau.growth_yoy()
	ax.diplomacy.annex(sau, ax.by_iso["IRN"], ax)
	var worst := 0.0
	for m in 14:
		_months(ax, 1)
		worst = maxf(worst, absf(sau.growth_yoy() - g_sau))
	_check(worst < 0.06, "annexing Iran does not inflate Saudi growth (maximum deviation %.1f pp)" % (worst * 100.0))
	var cede := _fresh("IRQ")
	_months(cede, 13)
	var iq: Country = cede.by_iso["IRQ"]
	var g_iq := iq.growth_yoy()
	cede.diplomacy.transfer(iq, cede.by_iso["SYR"], 0.3, cede)
	var worst_iq := 0.0
	for m in 14:
		_months(cede, 1)
		worst_iq = maxf(worst_iq, absf(iq.growth_yoy() - g_iq))
	_check(worst_iq < 0.06, "ceding 30%% of the territory does not become a recession in Iraq (maximum deviation %.1f pp)" % (worst_iq * 100.0))
