extends Node
## Menus do jogador na oposição: o dock, o HUD e as janelas mostram só o que cabe a ela, com selo e nomes próprios,
## e voltam ao normal, sem recarregar, quando ele assume o governo. Tira capturas dos dois modos para comparar.
## Uso: godot --path . -- --ui-opposition --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var failures := 0

## Itens do dock que só o governo tem, e os que só a oposição tem.
const GOV_ITEMS := ["dock_ministros", "dock_fiscal", "dock_moeda", "dock_comercio", "dock_militar", "dock_divisoes"]
const OPP_ITEMS := ["dock_oposicao"]
const SHARED_ITEMS := ["dock_painel", "dock_politica", "dock_legislacao", "dock_economia", "dock_mundo"]


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
	print("shot: ", name_)


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _item(dock: Dock, name_: String) -> DockItem:
	return dock.find_child(name_, true, false) as DockItem


func _any_modal_closed() -> void:
	main.prompts.clear()
	while main.modal_open and main.modal_root.get_child_count() > 0:
		main._close_modal(_top())
		await _wait(2)


## Confere o dock, o selo e os títulos de um dos dois papéis.
func _check_role(hud: Hud, office: bool, tag: String) -> void:
	var dock: Dock = hud._dock
	var desk: WindowDesk = hud._desk
	for n: String in GOV_ITEMS:
		_check(_item(dock, n).visible == office, "%s: %s %s no dock" % [tag, n, "aparece" if office else "some"])
	for n: String in OPP_ITEMS:
		_check(_item(dock, n).visible == not office, "%s: %s %s no dock" % [tag, n, "some" if office else "aparece"])
	for n: String in SHARED_ITEMS:
		_check(_item(dock, n).visible, "%s: %s continua no dock" % [tag, n])
	_check((hud.find_child("selo_oposicao", true, false) as Control).visible == not office, "%s: selo \"Oposição\" %s" % [tag, "escondido" if office else "no topo"])
	for i in [1, 2, 3, 4, 6, 8]:
		_check(desk.window(i).locked == not office, "%s: janela %d %s" % [tag, i, "livre" if office else "trancada"])
	_check(desk.window(11).locked == office, "%s: janela da fiscalização %s" % [tag, "trancada" if office else "livre"])
	_check(desk.window(0).title == ("Painel do governo" if office else "Painel da oposição"), "%s: título do painel: %s" % [tag, desk.window(0).title])
	_check(desk.window(7).title == ("Política" if office else "Partido e pesquisas"), "%s: título da política: %s" % [tag, desk.window(7).title])
	_check(desk.window(10).title == ("Centro legislativo" if office else "Projetos e emendas"), "%s: título do centro legislativo: %s" % [tag, desk.window(10).title])
	_check(_item(dock, "dock_painel").label == desk.window(0).title, "%s: o dock e a janela do painel têm o mesmo nome" % tag)
	_check(hud.find_child("bills", true, false).visible == office, "%s: votações de governo na janela Política %s" % [tag, "aparecem" if office else "somem"])
	# Nada de governo abre por fora do dock.
	for i in [1, 2, 3, 4, 6, 8]:
		desk.open(i)
	await _wait(3)
	var leaked := false
	for i in [1, 2, 3, 4, 6, 8]:
		leaked = leaked or (desk.is_open(i) and not office)
	_check(not leaked, "%s: janelas de governo %s ao pedir para abrir" % [tag, "abrem" if office else "não abrem"])
	for i in [1, 2, 3, 4, 6, 8]:
		desk.close(i)
	await _wait(20)


func _run() -> void:
	await _wait(5)
	var w: GameWorld = main.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirmar").pressed.emit()
	await _wait()
	# Começa na oposição: escolhe "oposição" e um partido que não governa.
	var picker := _top()
	picker.get_node("%role_opposition").pressed.emit()
	await _wait()
	var chosen := false
	for row in picker.get_node("%party_rows").get_children():
		var b: Button = row.get_node("%pick")
		if not b.disabled and not chosen:
			chosen = true
			b.pressed.emit()
	await _wait(6)
	main._set_speed(0)
	await _any_modal_closed()
	var hud: Hud = main.hud
	var desk: WindowDesk = hud._desk
	var dock: Dock = hud._dock
	_check(not w.in_office, "a partida começa na oposição")
	hud.refresh(true)
	await _wait()

	# --- Oposição ---
	await _check_role(hud, false, "oposição")
	_check((hud.get_node("%player_name") as Label).text.contains("oposição"), "o nome do jogador diz oposição: " + (hud.get_node("%player_name") as Label).text)
	await _shot("o1_mapa_oposicao")
	for i in [0, 7, 11]:
		dock.item_for_window(i).pressed.emit()
		await _wait(14)
	_check(desk.is_open(0) and desk.is_open(7) and desk.is_open(11), "painel, política e fiscalização abrem pelo dock")
	var panel: OppositionPanel = hud.get_node("%oposicao")
	_check((panel.get_node("%ruling_label") as Label).text.begins_with("Governo:") and (panel.get_node("%v_approval") as Label).text.ends_with("%"), "a fiscalização mostra o governo e os números dele")
	desk.window(0).position = Vector2(10, 10)
	desk.window(7).position = Vector2(480, 10)
	desk.window(11).position = Vector2(980, 10)
	await _shot("o2_janelas_oposicao")
	hud.show_country(w.by_iso["USA"])
	await _wait(3)
	_check(not hud.find_child("dossier_talk", true, false).visible and not hud.find_child("ProporTratado", true, false).visible, "oposição: o dossiê de outro país não tem conversa nem tratado")
	_check(not hud.find_child("action_war", true, false).is_visible_in_tree(), "oposição: sem política externa no dossiê")
	_check(hud.find_child("OposicaoNota", true, false).visible, "oposição: o dossiê explica por que não há ações")
	await _shot("o3_dossie_oposicao")
	hud.show_country(null)
	desk.close_all()
	await _wait(20)

	# --- Governo: tudo volta, sem recarregar ---
	w.in_office = true
	hud.refresh(true)
	await _wait()
	await _check_role(hud, true, "governo")
	await _shot("g1_mapa_governo")
	for i in [0, 7, 1]:
		dock.item_for_window(i).pressed.emit()
		await _wait(14)
	desk.window(0).position = Vector2(10, 10)
	desk.window(7).position = Vector2(480, 10)
	desk.window(1).position = Vector2(980, 10)
	await _shot("g2_janelas_governo")
	hud.show_country(w.by_iso["USA"])
	await _wait(3)
	_check(hud.find_child("dossier_talk", true, false).visible and hud.find_child("ProporTratado", true, false).visible, "governo: o dossiê de outro país tem conversa e tratado")
	_check(not hud.find_child("OposicaoNota", true, false).visible, "governo: sem nota de oposição no dossiê")
	await _shot("g3_dossie_governo")
	hud.show_country(null)

	# --- Perder o cargo com a janela de orçamento aberta fecha a janela ---
	_check(desk.is_open(1), "o orçamento está aberto no governo")
	w.enter_opposition("Teste.", "Derrota")
	hud.refresh(true)
	await _wait(20)
	await _any_modal_closed()
	_check(not w.in_office and not desk.is_open(1) and desk.window(1).locked, "ao cair, a janela de orçamento fecha e não reabre")
	_check(not _item(dock, "dock_fiscal").visible and _item(dock, "dock_oposicao").visible, "ao cair, o dock vira o da oposição")
	_check(desk.is_open(0) and desk.window(0).title == "Painel da oposição", "o painel continua aberto, já com o nome da oposição")
	await _shot("o4_depois_da_derrota")
