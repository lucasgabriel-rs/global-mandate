extends Node
## Informação econômica (aba Economia > Informação): gráfico comparando países, boletim de expectativas
## do mercado e previsões do FMI, depois de um ano de jogo.
## Uso: godot --path . -- --ui-econ-info --shots=/caminho/da/pasta

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
	print("RESULTADO: %d falhas" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _wait(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name_: String) -> void:
	# Diálogos que a partida abre sozinha (pedidos de conversa etc.) cobririam o painel.
	for m in main.modal_root.get_children():
		m.queue_free()
	await _wait(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


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
	for i in 400:
		w.tick_day()
	var hud: Hud = main.hud
	var desk: WindowDesk = hud._desk
	desk.current_tab = 9
	var economy: EconomyPanel = hud.economy
	(economy.get_node("%sub_tabs") as TabContainer).current_tab = 4
	hud.refresh(true)
	await _wait()
	var info: InfoPanel = economy.info
	_check(info.is_visible_in_tree(), "a subaba Informação aparece")
	var tabs: TabContainer = info.get_node("%info_tabs")
	# Gráficos: inflação do Brasil contra EUA e Argentina.
	(info.get_node("%series_pick") as OptionButton).selected = 1
	info.pick_country(0, "USA")
	info.pick_country(1, "ARG")
	await _wait()
	var chart: CompareChart = info.get_node("%compare_chart")
	_check(chart._series.size() == 3, "três países no gráfico: %d" % chart._series.size())
	_check(chart._series[0].size() >= 12, "a série tem um ano de dados: %d" % chart._series[0].size())
	_check((info.get_node("%chart_note") as Label).text.contains("%"), "a nota mostra o último dado")
	await _shot("i1_graficos")
	# Expectativas do mercado.
	tabs.current_tab = 1
	await _wait()
	var cell: Label = info.get_node("%fc_infl_0")
	_check(cell.text.contains("%"), "inflação esperada: " + cell.text)
	_check((info.get_node("%year_0") as Label).text == str(w.year), "o ano corrente no cabeçalho")
	var m := Outlook.market(w.player, w)
	_check(absf(m.infl[2] - w.player.pi_target) < absf(m.infl[0] - w.player.pi_target) + 0.0001, "a inflação esperada converge para a meta")
	await _shot("i2_expectativas")
	# FMI.
	tabs.current_tab = 2
	await _wait()
	var rows: VBoxContainer = info.get_node("%imf_rows")
	_check(rows.get_child_count() >= 5, "mundo, o país e as grandes economias: %d linhas" % rows.get_child_count())
	_check((rows.get_child(1).get_node("%imf_name") as Label).text == tr(w.player.name), "o jogador vem logo depois do mundo")
	_check(not (info.get_node("%imf_risks") as Label).text.is_empty(), "o FMI avalia o país")
	await _shot("i3_fmi")
	get_window().size = Vector2i(1100, 700)
	await _wait(8)
	await _shot("i4_janela_menor")
