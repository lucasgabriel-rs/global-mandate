extends Node
## Ponto de entrada: tela inicial, relógio em tempo real, decisões, menu e fim de jogo.

const SAVE_PATH := "user://mandato.save"
const BACKUP_PATH := "user://mandato.bak"
## Na velocidade normal, cada 0,05 s reais é 1 minuto de jogo. Os valores multiplicam isso.
const SECONDS_PER_MINUTE := 0.05
const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const MAX_MINUTES_PER_FRAME := 60
const START_SCREEN := preload("res://scenes/ui/start_screen.tscn")
const LOADING_SCREEN := preload("res://scenes/ui/loading_screen.tscn")
## Tempo por quadro para criar nós do mapa na thread principal, para a animação de carga não engasgar.
const BOOT_SLICE_USEC := 6000
const PAUSE_MENU := preload("res://scenes/ui/modals/pause_menu.tscn")
const HELP := preload("res://scenes/ui/modals/help.tscn")
const CONFIRM := preload("res://scenes/ui/modals/confirm.tscn")
const PROMPT := preload("res://scenes/ui/modals/prompt.tscn")
const GAME_OVER := preload("res://scenes/ui/modals/game_over.tscn")
const CREATOR := preload("res://scenes/ui/modals/creator.tscn")
const PARTY_PICKER := preload("res://scenes/ui/modals/party_picker.tscn")
const PARTY_DETAIL := preload("res://scenes/ui/modals/party_detail.tscn")
const MINISTER_PICKER := preload("res://scenes/ui/modals/minister_picker.tscn")
const TALK := preload("res://scenes/ui/modals/talk.tscn")
const MEMBER_ROW := preload("res://scenes/ui/rows/member_row.tscn")
const PARTY_PICK_ROW := preload("res://scenes/ui/rows/party_pick_row.tscn")
const TALK_OPTION := preload("res://scenes/ui/rows/talk_option.tscn")
const PROMPT_OPTION := preload("res://scenes/ui/rows/prompt_option.tscn")
const LEGISLATION_CENTER := preload("res://scenes/ui/legislation/legislation_center.tscn")
const LAW_EDITOR := preload("res://scenes/ui/legislation/law_editor.tscn")
const NORM_PAGE := preload("res://scenes/ui/legislation/norm_page.tscn")
const AMENDMENT_EDITOR := preload("res://scenes/ui/legislation/amendment_editor.tscn")
const NEGOTIATION := preload("res://scenes/ui/legislation/negotiation.tscn")
const TREATY := preload("res://scenes/ui/modals/treaty.tscn")
const ELECTION_REPORT := preload("res://scenes/ui/modals/election_report.tscn")
## Menor janela que ainda deixa a interface legível.
const MIN_WINDOW := Vector2i(1024, 576)

var world: GameWorld
var start_screen: Control
## Abrindo, carregando ou recomeçando: não há mundo pronto para a interface usar.
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
var _rate_clock := 0
var _rate_usec := 0
var _skip_left := 0
var _skip_total := 0
var _skip_before := {}
var _skip_news: Array = []


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
	_build_start_screen()
	_hide_loading()
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
	if OS.get_cmdline_user_args().has("--ui-layout"):
		autotest = load("res://tests/ui_layout.gd")
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
# O mundo só tem um dono de cada vez. A interface o usa livremente na thread principal, até _launch_sim
# entregá-lo a uma thread de trabalho e marcar world.busy. Enquanto isso, os quadros seguem desenhando, mas
# ninguém lê nem muda o mundo: _process retorna antes, e qualquer clique ou tecla chama join_sim, que espera a
# thread acabar. Os sinais da simulação ficam na fila e são entregues em join_sim, já de volta à thread principal.

## Agenda um trabalho sobre o mundo. Só começa depois que os nós terminam de se desenhar neste quadro.
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


## Devolve o mundo à thread principal, esperando o que ainda estiver rodando.
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
	# Passar o mouse não muda nada no mundo. Clique, arraste e tecla precisam dele de volta primeiro.
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


