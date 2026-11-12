extends SceneTree
## Exchange and sovereign fund: central bank intervention with reserves, capital controls and flight,
## dollarization, uncovered parity, starting fund balances, return, withdrawal rule, commodity
## buffer, risk, approval and the Exchange Law in the legislative center.
## Usage: godot --headless --path . --script tests/fx_swf.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _fresh(iso: String, seed_value := 11) -> GameWorld:
	var world := GameWorld.new()
	world.setup(seed_value)
	world.set_player(world.by_iso[iso], "normal")
	world.leader = Character.random(world.rng)
	return world


func _force_majority(world: GameWorld) -> void:
	var data: Dictionary = world.politics.data_of(world.player.iso)
	for party: Dictionary in data.parties:
		party.econ = 0.0
		party.social = 0.0
	world.player.approval = 0.9


func _settle(world: GameWorld, norm: Dictionary, limit := 300) -> void:
	for i in limit:
		world.player.next_election = 9999.0
		_force_majority(world)
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


func _months(world: GameWorld, n: int) -> void:
	for i in int(n * 30.4167):
		world.player.next_election = world.year_float() + 2.0
		world.over = false
		world.tick_day()
	world.flush_events()


func _blocks_of(norm: Dictionary, type: String) -> Array:
	return LawProgram.all_blocks(norm.program).filter(func(b): return b.type == type)


