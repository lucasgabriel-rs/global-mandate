extends Node
## Aperta todos os comandos do menu debug, um por vez, avançando alguns dias depois de cada um.
## Erros de script ficam no log logo depois da linha "debug: <comando>".
## Uso: godot --path . -- --ui-debug --shots=/caminho/da/pasta

var main: Node
var want_start := false
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var index := 0
var menu: DebugMenu
var restarts := 0
var phase := 0


func _ready() -> void:
	Legislation.skip_unit_approval = true
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)


func _shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])
	print("shot: ", name_)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _start_game() -> void:
	main._pick_start(main.world.by_iso["BRA"])
	main._begin()
	main._set_speed(0)
	menu = main.hud.debug
	menu.main = main
	if not menu.visible:
		menu.toggle()


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	get_viewport().push_input(e)


func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and not child.disabled:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null


func _command(label: String) -> int:
	for i in menu.commands.size():
		if menu.commands[i].label == label:
			return i
	failures += 1
	print("FAIL: comando não existe: ", label)
	return 0


## Limpa o que o comando abriu, como um jogador faria: janela, demarcação ou desenho.
func _settle() -> void:
	var guard := 0
	while guard < 12:
		guard += 1
		var opened := false
		for dim in main.modal_root.get_children():
			if dim is ColorRect and not dim.is_queued_for_deletion():
				var b := _last_choice(dim)
				if b:
					b.pressed.emit()
					opened = true
		if main.hud.border.active:
			main.hud.border._on_decline()
			opened = true
		if main.map.drawing:
			main.map.cancel_draft()
		if main.prompts.is_empty() and not opened:
			break
		if not main.prompts.is_empty() and not main.modal_open:
			main._show_prompt(main.prompts.pop_front())


## Fecha a janela de verdade: o criador abre com setas, então "Confirmar" vem antes da primeira opção.
func _last_choice(dim: Node) -> Button:
	var confirm := _named(dim, "Confirmar")
	return confirm if confirm else _first_button(dim)