## Espera um trabalho em segundo plano sem parar a tela.
func _wait_task(id: int) -> void:
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)


## Abertura do jogo: o mapa e o mundo se montam ao mesmo tempo, em outras threads.
func _boot() -> void:
	_show_loading("Preparando o mundo...")
	await get_tree().process_frame
	var fresh := GameWorld.new()
	var world_task := WorkerThreadPool.add_task(fresh.setup.bind(0), true, "mundo")
	var data_task := WorkerThreadPool.add_task(map.load_feature_data, true, "mapa")
	await _wait_task(data_task)
	var shapes := WorkerThreadPool.add_group_task(map.prepare_feature, map.feature_count(), -1, true, "triangulação")
	while not WorkerThreadPool.is_group_task_completed(shapes):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(shapes)
	(_loading_screen.get_node("%status") as Label).text = "Desenhando o mapa..."
	while not map.build_features_slice(BOOT_SLICE_USEC):
		await get_tree().process_frame
	await _wait_task(world_task)
	_adopt_world(fresh)


## Espera tudo o que está em segundo plano acabar. Para os testes e para quem precisa do resultado.
func idle() -> void:
	join_sim()
	while loading:
		await get_tree().process_frame


# --- Tela inicial --------------------------------------------------------------

func _build_start_screen() -> void:
	start_screen = START_SCREEN.instantiate()
	modal_root.add_child(start_screen)
	map.frame_region(10.0, get_viewport().get_visible_rect().size.x - 400.0)
	_start_title = start_screen.get_node("%start_title")
	_start_info = start_screen.get_node("%start_info")
	_start_button = start_screen.get_node("%start_button")
	# Cada botão pick_XXX do editor abre o país com aquele código ISO.
	for b: Node in start_screen.get_node("%pick_BRA").get_parent().get_children():
		if b.name.begins_with("pick_"):
			var iso := String(b.name).trim_prefix("pick_")
			b.pressed.connect(func(): _pick_start(world.by_iso[iso]))
	var diff_buttons := {"facil": start_screen.get_node("%diff_facil"), "normal": start_screen.get_node("%diff_normal"), "dificil": start_screen.get_node("%diff_dificil")}
	var style_diff := func(sel: String):
		_difficulty = sel
		for k: String in diff_buttons:
			(diff_buttons[k] as Button).add_theme_color_override("font_color", UiKit.ACCENT if k == sel else UiKit.TEXT)
	for k: String in diff_buttons:
		diff_buttons[k].pressed.connect(style_diff.bind(k))
	style_diff.call("normal")
	_start_button.pressed.connect(func(): _open_creator(Character.random(world.rng), func(ch):
		_open_party_picker(_start_pick, true, func(choice): _begin(ch, choice))))
	var saved: Button = start_screen.get_node("%continue_game")
	saved.visible = FileAccess.file_exists(SAVE_PATH)
	saved.pressed.connect(_load_game)


func _pick_start(c: Country) -> void:
	if c == null or start_screen == null:
		return
	_start_pick = c
	map.select(c)
	_start_title.text = c.name
	_start_button.disabled = false
	var regime := "Democracia: eleição a cada 4 anos" if c.dem >= 6.0 else ("Regime híbrido: eleição a cada 4 anos" if c.dem >= 4.0 else "Regime autoritário: risco de golpe e revolta")
	var lines := [
		regime,
		"PIB: %s  ·  per capita: US$ %s" % [UiKit.money(c.y_usd()), UiKit.thousand(c.gdp_pc())],
		"População: %s mi  ·  crescimento potencial: %s" % [UiKit.num(c.pop, 1), UiKit.pct(c.g0)],
		"Inflação: %s  ·  juro: %s  ·  desemprego: %s" % [UiKit.pct(c.pi_yoy), UiKit.pct(c.rate), UiKit.pct(c.unemp)],
		"Dívida/PIB: %s  ·  juros da dívida: %s do PIB" % [UiKit.pct(c.debt_ratio, 0), UiKit.pct(c.avg_rate * c.debt_ratio)],
		"Tropas: %s mil  ·  ogivas: %s" % [UiKit.thousand(c.troops), UiKit.thousand(c.nukes)],
	]
	if c.peg == 2:
		lines.append("Moeda: euro (juros definidos pelo BCE)")
	elif c.peg == 1:
		lines.append("Moeda ancorada no dólar")
	if world.diplomacy.in_war(c.idx):
		lines.append("EM GUERRA no início da partida")
	_start_info.text = "\n".join(lines)


