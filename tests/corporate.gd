extends SceneTree
## Empresas e bolsa: dados, receita pelo setor, juro, índice, crise bancária, quebras, dividendos de estatais,
## privatização e estatização por lei, IPOs, campeãs nacionais, salvar e carregar, e custo de CPU.
## Uso: godot --headless --path . --script tests/corporate.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _fresh(iso := "BRA") -> GameWorld:
	var world := GameWorld.new()
	world.setup(11)
	world.leader = Character.random(world.rng)
	world.set_player(world.by_iso[iso], "normal")
	return world


func _majority(world: GameWorld) -> void:
	var data: Dictionary = world.politics.data_of(world.player.iso)
	data.coalition = data.parties.map(func(p): return p.id)
	for p: Dictionary in data.parties:
		p.econ = 0.0
		p.social = 0.0


func _settle(world: GameWorld, norm: Dictionary) -> void:
	for i in 300:
		world.player.next_election = 9999.0
		world.player.approval = 0.6
		world.player.stability = 0.6
		world.leader.erase("illness")
		world.leader["birth_year"] = world.year - 40
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


func _norm(world: GameWorld, type: String, fields: Dictionary) -> Dictionary:
	var norm: Dictionary = world.legislation.new_norm(world, "ordinaria")
	norm.title = type
	norm.ementa = "Teste"
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2.ZERO)
	var block := LawProgram.new_block(program, type)
	for key: String in fields:
		block.fields[key] = fields[key]
	stack.blocks.append(block)
	norm.program = program
	return norm


func _co(world: GameWorld, iso: String, name_: String) -> Dictionary:
	return Corporate.find(world.corporate.market_of(iso), name_)


func _init() -> void:
	var world := _fresh()
	_data(world)
	_revenue_and_rates(world)
	_index(world)
	_crisis(_fresh())
	_failure(_fresh())
	_dividends(_fresh())
	_laws(_fresh())
	_champion(_fresh())
	_time_and_save()
	print("RESULTADO: %d falhas" % failures)
	quit()


func _data(world: GameWorld) -> void:
	var bra: Array = world.corporate.companies_of("BRA")
	_check(bra.size() >= 10, "o Brasil tem %d empresas" % bra.size())
	var petro := _co(world, "BRA", "Petrobras")
	_check(not petro.is_empty() and petro.listed and Corporate.control_of(petro) == "Mista", "Petrobras é mista e listada")
	var odebrecht := _co(world, "BRA", "Odebrecht (Novonor)")
	_check(not odebrecht.is_empty() and not odebrecht.listed and Corporate.control_of(odebrecht) == "Privada", "Odebrecht é privada e fechada")
	_check(Corporate.control_of(_co(world, "BRA", "Caixa Econômica Federal")) == "Estatal", "Caixa é estatal")
	for iso: String in ["USA", "CHN", "JPN", "DEU", "IND"]:
		_check(world.corporate.companies_of(iso).size() >= 10, "%s tem 10 ou mais empresas" % iso)
	var ids := {}
	var dup := false
	var empty := 0
	for c: Country in world.countries:
		var names := {}
		var list: Array = world.corporate.companies_of(c.iso)
		if list.is_empty():
			empty += 1
		for co: Dictionary in list:
			dup = dup or ids.has(co.id) or names.has(co.name)
			ids[co.id] = true
			names[co.name] = true
	_check(empty == 0, "todo país tem empresas (sem dado: geradas pelos setores); vazios: %d" % empty)
	_check(not dup, "ids únicos e nomes únicos dentro de cada país")
	var ken: Array = world.corporate.companies_of("KEN")
	_check(ken.size() >= 2 and ken.size() <= 8, "o Quênia ganhou %d empresas geradas" % ken.size())
	_check(is_equal_approx(world.by_iso["USA"].stock, 100.0), "o índice começa em 100")
	_check(absf(float(world.corporate.market_of("USA").cap) - 55000.0) < 1.0, "valor de mercado dos EUA bate com o dado")
	_check(absf(float(petro.value) - 90.0) < 0.5, "o valor da Petrobras bate com o dado: %.1f" % float(petro.value))


