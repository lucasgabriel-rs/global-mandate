extends Node
## Telas de empresas e bolsa: subaba Empresas com filtros, subaba Bolsa com índice e movimentos,
## e o bloco de privatização no editor de normas.
## Uso: godot --path . -- --ui-corporate --shots=/caminho/da/pasta

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
	main.join_sim()
	_check(main.playing, "a partida começa")
	# Um ano e pouco de jogo, para a bolsa ter história.
	for i in 400:
		w.player.next_election = 9999.0
		w.tick_day()
	main.prompts.clear()
	var hud: Hud = main.hud
	hud._desk.current_tab = 9
	var economy: EconomyPanel = hud.economy
	var tabs: TabContainer = economy.get_node("%sub_tabs")
	tabs.current_tab = 2
	hud.refresh(true)
	await _wait()
	var companies: CompaniesPanel = economy.companies
	var rows: VBoxContainer = companies.get_node("%company_rows")
	var visible_rows := rows.get_children().filter(func(r): return r.visible)
	_check(visible_rows.size() >= 10, "a subaba Empresas lista %d empresas" % visible_rows.size())
	_check((visible_rows[0].get_node("%company_name") as Label).text != "", "a linha mostra o nome")
	_check(companies.get_node("%summary").text.contains("empresas"), "o resumo aparece: " + companies.get_node("%summary").text)
	await _shot("c1_empresas")
	companies.set_filters(Sectors.FINANCE, CompaniesPanel.CAPITAL_ALL)
	await _wait()
	visible_rows = rows.get_children().filter(func(r): return r.visible)
	var all_finance := visible_rows.all(func(r): return (r.get_node("%company_info") as Label).text.begins_with(Sectors.NAMES[Sectors.FINANCE]))
	_check(visible_rows.size() >= 3 and all_finance, "o filtro de setor mostra só os bancos: %d" % visible_rows.size())
	await _shot("c2_filtro_financas")
	companies.set_filters(-1, CompaniesPanel.CAPITAL_CLOSED)
	await _wait()
	visible_rows = rows.get_children().filter(func(r): return r.visible)
	_check(visible_rows.size() >= 2 and visible_rows.all(func(r): return (r.get_node("%company_info") as Label).text.contains("Capital fechado")), "o filtro de capital fechado funciona: %d" % visible_rows.size())
	await _shot("c3_fechadas")
	companies.set_filters(-1, CompaniesPanel.CAPITAL_ALL)
	# Bolsa.
	tabs.current_tab = 3
	hud.refresh(true)
	await _wait()
	var stock: StockPanel = economy.stock
	_check(stock.get_node("%exchange").text == "B3", "a bolsa é a B3")
	_check(stock.get_node("%index_chart").series.size() >= 12, "o gráfico do índice tem história")
	_check(stock.get_node("%gainers").get_children().any(func(r): return r.visible), "há maiores altas")
	_check(stock.get_node("%losers").get_children().any(func(r): return r.visible), "há maiores baixas")
	_check(stock.get_node("%total_cap").text.contains("US$"), "valor de mercado total: " + stock.get_node("%total_cap").text)
	await _shot("c4_bolsa")
	# Abertura de capital e privatização aparecem nos movimentos recentes.
	w.corporate.privatize(w, w.player, "Caixa Econômica Federal", 0.4)
	hud.refresh(true)
	await _wait()
	var events := stock.get_node("%events").get_children().filter(func(r): return r.visible)
	_check(events.any(func(r): return (r.get_node("%stock_name") as Label).text == "Caixa Econômica Federal"), "a privatização entra nos movimentos recentes")
	var scroll := stock.get_parent()
	while scroll and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll:
		(scroll as ScrollContainer).scroll_vertical = 100000
	await _shot("c5_bolsa_movimentos")
	if scroll:
		(scroll as ScrollContainer).scroll_vertical = 0
	# Editor de normas: bloco de privatização com a lista de empresas.
	var law: Dictionary = w.legislation.new_norm(w, "ordinaria")
	law.title = "Privatização"
	law.ementa = "Teste"
	var stack := LawProgram.add_stack(law.program, LawProgram.new_block(law.program, "ev_enact"), Vector2(40, 40))
	var block := LawProgram.new_block(law.program, "ec_privatize")
	stack.blocks.append(block)
	main.open_law_editor(law)
	await _wait()
	var editor: LawEditor = _top()
	_check(not editor.last_compile.ok, "sem escolher a empresa, é erro")
	editor.select_block(int(block.id))
	await _wait()
	var option: OptionButton = editor.get_node("%props_box").get_child(1).get_node("%option")
	_check(option.visible and option.item_count >= 10, "o campo lista as empresas: %d" % option.item_count)
	for i in option.item_count:
		if option.get_item_metadata(i) == "Petrobras":
			option.select(i)
			option.item_selected.emit(i)
	await _wait()
	_check(editor.last_compile.ok, "com a Petrobras escolhida, compila: %s" % str(editor.last_compile.errors))
	await _shot("c6_privatizar")
	editor.close_editor()
	await _wait()