func _begin(character := {}, choice := {}) -> void:
	if _start_pick == null:
		return
	world.leader = character if not character.is_empty() else Character.random(world.rng)
	world.set_player(_start_pick, _difficulty)
	_apply_party_choice(choice, true)
	world.diplomacy.update_prod_factors(world)
	_enter_game()
	map.select(null)
	map.reset_view()
	map.focus_on(_start_pick)
	if world.in_office:
		world.emit_news("%s toma posse em %s. O mundo observa." % [world.leader.name, _start_pick.name], "politica", _start_pick)
	else:
		world.emit_news("%s lidera a oposição em %s contra o governo de %s." % [world.leader.name, _start_pick.name, world.politics.ruling_party(_start_pick.iso).get("name", "")], "politica", _start_pick)


func _enter_game() -> void:
	playing = true
	if world.leader.is_empty():
		# Save de antes do criador de personagem: gera um líder fixo para aquele país.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(world.player.iso)
		world.leader = Character.random(rng)
	if start_screen:
		start_screen.queue_free()
		start_screen = null
	hud.visible = true
	hud.bind(world, map)
	map.refresh_colors()
	_set_speed(1)


# --- Relógio -------------------------------------------------------------------

func _process(delta: float) -> void:
	if loading:
		return
	if _sim_task >= 0:
		if not WorkerThreadPool.is_task_completed(_sim_task):
			# O relógio espera a thread: o tempo não se perde, e a tela continua desenhando.
			if speed > 0:
				accumulator = minf(accumulator + delta / SECONDS_PER_MINUTE * SPEEDS[speed], float(MAX_MINUTES_PER_FRAME))
			return
		join_sim()
	if not playing:
		return
	if not prompts.is_empty() and not modal_open:
		_show_prompt(prompts.pop_front())
	if _skip_left > 0:
		_run_skip()
	elif speed > 0 and not modal_open and not world.over and not hud.border.active:
		accumulator += delta / SECONDS_PER_MINUTE * SPEEDS[speed]
		var ticks := 0
		while accumulator >= 1.0 and ticks < MAX_MINUTES_PER_FRAME:
			accumulator -= 1.0
			# A virada do dia é o que pesa: ela roda em outra thread, e o resto do relógio espera.
			if world.minute + 1 >= world.MINUTES_PER_DAY:
				_run_on_worker(world.tick_minute)
				break
			world.tick_minute()
			ticks += 1
			if not prompts.is_empty():
				accumulator = 0.0
				break
		accumulator = minf(accumulator, float(MAX_MINUTES_PER_FRAME))
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


## Avança dias de uma vez: a simulação roda cada dia normalmente, sem esperar o relógio. O horário
## não muda. Uma decisão no meio do caminho interrompe o avanço, que continua depois da resposta.
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


## Na thread de trabalho: avança até acabar ou até surgir algo que precise do jogador.
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


## Ritmo real do relógio na tela, medido a cada segundo: mostra se a velocidade escolhida está valendo.
func _measure_rate() -> void:
	var now := Time.get_ticks_usec()
	if now - _rate_usec < 1000000:
		return
	var clock := _clock_minutes()
	var rate := float(clock - _rate_clock) / ((now - _rate_usec) / 1000000.0)
	_rate_clock = clock
	_rate_usec = now
	var running: bool = speed > 0 and not modal_open and not world.over and not hud.border.active and _skip_left == 0
	hud.set_rate_display(rate if running else 0.0, SPEEDS[speed] * (1.0 / SECONDS_PER_MINUTE) if running else 0.0)


