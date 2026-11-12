extends Node
## Dock e janelas flutuantes: abrir pelo dock, trazer para a frente, arrastar, redimensionar, minimizar,
## data sem a hora e janela pequena.
## Uso: godot --path . -- --ui-desk --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var failures := 0


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)
	await _run()
	print("RESULT: %d failures" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _wait(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name_: String) -> void:
	await _wait(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _press(item: DockItem) -> void:
	item.pressed.emit()
	await _wait(14)


func _run() -> void:
	await _wait(5)
	var w: GameWorld = main.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirmar").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	for i in 60:
		w.tick_day()
	var hud: Hud = main.hud
	var desk: WindowDesk = hud._desk
	var dock: Dock = hud._dock
	hud.refresh(true)
	await _wait()
	_check(not (hud.get_node("%date") as Label).text.contains(":"), "a data aparece sem a hora: " + (hud.get_node("%date") as Label).text)
	_check(desk.open_count() == 0, "o jogo começa sem janelas abertas, com o mapa livre")
	_check(dock.items().filter(func(i): return i.window_index >= 0).size() == desk.get_tab_count(), "o dock tem um ícone por janela: %d" % dock.items().size())
	await _shot("d1_mapa_livre")

	# Abrir pelo dock.
	await _press(dock.item_for_window(0))
	_check(desk.is_open(0) and desk.current_tab == 0, "o ícone do Painel abre a janela")
	_check((desk.window(0).content() as Control).is_visible_in_tree(), "o conteúdo do Painel está dentro da janela")
	await _press(dock.item_for_window(1))
	await _press(dock.item_for_window(9))
	_check(desk.open_count() == 3 and desk.current_tab == 9, "três janelas abertas, a última na frente")
	_check(dock.item_for_window(1)._dot.visible, "o ponto marca as janelas abertas no dock")
	hud.refresh(true)
	await _shot("d2_tres_janelas")

	# Trazer para a frente e minimizar.
	await _press(dock.item_for_window(1))
	_check(desk.current_tab == 1 and desk.open_count() == 3, "clicar no ícone de uma janela de trás a traz para a frente")
	await _press(dock.item_for_window(1))
	_check(not desk.is_open(1) and desk.current_tab == 9, "clicar de novo minimiza, e a de trás vira a da frente")
	await _wait(20)
	_check(not desk.window(1).visible, "a janela minimizada some depois da animação")

	# Arrastar e redimensionar pela barra e pelo canto.
	var win := desk.window(0)
	win.raise()
	var bar: Control = win.get_node("%title_bar")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = bar.get_global_rect().get_center()
	press.position = press.global_position
	Input.warp_mouse(press.global_position)
	await _wait(2)
	bar.gui_input.emit(press)
	var before := win.position
	Input.warp_mouse(press.global_position + Vector2(240, 60))
	await _wait(2)
	var motion := InputEventMouseMotion.new()
	bar.gui_input.emit(motion)
	press.pressed = false
	bar.gui_input.emit(press)
	_check(win.position.distance_to(before) > 40.0, "a janela anda ao arrastar a barra: %s → %s" % [str(before), str(win.position)])
	win.size = Vector2(5000, 5000)
	win.fit()
	_check(win.get_rect().end.x <= desk.size.x + 1.0 and win.get_rect().end.y <= desk.size.y + 1.0, "a janela não passa da área livre")
	win.size = win.default_size
	(win.get_node("%close") as Button).pressed.emit()
	await _wait(20)
	_check(not desk.is_open(0), "o botão vermelho fecha a janela")

	# Divisões: abrir a janela liga a escolha de unidades no mapa.
	desk.current_tab = hud._divisions_tab
	await _wait()
	_check(main.map.unit_pick, "a janela de Divisões na frente liga a escolha de unidades")
	desk.close(hud._divisions_tab)
	await _wait(20)
	_check(not main.map.unit_pick, "fechada, o mapa volta ao normal")

	# Legislação abre o centro legislativo.
	for it in dock.items():
		if it.action == "legislation":
			await _press(it)
	_check(main.legislation_center() != null and desk.current_tab == hud.LEGISLATION_WINDOW, "o ícone da legislação abre o centro legislativo como janela")
	_check(not main.modal_open, "o centro não bloqueia o resto da tela")
	var center_rect := desk.window(hud.LEGISLATION_WINDOW).get_rect()
	_check(absf(center_rect.get_center().x - desk.size.x * 0.5) < 60.0, "a janela abre no centro da tela")
	await _shot("d3_legislacao")
	for it in dock.items():
		if it.action == "legislation":
			await _press(it)
	_check(main.legislation_center() == null, "clicar de novo no ícone minimiza o centro")

	# Dock com o mouse em cima: os ícones crescem.
	desk.current_tab = 7
	await _wait(14)
	var target := dock.item_for_window(2)
	Input.warp_mouse(target.get_global_rect().get_center())
	await _wait(30)
	_check(target.magnify > 1.3, "o ícone sob o mouse cresce: %.2f" % target.magnify)
	hud.refresh(true)
	await _shot("d4_dock_ampliado")

	# Tela menor.
	get_window().size = Vector2i(1100, 680)
	await _wait(12)
	for i in desk.get_tab_count():
		if desk.is_open(i):
			var r := desk.window(i).get_rect()
			_check(r.end.x <= desk.size.x + 1.0 and r.end.y <= desk.size.y + 1.0, "a janela %d cabe na tela menor" % i)
	await _shot("d5_tela_menor")
