extends Node
## Simulation on another thread: frames keep flowing, nothing is lost, and clicks in the middle are safe.
## Uso: godot --path . -- --ui-threads

const FRAME_LIMIT_MS := 50.0

var main: Node
var failures := 0


func _ready() -> void:
	main = get_parent()
	await _run()
	print("RESULT: %d failures" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	_check(not main.loading and Game.world != null, "the opening ends with the world ready")
	_check(main.map.features.size() > 150, "the map was built: %d" % main.map.features.size())
	_check(not main.map._border_points.is_empty(), "the borders were built")
	main._pick_start(Game.world.by_iso["BRA"])
	main._begin(Character.random(Game.world.rng), {})
	main._set_speed(0)
	await _frames(5)
	# Independent central bank: the screen does not let you choose the rate.
	var c: Country = Game.world.player
	main.hud._desk.current_tab = 2
	main.hud.refresh(true)
	await _frames(2)
	_check(c.cb_independent, "Brazil has an independent central bank")
	_check((main.hud.get_node("%ToggleTaylorRule") as Button).disabled, "the manual rate button stays locked")
	_check(not (main.hud._sliders.rate_set as HSlider).editable, "the rate control stays locked")
	_check(main.hud._dyn.m_status.text.contains("independente"), "the tab says who decides:" + main.hud._dyn.m_status.text)
	var rate0 := c.rate_manual
	main.hud._on_toggle_taylor()
	_check(c.rate_manual == rate0, "not even calling the government directly changes the regime")
	main.hud._desk.current_tab = 0
	await _day_turn()
	await _month_turn()
	await _click_during_work()
	await _skip_and_prompt()
	await _save_and_load()
	await _restart()


## The day turn happens even on another thread, and the clock does not lose time.
func _day_turn() -> void:
	var w: GameWorld = Game.world
	var day := w.day_index
	main.accumulator = 0.9
	main._set_speed(3)
	var saw_busy := false
	for i in 120:
		await get_tree().process_frame
		saw_busy = saw_busy or w.busy
		if w.day_index > day:
			break
	main._set_speed(0)
	main.join_sim()
	_check(w.day_index == day + 1, "the day turned once: day %d" % w.day_index)
	_check(saw_busy, "the turn ran off the main thread")
	_check(not w.busy and not w.defer_events, "the world returned to the interface")


## The worst moment of the game: the month turn, with all countries acting.
func _month_turn() -> void:
	var w: GameWorld = Game.world
	w.month = 11
	w.day = w.MONTH_DAYS[11]
	main.accumulator = 0.9
	var month: int = w.months_elapsed
	var got_month := [false]
	var news := [0]
	w.month_passed.connect(func():
		_check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "the month's signal arrives on the main thread")
		got_month[0] = true)
	w.news_posted.connect(func(_t, _k, _c):
		news[0] += 1
		_check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "news arrives on the main thread") if news[0] == 1 else null)
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
	_check(w.months_elapsed == month + 1, "the month turned")
	_check(got_month[0], "the month's signal was delivered")
	_check(worst < FRAME_LIMIT_MS, "the screen does not freeze: %.1f ms" % worst)


## A click with the simulation in the middle waits for the thread, instead of changing the world along with it.
func _click_during_work() -> void:
	var w: GameWorld = Game.world
	var day := w.day_index
	main._run_on_worker(func():
		for i in 40:
			w.tick_day())
	await RenderingServer.frame_post_draw
	_check(w.busy, "the simulation is running")
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	get_viewport().push_input(key)
	_check(not w.busy and w.day_index == day + 40, "the key waited for the simulation to finish: day %d" % (w.day_index - day))
	main._set_speed(0)
	await _frames()
	# Moving the mouse does not wait: the screen keeps responding.
	main._run_on_worker(func():
		for i in 40:
			w.tick_day())
	await RenderingServer.frame_post_draw
	var move := InputEventMouseMotion.new()
	move.position = Vector2(800, 400)
	move.global_position = move.position
	get_viewport().push_input(move)
	main.join_sim()
	_check(not w.busy, "moving the mouse in the middle breaks nothing")


