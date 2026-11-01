extends Node
## Roteiro de teste da interface: joga sozinho, exercita cada aba e guarda capturas de tela.
## Uso: godot --path . -- --ui-test --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var step := 0
var wait := 0.0
var failures := 0
var saved_day := 0


func _ready() -> void:
	Legislation.skip_unit_approval = true
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)
	wait = 1.0


func _shot(name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name_])
	print("shot: ", name_)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FALHA: ", what)
	else:
		print("ok: ", what)


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	wait -= delta
	if wait > 0.0:
		return
	step += 1
	wait = 0.6
	var w: GameWorld = main.world
	match step:
		1:
			_shot("01_inicio")
			main._pick_start(w.by_iso["BRA"])
		2:
			_shot("02_escolha")
			_check(not main._start_button.disabled, "botão de início habilitado")
			main._begin()
			main._set_speed(3)
			main.start_skip(60)
		3:
			_check(main.playing, "partida iniciada")
		4:
			wait = 6.0
		5:
			_dismiss_prompts()
			_shot("03_painel")
			# Uma decisão aleatória pode pausar o jogo já no primeiro mês.
			_check(w.day_index > 25, "tempo passou (dia %d)" % w.day_index)
			main.hud._gov_tabs.current_tab = 1
		6:
			_dismiss_prompts()
			_shot("04_fiscal")
			main.hud._gov_tabs.current_tab = 2
		7:
			_dismiss_prompts()
			_shot("05_moeda")
			main.hud._gov_tabs.current_tab = 3
		8:
			_dismiss_prompts()
			_shot("06_comercio")
			main.hud._gov_tabs.current_tab = 4
		9:
			_dismiss_prompts()
			_shot("07_militar")
			main.hud._gov_tabs.current_tab = 5
		10:
			_dismiss_prompts()
			_shot("08_mundo")
			main.hud._gov_tabs.current_tab = 0
			main.map.select(w.by_iso["CHN"])
			main.hud.show_country(w.by_iso["CHN"])
		11:
			_dismiss_prompts()
			_shot("09_dossie")
			var rel: float = w.diplomacy.relation(w.player.idx, w.by_iso["CHN"].idx)
			main.hud._on_action("mission")
			_check(w.action_wait("mission", w.by_iso["CHN"]) > 0, "a mesma ação só se repete depois de um intervalo")
			_check(w.diplomacy.relation(w.player.idx, w.by_iso["CHN"].idx) > rel, "missão melhora relação")
			main.hud._on_mode("inflacao")
		12:
			_dismiss_prompts()
			_shot("10_modo_inflacao")
			main.hud._on_mode("relacoes")
		13:
			_dismiss_prompts()
			_shot("11_modo_relacoes")
			main.hud._on_mode("politico")
			w.offer_alliance(w.by_iso["PER"])
			w.diplomacy.declare_war(w.by_iso["IND"], w.by_iso["BGD"], w)
			main.map.select(w.by_iso["ARG"])
			main.hud.show_country(w.by_iso["ARG"])
			main.hud._gov_tabs.current_tab = 4
		14:
			_shot("11b_decisao")
			_dismiss_prompts()
			_shot("12_guerra_alheia")
			_dismiss_prompts()
			var r: Dictionary = w.do_action("war", w.by_iso["ARG"])
			_check(r.ok, "jogador declara guerra")
		15:
			wait = 3.0
		16:
			_dismiss_prompts()
			_shot("13_guerra_jogador")
			main._save_game()
			main.join_sim()
			_check(FileAccess.file_exists(main.SAVE_PATH), "arquivo salvo")
			main._set_speed(0)
			saved_day = w.day_index
		17:
			var y0: float = w.player.y
			main._load_game()
			_check(main.world.day_index == saved_day, "carregamento restaura a data (%d)" % main.world.day_index)
			_check(absf(main.world.player.y - y0) < 0.001 * y0 + 5.0, "carregamento restaura o PIB")
			_check(main.world.player.iso == "BRA", "carregamento restaura o jogador")
		18:
			main._set_speed(3)
			main.start_skip(30)
			wait = 3.0
		19:
			_dismiss_prompts()
			_check(main.world.day_index > 0, "jogo prossegue depois de carregar")
			_shot("14_depois_de_carregar")
			main.world.player.approval = 0.02
			main.world.player.next_election = main.world.year_float()
			main.world.player.dem = 7.0
			main.start_skip(60)
		20, 21, 22, 23, 24, 25, 26:
			# Só o modal de fim de jogo pode permanecer aberto.
			wait = 0.8
			main._set_speed(3)
			if not main.world.over:
				_dismiss_prompts()
		27:
			_shot("15_fim")
			_check(not main.world.in_office and not main.world.over, "derrota eleitoral leva à oposição (próxima eleição %.2f, ano %.2f)" % [main.world.player.next_election, main.world.year_float()])
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)


func _dismiss_prompts() -> void:
	# A demarcação para o relógio até o jogador decidir: aqui ele abre mão do território.
	if main.hud.border.active:
		print("demarcação aberta durante o roteiro: encerrando sem território")
		main.hud.border._on_decline()
	# Fecha decisões pendentes escolhendo a primeira opção, como um jogador faria.
	for dim in main.modal_root.get_children():
		if dim is ColorRect:
			var btn := _first_button(dim)
			if btn:
				btn.pressed.emit()


func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null
