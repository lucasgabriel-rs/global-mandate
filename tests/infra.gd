extends SceneTree
## Portos e aeroportos: dados, demanda, saturação, guerra, obras, concessões e salvar/carregar, sem interface.
## Uso: godot --headless --path . --script tests/infra.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _world(iso := "BRA", seed_value := 11) -> GameWorld:
	var w := GameWorld.new()
	w.setup(seed_value)
	w.leader = Character.random(w.rng)
	w.set_player(w.by_iso[iso], "normal")
	return w


func _months(w: GameWorld, n: int) -> void:
	for i in n:
		var m := w.months_elapsed
		while w.months_elapsed == m:
			w.tick_day()
		w.flush_events()


func _of(w: GameWorld, iso: String, kind := "") -> Array:
	return w.infra.facilities_of(w.by_iso[iso], w).filter(func(f): return kind == "" or f.kind == kind)


func _named(w: GameWorld, iso: String, part: String) -> Dictionary:
	for f: Dictionary in _of(w, iso):
		if String(f.name).contains(part):
			return f
	return {}


func _init() -> void:
	_data()
	_neutral_start()
	_saturation()
	_war()
	_build()
	_concession()
	_ai()
	_save()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)


func _data() -> void:
	var w := _world()
	var inf := w.infra
	_check(_of(w, "USA", "port").size() >= 8 and _of(w, "USA", "air").size() >= 8, "os EUA têm vários portos e aeroportos")
	_check(_of(w, "CHN", "port").size() >= 8 and _of(w, "CHN", "air").size() >= 8, "a China também")
	for part in ["Santos", "Paranaguá", "Itaguaí", "Guarulhos", "Galeão", "Brasília"]:
		_check(not _named(w, "BRA", part).is_empty(), "o Brasil tem %s" % part)
	_check(_of(w, "CHE", "port").is_empty() and _of(w, "BOL", "port").is_empty(), "Suíça e Bolívia não têm porto marítimo")
	# Fora do arquivo: gerado pela economia, com aeroporto e sem porto (sem litoral).
	var tcd := _of(w, "TCD")
	_check(tcd.size() == 1 and tcd[0].kind == "air" and float(tcd[0].cap) > 0.0, "o Chade recebe um aeroporto gerado: %s" % str(tcd.map(func(f): return f.name)))
	_check(_of(w, "PSE").is_empty(), "lista vazia no arquivo = nenhuma instalação")
	var gru := _named(w, "BRA", "Guarulhos")
	_check(gru.owner == "concession" and is_equal_approx(float(gru.lat), -23.43), "Guarulhos: concessão, com coordenadas")
	var total := 0
	for c: Country in w.countries:
		if not w.infra.facilities_of(c, w).is_empty():
			total += 1
	_check(total >= w.countries.size() - 2, "quase todo país tem alguma instalação (%d de %d)" % [total, w.countries.size()])
	_check(inf.saturation(w.by_iso["CHE"], "port") < 0.0, "sem porto, a saturação de porto não existe")


func _neutral_start() -> void:
	var w := _world()
	var ok := true
	for c: Country in w.countries:
		if absf(c.logistics - 1.0) > 0.001:
			ok = false
	_check(ok, "no início, a logística é neutra em todo país")
	_months(w, 2)
	var bra: Country = w.by_iso["BRA"]
	_check(absf(bra.logistics - 1.0) < 0.05, "dois meses depois, ainda perto de neutra: %.3f" % bra.logistics)
	var s := w.infra.saturation(bra, "port")
	_check(s > 0.5 and s < 1.1, "a saturação dos portos brasileiros é plausível: %.2f" % s)


