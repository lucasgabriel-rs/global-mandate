extends Node
## Entry point: start screen, real-time clock, decisions, menu and game over.

## At normal speed 1 game day passes per real second. The values multiply that.
const DAYS_PER_SECOND := 1.0
const SPEEDS := [0.0, 1.0, 2.0, 4.0]
## Maximum lag kept when the simulation is slow: beyond that, the lost time is not recovered.
const MAX_DAYS_BEHIND := 2.0
const MAIN_MENU := preload("res://scenes/ui/main_menu.tscn")
const SETTINGS := preload("res://scenes/ui/modals/settings.tscn")
const START_SCREEN := preload("res://scenes/ui/start_screen.tscn")
const LOADING_SCREEN := preload("res://scenes/ui/loading_screen.tscn")
## Time per frame to create map nodes on the main thread, so the loading animation does not stutter.
const BOOT_SLICE_USEC := 6000
const PAUSE_MENU := preload("res://scenes/ui/modals/pause_menu.tscn")
const HELP := preload("res://scenes/ui/modals/help.tscn")
const CONFIRM := preload("res://scenes/ui/modals/confirm.tscn")
const PROMPT := preload("res://scenes/ui/modals/prompt.tscn")
const GAME_OVER := preload("res://scenes/ui/modals/game_over.tscn")
const CREATOR := preload("res://scenes/ui/modals/creator.tscn")
const PARTY_PICKER := preload("res://scenes/ui/modals/party_picker.tscn")
const CORRUPTION := preload("res://scenes/ui/modals/corruption.tscn")
const PARTY_DETAIL := preload("res://scenes/ui/modals/party_detail.tscn")
const MINISTER_PICKER := preload("res://scenes/ui/modals/minister_picker.tscn")
const CHAT := preload("res://scenes/ui/chat/chat.tscn")
const AGENDA := preload("res://scenes/ui/agenda.tscn")
const MEMBER_ROW := preload("res://scenes/ui/rows/member_row.tscn")
const PARTY_PICK_ROW := preload("res://scenes/ui/rows/party_pick_row.tscn")
const PROMPT_OPTION := preload("res://scenes/ui/rows/prompt_option.tscn")
const LEGISLATION_CENTER := preload("res://scenes/ui/legislation/legislation_center.tscn")
const LAW_EDITOR := preload("res://scenes/ui/legislation/law_editor.tscn")
const NORM_PAGE := preload("res://scenes/ui/legislation/norm_page.tscn")
const AMENDMENT_EDITOR := preload("res://scenes/ui/legislation/amendment_editor.tscn")
const NEGOTIATION := preload("res://scenes/ui/legislation/negotiation.tscn")
const TREATY := preload("res://scenes/ui/modals/treaty.tscn")
const ELECTION_REPORT := preload("res://scenes/ui/modals/election_report.tscn")
## Smallest window that still keeps the interface legible.
const MIN_WINDOW := Vector2i(1024, 576)

## The match in progress lives in the Game autoload; this is a shortcut to it.
var world: GameWorld:
	get:
		return Game.world
	set(value):
		Game.world = value
var start_screen: Control
var main_menu: Control
## Opening, loading or restarting: there is no world ready for the interface to use.
var loading := false
var _loading_screen: Control
var _sim_task := -1
var _sim_pending := Callable()
var _sim_after := Callable()

@onready var map: MapView = $Map
@onready var ui_layer: CanvasLayer = $UiLayer
@onready var hud: Hud = $UiLayer/Hud
@onready var modal_root: Control = $UiLayer/ModalRoot

var speed := 1
var last_speed := 1
var accumulator := 0.0
var refresh_timer := 0.0
var map_timer := 0.0
var prompts: Array = []
var modal_open := false
var playing := false
var _start_pick: Country
var _start_info: Label
var _start_button: Button
var _start_title: Label
var _difficulty := "normal"
var _autotest := ""
var _rate_clock := 0.0
var _rate_usec := 0
var _skip_left := 0
var _skip_total := 0
var _skip_before := {}
var _skip_news: Array = []
## A language change only redoes the screen after the world exists; before that there is nothing to redo.
var _lang_ready := false
var _lang_pending := false


func _ready() -> void:
	map.country_clicked.connect(_on_country_clicked)
	map.country_hovered.connect(_on_country_hovered)
	hud.debug.main = self
	map.unit_clicked.connect(func(id: int):
		if id >= 0:
			hud.debug.set_target(world.player))
	hud.speed_requested.connect(_set_speed)
	hud.skip_requested.connect(start_skip)
	hud.menu_requested.connect(_open_menu)
	hud.confirm_requested.connect(_confirm)
	hud.party_detail_requested.connect(_open_party_detail)
	hud.minister_pick_requested.connect(_open_minister_picker)
	hud.talk_requested.connect(_open_talk)
	hud.legislation_requested.connect(open_legislation)
	hud.agenda_requested.connect(open_agenda)
	hud.corruption_requested.connect(_open_corruption)
	hud.treaty_requested.connect(open_treaty)
	hud.election_requested.connect(open_election_report)
	hud.tax_law_requested.connect(func():
		open_law_editor(world.legislation.start_tax_bill(world)))
	hud.party_requested.connect(func():
		_open_party_picker(world.player, false, func(choice):
			var r := _apply_party_choice(choice, false)
			hud._politics.say(r.msg, not r.ok)
			hud.refresh(true)))
	hud.character_requested.connect(func():
		_open_creator(world.leader.duplicate(), func(ch):
			world.leader = ch
			world.politics.sync_player(world)
			hud.refresh_leader()))
	RenderingServer.frame_pre_draw.connect(_launch_sim)
	get_window().unresizable = false
	get_window().min_size = MIN_WINDOW
	await _boot()
	# Interface tests start straight at the country choice.
	var args := Array(OS.get_cmdline_user_args())
	if args.any(func(a: String): return a.begins_with("--ui-")) and not args.has("--ui-menu"):
		_build_start_screen()
	else:
		_build_main_menu()
	_hide_loading()
	_lang_ready = true
	var autotest := load("res://tests/ui_drive.gd") if OS.get_cmdline_user_args().has("--ui-test") else null
	if OS.get_cmdline_user_args().has("--ui-divisions"):
		autotest = load("res://tests/ui_divisions.gd")
	if OS.get_cmdline_user_args().has("--ui-statecraft"):
		autotest = load("res://tests/ui_statecraft.gd")
	if OS.get_cmdline_user_args().has("--ui-politics"):
		autotest = load("res://tests/ui_politics.gd")
	if OS.get_cmdline_user_args().has("--ui-clock"):
		autotest = load("res://tests/ui_clock.gd")
	if OS.get_cmdline_user_args().has("--ui-capitals"):
		autotest = load("res://tests/ui_capitals.gd")
	if OS.get_cmdline_user_args().has("--ui-debug"):
		autotest = load("res://tests/ui_debug.gd")
	if OS.get_cmdline_user_args().has("--ui-borders"):
		autotest = load("res://tests/ui_borders.gd")
	if OS.get_cmdline_user_args().has("--ui-legislation"):
		autotest = load("res://tests/ui_legislation.gd")
	if OS.get_cmdline_user_args().has("--ui-society"):
		autotest = load("res://tests/ui_society.gd")
	if OS.get_cmdline_user_args().has("--ui-infra"):
		autotest = load("res://tests/ui_infra.gd")
	if OS.get_cmdline_user_args().has("--ui-corporate"):
		autotest = load("res://tests/ui_corporate.gd")
	if OS.get_cmdline_user_args().has("--ui-boot"):
		print("abertura ok: %d países, %d no mapa, %d ms" % [world.countries.size(), map.features.size(), Time.get_ticks_msec()])
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--ui-threads"):
		autotest = load("res://tests/ui_threads.gd")
	if OS.get_cmdline_user_args().has("--ui-profile"):
		autotest = load("res://tests/ui_profile.gd")
	if OS.get_cmdline_user_args().has("--ui-desk"):
		autotest = load("res://tests/ui_desk.gd")
	if OS.get_cmdline_user_args().has("--ui-economy"):
		autotest = load("res://tests/ui_economy.gd")
	if OS.get_cmdline_user_args().has("--ui-econ-audit"):
		autotest = load("res://tests/ui_econ_audit.gd")
	if OS.get_cmdline_user_args().has("--ui-layout"):
		autotest = load("res://tests/ui_layout.gd")
	if OS.get_cmdline_user_args().has("--ui-creator"):
		autotest = load("res://tests/ui_creator.gd")
	if OS.get_cmdline_user_args().has("--ui-diplomacy"):
		autotest = load("res://tests/ui_diplomacy.gd")
	if OS.get_cmdline_user_args().has("--ui-locale"):
		autotest = load("res://tests/ui_locale.gd")
	if OS.get_cmdline_user_args().has("--ui-menu"):
		autotest = load("res://tests/ui_menu.gd")
	if OS.get_cmdline_user_args().has("--ui-opposition"):
		autotest = load("res://tests/ui_opposition.gd")
	if autotest:
		add_child(autotest.new())


