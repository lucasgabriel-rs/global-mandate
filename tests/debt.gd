extends SceneTree
## Dívida e juros: curva de juros, efeito Fisher, títulos prefixados, indexados e em dólar, rolagem dos
## vencimentos e a identidade Δb = (r − g)/(1 + g)·b − saldo primário.
## Uso: godot --headless --path . -s tests/debt.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _months(w: GameWorld, n: int) -> void:
	for i in int(n * 30.4167):
		w.tick_day()


func _init() -> void:
	var w := GameWorld.new()
	w.setup(11)
	var usa: Country = w.by_iso["USA"]
	var bra: Country = w.by_iso["BRA"]
	var gbr: Country = w.by_iso["GBR"]

	_check(usa.curve.size() == Economy.TENORS.size(), "curva tem um rendimento por prazo")
	_check(is_equal_approx(usa.yield_gov, usa.curve[Economy.TENOR_10Y]), "rendimento do governo é o título de 10 anos")
	_check(bra.debt_il_share > 0.3 and gbr.debt_maturity > 10.0, "Brasil tem muita dívida indexada; Reino Unido, prazo longo")

	# Efeito Fisher na ponta longa: i = r + πᵉ.
	var fisher := Economy.yield_at(bra, 30.0) - Economy.real_yield_at(bra, 30.0)
	_check(is_equal_approx(fisher, Economy.expected_inflation(bra, 30.0)), "i − r = inflação esperada (%.2f%%)" % (fisher * 100.0))
	var c2: Country = Country.from_dict(bra.to_dict())
	c2.pi_e += 0.05
	c2.cred = 0.0
	Economy.update_curve(c2, w)
	_check(c2.curve[5] > bra.curve[5] + 0.04, "inflação esperada maior sobe o juro longo")

	# Curva: juro curto acima do longo inverte a curva.
	var inv: Country = Country.from_dict(usa.to_dict())
	inv.rate = 0.09
	Economy.update_curve(inv, w)
	_check(inv.curve[0] > inv.curve[5], "aperto monetário forte inverte a curva")
	var norm: Country = Country.from_dict(usa.to_dict())
	norm.rate = norm.r_n + norm.pi_e - 0.01
	Economy.update_curve(norm, w)
	_check(norm.curve[5] > norm.curve[0], "juro curto baixo deixa a curva positivamente inclinada")

	# Vencimentos: a escada soma a dívida toda, e o primeiro ano é o que precisa ser rolado.
	var mats := Economy.maturities(bra, 200)
	var total := 0.0
	for v in mats:
		total += v
	var debt := bra.debt_loc + bra.debt_fx * bra.e
	_check(absf(total - debt) / debt < 0.001, "vencimentos somam a dívida")
	_check(is_equal_approx(Economy.maturities(bra, 1)[0], bra.rollover) or bra.rollover == 0.0, "rolagem do ano = vencimentos de 12 meses")
	var short_m: Country = Country.from_dict(bra.to_dict())
	short_m.debt_maturity = 1.5
	_check(Economy.maturities(short_m, 1)[0] > Economy.maturities(bra, 1)[0] * 1.5, "prazo curto aumenta os vencimentos")

	# Bola de neve exata.
	_check(is_equal_approx(Economy.debt_snowball(1.0, 0.05, 0.02), 0.03 / 1.02), "(r − g)/(1 + g)·b")

	_months(w, 26)
	_check(bra.rollover > 0.0, "rolagem calculada")
	# Sem dívida externa nem emissão monetária, a identidade fecha sem ajuste.
	var d: Dictionary = usa.debt_dyn
	_check(absf(d.adjust) < 0.002, "EUA: Δb = bola de neve − primário (ajuste %.4f)" % d.adjust)
	_check(absf(d.change - (d.snowball - d.primary + d.adjust)) < 1e-5, "decomposição soma a variação da dívida")

	# Indexados: inflação alta encarece o juro só da parte corrigida.
	var hi: Country = Country.from_dict(bra.to_dict())
	var lo: Country = Country.from_dict(bra.to_dict())
	hi.pi_yoy = 0.2
	lo.pi_yoy = 0.0
	Economy._fiscal_flows(hi)
	Economy._fiscal_flows(lo)
	var expect := bra.debt_loc * bra.debt_il_share * 0.2
	_check(absf((hi.interest - lo.interest) - expect) < expect * 0.01, "correção monetária só na dívida indexada")

	# Risco alto encurta o prazo que o mercado aceita.
	var risky: Country = w.by_iso["ARG"]
	var m0 := risky.debt_mat0
	_check(risky.risk < 0.1 or risky.debt_maturity < m0, "risco alto encurta o prazo médio")

	print("falhas: ", failures)
	quit(1 if failures > 0 else 0)
