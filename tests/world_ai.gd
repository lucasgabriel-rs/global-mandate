extends SceneTree
## O mundo se mexe sozinho: governos agem conforme a bússola do líder, parlamentos livres votam projetos e
## a economia continua sã. Imprime o que aconteceu em anos de jogo, sem o jogador fazer nada.
## Uso: godot --headless --path . --script tests/world_ai.gd -- [anos] [semente]

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 5
	var seed_value := int(args[1]) if args.size() > 1 else 42
	_compass_changes_behavior()
	_run(years, seed_value)
	print("RESULT: %d failures" % failures)
	quit()


func _force_leader(world: GameWorld, iso: String, econ: float, social: float) -> void:
	var leader: Dictionary = world.politics.leader_of(iso)
	leader.econ = econ
	leader.social = social


## O mesmo país, com líderes opostos, toma caminhos diferentes.
func _compass_changes_behavior() -> void:
	var results := {}
	for label: String in ["esquerda", "direita"]:
		var world := GameWorld.new()
		world.setup(11)
		var c: Country = world.by_iso["DEU"]
		_force_leader(world, "DEU", -0.9 if label == "esquerda" else 0.9, 0.0)
		var social0 := c.sp_social
		for i in 24:
			NationAI._ideology_drift(c, NationAI._mind(c, world))
		results[label] = c.sp_social - social0
	_check(float(results.esquerda) > float(results.direita), "líder de esquerda gasta mais com o social que o de direita")
	var world := GameWorld.new()
	world.setup(11)
	var c: Country = world.by_iso["DEU"]
	_force_leader(world, "DEU", 0.0, -0.9)
	var hawk: float = NationAI._mind(c, world).hawk
	_force_leader(world, "DEU", 0.0, 0.9)
	_check(hawk > float(NationAI._mind(c, world).hawk), "líder autoritário é mais belicoso que o libertário")


func _run(years: int, seed_value: int) -> void:
	var world := GameWorld.new()
	world.setup(seed_value)
	world.set_player(world.by_iso["BRA"], "normal")
	world.leader = Character.random(world.rng)
	var news := []
	var kinds := {}
	world.news_posted.connect(func(text, kind, _c):
		news.append(text)
		kinds[kind] = int(kinds.get(kind, 0)) + 1)
	var wars0: int = world.diplomacy.wars.size()
	var sanctions0: int = world.diplomacy.sanctions.size()
	var alliances0: int = world.diplomacy.alliances.size()
	var fta0: int = world.diplomacy.fta.size()
	var war_news := 0
	world.prompt_requested.connect(func(_p): pass)
	var t0 := Time.get_ticks_msec()
	for y in years:
		for d in 365:
			world.player.next_election = 9999.0
			world.player.approval = 0.5
			world.player.stability = 0.6
			world.tick_day()
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0
	for text: String in news:
		if text.contains("guerra") or text.contains("Guerra") or text.contains("invade") or text.contains("ataca"):
			war_news += 1
	print("em %d anos (%.1f s de cálculo): %d notícias, %s" % [years, seconds, news.size(), str(kinds)])
	print("sanções %d -> %d, alianças %d -> %d, livre comércio %d -> %d, guerras %d -> %d, notícias de guerra %d" % [sanctions0, world.diplomacy.sanctions.size(), alliances0, world.diplomacy.alliances.size(), fta0, world.diplomacy.fta.size(), wars0, world.diplomacy.wars.size(), war_news])
	var passed := 0
	var rejected := 0
	var closed_with_laws := 0
	for c: Country in world.countries:
		var data: Dictionary = world.politics.data_of(c.iso)
		var laws: Array = data.get("recent_laws", [])
		for law: Dictionary in laws:
			if law.passed:
				passed += 1
			else:
				rejected += 1
		if c.dem < Politics.FREE_PARLIAMENT_DEM and (not laws.is_empty() or data.has("pending_bill")):
			closed_with_laws += 1
	print("parlamentos: %d aprovados e %d rejeitados nas listas recentes" % [passed, rejected])
	var player_bills: Array = world.legislation.norms.values().filter(func(n): return not n.get("by_player", false) and not n.get("base_code", false) and n.type != "constituicao")
	print("projetos da IA no parlamento do jogador: %d" % player_bills.size())
	for line: String in news.slice(maxi(news.size() - 12, 0)):
		print("  · ", line)
	_check(news.size() > years * 12, "o noticiário tem mais de uma notícia por mês: %d" % news.size())
	_check(world.diplomacy.sanctions.size() != sanctions0 or world.diplomacy.alliances.size() != alliances0, "as relações entre países mudam")
	_check(world.diplomacy.fta.size() > fta0, "países fecham acordos sozinhos")
	_check(passed > 20, "parlamentos aprovam leis: %d" % passed)
	_check(rejected > 0, "parlamentos também rejeitam")
	_check(closed_with_laws == 0, "regimes fechados não têm propostas do parlamento")
	_check(player_bills.size() >= 3, "partidos propõem projetos no parlamento do jogador")
	# Economia sã, mesmo com tudo isso.
	var bad := []
	var living := 0
	for c: Country in world.countries:
		if not c.alive:
			continue
		living += 1
		for value: float in [c.y, c.pi_yoy, c.debt_ratio, c.approval, c.tax_total(), c.spend_total()]:
			if is_nan(value) or is_inf(value):
				bad.append(c.iso)
		if c.tax_total() > 0.75 or c.spend_total() > 0.85 or c.debt_ratio > 6.0:
			bad.append("%s imposto %.2f gasto %.2f dívida %.2f" % [c.iso, c.tax_total(), c.spend_total(), c.debt_ratio])
	print("países vivos: ", living)
	_check(bad.size() <= 3, "economias sem valores absurdos: %s" % str(bad.slice(0, 6)))
	_check(living > 120, "o mundo não se destrói: %d países" % living)
