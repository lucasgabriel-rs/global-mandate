extends SceneTree
## Debt and interest: yield curve, Fisher effect, fixed-rate, inflation-linked and dollar bonds, rollover of
## maturities and the identity Δb = (r − g)/(1 + g)·b − primary balance.
## Usage: godot --headless --path . -s tests/debt.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _months(w: GameWorld, n: int) -> void:
	for i in int(n * 30.4167):
		w.tick_day()


func _init() -> void:
	var w := GameWorld.new()
	w.setup(11)
	var usa: Country = w.by_iso["USA"]
	var bra: Country = w.by_iso["BRA"]
	var gbr: Country = w.by_iso["GBR"]

	_check(usa.curve.size() == Economy.TENORS.size(), "curve has one yield per tenor")
	_check(is_equal_approx(usa.yield_gov, usa.curve[Economy.TENOR_10Y]), "government yield is the 10-year bond")
	_check(bra.debt_il_share > 0.3 and gbr.debt_maturity > 10.0, "Brazil has a lot of indexed debt; the UK, a long maturity")

	# Fisher effect at the long end: i = r + πᵉ.
	var fisher := Economy.yield_at(bra, 30.0) - Economy.real_yield_at(bra, 30.0)
	_check(is_equal_approx(fisher, Economy.expected_inflation(bra, 30.0)), "i − r = expected inflation (%.2f%%)" % (fisher * 100.0))
	var c2: Country = Country.from_dict(bra.to_dict())
	c2.pi_e += 0.05
	c2.cred = 0.0
	Economy.update_curve(c2, w)
	_check(c2.curve[5] > bra.curve[5] + 0.04, "higher expected inflation raises the long rate")

	# Curve: a short rate above the long one inverts the curve.
	var inv: Country = Country.from_dict(usa.to_dict())
	inv.rate = 0.09
	Economy.update_curve(inv, w)
	_check(inv.curve[0] > inv.curve[5], "strong monetary tightening inverts the curve")
	var norm: Country = Country.from_dict(usa.to_dict())
	norm.rate = norm.r_n + norm.pi_e - 0.01
	Economy.update_curve(norm, w)
	_check(norm.curve[5] > norm.curve[0], "a low short rate leaves the curve upward sloping")

	# Maturities: the ladder adds up to the whole debt, and the first year is what has to be rolled over.
	var mats := Economy.maturities(bra, 200)
	var total := 0.0
	for v in mats:
		total += v
	var debt := bra.debt_loc + bra.debt_fx * bra.e
	_check(absf(total - debt) / debt < 0.001, "maturities add up to the debt")
	_check(is_equal_approx(Economy.maturities(bra, 1)[0], bra.rollover) or bra.rollover == 0.0, "yearly rollover = maturities of 12 months")
	var short_m: Country = Country.from_dict(bra.to_dict())
	short_m.debt_maturity = 1.5
	_check(Economy.maturities(short_m, 1)[0] > Economy.maturities(bra, 1)[0] * 1.5, "a short maturity increases the maturities")

	# Exact snowball.
	_check(is_equal_approx(Economy.debt_snowball(1.0, 0.05, 0.02), 0.03 / 1.02), "(r − g)/(1 + g)·b")

	_months(w, 26)
	_check(bra.rollover > 0.0, "rollover computed")
	# Without external debt or money issuance, the identity closes without adjustment.
	var d: Dictionary = usa.debt_dyn
	_check(absf(d.adjust) < 0.002, "US: Δb = snowball − primary (adjustment %.4f)" % d.adjust)
	_check(absf(d.change - (d.snowball - d.primary + d.adjust)) < 1e-5, "decomposition adds up to the change in debt")

	# Indexed: high inflation raises interest only on the indexed part.
	var hi: Country = Country.from_dict(bra.to_dict())
	var lo: Country = Country.from_dict(bra.to_dict())
	hi.pi_yoy = 0.2
	lo.pi_yoy = 0.0
	Economy._fiscal_flows(hi)
	Economy._fiscal_flows(lo)
	var expect := bra.debt_loc * bra.debt_il_share * 0.2
	_check(absf((hi.interest - lo.interest) - expect) < expect * 0.01, "inflation accrual only on the indexed debt")

	# High risk shortens the maturity the market accepts.
	var risky: Country = w.by_iso["ARG"]
	var m0 := risky.debt_mat0
	_check(risky.risk < 0.1 or risky.debt_maturity < m0, "high risk shortens the average maturity")

	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