func _clock_minutes() -> int:
	return world.day_index * world.MINUTES_PER_DAY + world.minute


func _set_speed(s: int) -> void:
	if s > 0:
		last_speed = s
	if s != speed and world:
		print("velocidade: %s, relógio em %s" % ["pausa" if s == 0 else "%dx" % int(SPEEDS[s]), world.date_string()])
		# A próxima medida do ritmo não mistura a velocidade anterior.
		_rate_clock = _clock_minutes()
		_rate_usec = Time.get_ticks_usec()
		var expected: float = SPEEDS[s] * (1.0 / SECONDS_PER_MINUTE)
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

## Abre uma janela da pasta scenes/ui/modals. Título e texto vazios mantêm o que está na cena.
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
	# A resposta de uma janela pode ter aberto outra: fim de jogo, conversa, novo personagem.
	var another := false
	for child: Node in modal_root.get_children():
		if child != dim and child != start_screen and child != _loading_screen and not child.is_queued_for_deletion():
			another = true
	modal_open = another
	map.interactive = not another
	# Salvar deixa o mundo com outra thread: a tela se atualiza quando ele voltar.
	if world.busy or _sim_pending.is_valid():
		return
	hud.refresh(true)
	map.refresh_colors()


# --- Escolha de partido -------------------------------------------------------------

## choice: {"id": partido existente} ou {"found": nome, "family": família, "color": cor}.
func _apply_party_choice(choice: Dictionary, at_start: bool) -> Dictionary:
	# Só quem funda um partido escolhe as ideias; quem entra em outro adota as dele.
	if choice.has("found"):
		world.leader["econ"] = choice.econ
		world.leader["social"] = choice.social
	# O papel vem antes do partido: na oposição, entrar em um partido não o faz governar.
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
	var face: CharacterView = row.get_node("%face")
	face.character = world.leader if member.get("player", false) else Character.for_politician(member)
	var text := "%s, %d anos  ·  %s  ·  competência %d%%%s" % [member.name, People.age_of(member, world), party.short, int(float(member.competence) * 100.0), "  ·  doente" if member.has("illness") else ""]
	var pick: Button = row.get_node("%pick")
	var label: Label = row.get_node("%label")
	pick.visible = on_press.is_valid()
	label.visible = not on_press.is_valid()
	if on_press.is_valid():
		pick.text = text
		pick.pressed.connect(on_press)
	else:
		label.text = ("Você: " if member.get("player", false) else "") + text
	var compass: CompassView = row.get_node("%compass")
	compass.points = [{"econ": member.econ, "social": member.social, "color": Color.WHITE, "big": true}]
	return row


func _open_party_detail(id: int) -> void:
	var party: Dictionary = world.politics.party_of(world.player.iso, id)
	var dim := _modal(PARTY_DETAIL, party.name, "%s  ·  %d assentos  ·  %s dos votos. A bússola do partido é a média dos políticos." % [Politics.FAMILIES[party.family].label, int(party.seats), UiKit.pct(party.support, 0)])
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


func _open_minister_picker(post: String) -> void:
	var portfolio := {}
	for p: Dictionary in world.politics.portfolios(world):
		if p.id == post:
			portfolio = p
	var dim := _modal(MINISTER_PICKER, "Ministério: %s" % portfolio.label, String(portfolio.desc))
	var rows: Control = dim.get_node("%rows")
	for e: Dictionary in world.politics.eligible_ministers(world, post):
		rows.add_child(_member_row(e.member, e.party, func():
			var r: Dictionary = world.politics.appoint(world, post, e.party.id, e.member.id)
			hud._cabinet.say(("%s assume a pasta." % e.member.name) if r.ok else r.msg, not r.ok)
			_close_modal(dim)))
	dim.get_node("%Cancelar").pressed.connect(func(): _close_modal(dim))