func _adopt_world(fresh: GameWorld) -> void:
	_skip_left = 0
	hud.debug.infinite_dp = false
	hud.debug.visible = false
	world = fresh
	world.prompt_requested.connect(func(p): prompts.append(p))
	world.game_ended.connect(_on_game_ended)
	world.demarcation_requested.connect(func(s): hud.begin_demarcation(s))
	world.talk_requested.connect(func(c): _open_talk(c, true))
	world.news_posted.connect(func(text, kind, _c):
		if _skip_left > 0:
			_skip_news.append([text, kind]))
	map.bind(world)


# --- Threads --------------------------------------------------------------------------
#
# The world has only one owner at a time. The interface uses it freely on the main thread, until _launch_sim
# hands it to a worker thread and marks world.busy. Meanwhile, frames keep drawing, but
# nobody reads or changes the world: _process returns early, and any click or key calls join_sim, which waits for the
# thread to finish. The simulation's signals stay queued and are delivered in join_sim, back on the main thread.

## Schedules a job on the world. It only starts after the nodes finish drawing in this frame.
func _run_on_worker(work: Callable, after := Callable()) -> void:
	_sim_pending = work
	_sim_after = after


func _launch_sim() -> void:
	if not _sim_pending.is_valid():
		return
	world.busy = true
	world.defer_events = true
	_sim_task = WorkerThreadPool.add_task(_sim_pending, true, "simulação")
	_sim_pending = Callable()


## Returns the world to the main thread, waiting for whatever is still running.
func join_sim() -> void:
	if _sim_pending.is_valid():
		var work := _sim_pending
		_sim_pending = Callable()
		world.defer_events = true
		work.call()
	elif _sim_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_sim_task)
		_sim_task = -1
	else:
		return
	world.busy = false
	world.defer_events = false
	world.flush_events()
	if _sim_after.is_valid():
		var after := _sim_after
		_sim_after = Callable()
		after.call()


func _input(event: InputEvent) -> void:
	# Hovering changes nothing in the world. Click, drag and key need it back first.
	if event is InputEventMouseMotion and event.button_mask == 0:
		return
	if _sim_task >= 0:
		join_sim()


func _exit_tree() -> void:
	if world:
		join_sim()


func _show_loading(text: String) -> void:
	if _loading_screen == null:
		_loading_screen = LOADING_SCREEN.instantiate()
		modal_root.add_child(_loading_screen)
	(_loading_screen.get_node("%status") as Label).text = text
	loading = true


func _hide_loading() -> void:
	if _loading_screen:
		modal_root.remove_child(_loading_screen)
		_loading_screen.queue_free()
		_loading_screen = null
	loading = false


## Waits for a background job without stopping the screen.
func _wait_task(id: int) -> void:
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)


## Game opening: the map and the world are built at the same time, on other threads.
func _boot() -> void:
	_show_loading(tr("Preparando o mundo..."))
	await get_tree().process_frame
	var fresh := GameWorld.new()
	var world_task := WorkerThreadPool.add_task(fresh.setup.bind(0), true, "mundo")
	var data_task := WorkerThreadPool.add_task(map.load_feature_data, true, "mapa")
	await _wait_task(data_task)
	var shapes := WorkerThreadPool.add_group_task(map.prepare_feature, map.feature_count(), -1, true, "triangulação")
	while not WorkerThreadPool.is_group_task_completed(shapes):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(shapes)
	(_loading_screen.get_node("%status") as Label).text = tr("Desenhando o mapa...")
	while not map.build_features_slice(BOOT_SLICE_USEC):
		await get_tree().process_frame
	await _wait_task(world_task)
	_adopt_world(fresh)


## Waits for everything in the background to finish. For the tests and for whoever needs the result.
func idle() -> void:
	join_sim()
	while loading:
		await get_tree().process_frame


# --- Idioma ---------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _lang_ready and not _lang_pending:
		# All nodes receive the notice at once; redoes the screen only once, at the end of the frame.
		_lang_pending = true
		_on_language_changed.call_deferred()


## Scenes translate themselves; here is redone what is built in code with already translated texts.
func _on_language_changed() -> void:
	_lang_pending = false
	join_sim()
	world.localize_country_names()
	if start_screen and _start_pick:
		_pick_start(_start_pick)
	if playing:
		hud.refresh_leader()
		hud.refresh(true)
		if hud.selected:
			hud.show_country(hud.selected)
		var center := legislation_center()
		if center:
			open_legislation(center.current_tab())