func _revenue_and_rates(world: GameWorld) -> void:
	var c: Country = world.by_iso["BRA"]
	var weg := _co(world, "BRA", "WEG")
	var rev0 := float(weg.rev)
	var saved := c.sector_share.duplicate()
	c.sector_share[Sectors.INDUSTRY] *= 1.5
	Corporate.update_index(c, world, c.g0)
	_check(float(weg.rev) / rev0 > 1.4 and float(weg.rev) / rev0 < 1.6, "a receita segue o produto do setor: x%.2f" % (float(weg.rev) / rev0))
	c.sector_share = saved
	# Juro real cinco pontos acima: margem da construção cai e o valor da bolsa encolhe.
	var cap0 := 0.0
	for co: Dictionary in world.corporate.companies_of("BRA"):
		cap0 += float(co.value)
	var build := _co(world, "BRA", "Odebrecht (Novonor)")
	var margin0 := float(build.profit) / float(build.rev)
	c.rate += 0.05
	Corporate.update_index(c, world, c.g0)
	var cap1 := 0.0
	for co: Dictionary in world.corporate.companies_of("BRA"):
		cap1 += float(co.value)
	_check(float(build.profit) / float(build.rev) < margin0 - 0.02, "o juro aperta a margem da construção: %.3f -> %.3f" % [margin0, float(build.profit) / float(build.rev)])
	_check(cap1 < cap0 * 0.9, "o juro derruba o valor das empresas: %.0f -> %.0f" % [cap0, cap1])
	c.rate -= 0.05


func _index(world: GameWorld) -> void:
	var c: Country = world.by_iso["DEU"]
	var m: Dictionary = world.corporate.market_of("DEU")
	var before := 0.0
	for co: Dictionary in m.list:
		if co.listed:
			before += float(co.local)
	before += float(m.rest) * c.e
	var count: int = m.list.size()
	var s0 := c.stock
	Corporate.update_index(c, world, c.growth_yoy())
	var after := 0.0
	for co: Dictionary in m.list:
		if co.listed:
			after += float(co.local)
	after += float(m.rest) * c.e
	if m.list.size() == count:
		_check(absf(c.stock / s0 - after / before) < 0.001, "o índice segue o valor de mercado das listadas: %.4f vs %.4f" % [c.stock / s0, after / before])
	var big := Corporate.find(m, "SAP")
	_check(Corporate.price_of(big) > 0.0 and Corporate.pe_of(big) > 5.0, "ação tem preço e P/L")


func _crisis(world: GameWorld) -> void:
	var c: Country = world.player
	var news := []
	world.news_posted.connect(func(t, _k, _c): news.append(t))
	Corporate.update_index(c, world, c.g0)
	var s0 := c.stock
	Economy.banking_crisis(c, world)
	Corporate.update_index(c, world, c.g0)
	_check(c.stock < s0 * 0.92, "crise bancária derruba a bolsa: %.1f -> %.1f" % [s0, c.stock])
	_check(news.any(func(t): return String(t).contains("despenca")), "a queda vira notícia")


func _failure(world: GameWorld) -> void:
	var c: Country = world.player
	var news := []
	world.news_posted.connect(func(t, _k, _c): news.append(t))
	var victim := _co(world, "BRA", "Magazine Luiza")
	var mood0 := float(world.corporate.market_of("BRA").mood)
	var gone := false
	for i in 60:
		victim.distress = 5.0
		victim.mb = -0.2
		Corporate.update_index(c, world, c.g0)
		if _co(world, "BRA", "Magazine Luiza").is_empty():
			gone = true
			break
	_check(gone, "empresa privada em dificuldade quebra e sai do mercado")
	_check(news.any(func(t): return String(t).contains("Magazine Luiza quebra")), "a quebra vira notícia")
	_check(world.corporate.market_of("BRA").events.any(func(e): return e.kind == "falencia"), "a quebra fica no histórico da bolsa")
	# Estatal não quebra: o Tesouro socorre.
	var caixa := _co(world, "BRA", "Caixa Econômica Federal")
	c.extra_spend_bucket = 0.0
	for i in 60:
		caixa.distress = 5.0
		Corporate.update_index(c, world, c.g0)
		if float(caixa.distress) < 1.0:
			break
	_check(not _co(world, "BRA", "Caixa Econômica Federal").is_empty() and c.extra_spend_bucket > 0.0, "estatal em crise é socorrida pelo Tesouro")
	_check(mood0 != float(world.corporate.market_of("BRA").mood), "o humor do mercado mudou")


func _dividends(world: GameWorld) -> void:
	var c: Country = world.player
	c.extra_rev_bucket = 0.0
	Corporate.update_index(c, world, c.g0)
	var base := c.extra_rev_bucket
	_check(absf(base) < c.y_usd() * 0.002, "no começo os dividendos já estão na receita-base: %.2f" % base)
	var spend0 := c.extra_spend_bucket
	world.corporate.nationalize(world, c, "Vale", 1.0)
	_check(c.extra_spend_bucket > spend0 + 30.0, "estatizar custa ao Tesouro: %.1f" % (c.extra_spend_bucket - spend0))
	_check(not _co(world, "BRA", "Vale").listed, "estatizada por inteiro, a Vale sai da bolsa")
	c.extra_rev_bucket = 0.0
	Corporate.update_index(c, world, c.g0)
	_check(c.extra_rev_bucket > base + 0.1, "a estatal paga dividendos ao Tesouro: %.2f por mês" % c.extra_rev_bucket)
	var rev0 := c.extra_rev_bucket
	var value := float(_co(world, "BRA", "Vale").value)
	world.corporate.privatize(world, c, "Vale", 1.0)
	var gain := c.extra_rev_bucket - rev0
	_check(gain > value * 0.85 and _co(world, "BRA", "Vale").listed, "privatizar rende receita única (%.1f de %.1f) e reabre o capital" % [gain, value])