func _init() -> void:
	_starting_funds()
	_intervention()
	_capital_flows()
	_uip()
	_fund_mechanics()
	_fund_law()
	_long_run()
	print("RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)


## The seven large funds start near the real balances; those with no fund start at zero.
func _starting_funds() -> void:
	var world := GameWorld.new()
	world.setup(3)
	var real := {"NOR": 1800.0, "SAU": 940.0, "ARE": 1500.0, "KWT": 970.0, "QAT": 520.0, "CHN": 1330.0, "SGP": 1100.0}
	for iso: String in real:
		var c: Country = world.by_iso[iso]
		_check(c.swf_active and absf(c.swf / float(real[iso]) - 1.0) < 0.25, "%s starts with a fund of US$ %.0f bn (real ~%.0f)" % [iso, c.swf, real[iso]])
	_check(world.by_iso["BRA"].swf == 0.0 and not world.by_iso["BRA"].swf_active, "Brazil starts without a sovereign fund")
	var nor: Country = world.by_iso["NOR"]
	_check(absf(nor.swf_limit - 0.03) < 0.006, "Norway follows the 3%% rule: %.2f%%" % (nor.swf_limit * 100.0))
	_check(nor.swf_rent_share > 0.9, "Norwegian oil revenue all goes to the fund")


## Under depreciation pressure the central bank sells reserves and holds back part of the move.
func _intervention() -> void:
	var results := {}
	for lean in [0.0, 0.7]:
		var world := GameWorld.new()
		world.setup(5)
		var c: Country = world.by_iso["BRA"]
		c.fx_lean = lean
		c.risk = c.risk0 + 0.15
		var e0 := c.e
		var r0 := c.reserves
		world.rng.seed = 99
		for m in 6:
			Economy._float_exchange(c, world)
		results[lean] = [c.e / e0, r0 - c.reserves, c.fx_interv]
	print("  exchange rate without intervention x%.3f, with intervention x%.3f; reserves sold %.1f" % [results[0.0][0], results[0.7][0], results[0.7][1]])
	_check(results[0.7][1] > 1.0 and results[0.7][2] > 0.0, "the central bank sells reserves when the currency falls (US$ %.1f bn)" % results[0.7][1])
	_check(absf(results[0.0][1]) < 0.5, "with no intervention reserves stay still")
	_check(results[0.7][0] < results[0.0][0], "the intervention holds back the depreciation")
	# With the currency rising, the central bank buys dollars.
	var world2 := GameWorld.new()
	world2.setup(5)
	var b: Country = world2.by_iso["BRA"]
	b.fx_lean = 0.7
	b.e *= 1.4
	var r1 := b.reserves
	Economy._float_exchange(b, world2)
	_check(b.reserves > r1 and b.fx_interv < 0.0, "with the currency too weak the central bank buys reserves")
	# Without reserves there is nothing to sell.
	b.reserves = 0.0
	b.risk = b.risk0 + 0.2
	Economy._float_exchange(b, world2)
	_check(b.reserves >= 0.0, "reservas nunca ficam negativas")


## High risk makes capital flee; capital controls hold back the flight; high inflation dollarizes.
func _capital_flows() -> void:
	var world := GameWorld.new()
	world.setup(5)
	var c: Country = world.by_iso["BRA"]
	c.risk = c.risk0 + 0.1
	c.cap_controls = 0.0
	Economy._capital_flight(c, world, c.y_usd())
	var free := c.cap_flight
	c.cap_controls = 0.75
	Economy._capital_flight(c, world, c.y_usd())
	var closed := c.cap_flight
	_check(free > 0.0, "risk above the starting level makes capital flee (US$ %.0f bn/year)" % free)
	_check(closed < free * 0.5, "capital quotas cut the flight: %.0f -> %.0f" % [free, closed])
	var dz0 := c.dollarization
	c.pi_yoy = 0.6
	for m in 36:
		Economy._capital_flight(c, world, c.y_usd())
	_check(c.dollarization > dz0 + 0.2, "60%% inflation dollarizes the economy: %.0f%% -> %.0f%%" % [dz0 * 100.0, c.dollarization * 100.0])
	var high := c.dollarization
	c.pi_yoy = 0.03
	for m in 12:
		Economy._capital_flight(c, world, c.y_usd())
	_check(c.dollarization < high and c.dollarization > high * 0.8, "dollarization falls slowly when inflation drops")


## Uncovered parity: i - i* = expected depreciation + risk premium.
func _uip() -> void:
	var world := GameWorld.new()
	world.setup(5)
	var c: Country = world.by_iso["BRA"]
	Economy._float_exchange(c, world)
	var premium := c.risk + 0.5 * c.cap_flight / maxf(c.y_usd(), 0.001)
	_check(absf(c.rate - world.usa.rate - (c.uip_dep + premium)) < 1e-6, "i = i* + Δeᵉ + premium (Δeᵉ = %.2f%%)" % (c.uip_dep * 100.0))
	var low := c.uip_dep
	c.rate += 0.05
	Economy._float_exchange(c, world)
	_check(c.uip_dep > low + 0.04, "a higher interest rate raises the expected depreciation the market accepts")


## Return, contribution, withdrawal, commodity buffer, risk and approval.
func _fund_mechanics() -> void:
	var world := GameWorld.new()
	world.setup(5)
	var nor: Country = world.by_iso["NOR"]
	Economy._fiscal_flows(nor)
	var out0 := nor.swf_out
	_check(nor.swf_in > 0.0 and out0 > 0.0, "the Norwegian fund receives the oil revenue and pays the withdrawal")
	var draw := out0 / (nor.swf * nor.e)
	_check(absf(draw - nor.swf_limit) < 0.005, "withdrawal equal to the rule when revenue is at the average: %.2f%%" % (draw * 100.0))
	# Oil plunges: revenue falls below the average and the fund covers part of the fall.
	nor.rent_ref *= 2.0
	Economy._fiscal_flows(nor)
	_check(nor.swf_out > out0 * 1.2, "a fall in commodities increases the withdrawal: %.0f -> %.0f" % [out0, nor.swf_out])
	nor.rent_ref /= 2.0
	# The balance is a risk cushion.
	var risk_with := Economy._risk_premium(nor, world)
	var keep := nor.swf
	nor.swf = 0.0
	var risk_without := Economy._risk_premium(nor, world)
	nor.swf = keep
	_check(risk_with < risk_without, "a large fund reduces the risk premium: %.2f%% x %.2f%%" % [risk_with * 100.0, risk_without * 100.0])
	# Withdrawing too much takes away approval.
	nor.swf_limit = 0.03
	Economy._fiscal_flows(nor)
	Economy._fund_month(nor, world)
	_check(nor.swf_pain == 0.0, "a 3% withdrawal does not cost approval")
	nor.swf_limit = 0.12
	Economy._fiscal_flows(nor)
	Economy._fund_month(nor, world)
	_check(nor.swf_pain > 0.05, "a 12%% annual withdrawal takes away approval (%.1f pp)" % (nor.swf_pain * 100.0))
	# The fund invests abroad: keeping more revenue does not appreciate the currency.
	var es := []
	for share in [0.0, 1.0]:
		var w := GameWorld.new()
		w.setup(5)
		var n: Country = w.by_iso["NOR"]
		n.swf_rent_share = share
		Economy._fiscal_flows(n)
		w.rng.seed = 7
		for m in 3:
			Economy._float_exchange(n, w)
		es.append(n.e)
	_check(es[1] >= es[0] - 1e-9, "fund contributions do not appreciate the krone: %.4f x %.4f" % [es[0], es[1]])


## The fund is created by the Exchange Law; the withdrawal limit changes by law.
func _fund_law() -> void:
	var world := _fresh("BRA")
	var c := world.player
	var leg: Legislation = world.legislation
	_months(world, 1)
	_check(not leg.code_standing("cambial").is_empty(), "the Exchange Law applies from the start")
	_check(not c.swf_active, "Brazil has no fund in the starting law")
	var bill := leg.start_code_bill(world, "cambial")
	var stack: Dictionary = bill.program.stacks[0]
	var fund := LawProgram.new_block(bill.program, "fs_fundo")
	fund.fields.renda = 80.0
	fund.fields.superavit = 50.0
	stack.blocks.append(fund)
	var rule := LawProgram.new_block(bill.program, "fs_saque")
	rule.fields.limite = 3.0
	stack.blocks.append(rule)
	for b: Dictionary in _blocks_of(bill, "cb_controle"):
		b.fields.nivel = "imposto"
	_force_majority(world)
	var r := leg.present(world, bill)
	_check(r.ok, "fund project presented:" + str(r.get("msg", "")))
	_settle(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "the fund law takes effect:" + bill.state)
	_months(world, 2)
	_check(c.swf_active and is_equal_approx(c.swf_rent_share, 0.8) and is_equal_approx(c.swf_limit, 0.03), "the Brazilian fund exists with 80%% of the revenue and a 3%% withdrawal")
	_check(is_equal_approx(c.cap_controls, 0.35), "the tax on capital outflows applies: %.2f" % c.cap_controls)
	_months(world, 12)
	_check(c.swf > 1.0, "the fund accumulates with commodity revenue: US$ %.1f bn" % c.swf)
	_check(float(c.code_stats.get("fundo_soberano", -1.0)) == c.swf, "the code shows the fund balance")

	# Norway: raising the withdrawal to 10% by law takes away approval.
	var nw := _fresh("NOR")
	var nor := nw.player
	var nleg: Legislation = nw.legislation
	_months(nw, 1)
	_check(nor.swf_active and nor.swf_limit > 0.02, "Norway's starting law already has the fund and the rule")
	var change := nleg.start_code_bill(nw, "cambial")
	for b: Dictionary in _blocks_of(change, "fs_saque"):
		b.fields.limite = 10.0
	_force_majority(nw)
	nleg.present(nw, change)
	_settle(nw, change)
	_months(nw, 2)
	_check(is_equal_approx(nor.swf_limit, 0.10), "the withdrawal limit changes by law: %.1f%%" % (nor.swf_limit * 100.0))
	_check(nor.swf_pain > 0.05, "withdrawing 10%% a year weighs on approval (%.1f pp)" % (nor.swf_pain * 100.0))


## Ten years: reserves, exchange rate and funds finite and within plausible ranges.
func _long_run() -> void:
	var world := _fresh("BRA", 42)
	var start := {}
	for iso: String in ["NOR", "SAU", "CHN", "SGP", "BRA", "IND", "TUR", "ARG"]:
		var c: Country = world.by_iso[iso]
		start[iso] = [c.swf, c.reserves, c.e]
	_months(world, 120)
	var bad := 0
	for c: Country in world.countries:
		if not c.alive:
			continue
		for v: float in [c.e, c.reserves, c.swf, c.cap_flight, c.dollarization, c.fx_interv, c.uip_dep]:
			if is_nan(v) or is_inf(v):
				bad += 1
		if c.reserves < 0.0 or c.swf < 0.0:
			bad += 1
	_check(bad == 0, "no NaN, infinity or negative balance in 10 years (%d bad)" % bad)
	for iso: String in ["NOR", "SAU", "CHN", "SGP"]:
		var c: Country = world.by_iso[iso]
		var s0: float = start[iso][0]
		_check(c.swf > s0 * 0.6 and c.swf < s0 * 4.0, "%s: plausible fund over 10 years: %.0f -> %.0f" % [iso, s0, c.swf])
	for iso: String in ["BRA", "IND", "TUR", "ARG"]:
		var c: Country = world.by_iso[iso]
		var r0: float = start[iso][1]
		_check(c.reserves < r0 * 5.0 + 50.0, "%s: reserves without blowing up: %.0f -> %.0f" % [iso, r0, c.reserves])