# --- Menu inicial --------------------------------------------------------------

func _build_main_menu() -> void:
	main_menu = MAIN_MENU.instantiate()
	modal_root.add_child(main_menu)
	_sync_modal_state()
	map.frame_region(10.0, get_viewport().get_visible_rect().size.x)
	(main_menu.get_node("%versao") as Label).text = String(ProjectSettings.get_setting("application/config/version", ""))
	main_menu.get_node("%novo_jogo").pressed.connect(func():
		_close_main_menu()
		_build_start_screen())
	var load_button: Button = main_menu.get_node("%carregar_jogo")
	load_button.disabled = not SaveService.has_save()
	# The menu only goes away when the match loads (_enter_game): if the file is bad, it stays there.
	load_button.pressed.connect(_load_game)
	main_menu.get_node("%configuracoes").pressed.connect(_open_settings)
	main_menu.get_node("%sair_do_jogo").pressed.connect(func(): get_tree().quit())


func _close_main_menu() -> void:
	if main_menu == null:
		return
	main_menu.queue_free()
	main_menu = null
	_sync_modal_state()


func _open_settings() -> void:
	var dim := _modal(SETTINGS) as SettingsMenu
	dim.closed.connect(func(): _close_modal(dim))


# --- Tela inicial --------------------------------------------------------------

func _build_start_screen() -> void:
	start_screen = START_SCREEN.instantiate()
	modal_root.add_child(start_screen)
	map.frame_region(10.0, get_viewport().get_visible_rect().size.x - 400.0)
	_start_title = start_screen.get_node("%start_title")
	_start_info = start_screen.get_node("%start_info")
	_start_button = start_screen.get_node("%start_button")
	var diff_buttons := {"facil": start_screen.get_node("%diff_facil"), "normal": start_screen.get_node("%diff_normal"), "dificil": start_screen.get_node("%diff_dificil")}
	var style_diff := func(sel: String):
		_difficulty = sel
		for k: String in diff_buttons:
			(diff_buttons[k] as Button).add_theme_color_override("font_color", UiKit.ACCENT if k == sel else UiKit.TEXT)
	for k: String in diff_buttons:
		diff_buttons[k].pressed.connect(style_diff.bind(k))
	style_diff.call("normal")
	_start_button.pressed.connect(func(): _open_creator(Character.random(world.rng, _start_pick.iso, _start_pick.region), func(ch):
		_open_party_picker(_start_pick, true, func(choice): _begin(ch, choice))))
	var saved: Button = start_screen.get_node("%continue_game")
	saved.visible = SaveService.has_save()
	saved.pressed.connect(_load_game)


func _pick_start(c: Country) -> void:
	if c == null or start_screen == null:
		return
	_start_pick = c
	map.select(c)
	_start_title.text = c.name
	_start_button.disabled = false
	var stat := func(key: String, value: String, color := UiKit.TEXT) -> void:
		var l: Label = start_screen.get_node("%stat_" + key)
		l.text = value
		l.add_theme_color_override("font_color", color)
	# Green or red only when the number departs from the usual; otherwise, the normal text color.
	var tone := func(good: bool, bad: bool) -> Color:
		return UiKit.RED if bad else (UiKit.GREEN if good else UiKit.TEXT)
	var regions := {"AFR": tr("África"), "ASI": tr("Ásia"), "EUR": tr("Europa"), "LAM": tr("América Latina"),
		"MEA": tr("Oriente Médio"), "NAM": tr("América do Norte"), "OCE": tr("Oceania")}
	var regime := tr("Democracia") if c.dem >= 6.0 else (tr("Regime híbrido") if c.dem >= 4.0 else tr("Regime autoritário"))
	(start_screen.get_node("%start_sub") as Label).text = "%s  ·  %s" % [regions.get(c.region, c.region), regime]
	start_screen.get_node("%start_stats").visible = true
	(start_screen.get_node("%cap_gdp") as Label).text = tr("PIB  ·  #%d") % world.rank_of(c, func(x: Country): return x.y_usd())
	stat.call("gdp", UiKit.money(c.y_usd()))
	stat.call("gdp_pc", "US$ %s" % UiKit.thousand(c.gdp_pc()))
	stat.call("pop", tr("%s mi") % UiKit.num(c.pop, 1))
	stat.call("growth", UiKit.pct(c.g0), tone.call(c.g0 >= 0.04, c.g0 < 0.01))
	stat.call("inflation", UiKit.pct(c.pi_yoy), tone.call(false, c.pi_yoy > 0.06 or c.pi_yoy < -0.005))
	stat.call("unemp", UiKit.pct(c.unemp), tone.call(c.unemp < 0.04, c.unemp > 0.10))
	stat.call("rate", UiKit.pct(c.rate))
	stat.call("debt", UiKit.pct(c.debt_ratio, 0), tone.call(c.debt_ratio < 0.4, c.debt_ratio > c.debt_tol))
	stat.call("rating", c.rating, tone.call(c.rating.begins_with("A"), c.rating.begins_with("C") or c.rating.begins_with("D") or c.rating == "B" or c.rating.begins_with("B-")))
	stat.call("approval", UiKit.pct(c.approval, 0), tone.call(c.approval >= 0.55, c.approval < 0.35))
	stat.call("stability", UiKit.pct(c.stability, 0), tone.call(c.stability >= 0.7, c.stability < 0.4))
	stat.call("democracy", "%s / 10" % UiKit.num(c.dem, 1))
	stat.call("troops", tr("%s mil") % UiKit.thousand(c.troops))
	stat.call("nukes", UiKit.thousand(c.nukes) if c.nukes > 0 else "—")
	stat.call("defense", tr("%s do PIB") % UiKit.pct(c.sp_defense))
	var gov := []
	var party := world.politics.ruling_party(c.iso)
	if not party.is_empty():
		gov.append(tr("Governo: %s (%s das cadeiras)") % [tr(String(party.name)), UiKit.pct(world.politics.government_share(c.iso), 0)])
	if c.dem >= 4.0:
		gov.append(tr("Eleição a cada 4 anos"))
	else:
		gov.append(tr("Sem eleições livres: risco de golpe e revolta"))
	(start_screen.get_node("%start_gov") as Label).text = "\n".join(gov)
	var order := range(Sectors.COUNT)
	order.sort_custom(func(i: int, j: int): return c.sector_share[i] > c.sector_share[j])
	var top := []
	for i: int in order.slice(0, 4):
		top.append("%s  %s" % [tr(Sectors.NAMES[i]), UiKit.pct(c.sector_share[i], 0)])
	(start_screen.get_node("%start_sectors") as Label).text = "\n".join(top) if c.sector_share.size() >= Sectors.COUNT else "—"
	var notes := []
	if c.peg == 2:
		notes.append(tr("Moeda: euro (juros definidos pelo BCE)"))
	elif c.peg == 1:
		notes.append(tr("Moeda ancorada no dólar"))
	if world.diplomacy.in_war(c.idx):
		notes.append(tr("EM GUERRA no início da partida"))
	_start_info.text = "\n".join(notes)
	_start_info.visible = not notes.is_empty()