func _saturation() -> void:
	var w := _world()
	var bra: Country = w.by_iso["BRA"]
	var inf := w.infra
	_months(w, 1)
	var boost0 := bra.sector_boost[Sectors.TRANSPORT]
	var other0 := bra.sector_boost[Sectors.FINANCE]
	# O comércio dobra: os portos lotam, a logística piora e o transporte perde.
	inf.base_trade[bra.idx] *= 0.5
	inf.base_gdp[bra.idx] *= 0.7
	inf.step_month(w)
	_check(inf.saturation(bra, "port") > 1.2, "com o dobro de comércio, os portos passam da capacidade: %.2f" % inf.saturation(bra, "port"))
	_check(bra.logistics < 0.9, "a logística cai: %.3f" % bra.logistics)
	_check(bra.sector_boost[Sectors.TRANSPORT] < boost0 - 0.02, "o transporte perde produtividade: %.3f" % bra.sector_boost[Sectors.TRANSPORT])
	_check(bra.sector_boost[Sectors.TOURISM] < 0.0, "o turismo também, com aeroportos cheios")
	_check(is_equal_approx(bra.sector_boost[Sectors.FINANCE], other0), "o impulso de outros setores fica intocado")
	var santos := _named(w, "BRA", "Santos")
	_check(float(santos.util) >= 0.99, "Santos opera no limite: %d%%" % int(float(santos.util) * 100.0))
	# Outro sistema somou no transporte: o nosso efeito é trocado sem apagar o dele.
	bra.sector_boost[Sectors.TRANSPORT] += 0.01
	var before := bra.sector_boost[Sectors.TRANSPORT]
	inf.step_month(w)
	_check(absf(bra.sector_boost[Sectors.TRANSPORT] - before) < 0.01, "a soma de outro sistema sobrevive à etapa seguinte")


func _war() -> void:
	var w := _world()
	var bra: Country = w.by_iso["BRA"]
	var inf := w.infra
	_months(w, 1)
	var s0 := inf.saturation(bra, "port")
	bra.occupied = bra.occ0 + 1.0
	var news := []
	w.news_posted.connect(func(t, _k, _c): news.append(t))
	inf.step_month(w)
	w.flush_events()
	var closed := _of(w, "BRA").filter(func(f): return f.closed).size()
	_check(closed == _of(w, "BRA").size(), "com o país todo ocupado, tudo fecha (%d)" % closed)
	_check(inf.saturation(bra, "port") >= 2.0 and bra.logistics < 0.8, "sem portos, o comércio trava: logística %.2f" % bra.logistics)
	_check(news.any(func(t): return String(t).contains("fecha")), "o fechamento vira notícia")
	bra.occupied = bra.occ0
	inf.step_month(w)
	_check(_of(w, "BRA").all(func(f): return not f.closed), "desocupado, tudo reabre")
	_check(absf(inf.saturation(bra, "port") - s0) < 0.15, "e a saturação volta ao normal")
	# Dano de guerra: capacidade menor, reparo aos poucos.
	var santos := _named(w, "BRA", "Santos")
	santos.cond = 0.5
	inf._rebuild_index(w)
	var spend0 := bra.extra_spend_bucket
	inf.step_month(w)
	_check(float(santos.cond) > 0.5 and float(santos.cond) < 1.0, "fora da guerra, o porto se repara aos poucos: %.2f" % float(santos.cond))
	_check(bra.extra_spend_bucket > spend0, "e o Estado paga o reparo")