func _laws(world: GameWorld) -> void:
	_majority(world)
	var leg := world.legislation
	var bad: Dictionary = _norm(world, "ec_privatize", {"company": "Itaú Unibanco", "stake": 50})
	_check(not leg.compile_norm(bad).ok, "não se privatiza o que o Estado não tem")
	leg.delete_draft(int(bad.id))
	var ghost: Dictionary = _norm(world, "ec_nationalize", {"company": "Empresa Fantasma", "stake": 100})
	_check(not leg.compile_norm(ghost).ok, "não se estatiza empresa inexistente")
	leg.delete_draft(int(ghost.id))
	var bb := _co(world, "BRA", "Banco do Brasil")
	var sale: Dictionary = _norm(world, "ec_privatize", {"company": "Banco do Brasil", "stake": 50})
	_check(leg.compile_norm(sale).ok, "privatização compila: %s" % str(leg.compile_norm(sale).errors))
	leg.present(world, sale)
	_settle(world, sale)
	_check(sale.state == Legislation.STATE_IN_FORCE, "o parlamento aprova a privatização: " + sale.state)
	_check(absf(float(bb.state) - 0.25) < 0.01, "o Estado fica com 25%% do Banco do Brasil: %.2f" % float(bb.state))
	_check(world.corporate.market_of("BRA").events.any(func(e): return e.kind == "privatizacao"), "a privatização fica no histórico")
	var embraer := _co(world, "BRA", "Embraer")
	var take: Dictionary = _norm(world, "ec_nationalize", {"company": "Embraer", "stake": 100})
	_check(leg.compile_norm(take).ok, "estatização compila")
	leg.present(world, take)
	_settle(world, take)
	_check(take.state == Legislation.STATE_IN_FORCE and float(embraer.state) > 0.99 and not embraer.listed, "a lei estatiza a Embraer: " + take.state)


func _champion(world: GameWorld) -> void:
	var c: Country = world.by_iso["KOR"]
	var boost0 := c.sector_boost[Sectors.TECH]
	for co: Dictionary in world.corporate.companies_of("KOR"):
		if int(co.sector) == Sectors.TECH:
			co.k = float(co.k) * 1.5
	Corporate.update_index(c, world, c.g0)
	_check(c.sector_boost[Sectors.TECH] > boost0 + 0.01, "campeãs de tecnologia mais fortes puxam o setor: %.3f" % c.sector_boost[Sectors.TECH])


func _time_and_save() -> void:
	var world := _fresh()
	var t0 := Time.get_ticks_msec()
	for i in 365:
		world.tick_day()
	var ms := Time.get_ticks_msec() - t0
	print("  um ano de jogo: %d ms" % ms)
	for i in 365 * 4:
		world.tick_day()
	var counts := {}
	for iso: String in world.corporate.markets:
		for e: Dictionary in world.corporate.markets[iso].events:
			counts[e.kind] = int(counts.get(e.kind, 0)) + 1
	print("  em cinco anos: ", counts)
	_check(int(counts.get("ipo", 0)) > 0, "empresas abrem o capital com o tempo")
	_check(int(counts.get("fechamento", 0)) > 0, "empresas fecham o capital com o tempo")
	_check(int(counts.get("nova", 0)) > 0, "empresas nascem")
	for iso: String in ["USA", "BRA", "CHN", "JPN", "DEU"]:
		var s: float = world.by_iso[iso].stock
		_check(s > 30.0 and s < 600.0, "índice de %s em escala sensata depois de cinco anos: %.0f" % [iso, s])
	var bytes := var_to_bytes(world.to_dict())
	var loaded := GameWorld.new()
	loaded.setup(11)
	loaded.load_dict(bytes_to_var(bytes))
	var a: Array = world.corporate.companies_of("BRA")
	var b: Array = loaded.corporate.companies_of("BRA")
	_check(a.size() == b.size() and a[0].name == b[0].name and is_equal_approx(float(a[0].value), float(b[0].value)), "salvar e carregar preserva as empresas")
	_check(is_equal_approx(world.by_iso["BRA"].stock, loaded.by_iso["BRA"].stock), "e o índice")
	for i in 40:
		loaded.tick_day()
	_check(loaded.corporate.companies_of("BRA").size() > 0, "o mundo carregado segue rodando")