func _begin(character := {}, choice := {}) -> void:
	if _start_pick == null:
		return
	world.leader = character if not character.is_empty() else Character.random(world.rng, _start_pick.iso, _start_pick.region)
	world.set_player(_start_pick, _difficulty)
	_apply_party_choice(choice, true)
	world.diplomacy.update_prod_factors(world)
	_enter_game()
	map.select(null)
	map.reset_view()
	map.focus_on(_start_pick)
	if world.in_office:
		world.emit_news(tr("%s toma posse em %s. O mundo observa.") % [world.leader.name, _start_pick.name], "politica", _start_pick)
	else:
		world.emit_news(tr("%s lidera a oposição em %s contra o governo de %s.") % [world.leader.name, _start_pick.name, world.politics.ruling_party(_start_pick.iso).get("name", "")], "politica", _start_pick)


func _enter_game() -> void:
	playing = true
	if world.leader.is_empty():
		# Save from before the character creator: generates a fixed leader for that country.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(world.player.iso)
		world.leader = Character.random(rng, world.player.iso, world.player.region)
	if start_screen:
		start_screen.queue_free()
		start_screen = null
	_close_main_menu()
	hud.visible = true
	hud.bind(world, map)
	map.refresh_colors()
	_set_speed(1)


# --- Clock -------------------------------------------------------------------

func _process(delta: float) -> void:
	if loading:
		return
	if _sim_task >= 0:
		if not WorkerThreadPool.is_task_completed(_sim_task):
			# The clock waits for the thread: time is not lost, and the screen keeps drawing.
			if speed > 0:
				accumulator = minf(accumulator + delta * DAYS_PER_SECOND * SPEEDS[speed], MAX_DAYS_BEHIND)
			return
		join_sim()
	if not playing:
		return
	if not prompts.is_empty() and not modal_open:
		_show_prompt(prompts.pop_front())
	if _skip_left > 0:
		_run_skip()
	elif speed > 0 and not modal_open and not world.over and not hud.border.active:
		accumulator = minf(accumulator + delta * DAYS_PER_SECOND * SPEEDS[speed], MAX_DAYS_BEHIND)
		# Each day runs on another thread; the clock waits for it to finish before the next one.
		if accumulator >= 1.0:
			accumulator -= 1.0
			_run_on_worker(world.tick_day)
	hud.refresh_clock()
	_measure_rate()
	refresh_timer += delta
	map_timer += delta
	if refresh_timer > 0.25:
		refresh_timer = 0.0
		hud.refresh()
	if map_timer > 1.0:
		map_timer = 0.0
		if map.mode != "politico":
			map.refresh_colors()


## Advances days at once: the simulation runs each day normally, without waiting for the clock. The time
## does not change. A decision along the way interrupts the advance, which continues after the answer.
func start_skip(days: int) -> void:
	join_sim()
	if not playing or world.over or modal_open or hud.border.active or _skip_left > 0:
		return
	_skip_left = days
	_skip_total = days
	_skip_news = []
	_skip_before = hud.skip_snapshot()
	hud.set_skipping(true)


func _run_skip() -> void:
	if world.over:
		_skip_left = 0
		hud.set_skipping(false)
		return
	if modal_open or not prompts.is_empty() or hud.border.active or _sim_pending.is_valid():
		return
	_run_on_worker(_skip_days, _after_skip)


## On the worker thread: advances until it ends or until something needing the player comes up.
func _skip_days() -> void:
	while _skip_left > 0 and not world.over and not world.has_urgent_event():
		world.tick_day()
		_skip_left -= 1


func _after_skip() -> void:
	if _skip_left > 0:
		return
	hud.set_skipping(false)
	if not world.over:
		hud.show_skip_summary(_skip_total, _skip_before, _skip_news)
	hud.refresh(true)
	map.refresh_colors()


## Real rate of the clock on screen, measured every second: shows whether the chosen speed is in effect.
func _measure_rate() -> void:
	var now := Time.get_ticks_usec()
	if now - _rate_usec < 1000000:
		return
	var clock := _clock_days()
	var rate := (clock - _rate_clock) / ((now - _rate_usec) / 1000000.0)
	_rate_clock = clock
	_rate_usec = now
	var running: bool = speed > 0 and not modal_open and not world.over and not hud.border.active and _skip_left == 0
	hud.set_rate_display(rate if running else 0.0, SPEEDS[speed] * DAYS_PER_SECOND if running else 0.0)


## Game days counted with the fraction of the current day, so the measured rate does not oscillate.
func _clock_days() -> float:
	return world.day_index + accumulator


func _set_speed(s: int) -> void:
	if s > 0:
		last_speed = s
	if s != speed and world:
		print("velocidade: %s, relógio em %s" % ["pausa" if s == 0 else "%dx" % int(SPEEDS[s]), world.date_string()])
		# The lag accumulated at the previous speed is not charged at the new one, and the next rate measurement
		# does not mix the two.
		accumulator = fmod(accumulator, 1.0)
		_rate_clock = _clock_days()
		_rate_usec = Time.get_ticks_usec()
		var expected: float = SPEEDS[s] * DAYS_PER_SECOND
		hud.set_rate_display(expected, expected)
	speed = s
	hud.set_speed_display(s)


func _unhandled_key_input(event: InputEvent) -> void:
	if not playing or not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_SPACE:
			_set_speed(0 if speed > 0 else last_speed)
		KEY_1: _set_speed(1)
		KEY_2: _set_speed(2)
		KEY_3, KEY_4: _set_speed(3)
		KEY_N:
			if not modal_open:
				hud.start_drawing()
		KEY_L:
			if not modal_open:
				open_legislation()
		KEY_F12:
			hud.debug.toggle()
		KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_ESCAPE:
			if modal_open:
				return
			if map.drawing:
				map.cancel_draft()
				return
			if hud.debug.visible:
				hud.debug.toggle()
				return
			_open_menu()


# --- Mapa ----------------------------------------------------------------------

func _on_country_clicked(c: Country) -> void:
	if loading:
		return
	if not playing:
		_pick_start(c)
		return
	map.select(c)
	hud.show_country(c)


func _on_country_hovered(c: Country) -> void:
	if playing:
		hud.set_hover(c)