func _build() -> void:
	var w := _world()
	var bra: Country = w.by_iso["BRA"]
	var inf := w.infra
	var santos := _named(w, "BRA", "Santos")
	var cap0 := float(santos.cap)
	var q := inf.expansion_quote(santos, bra, 0.5)
	_check(float(q.cost) > 0.5 and float(q.cost) < 10.0 and int(q.months) >= 24, "ampliar Santos em 50%%: US$ %.1f bi, %d meses" % [q.cost, q.months])
	var r := inf.start_expansion(w, bra, int(santos.id), 0.5)
	_check(r.ok, "a ampliação começa: " + r.msg)
	_check(not inf.start_expansion(w, bra, int(santos.id), 0.5).ok, "não dá para abrir duas obras no mesmo porto")
	_check(not inf.start_expansion(w, bra, int(_named(w, "BRA", "Guarulhos").id), 0.5).ok, "concessão não é ampliada pelo governo")
	var near := _named(w, "BRA", "Brasília")
	var r2 := inf.start_new(w, bra, "air", int(near.id), 1)
	_check(r2.ok, "um aeroporto novo começa: " + r2.msg)
	_check(not inf.start_new(w, w.by_iso["CHE"], "port", int(_of(w, "CHE")[0].id), 0).ok, "a Suíça não constrói porto")
	_check(inf.projects_of(bra).size() == 2, "o país tem duas obras")
	var spent := 0.0
	var news := []
	w.news_posted.connect(func(t, _k, _c): news.append(t))
	for i in 70:
		bra.extra_spend_bucket = 0.0
		inf.step_month(w)
		spent += bra.extra_spend_bucket
	w.flush_events()
	_check(is_equal_approx(float(santos.cap), cap0 * 1.5), "Santos ganha 50%% de capacidade: %.2f" % float(santos.cap))
	_check(spent > float(q.cost) * 0.99, "o custo sai mês a mês pelo Tesouro: US$ %.1f bi" % spent)
	_check(not _named(w, "BRA", "Novo aeroporto de Brasília").is_empty(), "o aeroporto novo entra em operação")
	_check(news.any(func(t): return String(t).contains("Concluída a ampliação")) and news.any(func(t): return String(t).begins_with("Inaugurado")), "as conclusões viram notícia")
	_check(inf.projects_of(bra).filter(func(p): return p.public).is_empty(), "as obras públicas saem da lista")


func _concession() -> void:
	var w := _world()
	var bra: Country = w.by_iso["BRA"]
	var inf := w.infra
	_months(w, 1)
	var sd := _named(w, "BRA", "Santos Dumont")
	var value := inf.concession_value(sd, bra)
	var rev0 := bra.extra_rev_bucket
	var r := inf.concede(w, bra, int(sd.id))
	_check(r.ok and sd.owner == "concession", "Santos Dumont é concedido: " + r.msg)
	_check(is_equal_approx(bra.extra_rev_bucket - rev0, value) and value > 0.2, "a receita única entra no Tesouro: US$ %.2f bi" % value)
	_check(not inf.concede(w, bra, int(sd.id)).ok, "não se concede duas vezes")
	_check(not inf.concede(w, bra, int(_named(w, "BRA", "Tubarão").id)).ok, "ativo privado não se concede")


func _ai() -> void:
	var w := _world()
	var inf := w.infra
	# Todos os países com o dobro do comércio: a IA reage com obras, o jogador não.
	for c: Country in w.countries:
		inf.base_trade[c.idx] *= 0.45
	for i in 12:
		inf.step_month(w)
	var builders := {}
	for p: Dictionary in inf.projects:
		if p.public and p.kind == "port":
			builders[int(p.payer)] = true
	_check(builders.size() >= 20, "países saturados da IA investem em portos: %d" % builders.size())
	_check(not builders.has(w.player.idx), "o país do jogador não ganha obras públicas sozinho")
	_check(inf.projects.any(func(p): return not p.public), "operadoras privadas também ampliam")


func _save() -> void:
	var w := _world()
	var bra: Country = w.by_iso["BRA"]
	_months(w, 2)
	w.infra.start_expansion(w, bra, int(_named(w, "BRA", "Santos").id), 0.25)
	w.infra.concede(w, bra, int(_named(w, "BRA", "Santos Dumont").id))
	var back := GameWorld.new()
	back.load_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	var b2: Country = back.by_iso["BRA"]
	_check(back.infra.facilities.size() == w.infra.facilities.size(), "as instalações voltam do save")
	_check(back.infra.projects_of(b2).size() == w.infra.projects_of(bra).size(), "as obras também")
	_check(_named(back, "BRA", "Santos Dumont").owner == "concession", "e a concessão")
	_check(is_equal_approx(back.infra.saturation(b2, "port"), w.infra.saturation(bra, "port")), "a saturação é a mesma")
	w.infra.step_month(w)
	back.infra.step_month(back)
	_check(is_equal_approx(b2.logistics, bra.logistics), "e a simulação continua igual depois de carregar")
