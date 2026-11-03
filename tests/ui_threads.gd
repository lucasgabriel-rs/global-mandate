extends Node
## Simulação em outra thread: os quadros seguem fluindo, nada se perde, e cliques no meio são seguros.
## Uso: godot --path . -- --ui-threads

const FRAME_LIMIT_MS := 50.0

var main: Node
var failures := 0


func _ready() -> void:
	main = get_parent()
	await _run()
	print("RESULTADO: %d falhas" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	_check(not main.loading and main.world != null, "a abertura termina com o mundo pronto")
	_check(main.map.features.size() > 150, "o mapa foi montado: %d" % main.map.features.size())
	_check(not main.map._border_points.is_empty(), "as fronteiras foram montadas")
	main._pick_start(main.world.by_iso["BRA"])
	main._begin(Character.random(main.world.rng), {})
	main._set_speed(0)
	await _frames(5)
	# Banco central independente: a tela não deixa escolher o juro.
	var c: Country = main.world.player
	main.hud._desk.current_tab = 2
	main.hud.refresh(true)
	await _frames(2)
	_check(c.cb_independent, "o Brasil tem banco central independente")
	_check((main.hud.get_node("%AlternarRegraDeTaylorJuro") as Button).disabled, "o botão de juro manual fica travado")
	_check(not (main.hud._sliders.rate_set as HSlider).editable, "o controle de juro fica travado")
	_check(main.hud._dyn.m_status.text.contains("independente"), "a aba diz quem decide: " + main.hud._dyn.m_status.text)
	var rate0 := c.rate_manual
	main.hud._on_toggle_taylor()
	_check(c.rate_manual == rate0, "nem chamando direto o governo muda o regime")
	main.hud._desk.current_tab = 0
	await _day_turn()
	await _month_turn()
	await _click_during_work()
	await _skip_and_prompt()
	await _save_and_load()
	await _restart()


## A virada do dia acontece mesmo em outra thread, e o relógio não perde tempo.
func _day_turn() -> void:
	var w: GameWorld = main.world
	var day := w.day_index
	w.minute = w.MINUTES_PER_DAY - 3
	main._set_speed(3)
	var saw_busy := false
	for i in 120:
		await get_tree().process_frame
		saw_busy = saw_busy or w.busy
		if w.day_index > day:
			break
	main._set_speed(0)
	main.join_sim()
	_check(w.day_index == day + 1 and w.minute < 200, "o dia virou uma vez: dia %d, minuto %d" % [w.day_index, w.minute])
	_check(saw_busy, "a virada rodou fora da thread principal")
	_check(not w.busy and not w.defer_events, "o mundo voltou para a interface")


## O pior momento do jogo: a virada do mês, com todos os países agindo.
func _month_turn() -> void:
	var w: GameWorld = main.world
	w.month = 11
	w.day = w.MONTH_DAYS[11]
	w.minute = w.MINUTES_PER_DAY - 3
	var month: int = w.months_elapsed
	var got_month := [false]
	var news := [0]
	w.month_passed.connect(func():
		_check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "o sinal do mês chega na thread principal")
		got_month[0] = true)
	w.news_posted.connect(func(_t, _k, _c):
		news[0] += 1
		_check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "notícia chega na thread principal") if news[0] == 1 else null)
	main._set_speed(3)
	var worst := 0.0
	var stamp := Time.get_ticks_usec()
	for i in 240:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - stamp) / 1000.0)
		stamp = now
		if w.months_elapsed > month and not w.busy:
			break
	main._set_speed(0)
	main.join_sim()
	print("  pior quadro na virada de mês e de ano: %.1f ms" % worst)
	_check(w.months_elapsed == month + 1, "o mês virou")
	_check(got_month[0], "o sinal do mês foi entregue")
	_check(worst < FRAME_LIMIT_MS, "a tela não trava: %.1f ms" % worst)


## Um clique com a simulação no meio espera a thread, em vez de mexer no mundo junto com ela.
func _click_during_work() -> void:
	var w: GameWorld = main.world
	var day := w.day_index
	main._run_on_worker(func():
		for i in 40:
			w.tick_day())
	await RenderingServer.frame_post_draw
	_check(w.busy, "a simulação está rodando")
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	get_viewport().push_input(key)
	_check(not w.busy and w.day_index == day + 40, "a tecla esperou a simulação acabar: dia %d" % (w.day_index - day))
	main._set_speed(0)
	await _frames()
	# Passar o mouse não espera: a tela continua respondendo.
	main._run_on_worker(func():
		for i in 40:
			w.tick_day())
	await RenderingServer.frame_post_draw
	var move := InputEventMouseMotion.new()
	move.position = Vector2(800, 400)
	move.global_position = move.position
	get_viewport().push_input(move)
	main.join_sim()
	_check(not w.busy, "mover o mouse no meio não quebra nada")