# --- Janelas -------------------------------------------------------------------

## Opens a window from the scenes/ui/modals folder. Empty title and text keep what is in the scene.
func _modal(scene: PackedScene, title := "", body := "") -> Control:
	modal_open = true
	map.interactive = false
	var dim: Control = scene.instantiate()
	modal_root.add_child(dim)
	if title != "":
		(dim.get_node("%title") as Label).text = title
	if dim.has_node("%body"):
		var label: Label = dim.get_node("%body")
		label.text = body
		label.visible = body != ""
	return dim


func _close_modal(dim: Control) -> void:
	dim.queue_free()
	# A window's answer may have opened another: game over, conversation, new character.
	var another := false
	for child: Node in modal_root.get_children():
		if child != dim and child != start_screen and child != _loading_screen and not child.is_queued_for_deletion():
			another = true
	modal_open = another
	map.interactive = not another
	# Saving leaves the world with another thread: the screen updates when it comes back.
	if world.busy or _sim_pending.is_valid():
		return
	hud.refresh(true)
	map.refresh_colors()


# --- Party choice -------------------------------------------------------------

## choice: {"id": existing party} or {"found": name, "family": family, "color": color}.
func _apply_party_choice(choice: Dictionary, at_start: bool) -> Dictionary:
	# Only whoever founds a party chooses the ideas; whoever joins another adopts its own.
	if choice.has("found"):
		world.leader["econ"] = choice.econ
		world.leader["social"] = choice.social
	# The role comes before the party: in opposition, joining a party does not make it govern.
	if at_start and choice.get("role", "") == "opposition" and choice.get("id", -1) != int(world.politics.data_of(world.player.iso).ruling):
		world.start_in_opposition()
	var result := {"ok": true, "msg": ""}
	if choice.has("id"):
		if choice.id == int(world.politics.data_of(world.player.iso).player_party):
			world.politics.sync_player(world)
		else:
			result = world.politics.join_party(world, choice.id, at_start)
	elif choice.has("found"):
		result = world.politics.found_party(world, choice.found, choice.family, choice.color, at_start)
	else:
		world.politics.sync_player(world)
	if at_start:
		world.politics.auto_cabinet(world)
	return result


func _member_row(member: Dictionary, party: Dictionary, on_press := Callable()) -> Control:
	var row: Control = MEMBER_ROW.instantiate()
	var face: Countryball = row.get_node("%face")
	face.show_person(world.leader if member.get("player", false) else Character.for_politician(member), world.player.iso)
	var text := tr("%s, %d anos  ·  %s  ·  competência %d%%%s") % [member.name, People.age_of(member, world), party.short, int(float(member.competence) * 100.0), tr("  ·  doente") if member.has("illness") else ""]
	var pick: Button = row.get_node("%pick")
	var label: Label = row.get_node("%label")
	pick.visible = on_press.is_valid()
	label.visible = not on_press.is_valid()
	if on_press.is_valid():
		pick.text = text
		pick.pressed.connect(on_press)
	else:
		label.text = (tr("Você: ") if member.get("player", false) else "") + text
	var compass: CompassView = row.get_node("%compass")
	compass.points = [{"econ": member.econ, "social": member.social, "color": Color.WHITE, "big": true}]
	return row


func _open_party_detail(id: int) -> void:
	var party: Dictionary = world.politics.party_of(world.player.iso, id)
	var dim := _modal(PARTY_DETAIL, party.name, tr("%s  ·  %d assentos  ·  %s dos votos. A bússola do partido é a média dos políticos.") % [tr(Politics.FAMILIES[party.family].label), int(party.seats), UiKit.pct(party.support, 0)])
	var compass: CompassView = dim.get_node("%party_compass")
	var dots := []
	for m: Dictionary in party.members:
		dots.append({"econ": m.econ, "social": m.social, "color": Color.WHITE})
	dots.append({"econ": party.econ, "social": party.social, "color": party.color, "big": true})
	compass.points = dots
	var rows: Control = dim.get_node("%rows")
	for m: Dictionary in party.members:
		rows.add_child(_member_row(m, party))
	dim.get_node("%Fechar").pressed.connect(func(): _close_modal(dim))


func _open_corruption() -> void:
	var dim := _modal(CORRUPTION, tr("Caixa dois"), tr("Dinheiro por fora do orçamento oficial, pago por enquanto com o fundo do partido. Rende hoje e cobra amanhã."))
	var window: CorruptionWindow = dim as CorruptionWindow
	window.setup(world)
	window.closed.connect(func():
		_close_modal(dim)
		hud.refresh(true))


func _open_minister_picker(post: String) -> void:
	var portfolio := {}
	for p: Dictionary in world.politics.portfolios(world):
		if p.id == post:
			portfolio = p
	var dim := _modal(MINISTER_PICKER, tr("Ministério: %s") % tr(portfolio.label), tr(portfolio.desc))
	var rows: Control = dim.get_node("%rows")
	for e: Dictionary in world.politics.eligible_ministers(world, post):
		rows.add_child(_member_row(e.member, e.party, func():
			var r: Dictionary = world.politics.appoint(world, post, e.party.id, e.member.id)
			hud._cabinet.say((tr("%s assume a pasta.") % e.member.name) if r.ok else r.msg, not r.ok)
			_close_modal(dim)))
	dim.get_node("%Cancelar").pressed.connect(func(): _close_modal(dim))


# --- Conversation with leaders -----------------------------------------------------------

func _open_talk(target: Country, invited := false) -> void:
	var opened := Dialogue.start(world, target, invited)
	if not opened.ok:
		hud._set_feedback(opened.msg)
		return
	open_chat(ChatLog.country_key(target.iso))


## Opens the conversation window already at the indicated contact: "pais:ISO" or "partido:ID".
func open_chat(key: String) -> void:
	var dim: ChatWindow = _modal(CHAT, tr("Conversas"))
	dim.setup(self, key)


## Contact book: all party and country leaders. Inside the conversation window, chooses the contact in the window itself.
func open_agenda(chat: ChatWindow = null) -> void:
	var dim: AgendaWindow = _modal(AGENDA, tr("Agenda"))
	dim.setup(self, chat)


## Calls the contact from the book ("pais:ISO" or "partido:ID"): opens a new conversation with the leader, if possible, and shows the history.
func call_contact(key: String, chat: ChatWindow = null) -> void:
	if key.begins_with("pais:"):
		var c: Country = world.by_iso.get(key.trim_prefix("pais:"))
		if c and world.in_office and c.alive and Dialogue.turns_left(world, c) == 0 and Dialogue.wait_months(world, c) == 0:
			Dialogue.start(world, c)
	if chat and is_instance_valid(chat) and not chat.is_queued_for_deletion():
		chat.select(key)
	else:
		open_chat(key)


