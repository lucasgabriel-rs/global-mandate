extends Node
## Economy tab > Infrastructure: list of ports and airports, expand, build, concede, facility
## closed by war and markers on the map.
## Usage: godot --path . -- --ui-infra --shots=/path/to/folder

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
	_top().get_node("%Confirm").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	_check(main.playing, "the match starts")
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
	_check(ports.get_child_count() + airs.get_child_count() == facs.size(), "one row per facility: %d" % facs.size())
	_check(_row(ports, "Santos") != null and _row(airs, "Guarulhos") != null, "Santos e Guarulhos aparecem")
	_check((panel.get_node("%port_sat") as Label).text.contains("%"), "the summary shows port saturation:" + (panel.get_node("%port_sat") as Label).text)
	await _shot("i1_infra")
	# Ampliar Santos.
	var santos := _row(ports, "Santos")
	_check(santos.get_node("%expand").visible and not santos.get_node("%expand").disabled, "Santos (public) can be expanded")
	_check(not _row(airs, "Guarulhos").get_node("%expand").visible, "Guarulhos (concession) has no expand button")
	santos.get_node("%expand").pressed.emit()
	await _wait()
	_check(panel.form.visible and (panel.form.get_node("%quote") as Label).text.contains("US$"), "the form shows cost and term")
	await _scroll_to(panel, panel.get_node("%Actions"))
	await _shot("i2_expand")
	panel.form.get_node("%form_confirm").pressed.emit()
	await _wait()
	_check(inf.projects_of(c).size() == 1, "the project starts")
	_check(santos.get_node("%expand").disabled and (santos.get_node("%fac_detail") as Label).text.contains("em obra"), "Santos shows the project in progress")
	# New airport in Brasília.
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
	await _shot("i3_build")
	panel.form.get_node("%form_confirm").pressed.emit()
	await _wait()
	_check(inf.projects_of(c).size() == 2 and (panel.get_node("%project_rows") as Node).get_child_count() == 2, "two projects in the list")
	# Conceder Santos Dumont.
	var sd := _row(airs, "Santos Dumont")
	sd.get_node("%concede").pressed.emit()
	await _wait()
	_check((panel.form.get_node("%quote") as Label).text.contains("Outorga"), "the concession shows the grant")
	await _scroll_to(panel, panel.get_node("%Actions"))
	await _shot("i4_concede")
	panel.form.get_node("%form_confirm").pressed.emit()
	await _wait()
	_check(inf.facility(int(sd.get_meta("id"))).owner == "concession", "Santos Dumont becomes a concession")
	_check((panel.get_node("%feedback") as Label).text.contains("Tesouro"), "o painel confirma: " + (panel.get_node("%feedback") as Label).text)
	hud.refresh(true)
	await _wait()
	await _scroll_to(panel, panel.get_node("%WorksTitle"))
	await _shot("i5_works")
	# War: occupation closes facilities.
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
	_check(closed > 0, "closed facilities appear as closed: %d" % closed)
	await _scroll_to(panel, panel.get_node("%PortsTitle"))
	await _shot("i6_closed")
	# Map: markers of the country's assets.
	var map: MapView = main.map
	map._target_zoom = 2.2
	map._camera.zoom = Vector2.ONE * 2.2
	map._camera.position = map._project(-46.0, -21.0)
	hud._desk.current_tab = 0
	await _wait(6)
	_check(map._infra_marks.size() == inf.facilities_of(c, w).size(), "one marker per facility: %d" % map._infra_marks.size())
	await _shot("i7_map")
	map._target_zoom = 4.5
	map._camera.zoom = Vector2.ONE * 4.5
	map._camera.position = map._project(-45.0, -23.0)
	await _wait(6)
	await _shot("i8_map_names")
	c.occupied = c.occ0
	inf.step_month(w)
	# Time moves along with all this.
	main._set_speed(3)
	await _wait(40)
	main.join_sim()
	main._set_speed(0)
	_check(not w.over, "o jogo segue")
