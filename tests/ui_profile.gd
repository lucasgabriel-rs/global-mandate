extends Node
## Measures how long the frame stays stalled in each heavy operation of the game.
## Usage: godot --path . -- --ui-profile

var main: Node
var rows: Array = []


func _ready() -> void:
	main = get_parent()
	await _run()
	print("\n--- worst time of each operation (ms) ---")
	rows.sort_custom(func(a, b): return a[1] > b[1])
	for r: Array in rows:
		print("%9.1f  %s" % [r[1], r[0]])
	get_tree().quit()


func _time(name_: String, fn: Callable, times := 1) -> void:
	var worst := 0.0
	for i in times:
		var t := Time.get_ticks_usec()
		fn.call()
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
	rows.append([name_, worst])


func _worst_while(name_: String, active: Callable) -> void:
	var worst := 0.0
	var stamp := Time.get_ticks_usec()
	while true:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - stamp) / 1000.0)
		stamp = now
		if not active.call():
			break
	rows.append([name_, worst])


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(5)
	rows.append(["(inicialização: mundo, mapa e cenas, do início do processo)", Time.get_ticks_msec() * 1.0])
	var w: GameWorld = Game.world
	_time("pick country on the start screen", func(): main._pick_start(w.by_iso["BRA"]))
	await _frames()
	var ch := Character.random(w.rng)
	_time("  set_player", func():
		w.leader = ch
		w.set_player(w.by_iso["BRA"], "normal"))
	_time("  hud.bind", func(): main.hud.bind(w, main.map))
	_time("  refresh_units force", func(): main.map.refresh_units(true))
	_time("  map.focus", func(): main.map.focus_on(w.by_iso["BRA"]))
	_time("  map.reset_view", func(): main.map.reset_view())
	_time("start the match (_begin)", func(): main._begin(ch, {}))
	var frame_t := Time.get_ticks_usec()
	await get_tree().process_frame
	rows.append(["  primeiro quadro depois de começar", (Time.get_ticks_usec() - frame_t) / 1000.0])
	frame_t = Time.get_ticks_usec()
	await get_tree().process_frame
	rows.append(["  segundo quadro depois de começar", (Time.get_ticks_usec() - frame_t) / 1000.0])
	main._set_speed(0)
	await _frames(5)
	_time("ordinary tick_day", func(): w.tick_day(), 20)
	var worst_month := 0.0
	for d in 70:
		var t := Time.get_ticks_usec()
		w.tick_day()
		worst_month = maxf(worst_month, (Time.get_ticks_usec() - t) / 1000.0)
	rows.append(["tick_day, pior em 70 dias (virada de mês)", worst_month])
	_time("one monthly step of all countries", func():
		for c: Country in w.countries:
			Economy.step_month(c, w))
	_time("AI of all countries", func():
		for c: Country in w.countries:
			NationAI.step_month(c, w))
	_time("parliaments of the world", func(): w.politics.step_world_parliaments(w))
	_time("recompute trade (_compute_shares)", func(): w.diplomacy._compute_shares(w))
	_time("sanctions: refresh_sanction_cache", func(): w.diplomacy.refresh_sanction_cache(w))
	_time("a new sanction (set_sanction)", func(): w.diplomacy.set_sanction(w.by_iso["FRA"], w.by_iso["RUS"], 1, w))
	for mode: String in ["relations", "growth", "political"]:
		_time("map: mode %s" % mode, func(): main.hud._on_mode(mode))
	await _frames()
	_time("map: refresh_colors", func(): main.map.refresh_colors())
	_time("map: refresh_units(true)", func(): main.map.refresh_units(true))
	_time("hud.refresh(true), Panel tab", func(): main.hud.refresh(true))
	for tab in [main.hud._divisions_tab, main.hud._politics_tab]:
		main.hud._desk.current_tab = tab
		_time("open tab %d" % tab, func(): main.hud.refresh(true))
		await _frames()
	main.hud._desk.current_tab = 0
	_time("dossier of a country", func(): main.hud.show_country(w.by_iso["USA"]))
	main.hud.show_country(null)
	await _frames()
	_time("open legislative center", func(): main.open_legislation())
	await _frames()
	main._close_modal(main.modal_root.get_child(main.modal_root.get_child_count() - 1))
	await _frames()
	var dict := {}
	_time("save: world.to_dict", func(): dict = w.to_dict())
	var bytes := PackedByteArray()
	_time("save: serialize (var_to_bytes)", func(): bytes = var_to_bytes(dict))
	rows.append(["(tamanho do save em MB)", bytes.size() / 1048576.0])
	_time("save: screen stalled", func(): main._save_game())
	await _worst_while("salvar: pior quadro", func(): return Game.world.busy or main._sim_pending.is_valid())
	main.join_sim()
	main._load_game()
	await _worst_while("carregar: pior quadro", func(): return main.loading)
	await _frames(5)
	w = Game.world
	main.start_skip(30)
	await _worst_while("botão +30 dias: pior quadro", func(): return main._skip_left > 0)
	main.join_sim()
	main.hud._skip_card.visible = false
	_time("new world (GameWorld.setup)", func():
		var other := GameWorld.new()
		other.setup())
	# Real frames at 4x, looking closely at Brazil, for 20 s.
	main._set_speed(3)
	main.map.focus_on(w.by_iso["BRA"])
	w.day = 28
	var worst := 0.0
	var over_33 := 0
	var frames := 0
	var stamp := Time.get_ticks_usec()
	var end := stamp + 20000000
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - stamp) / 1000.0
		stamp = now
		worst = maxf(worst, ms)
		frames += 1
		if ms > 33.0:
			over_33 += 1
	main._set_speed(0)
	rows.append(["quadro mais lento a 4x", worst])
	rows.append(["quadros acima de 33 ms em %d" % frames, float(over_33)])
	SaveService.delete_files()
	