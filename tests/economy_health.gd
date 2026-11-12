extends SceneTree
## Saúde da economia em partidas longas: contas do primeiro dia, reservas, volatilidade da bolsa, nota de
## crédito, notícias macro, juro sob governo, sliders e impostos por lei, normas no peso fiscal e séries
## plausíveis em 15 anos.
## Uso: godot --headless --path . --script tests/economy_health.gd

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


## Avança sem eleição nem fim de jogo: o que se mede aqui é a economia.
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


## Antes da primeira etapa mensal, a aba Fiscal e a nota já têm números de verdade.
func _first_day() -> void:
	var world := _fresh()
	var bra: Country = world.player
	var usa: Country = world.usa
	_check(bra.revenue > 0.0 and bra.spending > bra.revenue * 0.5, "receita e gasto do Brasil no primeiro dia: %.0f / %.0f" % [bra.revenue, bra.spending])
	var dr := bra.deficit / bra.y_nominal()
	_check(dr > 0.03 and dr < 0.12, "déficit do Brasil no primeiro dia é plausível: %.1f%%" % (dr * 100.0))
	_check(bra.interest > 0.0, "juros da dívida já contam no primeiro dia")
	_check(usa.rating in ["AAA", "AA"], "a nota dos EUA no primeiro dia vem do risco, não do padrão: %s" % usa.rating)
	var ratings := {}
	for c: Country in world.countries:
		ratings[c.rating] = true
	_check(ratings.size() >= 4, "as notas de partida variam entre países: %s" % str(ratings.keys()))
	var nan := 0
	for c: Country in world.countries:
		if is_nan(c.revenue) or is_nan(c.deficit) or is_inf(c.deficit):
			nan += 1
	_check(nan == 0, "nenhum país começa com contas inválidas (%d)" % nan)


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

	# Reservas: país de câmbio flutuante sem fuga de capital não queima reservas com déficit externo.
	for iso in ["USA", "AUS", "BRA", "IND", "GBR"]:
		var c: Country = world.by_iso[iso]
		var r0: float = start[iso].res
		_check(c.reserves > r0 * 0.5, "%s mantém reservas em 15 anos: %.0f -> %.0f" % [iso, r0, c.reserves])
	_check(world.usa.rating in ["AAA", "AA"], "os EUA não perdem a nota por falta de reservas: %s" % world.usa.rating)

	# Bolsa: oscilação mensal na faixa das bolsas reais (EUA ~4-5%, emergentes até ~7%).
	var sds := []
	for iso in ["USA", "DEU", "JPN", "GBR", "FRA", "CAN"]:
		sds.append(_monthly_sd(world.by_iso[iso].hist.get("stock", PackedFloat32Array())))
	var avg_sd: float = sds.reduce(func(a, b): return a + b, 0.0) / sds.size()
	_check(avg_sd < 0.062 and sds.max() < 0.075, "bolsas ricas oscilam %.1f%% ao mês em média (< 6,2%%; antes ~7%%): %s" % [avg_sd * 100.0, str(sds.map(func(x): return snappedf(x * 100.0, 0.1)))])
	var bad_stock := 0
	for c: Country in world.countries:
		if c.alive and (is_nan(c.stock) or c.stock <= 0.0 or is_inf(c.stock)):
			bad_stock += 1
	_check(bad_stock == 0, "índices de bolsa positivos e finitos (%d ruins)" % bad_stock)

	# Nota de crédito não pisca todo mês, e cada mudança do jogador vira notícia.
	_check(bra_ratings.size() - 1 <= 8, "nota do Brasil muda poucas vezes em 15 anos: %s" % str(bra_ratings))
	var rating_news := news.filter(func(t): return String(t).contains("nota de crédito")).size()
	_check(rating_news == bra_ratings.size() - 1, "cada mudança de nota do jogador sai no noticiário (%d notícias, %d mudanças)" % [rating_news, bra_ratings.size() - 1])
	_check(news.any(func(t): return String(t).contains("juro básico")), "decisões do banco central aparecem no noticiário")

	# Séries agregadas plausíveis.
	var w0 := 0.0
	for iso in start:
		w0 += float(start[iso].y)
	var years := 15.0
	var world_g := pow(world.world_gdp() / w0, 1.0 / years) - 1.0
	_check(world_g > 0.01 and world_g < 0.08, "PIB mundial nominal em US$ cresce %.1f%% ao ano" % (world_g * 100.0))
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
	_check(nan == 0, "nenhuma série vira NaN (%d países)" % nan)
	_check(sectors_off == 0, "setores somam o PIB em todos os países (%d fora)" % sectors_off)
	_check(infl[mid] > 0.0 and infl[mid] < 0.08, "inflação mediana %.1f%%" % (infl[mid] * 100.0))
	_check(growth[mid] > 0.0 and growth[mid] < 0.07, "crescimento mediano %.1f%%" % (growth[mid] * 100.0))
	_check(unemp[mid] > 0.02 and unemp[mid] < 0.15, "desemprego mediano %.1f%%" % (unemp[mid] * 100.0))
	_check(debt[mid] > 0.2 and debt[mid] < 1.5, "dívida mediana %.0f%% do PIB" % (debt[mid] * 100.0))
	var hyper := infl.filter(func(x): return x > 1.0).size()
	_check(hyper <= 3, "poucas hiperinflações em 15 anos: %d" % hyper)

	# A IA mexe na própria economia.
	var moved := 0
	var ai := 0
	for c: Country in world.countries:
		if c == bra or not c.alive:
			continue
		ai += 1
		var s0: Dictionary = start[c.iso]
		if absf(c.tax_total() - float(s0.tax)) > 0.005 or absf(c.spend_total() - float(s0.sp)) > 0.005 or absf(c.tariff - float(s0.tariff)) > 0.005:
			moved += 1
	_check(moved > ai * 0.5, "a IA ajusta impostos, gastos ou tarifas em %d de %d países" % [moved, ai])


