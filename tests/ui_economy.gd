extends Node
## Aba Economia: a subaba Setores com o país do jogador, depois de um ano de jogo.
## Uso: godot --path . -- --ui-economy --shots=/caminho/da/pasta

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
	_check(main.playing, "a partida começa")
	for i in 400:
		w.tick_day()
	var hud: Hud = main.hud
	var tabs: WindowDesk = hud._desk
	tabs.current_tab = 9
	hud.refresh(true)
	await _wait()
	var panel: EconomyPanel = hud.economy
	_check(panel.is_visible_in_tree(), "a aba Economia aparece")
	var rows: VBoxContainer = panel.get_node("%sector_rows")
	_check(rows.get_child_count() == Sectors.COUNT, "uma linha por setor: %d" % rows.get_child_count())
	var first: Label = rows.get_child(0).get_node("%sector_name")
	var top := 0
	for i in Sectors.COUNT:
		if w.player.sector_share[i] > w.player.sector_share[top]:
			top = i
	_check(first.text == Sectors.NAMES[top], "o maior setor vem primeiro: " + first.text)
	_check((rows.get_child(0).get_node("%sector_value") as Label).text.contains("US$"), "mostra o valor em dólares")
	await _shot("e1_setores")
	for t in [1, 2, 3]:
		(panel.get_node("%sub_tabs") as TabContainer).current_tab = t
		hud.refresh(true)
		await _wait()
	await _shot("e2_bolsa")
	(panel.get_node("%sub_tabs") as TabContainer).current_tab = 0
	get_window().size = Vector2i(1100, 700)
	await _wait(8)
	await _shot("e3_janela_menor")
