extends SceneTree
## Fórmulas econômicas contra casos de livro-texto (Mankiw, Blanchard, Krugman-Obstfeld).
## Uso: godot --headless --path . --script tests/formulas.gd

var failures := 0


func _near(got: float, want: float, tol: float, what: String) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		failures += 1
	print("ok: " if ok else "FALHA: ", what, " (obtido %.6f, esperado %.6f)" % [got, want])


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _init() -> void:
	var F := EconFormulas
	# Quantitativa: M = 100, V = 5, Y = 250 → P = 2. Moeda +10%, V fixo, Y +3% → π ≈ 6,8%.
	_near(F.quantity_price(100.0, 5.0, 250.0), 2.0, 1e-9, "M·V = P·Y")
	_near(F.quantity_inflation(0.10, 0.0, 0.03), 1.10 / 1.03 - 1.0, 1e-9, "π = μ + Δv − g")
	_near(F.monetized_money_growth(1.0, 0.05, 2.0), 0.10, 1e-9, "emissão de 5% do PIB com V = 2 → moeda +10%")
	# Senhoriagem e imposto inflacionário: ΔM = 50, P = 2 → 25; π = 25%, M/P = 400 → 80.
	_near(F.seigniorage(50.0, 2.0), 25.0, 1e-9, "senhoriagem ΔM/P")
	_near(F.inflation_tax(0.25, 400.0), 80.0, 1e-9, "imposto inflacionário π/(1+π)·M/P")
	# Marshall-Lerner e curva J.
	_check(F.marshall_lerner(0.6, 0.5), "Marshall-Lerner vale com 0,6 + 0,5")
	_check(not F.marshall_lerner(0.3, 0.4), "Marshall-Lerner falha com 0,3 + 0,4")
	_check(F.j_curve(0.1, 0.6, 0.5, 0.0) < 0.0, "curva J: balança piora no impacto")
	_check(F.j_curve(0.1, 0.6, 0.5, 1.0) > 0.0, "curva J: balança melhora no longo prazo")
	var r := 1.0
	for i in 12:
		r = F.lagged_rer(r, 1.2)
	_check(r > 1.0 and r < 1.2, "câmbio real defasado converge devagar")
	# Multiplicador: c = 0,8, t = 0,25, m = 0,1 → 1/(1 − 0,6 + 0,1) = 2. Economia fechada sem imposto c = 0,75 → 4.
	_near(F.keynes_multiplier(0.8, 0.25, 0.1), 2.0, 1e-9, "multiplicador 1/(1 − c(1 − t) + m)")
	_near(F.keynes_multiplier(0.75, 0.0, 0.0), 4.0, 1e-9, "multiplicador simples 1/(1 − c)")
	_near(F.tax_multiplier(0.75, 0.0, 0.0, 0.0), 3.0, 1e-9, "multiplicador do imposto c/(1 − c)")
	_near(F.tax_multiplier(0.75, 0.0, 0.0, 1.0), 0.0, 1e-9, "equivalência ricardiana plena anula o corte de imposto")
	_check(F.ricardian_share(1.2, 0.6) > F.ricardian_share(0.4, 0.6), "ricardiana parcial cresce com a dívida")
	# Balassa-Samuelson: γ = 0,5, produtividade dos comercializáveis 3 p.p. acima do exterior → 1,5% a.a.
	_near(F.balassa_samuelson(0.05, 0.01, 0.02, 0.01, 0.5), 0.015, 1e-9, "Balassa-Samuelson")
	# Hotelling: renda 10 a 5% → 10·1,05^10 = 16,289.
	_near(F.hotelling_rent(10.0, 0.05, 10.0), 16.288946, 1e-5, "Hotelling: renda cresce a r")
	_near(F.hotelling_price(100.0, 0.0, 0.05, 10.0), 100.0, 1e-9, "Hotelling sem renda de escassez")
	# Gini: igualdade → 0; um só tem tudo entre 4 → (n−1)/n = 0,75; Lorenz lognormal reproduz o Gini.
	_near(F.gini(PackedFloat64Array([5, 5, 5, 5])), 0.0, 1e-9, "Gini da igualdade")
	_near(F.gini(PackedFloat64Array([0, 0, 0, 10])), 0.75, 1e-9, "Gini da concentração total")
	_near(F.gini(PackedFloat64Array([1, 2, 3, 4, 5])), 4.0 / 15.0, 1e-9, "Gini de 1..5 = 0,267")
	var pts := PackedVector2Array()
	for i in 201:
		pts.append(Vector2(i / 200.0, F.lorenz(i / 200.0, 0.4)))
	_near(F.gini_from_lorenz(pts), 0.4, 0.005, "curva de Lorenz lognormal com Gini 0,4")
	var q := F.quintile_shares(0.4)
	var sum := 0.0
	for x in q:
		sum += x
	_near(sum, 1.0, 1e-6, "quintis somam 100%")
	_check(q[0] < 0.08 and q[4] > 0.4, "quintis com Gini 0,4: pobres < 8%, ricos > 40%")
	_near(F.norm_inv(0.975), 1.959964, 1e-5, "inversa da normal")
	# Doença holandesa: renda de recursos +4 p.p. do PIB → indústria −2 p.p.
	_near(F.dutch_disease(0.04), -0.02, 1e-9, "doença holandesa")
	# Solow (Mankiw): s = 0,3, n + g + δ = 0,1, α = 0,5 → k* = 9, y* = 3, K/Y = 3.
	_near(F.solow_k_star(0.3, 0.02, 0.03, 0.05, 0.5), 9.0, 1e-9, "Solow k*")
	_near(F.solow_y_star(0.3, 0.02, 0.03, 0.05, 0.5), 3.0, 1e-9, "Solow y*")
	_near(F.solow_ky(0.3, 0.02, 0.03, 0.05), 3.0, 1e-9, "Solow K/Y")
	_near(F.cobb_douglas(1.0, 8.0, 1.0, 1.0 / 3.0), 2.0, 1e-9, "Cobb-Douglas 8^(1/3)")
	# Phillips: πe = 2%, κ = 0,3, hiato 1% → 2,3%.
	_near(F.phillips(0.02, 0.3, 0.01), 0.023, 1e-9, "Phillips aumentada")
	# Taylor (1993): r* = 2%, π = 2% na meta, hiato 0 → 4%; π = 4%, hiato 1% → 7,5%.
	_near(F.taylor(0.02, 0.02, 0.02, 0.0), 0.04, 1e-9, "Taylor na meta")
	_near(F.taylor(0.02, 0.04, 0.02, 0.01), 0.075, 1e-9, "Taylor com inflação e hiato")
	# PPC: inflação 10% contra 2% → depreciação 7,84%; P = 300, P* = 100 → E = 3.
	_near(F.ppp_depreciation(0.10, 0.02), 1.10 / 1.02 - 1.0, 1e-9, "PPC relativa")
	_near(F.ppp_rate(300.0, 100.0), 3.0, 1e-9, "PPC absoluta")
	# Laffer: ε = 1 → pico em 50%; arrecadação em t0 é t0; acima do pico cai.
	_near(F.laffer_peak(1.0), 0.5, 1e-9, "Laffer t* = 1/(1+ε)")
	_near(F.laffer_revenue(0.3, 0.3), 0.3, 1e-9, "Laffer na carga de partida")
	_check(F.laffer_revenue(0.7, 0.3, 1.0) < F.laffer_revenue(0.5, 0.3, 1.0), "Laffer cai acima do pico")
	# Gravitacional: dobrar a distância com θ = 1 corta o comércio pela metade; massas com expoente 1.
	_near(F.gravity(100.0, 50.0, 10.0, 1.0, 1.0, 1.0, 1.0), 500.0, 1e-9, "gravitacional Yi·Yj/D")
	_near(F.gravity(100.0, 50.0, 20.0, 1.0, 1.0, 1.0, 1.0) / F.gravity(100.0, 50.0, 10.0, 1.0, 1.0, 1.0, 1.0), 0.5, 1e-9, "distância em dobro, metade do comércio")
	print("\n%d falha(s)" % failures)
	quit(1 if failures > 0 else 0)