## Uma decisão no meio do avanço de dias para a contagem, e ele continua depois da resposta.
func _skip_and_prompt() -> void:
	var w: GameWorld = main.world
	var day := w.day_index
	var prompted := [false]
	var hook := func():
		if not prompted[0] and w.day_index >= day + 3:
			prompted[0] = true
			w.ask_player({"title": "Teste", "text": "", "options": [{"label": "Ok", "hint": ""}]})
	w.month_passed.connect(hook)
	main.prompts.clear()
	# A decisão é pedida direto na fila, como faz a simulação.
	w.defer_events = true
	w.ask_player({"title": "Decisão", "text": "", "options": [{"label": "Ok", "hint": ""}]})
	w.defer_events = false
	_check(w.has_urgent_event(), "a decisão fica na fila")
	main.start_skip(10)
	await _frames(4)
	main.join_sim()
	_check(main._skip_left == 10, "o avanço para diante de uma decisão: faltam %d" % main._skip_left)
	await _frames(4)
	_check(main.modal_open, "a decisão aparece")
	var dim: Control = main.modal_root.get_child(main.modal_root.get_child_count() - 1)
	dim.get_node("%col").get_child(dim.get_node("%col").get_child_count() - 1).get_node("%pick").pressed.emit()
	for i in 200:
		await get_tree().process_frame
		if main._skip_left == 0 and not w.busy:
			break
	main.join_sim()
	_check(main._skip_left == 0 and w.day_index >= day + 10, "o avanço termina depois da resposta")
	await _frames()
	_check(main.hud._skip_card.visible, "o resumo aparece")
	main.hud._skip_card.visible = false
	w.month_passed.disconnect(hook)


func _save_and_load() -> void:
	var w: GameWorld = main.world
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
	var day := w.day_index
	main._save_game()
	await RenderingServer.frame_post_draw
	_check(w.busy, "salvar roda em outra thread")
	main.join_sim()
	_check(FileAccess.file_exists(main.SAVE_PATH), "o save foi escrito")
	var news := main.hud._news_box.get_child(0) as Button
	_check(news.text.contains("Partida salva"), "a notícia do save aparece: " + news.text)
	w.tick_day()
	main._load_game()
	_check(main.loading and main.world == w, "enquanto carrega, o mundo atual continua inteiro")
	var worst := 0.0
	var stamp := Time.get_ticks_usec()
	while main.loading:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - stamp) / 1000.0)
		stamp = now
	print("  pior quadro ao carregar: %.1f ms" % worst)
	_check(worst < FRAME_LIMIT_MS, "carregar não trava a tela")
	_check(main.world != w and main.world.day_index == day, "o save voltou: dia %d" % main.world.day_index)
	_check(main.playing, "o jogo continua depois de carregar")
	# Arquivo principal estragado: vale a cópia de segurança.
	main._save_game()
	main.join_sim()
	main._save_game()
	main.join_sim()
	var broken := FileAccess.open(main.SAVE_PATH, FileAccess.WRITE)
	broken.store_string("lixo")
	broken.close()
	var before: GameWorld = main.world
	await main._load_game()
	_check(main.world != before and main.playing, "save estragado: carrega a cópia de segurança")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.BACKUP_PATH))


func _restart() -> void:
	var old: GameWorld = main.world
	await main._restart()
	_check(main.world != old and not main.playing and not main.loading, "nova partida monta outro mundo")
	_check(main.start_screen != null, "volta à tela inicial")
	# Estresse: jogar, simular, salvar e carregar em sequência, com as threads se revezando.
	for round_ in 4:
		main._pick_start(main.world.by_iso["BRA"])
		main._begin(Character.random(main.world.rng), {})
		main._set_speed(3)
		main.world.minute = main.world.MINUTES_PER_DAY - 5
		await _frames(30)
		main.start_skip(30)
		await _frames(10)
		main.join_sim()
		main.prompts.clear()
		main._skip_left = 0
		main.hud.set_skipping(false)
		main._save_game()
		await _frames(2)
		await main._load_game()
		await _frames(2)
		await main._restart()
	_check(not main.loading and main.start_screen != null, "o revezamento das threads termina inteiro")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.BACKUP_PATH))