func _named(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _named(child, text)
		if found:
			return found
	return null


func _click(screen: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = screen
		ev.global_position = screen
		ev.pressed = pressed
		get_viewport().push_input(ev)


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	if want_start:
		want_start = false
		if not main.playing:
			_start_game()
		return
	wait -= delta
	if wait > 0.0:
		return
	wait = 0.05
	match phase:
		0:
			_start_game()
			phase = 1
			wait = 0.5
		1:
			_check(menu.visible, "menu aberto")
			_key(KEY_F12)
			phase = 2
		2:
			_check(not menu.visible, "F12 fecha o menu")
			_key(KEY_F12)
			phase = 3
		3:
			_check(menu.visible, "F12 abre o menu")
			_shot("g1_menu")
			menu._search.text = "dilema"
			menu._apply_filter("dilema")
			phase = 4
			wait = 0.3
		4:
			_shot("g2_filtro")
			var shown := 0
			for row: Dictionary in menu._rows:
				for b: Button in row.buttons:
					if b.visible:
						shown += 1
			_check(shown == 9, "filtro mostra só os dilemas (%d)" % shown)
			menu._search.text = ""
			menu._apply_filter("")
			phase = 40
		40:
			# Clique real em um botão do painel.
			menu.set_meta("dp", float(main.world.politics.party_fund(main.world)))
			var b: Button = menu._rows[1].buttons[0]
			_click(b.get_global_rect().get_center())
			phase = 41
			wait = 0.2
		41:
			_check(main.world.politics.party_fund(main.world) > float(menu.get_meta("dp")), "clique no botão executa o comando")
			# Clique em um país no mapa muda o alvo, com o menu aberto.
			var pos: Vector2 = main.map.get_canvas_transform() * main.world.by_iso["USA"].center
			_click(pos)
			_check(menu.target == main.world.by_iso["USA"], "clique no mapa troca o alvo para EUA (%s)" % (menu.target.name if menu.target else "nenhum"))
			_check(menu._options.get_item_text(menu._options.selected) == "Estados Unidos", "lista mostra o alvo")
			_shot("g3_alvo")
			phase = 42
		42:
			_click(main.map.get_canvas_transform() * main.world.player.center)
			phase = 43
			wait = 0.3
		43:
			_shot("g4_proprio_pais")
			_own_country()
			phase = 5
		5:
			_effects()
			phase = 6
		6:
			_run_next()
		7:
			print("comandos executados: %d, reinícios: %d" % [menu.commands.size(), restarts])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			print("RESULT: ", failures, " failures")
			get_tree().quit(1 if failures > 0 else 0)


## O país do próprio jogador é um alvo válido, e cada comando de "Jogador" muda o que promete.
func _own_country() -> void:
	var w: GameWorld = main.world
	var me: Country = w.player
	_click(main.map.get_canvas_transform() * me.center)
	_check(menu.target == me, "clique no próprio país vira o alvo")
	_check(menu._options.get_item_text(menu._options.selected) == "%s (você)" % me.name, "lista mostra o próprio país")
	var war: Button = menu._buttons[_command("Declarar guerra ao alvo")]
	_check(war.disabled, "guerra contra si mesmo fica desativada")
	var relation: Button = menu._buttons[_command("Relação +100")]
	_check(relation.disabled, "relação consigo mesmo fica desativada")
	var wars: int = w.diplomacy.wars.size()
	menu.run(_command("Declarar guerra ao alvo"))
	_check(w.diplomacy.wars.size() == wars and menu._status.text.contains("outro país"), "comando recusado explica o motivo")
	var demand := me.demand_shock
	menu.run(_command("Recessão: Alvo"))
	_check(me.demand_shock < demand, "recessão no alvo atinge o próprio país")
	menu.run(_command("Crise bancária: Alvo"))
	_check(me.crisis_cooldown > 0.0, "crise bancária no alvo atinge o próprio país")
	var cases := [
		["Aprovação 90%", func(): return me.approval == 0.9],
		["Aprovação 5%", func(): return me.approval == 0.05],
		["Estabilidade 90%", func(): return me.stability == 0.9],
		["Estabilidade 5%", func(): return me.stability == 0.05],
		["Virar democracia", func(): return me.dem == 8.0],
		["Virar regime autoritário", func(): return me.dem == 2.0],
		["Virar democracia", func(): return me.dem == 8.0],
	]
	for case: Array in cases:
		menu.run(_command(case[0]))
		_check(case[1].call(), "efeito no próprio país: " + String(case[0]))
	var reserves := me.reserves
	menu.run(_command("Reservas +US$ 500 bi"))
	_check(me.reserves == reserves + 500.0, "efeito no próprio país: reservas")
	var debt := me.debt_loc
	menu.run(_command("Dívida +50% do PIB"))
	_check(me.debt_loc > debt, "efeito no próprio país: dívida")
	var troops := me.troops
	menu.run(_command("Tropas e equipamento x2"))
	_check(me.troops == troops * 2.0, "efeito no próprio país: tropas")
	var nukes := me.nukes
	menu.run(_command("Dar 1.000 ogivas"))
	_check(me.nukes == nukes + 1000, "efeito no próprio país: ogivas")
	menu.run(_command("Aprovação 90%"))
	menu.run(_command("Estabilidade 90%"))
	menu.set_target(w.by_iso["ARG"])
	_check(not war.disabled, "outro país reativa os comandos")
	main.map.select(null)
	main.hud.show_country(null)


## Confere o efeito real dos comandos principais.
func _effects() -> void:
	var w: GameWorld = main.world
	menu.set_target(w.by_iso["ARG"])
	var fund: float = w.politics.party_fund(w)
	menu.run(_command("Fundo do partido +20 unidades"))
	_check(w.politics.party_fund(w) > fund, "o fundo sobe")
	var day := w.day_index
	menu.run(_command("Avançar 1 dia"))
	_check(w.day_index == day + 1, "avança 1 dia")
	menu.run(_command("Crise bancária: Alvo"))
	_check(w.by_iso["ARG"].crisis_cooldown > 0.0, "crise bancária atinge o alvo")
	menu.run(_command("Declarar guerra ao alvo"))
	_check(w.diplomacy.at_war(w.player.idx, w.by_iso["ARG"].idx), "guerra declarada")
	_settle()
	menu.run(_command("Vitória por capitulação"))
	_check(not main.prompts.is_empty() or main.modal_open, "vitória abre a decisão")
	_settle()
	# A primeira opção da vitória anexa a Argentina: o alvo volta para o próprio país.
	if not w.by_iso["ARG"].alive:
		menu.run(_command("Reservas +US$ 500 bi"))
		_check(menu.target == w.player, "alvo anexado volta para o próprio país")
	menu.set_target(w.by_iso["URY"])
	menu.run(_command("Demarcar conquistas"))
	_check(main.hud.border.active and not menu.visible, "demarcação abre e o menu sai da frente")
	main.hud.border._on_decline()
	menu.toggle()
	menu.run(_command("Ganhar 10% do alvo"))
	_check(not w.territories.cessions.is_empty() or menu._status.text.contains("não tem"), "ganhar território muda o mapa: " + menu._status.text)
	menu.run(_command("Pandemia"))
	_settle()
	menu.run(_command("Fundir duas vizinhas agora"))
	_check(not w.subdivisions.custom_ids.is_empty(), "fusão direta cria a unidade")
	_settle()


func _run_next() -> void:
	if index >= menu.commands.size():
		phase = 7
		return
	var w: GameWorld = main.world
	# Comandos que aceitam o próprio país rodam nele; os outros, em um país estrangeiro.
	var foreign: Country = w.by_iso.get("ARG")
	if foreign == null or not foreign.alive or foreign == w.player:
		for c: Country in w.countries:
			if c.alive and c != w.player:
				foreign = c
				break
	menu.set_target(foreign if menu.commands[index].target else w.player)
	if not menu.visible:
		menu.toggle()
	var cmd: Dictionary = menu.commands[index]
	# Pula a própria repetição do que encerra a sessão de teste; o resto roda de verdade.
	menu.run(index)
	index += 1
	if main.loading:
		# Carregar e voltar ao início rodam em outra thread: o teste segue quando terminarem.
		want_start = true
		return
	_settle()
	if main.loading:
		restarts += 1
		want_start = true
		return
	if main.world.over or not main.playing:
		restarts += 1
		if main.playing:
			_settle()
			main._restart()
			want_start = true
			return
		_start_game()
		return
	# Alguns dias depois, o sistema precisa continuar de pé.
	for i in 3:
		if not main.world.over:
			main.world.tick_day()
	_settle()
	if main.loading:
		restarts += 1
		want_start = true
		return
	if main.world.over:
		restarts += 1
		main._restart()
		want_start = true
		return
	_check(_sane(main.world), "estado numérico válido depois de: " + String(cmd.label))


func _sane(w: GameWorld) -> bool:
	for c: Country in w.countries:
		if c.alive and (is_nan(c.y) or is_inf(c.y) or is_nan(c.pop) or c.pop <= 0.0 or is_nan(c.e)):
			print("país inválido: ", c.iso)
			return false
	return true