func _open_party_picker(country: Country, at_start: bool, on_done: Callable) -> void:
	var data: Dictionary = world.politics.data_of(country.iso)
	var body := tr("Todo político pertence a um partido. Escolha um deles ou crie o seu, e decida se começa no governo ou na oposição.") if at_start else tr("Só é possível mudar de partido uma vez por ano. O partido novo só ganha assentos na próxima eleição.")
	var dim := _modal(PARTY_PICKER, tr("Escolha seu partido em %s") % country.name, body)
	var picker: CompassView = dim.get_node("%my_compass")
	var first_family: Dictionary = Politics.FAMILIES[Politics.FAMILIES.keys()[0]]
	var idea := {"econ": float(first_family.econ), "social": float(first_family.social)}
	var show_ideas := func():
		var dots := []
		for p: Dictionary in data.parties:
			dots.append({"econ": p.econ, "social": p.social, "color": p.color, "big": true})
		dots.append({"econ": idea.econ, "social": idea.social, "color": Color.WHITE})
		picker.points = dots
	show_ideas.call()
	picker.picked.connect(func(e: float, s: float):
		idea.econ = e
		idea.social = s
		show_ideas.call())
	var party_rows: Control = dim.get_node("%party_rows")
	for n: Node in party_rows.get_parent().get_children():
		if n.is_in_group("at_start_only"):
			n.visible = at_start
	var role := {"value": "government"}
	var party_buttons := {}
	var role_buttons := {"government": dim.get_node("%role_government"), "opposition": dim.get_node("%role_opposition")}
	var apply_role := func():
		for id: int in party_buttons:
			(party_buttons[id] as Button).disabled = role.value == "opposition" and id == int(data.ruling)
		for key: String in role_buttons:
			var b: Button = role_buttons[key]
			b.add_theme_color_override("font_color", UiKit.ACCENT if role.value == key else UiKit.TEXT)
			b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.95, 0.7, 0.24, 0.2) if role.value == key else Color(1, 1, 1, 0.05), UiKit.ACCENT if role.value == key else UiKit.LINE, 3, 5))
	if at_start:
		var closed := country.dem < 4.0
		for key: String in role_buttons:
			role_buttons[key].pressed.connect(func():
				role.value = key
				apply_role.call())
		if closed:
			role_buttons.opposition.disabled = true
			role_buttons.opposition.tooltip_text = tr("Regimes fechados não têm eleições.")
		var ruling_name: String = world.politics.ruling_party(country.iso).get("name", "")
		(dim.get_node("%ruling_info") as Label).text = tr("Hoje governa: %s.") % ruling_name if not closed else tr("Regime fechado, sem eleições: só é possível governar.")
	var ordered: Array = data.parties.duplicate()
	ordered.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	for p: Dictionary in ordered:
		var row: Control = PARTY_PICK_ROW.instantiate()
		(row.get_node("%chip") as ColorRect).color = p.color
		var mine: bool = int(data.player_party) == p.id and not at_start
		var b: Button = row.get_node("%pick")
		b.text = (tr("Ficar em %s  ·  %s  ·  %s dos votos  ·  %d de %d assentos") if mine else tr("%s  ·  %s  ·  %s dos votos  ·  %d de %d assentos")) % [p.name, tr(Politics.FAMILIES[p.family].label), UiKit.pct(p.support, 0), int(p.seats), int(data.seats_total)]
		b.tooltip_text = tr("%s. Clique para escolher.") % p.name
		b.pressed.connect(func():
			_close_modal(dim)
			on_done.call({"id": p.id, "role": role.value}))
		party_buttons[int(p.id)] = b
		party_rows.add_child(row)
	var name_edit: LineEdit = dim.get_node("%party_name")
	var family: OptionButton = dim.get_node("%party_family")
	for key: String in Politics.FAMILIES:
		family.add_item(tr(Politics.FAMILIES[key].label))
		family.set_item_metadata(family.item_count - 1, key)
	var color: ColorPickerButton = dim.get_node("%party_color")
	color.color = Politics.FAMILIES[Politics.FAMILIES.keys()[0]].color
	family.item_selected.connect(func(i: int):
		var chosen: Dictionary = Politics.FAMILIES[family.get_item_metadata(i)]
		color.color = chosen.color
		idea.econ = float(chosen.econ)
		idea.social = float(chosen.social)
		show_ideas.call())
	var toggle: Button = dim.get_node("%found_toggle")
	toggle.pressed.connect(func():
		toggle.visible = false
		(dim.get_node("%ideas_col") as Control).visible = true
		for n: Node in toggle.get_parent().get_children():
			if n.is_in_group("founding"):
				(n as Control).visible = true
		name_edit.grab_focus())
	var warn: Label = dim.get_node("%warn")
	dim.get_node("%FundarPartido").pressed.connect(func():
		var clean := name_edit.text.strip_edges()
		if clean == "":
			warn.text = tr("Dê um nome ao partido.")
			return
		for p: Dictionary in data.parties:
			if String(p.name).to_lower() == clean.to_lower():
				warn.text = tr("Já existe um partido com esse nome.")
				return
		_close_modal(dim)
		on_done.call({"found": clean, "family": family.get_item_metadata(family.selected), "color": color.color, "econ": idea.econ, "social": idea.social, "role": role.value}))
	var cancel: Button = dim.get_node("%cancel")
	cancel.visible = not at_start
	cancel.pressed.connect(func(): _close_modal(dim))
	if at_start:
		apply_role.call()


# --- Legislation ---------------------------------------------------------------------------

## One window at a time: opening another swaps the one in front.
func _swap_law_screen(scene: PackedScene) -> Control:
	_drop_law_screens()
	return _modal(scene)


func _drop_law_screens() -> void:
	for child in modal_root.get_children():
		if child is LegislationCenter or child is LawEditor or child is NormPage or child is AmendmentEditor or child is NegotiationScreen:
			modal_root.remove_child(child)
			child.queue_free()


## The legislative center is a floating window like the others; editor, norm and amendment stay on top, on their own screen.
func open_legislation(tab := 0, message := "") -> void:
	if not playing or (modal_open and not _law_screen_open()):
		return
	_drop_law_screens()
	_sync_modal_state()
	var center: LegislationCenter = LEGISLATION_CENTER.instantiate()
	hud.show_legislation(center)
	center.setup(self, tab, message)


func close_legislation() -> void:
	hud.close_legislation()


## The legislative center window, if it is open.
func legislation_center() -> LegislationCenter:
	return hud.legislation_center()


func _sync_modal_state() -> void:
	var another := false
	for child: Node in modal_root.get_children():
		if child != start_screen and child != _loading_screen and not child.is_queued_for_deletion() and child.visible:
			another = true
	modal_open = another
	map.interactive = not another