# --- Conversa com líderes -----------------------------------------------------------

func _open_talk(target: Country, invited := false) -> void:
	var opened := Dialogue.start(world, target, invited)
	if not opened.ok:
		hud._set_feedback(opened.msg)
		return
	var theirs := Dialogue.leader_of(world, target)
	var party_now: Dictionary = world.politics.player_party(world)
	var dim := _modal(TALK, "Conversa com %s" % theirs.get("name", "o líder"), "%s  ·  %s  ·  %s, %d anos, %s" % [target.name, world.politics.ruling_party(target.iso).get("name", ""), theirs.get("name", ""), People.age_of(theirs, world), Dialogue.temper(theirs)])
	(dim.get_node("%face") as CharacterView).character = Character.for_politician(theirs)
	var compass: CompassView = dim.get_node("%talk_compass")
	compass.points = [{"econ": theirs.get("econ", 0.0), "social": theirs.get("social", 0.0), "color": Color("f2b33d"), "big": true}, {"econ": party_now.get("econ", 0.0), "social": party_now.get("social", 0.0), "color": Color.WHITE, "big": true}]
	(dim.get_node("%legend") as Label).text = "Dourado: %s. Branco: seu partido." % theirs.get("name", "líder")
	(dim.get_node("%talk_reply") as Label).text = "“%s”" % opened.greeting
	dim.get_node("%say_end").pressed.connect(func(): _close_modal(dim))
	_fill_talk(dim, target, Dialogue.TURNS_PER_MEETING)


func _fill_talk(dim: Control, target: Country, turns: int) -> void:
	var box: Control = dim.get_node("%choices")
	var remaining: Label = dim.get_node("%remaining")
	var reply: Label = dim.get_node("%talk_reply")
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var going: bool = turns > 0 and target.alive and prompts.is_empty()
	box.visible = going
	remaining.text = "Falas restantes: %d" % turns if going else "A conversa terminou."
	if not going:
		return
	for option: Dictionary in Dialogue.options(world, target):
		var b: Button = TALK_OPTION.instantiate()
		b.name = "say_" + String(option.id)
		b.text = option.label
		b.tooltip_text = option.hint
		b.pressed.connect(func():
			var result := Dialogue.choose(world, target, option.id)
			reply.text = "“%s”" % result.reply
			reply.add_theme_color_override("font_color", UiKit.GREEN if result.accepted else UiKit.RED)
			hud.refresh(true)
			_fill_talk(dim, target, turns - 1))
		box.add_child(b)


func _open_party_picker(country: Country, at_start: bool, on_done: Callable) -> void:
	var data: Dictionary = world.politics.data_of(country.iso)
	var body := "Todo político pertence a um partido. Escolha um deles ou crie o seu, e decida se começa no governo ou na oposição." if at_start else "Só é possível mudar de partido uma vez por ano. O partido novo só ganha assentos na próxima eleição."
	var dim := _modal(PARTY_PICKER, "Escolha seu partido em %s" % country.name, body)
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
			role_buttons.opposition.tooltip_text = "Regimes fechados não têm eleições."
		var ruling_name: String = world.politics.ruling_party(country.iso).get("name", "")
		(dim.get_node("%ruling_info") as Label).text = "Hoje governa: %s." % ruling_name if not closed else "Regime fechado, sem eleições: só é possível governar."
	var ordered: Array = data.parties.duplicate()
	ordered.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	for p: Dictionary in ordered:
		var row: Control = PARTY_PICK_ROW.instantiate()
		(row.get_node("%chip") as ColorRect).color = p.color
		var mine: bool = int(data.player_party) == p.id and not at_start
		var b: Button = row.get_node("%pick")
		b.text = "%s%s  ·  %s  ·  %s dos votos  ·  %d de %d assentos" % ["Ficar em " if mine else "", p.name, Politics.FAMILIES[p.family].label, UiKit.pct(p.support, 0), int(p.seats), int(data.seats_total)]
		b.tooltip_text = "%s. Clique para escolher." % p.name
		b.pressed.connect(func():
			_close_modal(dim)
			on_done.call({"id": p.id, "role": role.value}))
		party_buttons[int(p.id)] = b
		party_rows.add_child(row)
	var name_edit: LineEdit = dim.get_node("%party_name")
	var family: OptionButton = dim.get_node("%party_family")
	for key: String in Politics.FAMILIES:
		family.add_item(Politics.FAMILIES[key].label)
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
			warn.text = "Dê um nome ao partido."
			return
		for p: Dictionary in data.parties:
			if String(p.name).to_lower() == clean.to_lower():
				warn.text = "Já existe um partido com esse nome."
				return
		_close_modal(dim)
		on_done.call({"found": clean, "family": family.get_item_metadata(family.selected), "color": color.color, "econ": idea.econ, "social": idea.social, "role": role.value}))
	var cancel: Button = dim.get_node("%cancel")
	cancel.visible = not at_start
	cancel.pressed.connect(func(): _close_modal(dim))
	if at_start:
		apply_role.call()


