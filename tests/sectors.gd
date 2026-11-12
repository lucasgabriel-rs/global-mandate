extends SceneTree
## Sectors of the economy: starting composition, closing on GDP, reaction to the cycle and to shocks,
## sector impulse on potential and saving/loading.
## Usage: godot --headless --path . --script tests/sectors.gd

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


func _months(world: GameWorld, n: int) -> void:
	for i in int(n * 30.4167):
		world.tick_day()


func _sum(v: PackedFloat32Array) -> float:
	var t := 0.0
	for x in v:
		t += x
	return t


func _init() -> void:
	var world := _fresh()
	var bra: Country = world.by_iso["BRA"]
	var usa: Country = world.by_iso["USA"]
	var sau: Country = world.by_iso["SAU"]
	var bad := 0
	for c: Country in world.countries:
		if c.sector_share.size() != Sectors.COUNT or absf(_sum(c.sector_share) - 1.0) > 0.001:
			bad += 1
	_check(bad == 0, "every country has the ten sectors adding to 100%% (%d off)" % bad)
	_check(usa.sector_share[Sectors.AGRO] < 0.02, "agriculture weighs little in the USA: %.1f%%" % (usa.sector_share[Sectors.AGRO] * 100.0))
	_check(sau.sector_share[Sectors.MINING] > 0.2, "oil dominates Saudi Arabia: %.1f%%" % (sau.sector_share[Sectors.MINING] * 100.0))
	_check(usa.sector_share[Sectors.FINANCE] > bra.sector_share[Sectors.FINANCE], "finance weighs more in the USA than in Brazil")
	var poor := 0
	var rich := 0
	var n_poor := 0
	var n_rich := 0
	for c: Country in world.countries:
		if Sectors.CALIBRATION.has(c.iso):
			continue
		if c.gdp_pc() < 3000.0:
			poor += int(c.sector_share[Sectors.AGRO] > 0.15)
			n_poor += 1
		elif c.gdp_pc() > 40000.0:
			rich += int(c.sector_share[Sectors.AGRO] < 0.06)
			n_rich += 1
	_check(poor >= n_poor * 0.8 and rich >= n_rich * 0.8, "in the model, agriculture weighs on the poor (%d/%d) and little on the rich (%d/%d)" % [poor, n_poor, rich, n_rich])

	_months(world, 14)
	_check(absf(_sum(bra.sector_out) - bra.y) < bra.y * 0.001, "sectors add up to the month's GDP")
	_check(bra.hist.has("sec_%d" % Sectors.CONSTRUCTION) and bra.hist["sec_%d" % Sectors.CONSTRUCTION].size() >= 13, "the player's country keeps the series of each sector")
	var drift := 0.0
	for i in Sectors.COUNT:
		drift = maxf(drift, absf(bra.sector_share[i] - bra.sector_base[i]))
	_check(drift < 0.03, "with no shock, the composition stays near the structural one (maximum deviation %.1f pp)" % (drift * 100.0))

	# High interest: construction shrinks more than public service.
	var hike := _fresh()
	var hb: Country = hike.by_iso["BRA"]
	var base_c := hb.sector_share[Sectors.CONSTRUCTION]
	var base_p := hb.sector_share[Sectors.PUBLIC]
	for i in 8:
		hb.rgap = 0.07
		hb.gap = -0.04
		_months(hike, 1)
	_check(hb.sector_share[Sectors.CONSTRUCTION] / base_c < hb.sector_share[Sectors.PUBLIC] / base_p, "monetary tightening weighs more on construction (%.3f vs %.3f)" % [hb.sector_share[Sectors.CONSTRUCTION] / base_c, hb.sector_share[Sectors.PUBLIC] / base_p])

	# Expensive oil: Saudi mining gains weight.
	var oil := _fresh()
	var os: Country = oil.by_iso["SAU"]
	var m0 := os.sector_share[Sectors.MINING]
	for i in int(6 * 30.4167):
		oil.markets.price[Markets.OIL] = Markets.P0[Markets.OIL] * 1.8
		oil.tick_day()
	_check(os.sector_share[Sectors.MINING] > m0 * 1.04, "expensive oil increases Saudi mining (%.1f%% → %.1f%%)" % [m0 * 100.0, os.sector_share[Sectors.MINING] * 100.0])

	# War brings down tourism.
	var war := _fresh()
	var wb: Country = war.by_iso["BRA"]
	var t0 := wb.sector_share[Sectors.TOURISM]
	for i in 6:
		wb.unrest = 0.6
		_months(war, 1)
	_check(wb.sector_share[Sectors.TOURISM] < t0 * 0.92, "social unrest scares off tourism (%.2f%% → %.2f%%)" % [t0 * 100.0, wb.sector_share[Sectors.TOURISM] * 100.0])

	# Impulso setorial eleva o potencial.
	var a := _fresh()
	var b := _fresh()
	var ca: Country = a.by_iso["BRA"]
	var cb: Country = b.by_iso["BRA"]
	cb.sector_boost[Sectors.TRANSPORT] = 0.2
	cb.sector_boost[Sectors.INDUSTRY] = 0.1
	_months(a, 3)
	_months(b, 3)
	_check(cb.y_pot > ca.y_pot * 1.01, "an impulse in transport and industry raises potential GDP (%.0f vs %.0f)" % [cb.y_pot, ca.y_pot])

	# Salvar e carregar.
	var d := world.to_dict()
	var again := GameWorld.new()
	again.load_dict(d)
	var rb: Country = again.by_iso["BRA"]
	_check(rb.sector_share.size() == Sectors.COUNT and absf(rb.sector_share[Sectors.AGRO] - bra.sector_share[Sectors.AGRO]) < 0.0001, "the composition survives saving and loading")
	_months(again, 2)
	_check(absf(_sum(rb.sector_out) - rb.y) < rb.y * 0.001, "the loaded game keeps closing the sectors")

	print("RESULT: %d failures" % failures)
	quit()