## Sem banco central independente, o governo pode fixar o juro; com regra de Taylor, o juro anda sozinho.
func _central_bank() -> void:
	var world := _fresh("TUR")
	var tur: Country = world.player
	_check(not tur.cb_independent, "a Turquia começa com banco central subordinado")
	var r0 := tur.rate
	_months(world, 6)
	_check(absf(tur.rate - r0) > 0.01, "pela regra de Taylor o juro turco se move: %.1f%% -> %.1f%%" % [r0 * 100.0, tur.rate * 100.0])
	tur.rate_manual = true
	tur.rate_set = 0.2
	_months(world, 8)
	_check(absf(tur.rate - 0.2) < 0.01, "no juro manual a taxa vai ao alvo do governo: %.1f%%" % (tur.rate * 100.0))
	var said := tur.rate_said
	_check(absf(said - tur.rate) < 0.006, "o juro novo é anunciado no noticiário (%.1f%%)" % (said * 100.0))


## Sliders do orçamento e alíquotas fixadas por lei chegam às contas e não somem.
func _budget_and_taxes() -> void:
	var base := _fresh()
	var world := _fresh()
	var c: Country = world.player
	_months(base, 1)
	_months(world, 1)
	var r: Dictionary = world.politics.set_budget(world, "sp_infra", c.sp_infra + 0.02)
	_check(r.ok, "o governo muda o gasto em infraestrutura")
	_months(base, 36)
	_months(world, 36)
	var b: Country = base.player
	var gap := c.spending / c.y_nominal() - b.spending / b.y_nominal()
	_check(gap > 0.012, "três anos depois o gasto a mais ainda está nas contas: +%.1f pp" % (gap * 100.0))
	_check(c.capital / c.y > b.capital / b.y, "mais infraestrutura acumula mais capital por unidade de PIB")
	var before := c.revenue / c.y_nominal()
	world.legislation._set_policy(world, "tax_income", c.tax_income + 0.03)
	_months(world, 1)
	var after := c.revenue / c.y_nominal()
	_check(after - before > 0.02, "alíquota fixada por lei entra na arrecadação: %.1f%% -> %.1f%% do PIB" % [before * 100.0, after * 100.0])


## O dinheiro das normas entra no peso fiscal mesmo quando cai entre o fechamento e a etapa fiscal do país.
func _law_money() -> void:
	var world := _fresh()
	var c: Country = world.player
	_months(world, 2)
	for m in 12:
		# Do dia 2 em diante: depois do fechamento das normas e (para o Brasil) antes da etapa fiscal.
		while world.day != 2:
			world.tick_day()
		Legislation._collect(c, 1.0)
		_months(world, 1)
	var expected := 12.0 / c.y_usd()
	_check(c.law_tax > expected * 0.9, "law_tax conta toda a receita das normas: %.4f (esperado ≥ %.4f)" % [c.law_tax, expected * 0.9])


## Anexar ou ceder território não aparece como crescimento ou recessão: o histórico do PIB passa a
## contar as fronteiras novas.
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
	_check(worst < 0.06, "anexar o Irã não infla o crescimento saudita (desvio máximo %.1f pp)" % (worst * 100.0))
	var cede := _fresh("IRQ")
	_months(cede, 13)
	var iq: Country = cede.by_iso["IRQ"]
	var g_iq := iq.growth_yoy()
	cede.diplomacy.transfer(iq, cede.by_iso["SYR"], 0.3, cede)
	var worst_iq := 0.0
	for m in 14:
		_months(cede, 1)
		worst_iq = maxf(worst_iq, absf(iq.growth_yoy() - g_iq))
	_check(worst_iq < 0.06, "ceder 30%% do território não vira recessão no Iraque (desvio máximo %.1f pp)" % (worst_iq * 100.0))