# --- Legislação ---------------------------------------------------------------------------

## Uma janela de cada vez: abrir outra troca a que está na frente.
func _swap_law_screen(scene: PackedScene) -> Control:
	_drop_law_screens()
	return _modal(scene)


func _drop_law_screens() -> void:
	for child in modal_root.get_children():
		if child is LegislationCenter or child is LawEditor or child is NormPage or child is AmendmentEditor or child is NegotiationScreen:
			modal_root.remove_child(child)
			child.queue_free()


func open_legislation(tab := 0, message := "") -> void:
	if not playing or (modal_open and not _law_screen_open()):
		return
	var dim: LegislationCenter = _swap_law_screen(LEGISLATION_CENTER)
	dim.setup(self, tab, message)


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
	open_legislation(1 if message != "" else 0, message)


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


# --- Criador de personagem ---------------------------------------------------------

func _open_creator(character: Dictionary, on_done: Callable) -> void:
	var dim := _modal(CREATOR)
	var view: CharacterView = dim.get_node("%view")
	view.character = character
	var name_edit: LineEdit = dim.get_node("%name_edit")
	name_edit.text = character.name
	name_edit.text_changed.connect(func(t): character.name = t)
	var age_slider: HSlider = dim.get_node("%age_slider")
	var age_label: Label = dim.get_node("%age_label")
	var year_now: int = world.year
	age_slider.value = clampf(float(year_now - int(character.get("birth_year", year_now - 50))), age_slider.min_value, age_slider.max_value)
	age_label.text = "%d anos" % int(age_slider.value)
	age_slider.value_changed.connect(func(v: float):
		character["birth_year"] = year_now - int(v)
		age_label.text = "%d anos" % int(v))
	var values := {}
	var sync := func():
		for key: String in values:
			(values[key] as Label).text = Character.option_label(key, int(character[key]))
		view.queue_redraw()
	for key: String in Character.SHAPES:
		var count := Character.option_count(key)
		var step := func(by: int):
			character[key] = posmod(int(character[key]) + by, count)
			sync.call()
		dim.get_node("%prev_" + key).pressed.connect(step.bind(-1))
		dim.get_node("%next_" + key).pressed.connect(step.bind(1))
		values[key] = dim.get_node("%value_" + key)
	_skin_picker(dim, character, view)
	_color_wheel(dim, character, view)
	sync.call()
	dim.get_node("%Aleatorio").pressed.connect(func():
		var fresh := Character.random(world.rng)
		for key: String in fresh:
			if key != "name":
				character[key] = fresh[key]
		_close_modal(dim)
		_open_creator(character, on_done))
	dim.get_node("%Confirmar").pressed.connect(func():
		if name_edit.text.strip_edges() == "":
			character.name = "Sem Nome"
		_close_modal(dim)
		on_done.call(character))