func reopen_legislation(tab := 0, message := "") -> void:
	open_legislation(tab, message)


func _law_screen_open() -> bool:
	for child in modal_root.get_children():
		if child is LegislationCenter or child is LawEditor or child is NormPage or child is AmendmentEditor or child is NegotiationScreen:
			return true
	return false


func open_law_editor(norm: Dictionary, version := -1) -> void:
	var dim: LawEditor = _swap_law_screen(LAW_EDITOR)
	dim.setup(self, norm, version)


func close_law_screen(_screen: Control, message := "") -> void:
	open_legislation(0, message)


func open_norm(norm: Dictionary, message := "") -> void:
	var dim: NormPage = _swap_law_screen(NORM_PAGE)
	dim.setup(self, norm)
	(dim.get_node("%feedback") as Label).text = message


func open_negotiation(norm: Dictionary) -> void:
	var dim: NegotiationScreen = _swap_law_screen(NEGOTIATION)
	dim.setup(self, norm)


func open_amendment_editor(norm: Dictionary) -> void:
	var dim: AmendmentEditor = _swap_law_screen(AMENDMENT_EDITOR)
	dim.setup(self, norm)


# --- Character creator ---------------------------------------------------------

func _open_creator(character: Dictionary, on_done: Callable) -> void:
	var dim := _modal(CREATOR)
	var country := _creator_country()
	var group := Names.group_for(country.iso, country.region)
	var view: Countryball = dim.get_node("%view")
	view.show_person(character, country.iso)
	(dim.get_node("%country_label") as Label).text = tr("Bandeira: %s") % country.name
	var first_edit: LineEdit = dim.get_node("%first_name_edit")
	var last_edit: LineEdit = dim.get_node("%last_name_edit")
	var show_name := func():
		first_edit.text = character.first_name
		last_edit.text = character.last_name
	show_name.call()
	first_edit.text_changed.connect(func(t: String):
		character["first_rolled"] = false
		Character.set_names(character, t.strip_edges(), character.last_name))
	last_edit.text_changed.connect(func(t: String):
		character["last_rolled"] = false
		Character.set_names(character, character.first_name, t.strip_edges()))
	dim.get_node("%roll_name").pressed.connect(func():
		Character.reroll_name(character, group, world.rng)
		show_name.call())
	var gender_buttons := {"m": dim.get_node("%gender_m"), "f": dim.get_node("%gender_f")}
	var show_gender := func():
		for g: String in gender_buttons:
			(gender_buttons[g] as Button).set_pressed_no_signal(character.gender == g)
		view.queue_redraw()
	show_gender.call()
	for g: String in gender_buttons:
		(gender_buttons[g] as Button).pressed.connect(func():
			if character.gender != g:
				Character.set_gender(character, g, group, world.rng)
				show_name.call()
			show_gender.call())
	var age_slider: HSlider = dim.get_node("%age_slider")
	var age_label: Label = dim.get_node("%age_label")
	var year_now: int = world.year
	age_slider.value = clampf(float(year_now - int(character.get("birth_year", year_now - 50))), age_slider.min_value, age_slider.max_value)
	age_label.text = tr("%d anos") % int(age_slider.value)
	age_slider.value_changed.connect(func(v: float):
		character["birth_year"] = year_now - int(v)
		age_label.text = tr("%d anos") % int(v))
	dim.get_node("%Aleatorio").pressed.connect(func():
		var fresh := Character.random(world.rng, country.iso, country.region)
		for key: String in fresh:
			character[key] = fresh[key]
		_close_modal(dim)
		_open_creator(character, on_done))
	dim.get_node("%Confirmar").pressed.connect(func():
		if Character.full_name(character) == "":
			Character.reroll_name(character, group, world.rng)
		elif String(character.first_name) == "":
			Character.set_names(character, Names.first(group, character.gender, world.rng), character.last_name)
		_close_modal(dim)
		on_done.call(character))


## The character's country in the creator: the one chosen on the start screen or the match's; if it ceased to exist,
## whoever took it, which is where the new character will govern.
func _creator_country() -> Country:
	var c: Country = world.player if playing or _start_pick == null else _start_pick
	if c != null and not c.alive:
		c = world.countries[c.annexed_by] if c.annexed_by >= 0 else world.usa
	return c


func _show_prompt(p: Dictionary) -> void:
	var dim := _modal(PROMPT, p.title, p.get("text", ""))
	var col: Control = dim.get_node("%col")
	for opt: Dictionary in p.options:
		var box: Control = PROMPT_OPTION.instantiate()
		var b: Button = box.get_node("%pick")
		b.text = opt.label
		b.pressed.connect(func():
			if opt.has("fn"):
				opt.fn.call()
			_close_modal(dim))
		var hint: Label = box.get_node("%hint")
		hint.text = String(opt.get("hint", ""))
		hint.visible = hint.text != ""
		col.add_child(box)


func _confirm(text: String, fn: Callable) -> void:
	var dim := _modal(CONFIRM, "", text)
	dim.get_node("%Confirmar").pressed.connect(func():
		fn.call()
		_close_modal(dim))
	dim.get_node("%Cancelar").pressed.connect(func(): _close_modal(dim))


func _open_menu() -> void:
	if modal_open:
		return
	var dim := _modal(PAUSE_MENU)
	dim.get_node("%VoltarAoJogo").pressed.connect(func(): _close_modal(dim))
	dim.get_node("%SalvarPartida").pressed.connect(func():
		_save_game()
		_close_modal(dim))
	var load_button: Button = dim.get_node("%CarregarPartida")
	load_button.visible = SaveService.has_save()
	load_button.pressed.connect(func():
		_close_modal(dim)
		_load_game())
	dim.get_node("%NovaPartida").pressed.connect(func():
		_close_modal(dim)
		_restart())
	dim.get_node("%MenuDebugF12").pressed.connect(func():
		_close_modal(dim)
		if not hud.debug.visible:
			hud.debug.toggle())
	dim.get_node("%ComoJogar").pressed.connect(func():
		_close_modal(dim)
		_show_help())
	dim.get_node("%Configuracoes").pressed.connect(func():
		_close_modal(dim)
		_open_settings())
	dim.get_node("%Sair").pressed.connect(func(): get_tree().quit())
	var quit_office: Button = dim.get_node("%Renunciar")
	quit_office.visible = world.in_office
	quit_office.pressed.connect(func():
		_close_modal(dim)
		_confirm(tr("Renunciar ao cargo? Isso encerra a sua carreira, e depois você escolhe entre um novo jogo e um novo personagem."), world.resign))


func _show_help() -> void:
	var dim := _modal(HELP)
	dim.get_node("%Entendi").pressed.connect(func(): _close_modal(dim))


