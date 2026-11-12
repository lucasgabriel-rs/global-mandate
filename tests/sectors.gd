extends SceneTree
## Setores da economia: composição de partida, fechamento no PIB, reação ao ciclo e aos choques,
## impulso setorial no potencial e salvar/carregar.
## Uso: godot --headless --path . --script tests/sectors.gd

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
	_check(bad == 0, "todo país tem os dez setores somando 100%% (%d fora)" % bad)
	_check(usa.sector_share[Sectors.AGRO] < 0.02, "agropecuária pesa pouco nos EUA: %.1f%%" % (usa.sector_share[Sectors.AGRO] * 100.0))
	_check(sau.sector_share[Sectors.MINING] > 0.2, "petróleo domina a Arábia Saudita: %.1f%%" % (sau.sector_share[Sectors.MINING] * 100.0))
	_check(usa.sector_share[Sectors.FINANCE] > bra.sector_share[Sectors.FINANCE], "finanças pesam mais nos EUA que no Brasil")
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
	_check(poor >= n_poor * 0.8 and rich >= n_rich * 0.8, "no modelo, o campo pesa nos pobres (%d/%d) e pouco nos ricos (%d/%d)" % [poor, n_poor, rich, n_rich])

	_months(world, 14)
	_check(absf(_sum(bra.sector_out) - bra.y) < bra.y * 0.001, "os setores fecham no PIB do mês")
	_check(bra.hist.has("sec_%d" % Sectors.CONSTRUCTION) and bra.hist["sec_%d" % Sectors.CONSTRUCTION].size() >= 13, "o país do jogador guarda a série de cada setor")
	var drift := 0.0
	for i in Sectors.COUNT:
		drift = maxf(drift, absf(bra.sector_share[i] - bra.sector_base[i]))
	_check(drift < 0.03, "sem choque, a composição fica perto da estrutural (desvio máximo %.1f pp)" % (drift * 100.0))

	# Juro alto: construção encolhe mais que o serviço público.
	var hike := _fresh()
	var hb: Country = hike.by_iso["BRA"]
	var base_c := hb.sector_share[Sectors.CONSTRUCTION]
	var base_p := hb.sector_share[Sectors.PUBLIC]
	for i in 8:
		hb.rgap = 0.07
		hb.gap = -0.04
		_months(hike, 1)
	_check(hb.sector_share[Sectors.CONSTRUCTION] / base_c < hb.sector_share[Sectors.PUBLIC] / base_p, "aperto monetário pesa mais na construção (%.3f vs %.3f)" % [hb.sector_share[Sectors.CONSTRUCTION] / base_c, hb.sector_share[Sectors.PUBLIC] / base_p])

	# Petróleo caro: a mineração saudita ganha peso.
	var oil := _fresh()
	var os: Country = oil.by_iso["SAU"]
	var m0 := os.sector_share[Sectors.MINING]
	for i in int(6 * 30.4167):
		oil.markets.price[Markets.OIL] = Markets.P0[Markets.OIL] * 1.8
		oil.tick_day()
	_check(os.sector_share[Sectors.MINING] > m0 * 1.04, "petróleo caro aumenta a mineração saudita (%.1f%% → %.1f%%)" % [m0 * 100.0, os.sector_share[Sectors.MINING] * 100.0])

	# Guerra derruba o turismo.
	var war := _fresh()
	var wb: Country = war.by_iso["BRA"]
	var t0 := wb.sector_share[Sectors.TOURISM]
	for i in 6:
		wb.unrest = 0.6
		_months(war, 1)
	_check(wb.sector_share[Sectors.TOURISM] < t0 * 0.92, "agitação social espanta o turismo (%.2f%% → %.2f%%)" % [t0 * 100.0, wb.sector_share[Sectors.TOURISM] * 100.0])

	# Impulso setorial eleva o potencial.
	var a := _fresh()
	var b := _fresh()
	var ca: Country = a.by_iso["BRA"]
	var cb: Country = b.by_iso["BRA"]
	cb.sector_boost[Sectors.TRANSPORT] = 0.2
	cb.sector_boost[Sectors.INDUSTRY] = 0.1
	_months(a, 3)
	_months(b, 3)
	_check(cb.y_pot > ca.y_pot * 1.01, "impulso em transporte e indústria eleva o PIB potencial (%.0f vs %.0f)" % [cb.y_pot, ca.y_pot])

	# Salvar e carregar.
	var d := world.to_dict()
	var again := GameWorld.new()
	again.load_dict(d)
	var rb: Country = again.by_iso["BRA"]
	_check(rb.sector_share.size() == Sectors.COUNT and absf(rb.sector_share[Sectors.AGRO] - bra.sector_share[Sectors.AGRO]) < 0.0001, "a composição sobrevive ao salvar e carregar")
	_months(again, 2)
	_check(absf(_sum(rb.sector_out) - rb.y) < rb.y * 0.001, "o jogo carregado continua fechando os setores")

	print("RESULT: %d failures" % failures)
	quit()