## Faixa de tons reais de pele: uma posição ao longo da escala, sem cor livre.
func _skin_picker(dim: Control, character: Dictionary, view: CharacterView) -> void:
	var slider: HSlider = dim.get_node("%skin_slider")
	slider.value = character.skin
	slider.value_changed.connect(func(v: float):
		character.skin = v
		view.queue_redraw())


## Roda de cor única: os botões escolhem o que ela está pintando.
func _color_wheel(dim: Control, character: Dictionary, view: CharacterView) -> void:
	var picker: ColorPicker = dim.get_node("%color_wheel")
	var target := {"key": "eyes_color"}
	var buttons := {}
	var select := func(key: String):
		target.key = key
		picker.color = character[key]
		for k: String in buttons:
			(buttons[k] as Button).add_theme_color_override("font_color", UiKit.ACCENT if k == key else UiKit.TEXT)
	for key: String in Character.COLOR_KEYS:
		var b: Button = dim.get_node("%paint_" + key)
		b.pressed.connect(select.bind(key))
		buttons[key] = b
	picker.color_changed.connect(func(c: Color):
		character[target.key] = c
		view.queue_redraw())
	select.call("eyes_color")


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
	load_button.visible = FileAccess.file_exists(SAVE_PATH)
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
	dim.get_node("%Sair").pressed.connect(func(): get_tree().quit())
	var quit_office: Button = dim.get_node("%Renunciar")
	quit_office.visible = world.in_office
	quit_office.pressed.connect(func():
		_close_modal(dim)
		_confirm("Renunciar ao cargo? Isso encerra a sua carreira, e depois você escolhe entre um novo jogo e um novo personagem.", world.resign))


func _show_help() -> void:
	var dim := _modal(HELP)
	dim.get_node("%Entendi").pressed.connect(func(): _close_modal(dim))


func _on_game_ended(result: Dictionary) -> void:
	var titles := {
		"impeachment": "Impeachment", "golpe": "Deposto", "renuncia": "Renúncia", "assassinato": "Assassinato", "morte": "Fim da vida",
	}
	var dim := _modal(GAME_OVER, titles.get(result.reason, "Fim de jogo"), result.text)
	var c := world.player
	var pc_ratio := (c.y / c.pop) / c.pc0
	(dim.get_node("%score") as Label).text = "Pontuação final: %s" % UiKit.thousand(result.score)
	(dim.get_node("%stats") as Label).text = "Tempo no poder: %s anos  ·  Reeleições: %d\nPIB per capita real: %s vezes o de 2025\nDívida/PIB: %s  ·  Inflação: %s  ·  Influência: %dº no mundo" % [
		UiKit.num(result.years, 1), result.mandates, UiKit.num(pc_ratio, 2), UiKit.pct(c.debt_ratio, 0), UiKit.pct(c.pi_yoy),
		world.rank_of(c, func(x: Country): return x.influence)]
	dim.get_node("%NovaPartida").pressed.connect(func():
		_close_modal(dim)
		_restart())
	dim.get_node("%NovoPersonagem").pressed.connect(func():
		_close_modal(dim)
		_new_character())