func _on_game_ended(result: Dictionary) -> void:
	var titles := {
		"impeachment": tr("Impeachment"), "golpe": tr("Deposto"), "renuncia": tr("Renúncia"), "assassinato": tr("Assassinato"), "morte": tr("Fim da vida"),
	}
	var dim := _modal(GAME_OVER, titles.get(result.reason, tr("Fim de jogo")), result.text)
	var c := world.player
	var pc_ratio := (c.y / c.pop) / c.pc0
	(dim.get_node("%score") as Label).text = tr("Pontuação final: %s") % UiKit.thousand(result.score)
	(dim.get_node("%stats") as Label).text = tr("Tempo no poder: %s anos  ·  Reeleições: %d\nPIB per capita real: %s vezes o de 2025\nDívida/PIB: %s  ·  Inflação: %s  ·  Influência: %dº no mundo") % [
		UiKit.num(result.years, 1), result.mandates, UiKit.num(pc_ratio, 2), UiKit.pct(c.debt_ratio, 0), UiKit.pct(c.pi_yoy),
		world.rank_of(c, func(x: Country): return x.influence)]
	dim.get_node("%NovaPartida").pressed.connect(func():
		_close_modal(dim)
		_restart())
	dim.get_node("%NovoPersonagem").pressed.connect(func():
		_close_modal(dim)
		_new_character())


## The match continues with another person: in the same country, or in whoever took it if it ceased to exist.
func _new_character() -> void:
	var home := _creator_country()
	_open_creator(Character.random(world.rng, home.iso, home.region), func(ch):
		world.assume_new_character(ch)
		hud.refresh_leader()
		hud.refresh(true)
		map.refresh_colors()
		if world.player.dem < Politics.FREE_PARLIAMENT_DEM:
			return
		_open_party_picker(world.player, false, func(choice):
			var r := _apply_party_choice(choice, false)
			hud._politics.say(r.msg, not r.ok)
			hud.refresh(true)))


func open_treaty(target: Country) -> void:
	if target == null or modal_open:
		return
	var dim := _modal(TREATY, tr("Tratado com %s") % target.name, tr("O líder de lá é %s (%s).") % [world.politics.leader_of(target.iso).get("name", ""), Dialogue.temper(world.politics.leader_of(target.iso))])
	var pick: OptionButton = dim.get_node("%type_pick")
	var desc: Label = dim.get_node("%desc")
	for key: String in Treaties.TYPES:
		pick.add_item(tr(Treaties.TYPES[key].label))
		pick.set_item_metadata(pick.item_count - 1, key)
	var show_desc := func(i: int):
		var def: Dictionary = Treaties.TYPES[pick.get_item_metadata(i)]
		desc.text = "%s %s" % [tr(def.desc), tr("Vale por %d anos.") % int(def.term) if int(def.term) > 0 else tr("Sem prazo.")]
	pick.item_selected.connect(show_desc)
	show_desc.call(0)
	var note: Label = dim.get_node("%feedback")
	dim.get_node("%propose").pressed.connect(func():
		var r: Dictionary = world.treaties.propose(world, target, pick.get_item_metadata(pick.selected))
		note.text = r.msg
		note.add_theme_color_override("font_color", UiKit.GREEN if r.get("accepted", false) else UiKit.RED))
	dim.get_node("%close").pressed.connect(func(): _close_modal(dim))
	(dim.get_node("%propose") as Button).disabled = not world.in_office


func open_election_report() -> void:
	var report: Dictionary = world.politics.data_of(world.player.iso).get("last_election", {})
	if report.is_empty() or modal_open:
		return
	var dim := _modal(ELECTION_REPORT, tr("Eleição de %s em %s") % [report.date, report.country])
	var lines := [
		tr("[color=#8ba2af]Sistema:[/color] %s  ·  cláusula de barreira de %d%%") % [tr(Elections.SYSTEMS[report.system]), roundi(float(report.threshold) * 100.0)],
		tr("[color=#8ba2af]Regime:[/color] %s") % tr(Elections.HEADS[report.head_system]),
		tr("[color=#8ba2af]Comparecimento:[/color] %s  ·  %d distritos") % [UiKit.pct(float(report.turnout), 0), int(report.district_total)],
	]
	if not report.head.is_empty():
		lines.append(tr("[color=#8ba2af]Chefe de governo:[/color] %s, com %s, em %d turno(s)") % [report.head.name, UiKit.pct(float(report.head.share), 0), int(report.head.rounds)])
	lines.append("")
	for p: Dictionary in report.parties:
		lines.append(tr("[color=#%s]■[/color] %s: %s dos votos, %d deputados, %d senadores") % [p.color.to_html(false), p.name, UiKit.pct(float(p.vote), 0), int(p.seats), int(p.upper)])
	lines.append("")
	lines.append("[color=#f2b33d]Distritos[/color]")
	for d: Dictionary in report.districts:
		lines.append(tr("%s: %d cadeiras, %s mi de habitantes, maioria de %s") % [d.name, int(d.seats), UiKit.num(float(d.population), 1), d.winner])
	(dim.get_node("%report") as RichTextLabel).text = "\n".join(lines)
	dim.get_node("%close").pressed.connect(func(): _close_modal(dim))


func _restart() -> void:
	join_sim()
	playing = false
	prompts.clear()
	hud.visible = false
	_show_loading(tr("Preparando o mundo..."))
	var fresh := GameWorld.new()
	await _wait_task(WorkerThreadPool.add_task(fresh.setup.bind(0), true, "mundo"))
	_adopt_world(fresh)
	_start_pick = null
	_build_start_screen()
	_hide_loading()


# --- Salvar / carregar -----------------------------------------------------------

## Writes to a temporary file, checks the reading and only then swaps: a failure midway
## does not corrupt the previous save, which is still kept as a backup copy. Runs on another thread.
func _save_game() -> void:
	join_sim()
	_run_on_worker(_write_save)


func _write_save() -> void:
	var error := SaveService.write(world)
	if error != "":
		world.emit_news(error, "crise", null)
		return
	world.emit_news(tr("Partida salva."), "politica", null)


## Reads the file and builds the new world on another thread. The current world is only swapped if everything goes well.
func _load_game() -> void:
	join_sim()
	var was_playing := playing
	playing = false
	_show_loading(tr("Carregando a partida..."))
	var box := {"world": null}
	await _wait_task(WorkerThreadPool.add_task(func(): box.world = SaveService.read(), true, "carregar"))
	var fresh: GameWorld = box.world
	if fresh == null:
		playing = was_playing
		_hide_loading()
		return
	prompts.clear()
	_adopt_world(fresh)
	_enter_game()
	_set_speed(0)
	_hide_loading()
