extends SceneTree
## Economic formulas against textbook cases (Mankiw, Blanchard, Krugman-Obstfeld).
## Usage: godot --headless --path . -s tests/formulas.gd

var failures := 0


func _near(got: float, want: float, tol: float, what: String) -> void:
	var ok := absf(got - want) <= tol
	if ok:
		print("ok: ", what, " (got %.6f, expected %.6f)" % [got, want])
	else:
		failures += 1
		print("FAIL: ", what, " (got %.6f, expected %.6f)" % [got, want])


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	var F := EconFormulas
	# Quantity equation: M = 100, V = 5, Y = 250 → P = 2. Money +10%, V fixed, Y +3% → π ≈ 6.8%.
	_near(F.quantity_price(100.0, 5.0, 250.0), 2.0, 1e-9, "M·V = P·Y")
	_near(F.quantity_inflation(0.10, 0.0, 0.03), 1.10 / 1.03 - 1.0, 1e-9, "π = μ + Δv − g")
	_near(F.monetized_money_growth(1.0, 0.05, 2.0), 0.10, 1e-9, "issuance of 5% of GDP with V = 2 → money +10%")
	# Seigniorage and inflation tax: ΔM = 50, P = 2 → 25; π = 25%, M/P = 400 → 80.
	_near(F.seigniorage(50.0, 2.0), 25.0, 1e-9, "seigniorage ΔM/P")
	_near(F.inflation_tax(0.25, 400.0), 80.0, 1e-9, "inflation tax π/(1+π)·M/P")
	# Marshall-Lerner and J curve.
	_check(F.marshall_lerner(0.6, 0.5), "Marshall-Lerner holds with 0.6 + 0.5")
	_check(not F.marshall_lerner(0.3, 0.4), "Marshall-Lerner fails with 0.3 + 0.4")
	_check(F.j_curve(0.1, 0.6, 0.5, 0.0) < 0.0, "J curve: the trade balance worsens on impact")
	_check(F.j_curve(0.1, 0.6, 0.5, 1.0) > 0.0, "J curve: the trade balance improves in the long run")
	var r := 1.0
	for i in 12:
		r = F.lagged_rer(r, 1.2)
	_check(r > 1.0 and r < 1.2, "lagged real exchange rate converges slowly")
	# Multiplier: c = 0.8, t = 0.25, m = 0.1 → 1/(1 − 0.6 + 0.1) = 2. Closed economy without tax, c = 0.75 → 4.
	_near(F.keynes_multiplier(0.8, 0.25, 0.1), 2.0, 1e-9, "multiplier 1/(1 − c(1 − t) + m)")
	_near(F.keynes_multiplier(0.75, 0.0, 0.0), 4.0, 1e-9, "simple multiplier 1/(1 − c)")
	_near(F.tax_multiplier(0.75, 0.0, 0.0, 0.0), 3.0, 1e-9, "tax multiplier c/(1 − c)")
	_near(F.tax_multiplier(0.75, 0.0, 0.0, 1.0), 0.0, 1e-9, "full Ricardian equivalence cancels the tax cut")
	_check(F.ricardian_share(1.2, 0.6) > F.ricardian_share(0.4, 0.6), "partial Ricardian share grows with debt")
	# Balassa-Samuelson: γ = 0.5, tradables productivity 3 p.p. above abroad → 1.5% a year.
	_near(F.balassa_samuelson(0.05, 0.01, 0.02, 0.01, 0.5), 0.015, 1e-9, "Balassa-Samuelson")
	# Hotelling: rent 10 at 5% → 10·1.05^10 = 16.289.
	_near(F.hotelling_rent(10.0, 0.05, 10.0), 16.288946, 1e-5, "Hotelling: rent grows at r")
	_near(F.hotelling_price(100.0, 0.0, 0.05, 10.0), 100.0, 1e-9, "Hotelling without scarcity rent")
	# Gini: equality → 0; one of 4 has everything → (n−1)/n = 0.75; lognormal Lorenz reproduces the Gini.
	_near(F.gini(PackedFloat64Array([5, 5, 5, 5])), 0.0, 1e-9, "Gini of equality")
	_near(F.gini(PackedFloat64Array([0, 0, 0, 10])), 0.75, 1e-9, "Gini of total concentration")
	_near(F.gini(PackedFloat64Array([1, 2, 3, 4, 5])), 4.0 / 15.0, 1e-9, "Gini of 1..5 = 0.267")
	var pts := PackedVector2Array()
	for i in 201:
		pts.append(Vector2(i / 200.0, F.lorenz(i / 200.0, 0.4)))
	_near(F.gini_from_lorenz(pts), 0.4, 0.005, "lognormal Lorenz curve with Gini 0.4")
	var q := F.quintile_shares(0.4)
	var sum := 0.0
	for x in q:
		sum += x
	_near(sum, 1.0, 1e-6, "quintiles add up to 100%")
	_check(q[0] < 0.08 and q[4] > 0.4, "quintiles with Gini 0.4: poor < 8%, rich > 40%")
	_near(F.norm_inv(0.975), 1.959964, 1e-5, "inverse of the normal")
	# Dutch disease: resource income +4 p.p. of GDP → industry −2 p.p.
	_near(F.dutch_disease(0.04), -0.02, 1e-9, "Dutch disease")
	# Solow (Mankiw): s = 0.3, n + g + δ = 0.1, α = 0.5 → k* = 9, y* = 3, K/Y = 3.
	_near(F.solow_k_star(0.3, 0.02, 0.03, 0.05, 0.5), 9.0, 1e-9, "Solow k*")
	_near(F.solow_y_star(0.3, 0.02, 0.03, 0.05, 0.5), 3.0, 1e-9, "Solow y*")
	_near(F.solow_ky(0.3, 0.02, 0.03, 0.05), 3.0, 1e-9, "Solow K/Y")
	_near(F.cobb_douglas(1.0, 8.0, 1.0, 1.0 / 3.0), 2.0, 1e-9, "Cobb-Douglas 8^(1/3)")
	# Phillips: πe = 2%, κ = 0.3, gap 1% → 2.3%.
	_near(F.phillips(0.02, 0.3, 0.01), 0.023, 1e-9, "augmented Phillips")
	# Taylor (1993): r* = 2%, π = 2% on target, gap 0 → 4%; π = 4%, gap 1% → 7.5%.
	_near(F.taylor(0.02, 0.02, 0.02, 0.0), 0.04, 1e-9, "Taylor on target")
	_near(F.taylor(0.02, 0.04, 0.02, 0.01), 0.075, 1e-9, "Taylor with inflation and gap")
	# PPP: inflation 10% against 2% → depreciation 7.84%; P = 300, P* = 100 → E = 3.
	_near(F.ppp_depreciation(0.10, 0.02), 1.10 / 1.02 - 1.0, 1e-9, "relative PPP")
	_near(F.ppp_rate(300.0, 100.0), 3.0, 1e-9, "absolute PPP")
	# Laffer: ε = 1 → peak at 50%; revenue at t0 is t0; above the peak it falls.
	_near(F.laffer_peak(1.0), 0.5, 1e-9, "Laffer t* = 1/(1+ε)")
	_near(F.laffer_revenue(0.3, 0.3), 0.3, 1e-9, "Laffer at the starting burden")
	_check(F.laffer_revenue(0.7, 0.3, 1.0) < F.laffer_revenue(0.5, 0.3, 1.0), "Laffer falls above the peak")
	# Gravity: doubling the distance with θ = 1 halves trade; masses with exponent 1.
	_near(F.gravity(100.0, 50.0, 10.0, 1.0, 1.0, 1.0, 1.0), 500.0, 1e-9, "gravity Yi·Yj/D")
	_near(F.gravity(100.0, 50.0, 20.0, 1.0, 1.0, 1.0, 1.0) / F.gravity(100.0, 50.0, 10.0, 1.0, 1.0, 1.0, 1.0), 0.5, 1e-9, "double the distance, half the trade")
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
