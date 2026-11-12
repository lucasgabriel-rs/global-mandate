extends Node
## Company and exchange screens: Companies sub-tab with filters, Exchange sub-tab with index and moves,
## and the privatization block in the norm editor.
## Usage: godot --path . -- --ui-corporate --shots=/path/to/folder

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


func _run() -> void:
	await _wait(5)
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirm").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	main.join_sim()
	_check(main.playing, "the match starts")
	# A year and a bit of game, so the exchange has history.
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
	_check((visible_rows[0].get_node("%company_name") as Label).text != "", "the row shows the name")
	_check(companies.get_node("%summary").text.contains("empresas"), "o resumo aparece: " + companies.get_node("%summary").text)
	await _shot("c1_empresas")
	companies.set_filters(Sectors.FINANCE, CompaniesPanel.CAPITAL_ALL)
	await _wait()
	visible_rows = rows.get_children().filter(func(r): return r.visible)
	var all_finance := visible_rows.all(func(r): return (r.get_node("%company_info") as Label).text.begins_with(Sectors.NAMES[Sectors.FINANCE]))
	_check(visible_rows.size() >= 3 and all_finance, "the sector filter shows only banks: %d" % visible_rows.size())
	await _shot("c2_filtro_financas")
	companies.set_filters(-1, CompaniesPanel.CAPITAL_CLOSED)
	await _wait()
	visible_rows = rows.get_children().filter(func(r): return r.visible)
	_check(visible_rows.size() >= 2 and visible_rows.all(func(r): return (r.get_node("%company_info") as Label).text.contains("Capital fechado")), "the closed-capital filter works: %d" % visible_rows.size())
	await _shot("c3_fechadas")
	companies.set_filters(-1, CompaniesPanel.CAPITAL_ALL)
	# Bolsa.
	tabs.current_tab = 3
	hud.refresh(true)
	await _wait()
	var stock: StockPanel = economy.stock
	_check(stock.get_node("%exchange").text == "B3", "the exchange is the B3")
	_check(stock.get_node("%index_chart").series.size() >= 12, "the index chart has history")
	_check(stock.get_node("%gainers").get_children().any(func(r): return r.visible), "there are top gainers")
	_check(stock.get_node("%losers").get_children().any(func(r): return r.visible), "there are top losers")
	_check(stock.get_node("%total_cap").text.contains("US$"), "total market value:" + stock.get_node("%total_cap").text)
	await _shot("c4_bolsa")
	# IPOs and privatization appear in the recent moves.
	w.corporate.privatize(w, w.player, "Caixa Econômica Federal", 0.4)
	hud.refresh(true)
	await _wait()
	var events := stock.get_node("%events").get_children().filter(func(r): return r.visible)
	_check(events.any(func(r): return (r.get_node("%stock_name") as Label).text == "Caixa Econômica Federal"), "the privatization enters the recent moves")
	var scroll := stock.get_parent()
	while scroll and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll:
		(scroll as ScrollContainer).scroll_vertical = 100000
	await _shot("c5_bolsa_movimentos")
	if scroll:
		(scroll as ScrollContainer).scroll_vertical = 0
	# Norm editor: privatization block with the list of companies.
	var law: Dictionary = w.legislation.new_norm(w, "ordinaria")
	law.title = "Privatização"
	law.ementa = "Teste"
	var stack := LawProgram.add_stack(law.program, LawProgram.new_block(law.program, "ev_enact"), Vector2(40, 40))
	var block := LawProgram.new_block(law.program, "ec_privatize")
	stack.blocks.append(block)
	main.open_law_editor(law)
	await _wait()
	var editor: LawEditor = _top()
	_check(not editor.last_compile.ok, "without choosing the company, it is an error")
	editor.select_block(int(block.id))
	await _wait()
	var option: OptionButton = editor.get_node("%props_box").get_child(1).get_node("%option")
	_check(option.visible and option.item_count >= 10, "the field lists the companies: %d" % option.item_count)
	for i in option.item_count:
		if option.get_item_metadata(i) == "Petrobras":
			option.select(i)
			option.item_selected.emit(i)
	await _wait()
	_check(editor.last_compile.ok, "with Petrobras chosen, it compiles: %s" % str(editor.last_compile.errors))
	await _shot("c6_privatizar")
	editor.close_editor()
	await _wait()
