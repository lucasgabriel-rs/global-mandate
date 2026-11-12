extends SceneTree
## Tests of the day clock and of the absence of random events, without the interface.
## Uso: godot --headless --path . -s tests/clock.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	var w := GameWorld.new()
	w.setup(11)
	w.set_player(w.by_iso["BRA"], "normal")
	_check(w.date_string() == "01 Jan 2025", "date without hour:" + w.date_string())
	w.tick_day()
	_check(w.date_string() == "02 Jan 2025" and w.day_index == 1, "a tick is a day:" + w.date_string())
	for i in 30:
		w.tick_day()
	_check(w.date_string() == "01 Fev 2025", "31 days make the month:" + w.date_string())

	# Old saves stored the hour; it is ignored on loading.
	var old := w.to_dict()
	old["minute"] = 333
	var w3 := GameWorld.new()
	w3.setup(11)
	w3.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(w3.date_string() == w.date_string(), "old save with hour opens on the same date")

	# Random events: 20 years with no shock or dilemma.
	_check(not WorldEvents.RANDOM_EVENTS, "event draw turned off")
	# Texts copied from events.gd.
	var banned := ["El Niño e seca derrubam safras; preço de grãos dispara.", "OMS declara pandemia: fronteiras fecham e atividade desaba no mundo inteiro.", "Salto em inteligência artificial eleva produtividade em economias avançadas.", "Protestos em massa tomam as ruas de "]
	var dilemmas := ["Pandemia global", "Greve geral", "Escândalo de corrupção", "Desastre natural", "Banco sistêmico em risco", "Combustível em alta", "Alimentos caros", "Onda migratória", "Política industrial"]
	var hits := []
	var all_prompts := []
	var sim := GameWorld.new()
	sim.setup(31)
	sim.set_player(sim.by_iso["BRA"], "normal")
	sim.news_posted.connect(func(text, _k, _c):
		for b: String in banned:
			if text.contains(b):
				hits.append(text))
	sim.prompt_requested.connect(func(p):
		all_prompts.append(p.title)
		for d: String in dilemmas:
			if String(p.title) == d:
				hits.append(p.title))
	var prices0: float = sim.markets.shock[Markets.GRAIN]
	sim.player.next_election = 9999.0
	for i in 365 * 20:
		sim.player.approval = 0.6
		sim.player.stability = 0.8
		sim.tick_day()
		if sim.over:
			break
	var titles := {}
	for t: String in all_prompts:
		titles[t.split(" ")[0]] = int(titles.get(t.split(" ")[0], 0)) + 1
	print("janelas em 20 anos: ", titles)
	_check(hits.is_empty(), "no random event in 20 years %s" % str(hits.slice(0, 5)))
	_check(sim.markets.shock[Markets.GRAIN] == 0.0 or sim.markets.shock[Markets.GRAIN] <= prices0 + 0.0001, "no grain shock")
	# The debug menu can still fire them.
	var before := sim.global_risk
	WorldEvents._pandemic(sim)
	_check(sim.global_risk > before, "event is still available when called")

	# With no time limit, no history can grow forever.
	var hw := GameWorld.new()
	hw.setup(11)
	hw.global_hist = {"tension": PackedFloat32Array(), "risk": PackedFloat32Array(), "world_gdp": PackedFloat32Array()}
	for i in 600:
		hw._update_global()
	_check(hw.global_hist.tension.size() <= 480, "global history has a cap (%d)" % hw.global_hist.tension.size())

	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