## A decision in the middle of the day advance stops the count, and it continues after the answer.
func _skip_and_prompt() -> void:
	var w: GameWorld = Game.world
	var day := w.day_index
	var prompted := [false]
	var hook := func():
		if not prompted[0] and w.day_index >= day + 3:
			prompted[0] = true
			w.ask_player({"title": "Teste", "text": "", "options": [{"label": "Ok", "hint": ""}]})
	w.month_passed.connect(hook)
	main.prompts.clear()
	# The decision is requested directly in the queue, as the simulation does.
	w.defer_events = true
	w.ask_player({"title": "Decisão", "text": "", "options": [{"label": "Ok", "hint": ""}]})
	w.defer_events = false
	_check(w.has_urgent_event(), "the decision stays in the queue")
	main.start_skip(10)
	await _frames(4)
	main.join_sim()
	_check(main._skip_left == 10, "the advance stops before a decision: %d left" % main._skip_left)
	await _frames(4)
	_check(main.modal_open, "the decision appears")
	var dim: Control = main.modal_root.get_child(main.modal_root.get_child_count() - 1)
	dim.get_node("%col").get_child(dim.get_node("%col").get_child_count() - 1).get_node("%pick").pressed.emit()
	for i in 200:
		await get_tree().process_frame
		if main._skip_left == 0 and not w.busy:
			break
	main.join_sim()
	_check(main._skip_left == 0 and w.day_index >= day + 10, "the advance ends after the answer")
	await _frames()
	_check(main.hud._skip_card.visible, "o resumo aparece")
	main.hud._skip_card.visible = false
	w.month_passed.disconnect(hook)


func _save_and_load() -> void:
	var w: GameWorld = Game.world
	SaveService.delete_files()
	var day := w.day_index
	main._save_game()
	await RenderingServer.frame_post_draw
	_check(w.busy, "saving runs on another thread")
	main.join_sim()
	_check(FileAccess.file_exists(SaveService.path), "the save was written")
	var news := main.hud._news_box.get_child(0) as Button
	_check(news.text.contains("Partida salva"), "the save's news appears:" + news.text)
	w.tick_day()
	main._load_game()
	_check(main.loading and Game.world == w, "enquanto carrega, o mundo atual continua inteiro")
	var worst := 0.0
	var stamp := Time.get_ticks_usec()
	while main.loading:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - stamp) / 1000.0)
		stamp = now
	print("  pior quadro ao carregar: %.1f ms" % worst)
	_check(worst < FRAME_LIMIT_MS, "loading does not freeze the screen")
	_check(Game.world != w and Game.world.day_index == day, "the save came back: day %d" % Game.world.day_index)
	_check(main.playing, "the game continues after loading")
	# Main file corrupted: the backup copy applies.
	main._save_game()
	main.join_sim()
	main._save_game()
	main.join_sim()
	var broken := FileAccess.open(SaveService.path, FileAccess.WRITE)
	broken.store_string("lixo")
	broken.close()
	var before: GameWorld = Game.world
	await main._load_game()
	_check(Game.world != before and main.playing, "corrupted save: loads the backup copy")
	SaveService.delete_files()
	

func _restart() -> void:
	var old: GameWorld = Game.world
	await main._restart()
	_check(Game.world != old and not main.playing and not main.loading, "nova partida monta outro mundo")
	_check(main.start_screen != null, "goes back to the start screen")
	# Stress: play, simulate, save and load in sequence, with the threads taking turns.
	for round_ in 4:
		main._pick_start(Game.world.by_iso["BRA"])
		main._begin(Character.random(Game.world.rng), {})
		main._set_speed(3)
		main.accumulator = 0.9
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
	_check(not main.loading and main.start_screen != null, "the thread rotation finishes entirely")
	SaveService.delete_files()
	