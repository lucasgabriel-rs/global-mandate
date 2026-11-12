extends Node
## Aba Economia > Infraestrutura: lista de portos e aeroportos, ampliar, construir, conceder, instalação
## fechada pela guerra e marcadores no mapa.
## Uso: godot --path . -- --ui-infra --shots=/caminho/da/pasta

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
	print("shot: ", name_)


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _row(box: Node, part: String) -> Control:
	for row in box.get_children():
		if (row.get_node("%fac_name") as Label).text.contains(part):
			return row
	return null


func _scroll_to(panel: InfraPanel, node: Control) -> void:
	var scroll := panel.get_parent()
	while scroll and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	await _wait()
	(scroll as ScrollContainer).scroll_vertical = int(node.global_position.y - (scroll as ScrollContainer).global_position.y + (scroll as ScrollContainer).scroll_vertical - 10.0)
	await _wait()


func _run() -> void:
	await _wait(5)
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirmar").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	_check(main.playing, "a partida começa")
	var hud: Hud = main.hud
	var c := w.player
	var inf := w.infra
	hud._desk.current_tab = hud._tab_of(hud.economy)
	var sub: TabContainer = hud.economy.get_node("%sub_tabs")
	sub.current_tab = 1
	hud.refresh(true)
	await _wait()
	var panel: InfraPanel = hud.economy.infra
	var ports: VBoxContainer = panel.get_node("%port_rows")
	var airs: VBoxContainer = panel.get_node("%air_rows")
	var facs := inf.facilities_of(c, w)
	_check(ports.get_child_count() + airs.get_child_count() == facs.size(), "uma linha por instalação: %d" % facs.size())
	_check(_row(ports, "Santos") != null and _row(airs, "Guarulhos") != null, "Santos e Guarulhos aparecem")
	_check((panel.get_node("%port_sat") as Label).text.contains("%"), "o resumo mostra a saturação dos portos: " + (panel.get_node("%port_sat") as Label).text)
	await _shot("i1_infra")
	# Ampliar Santos.
	var santos := _row(ports, "Santos")
	_check(santos.get_node("%expand").visible and not santos.get_node("%expand").disabled, "Santos (público) pode ser ampliado")
	_check(not _row(airs, "Guarulhos").get_node("%expand").visible, "Guarulhos (concessão) não tem botão de ampliar")
	santos.get_node("%expand").pressed.emit()
	await _wait()
	_check(panel.form.visible and (panel.form.get_node("%quote") as Label).text.contains("US$"), "o formulário mostra custo e prazo")
	await _scroll_to(panel, panel.get_node("%Acoes"))
	await _shot("i2_ampliar")
	panel.form.get_node("%form_confirm").pressed.emit()
	await _wait()
	_check(inf.projects_of(c).size() == 1, "a obra começa")
	_check(santos.get_node("%expand").disabled and (santos.get_node("%fac_detail") as Label).text.contains("em obra"), "Santos mostra a obra em andamento")
	# Aeroporto novo em Brasília.
	panel.get_node("%build_air").pressed.emit()
	await _wait()
	var city: OptionButton = panel.form.get_node("%city_pick")
	for i in city.item_count:
		if city.get_item_text(i) == "Brasília":
			city.select(i)
			city.item_selected.emit(i)
	var size: OptionButton = panel.form.get_node("%size_pick")
	size.select(2)
	size.item_selected.emit(2)
	await _wait()
	await _shot("i3_construir")
	panel.form.get_node("%form_confirm").pressed.emit()
	await _wait()
	_check(inf.projects_of(c).size() == 2 and (panel.get_node("%project_rows") as Node).get_child_count() == 2, "duas obras na lista")
	# Conceder Santos Dumont.
	var sd := _row(airs, "Santos Dumont")
	sd.get_node("%concede").pressed.emit()
	await _wait()
	_check((panel.form.get_node("%quote") as Label).text.contains("Outorga"), "a concessão mostra a outorga")
	await _scroll_to(panel, panel.get_node("%Acoes"))
	await _shot("i4_conceder")
	panel.form.get_node("%form_confirm").pressed.emit()
	await _wait()
	_check(inf.facility(int(sd.get_meta("id"))).owner == "concession", "Santos Dumont vira concessão")
	_check((panel.get_node("%feedback") as Label).text.contains("Tesouro"), "o painel confirma: " + (panel.get_node("%feedback") as Label).text)
	hud.refresh(true)
	await _wait()
	await _scroll_to(panel, panel.get_node("%ObrasTitulo"))
	await _shot("i5_obras")
	# Guerra: ocupação fecha instalações.
	c.occupied = c.occ0 + 0.6
	inf.step_month(w)
	w.flush_events()
	hud.refresh(true)
	await _wait()
	var closed := 0
	for box: Node in [ports, airs]:
		for row in box.get_children():
			if (row.get_node("%fac_use") as Label).text == "fechado":
				closed += 1
	_check(closed > 0, "instalações fechadas aparecem como fechadas: %d" % closed)
	await _scroll_to(panel, panel.get_node("%PortosTitulo"))
	await _shot("i6_fechados")
	# Mapa: marcadores dos ativos do país.
	var map: MapView = main.map
	map._target_zoom = 2.2
	map._camera.zoom = Vector2.ONE * 2.2
	map._camera.position = map._project(-46.0, -21.0)
	hud._desk.current_tab = 0
	await _wait(6)
	_check(map._infra_marks.size() == inf.facilities_of(c, w).size(), "um marcador por instalação: %d" % map._infra_marks.size())
	await _shot("i7_mapa")
	map._target_zoom = 4.5
	map._camera.zoom = Vector2.ONE * 4.5
	map._camera.position = map._project(-45.0, -23.0)
	await _wait(6)
	await _shot("i8_mapa_nomes")
	c.occupied = c.occ0
	inf.step_month(w)
	# O tempo anda com tudo isso.
	main._set_speed(3)
	await _wait(40)
	main.join_sim()
	main._set_speed(0)
	_check(not w.over, "o jogo segue")