## A partida segue com outra pessoa: no mesmo país, ou em quem o tomou se ele deixou de existir.
func _new_character() -> void:
	_open_creator(Character.random(world.rng), func(ch):
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
	var dim := _modal(TREATY, "Tratado com %s" % target.name, "O líder de lá é %s (%s)." % [world.politics.leader_of(target.iso).get("name", ""), Dialogue.temper(world.politics.leader_of(target.iso))])
	var pick: OptionButton = dim.get_node("%type_pick")
	var desc: Label = dim.get_node("%desc")
	for key: String in Treaties.TYPES:
		pick.add_item(Treaties.TYPES[key].label)
		pick.set_item_metadata(pick.item_count - 1, key)
	var show_desc := func(i: int):
		var def: Dictionary = Treaties.TYPES[pick.get_item_metadata(i)]
		desc.text = "%s %s" % [def.desc, "Vale por %d anos." % int(def.term) if int(def.term) > 0 else "Sem prazo."]
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
	var dim := _modal(ELECTION_REPORT, "Eleição de %s em %s" % [report.date, report.country])
	var lines := [
		"[color=#8ba2af]Sistema:[/color] %s  ·  cláusula de barreira de %d%%" % [Elections.SYSTEMS[report.system], roundi(float(report.threshold) * 100.0)],
		"[color=#8ba2af]Regime:[/color] %s" % Elections.HEADS[report.head_system],
		"[color=#8ba2af]Comparecimento:[/color] %s  ·  %d distritos" % [UiKit.pct(float(report.turnout), 0), int(report.district_total)],
	]
	if not report.head.is_empty():
		lines.append("[color=#8ba2af]Chefe de governo:[/color] %s, com %s, em %d turno(s)" % [report.head.name, UiKit.pct(float(report.head.share), 0), int(report.head.rounds)])
	lines.append("")
	for p: Dictionary in report.parties:
		lines.append("[color=#%s]■[/color] %s: %s dos votos, %d deputados, %d senadores" % [p.color.to_html(false), p.name, UiKit.pct(float(p.vote), 0), int(p.seats), int(p.upper)])
	lines.append("")
	lines.append("[color=#f2b33d]Distritos[/color]")
	for d: Dictionary in report.districts:
		lines.append("%s: %d cadeiras, %s mi de habitantes, maioria de %s" % [d.name, int(d.seats), UiKit.num(float(d.population), 1), d.winner])
	(dim.get_node("%report") as RichTextLabel).text = "\n".join(lines)
	dim.get_node("%close").pressed.connect(func(): _close_modal(dim))


func _restart() -> void:
	join_sim()
	playing = false
	prompts.clear()
	hud.visible = false
	_show_loading("Preparando o mundo...")
	var fresh := GameWorld.new()
	await _wait_task(WorkerThreadPool.add_task(fresh.setup.bind(0), true, "mundo"))
	_adopt_world(fresh)
	_start_pick = null
	_build_start_screen()
	_hide_loading()


# --- Salvar / carregar -----------------------------------------------------------

## Escreve em um arquivo temporário, confere a leitura e só então troca: uma falha no meio do caminho
## não corrompe o save anterior, que ainda fica guardado como cópia de segurança. Roda em outra thread.
func _save_game() -> void:
	join_sim()
	_run_on_worker(_write_save)


func _write_save() -> void:
	var temp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		world.emit_news("Não foi possível salvar: erro %d." % FileAccess.get_open_error(), "crise", null)
		return
	f.store_var(world.to_dict())
	f.close()
	var check := FileAccess.open(temp, FileAccess.READ)
	var readable: bool = check != null and check.get_var() is Dictionary
	if check:
		check.close()
	if not readable:
		world.emit_news("Não foi possível salvar: o arquivo não pôde ser conferido.", "crise", null)
		return
	var folder := DirAccess.open("user://")
	if FileAccess.file_exists(SAVE_PATH):
		folder.rename(SAVE_PATH.get_file(), BACKUP_PATH.get_file())
	folder.rename(temp.get_file(), SAVE_PATH.get_file())
	world.emit_news("Partida salva.", "politica", null)


## Lê o arquivo e monta o mundo novo em outra thread. O mundo atual só é trocado se tudo der certo.
func _load_game() -> void:
	join_sim()
	var was_playing := playing
	playing = false
	_show_loading("Carregando a partida...")
	var box := {"world": null}
	await _wait_task(WorkerThreadPool.add_task(_read_save.bind(box), true, "carregar"))
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


static func _read_save(box: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var raw: Variant = f.get_var() if f else null
	if not raw is Dictionary:
		f = FileAccess.open(BACKUP_PATH, FileAccess.READ)
		raw = f.get_var() if f else null
	if not raw is Dictionary:
		return
	var fresh := GameWorld.new()
	fresh.setup()
	fresh.load_dict(raw)
	box.world = fresh
