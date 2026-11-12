extends Node
## Player menus in opposition: the dock, the HUD and the windows show only what suits it, with a seal and own names,
## and go back to normal, without reloading, when the player takes over the government. Takes captures of both modes to compare.
## Usage: godot --path . -- --ui-opposition --shots=/path/to/folder

var main: Node
var out := "user://shots"
var failures := 0

## Dock items that only the government has, and those that only the opposition has.
const GOV_ITEMS := ["dock_ministers", "dock_fiscal", "dock_currency", "dock_trade", "dock_military", "dock_divisions"]
const OPP_ITEMS := ["dock_opposition"]
const SHARED_ITEMS := ["dock_panel", "dock_politics", "dock_legislation", "dock_economy", "dock_world"]


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


## Checks the dock, the seal and the titles of one of the two roles.
func _check_role(hud: Hud, office: bool, tag: String) -> void:
	var dock: Dock = hud._dock
	var desk: WindowDesk = hud._desk
	for n: String in GOV_ITEMS:
		_check(_item(dock, n).visible == office, "%s: %s %s in the dock" % [tag, n, "aparece" if office else "some"])
	for n: String in OPP_ITEMS:
		_check(_item(dock, n).visible == not office, "%s: %s %s in the dock" % [tag, n, "some" if office else "aparece"])
	for n: String in SHARED_ITEMS:
		_check(_item(dock, n).visible, "%s: %s stays in the dock" % [tag, n])
	_check((hud.find_child("seal_opposition", true, false) as Control).visible == not office, "%s: \"Oposição\" seal %s" % [tag, "escondido" if office else "no topo"])
	for i in [1, 2, 3, 4, 6, 8]:
		_check(desk.window(i).locked == not office, "%s: window %d %s" % [tag, i, "livre" if office else "trancada"])
	_check(desk.window(11).locked == office, "%s: oversight window %s" % [tag, "trancada" if office else "livre"])
	_check(desk.window(0).title == ("Painel do governo" if office else "Painel da oposição"), "%s: panel title: %s" % [tag, desk.window(0).title])
	_check(desk.window(7).title == ("Política" if office else "Partido e pesquisas"), "%s: politics title: %s" % [tag, desk.window(7).title])
	_check(desk.window(10).title == ("Centro legislativo" if office else "Projetos e emendas"), "%s: legislative center title: %s" % [tag, desk.window(10).title])
	_check(_item(dock, "dock_panel").label == desk.window(0).title, "%s: the dock and the panel window have the same name" % tag)
	_check(hud.find_child("bills", true, false).visible == office, "%s: government votes in the Politics window %s" % [tag, "aparecem" if office else "somem"])
	# Nothing of the government opens outside the dock.
	for i in [1, 2, 3, 4, 6, 8]:
		desk.open(i)
	await _wait(3)
	var leaked := false
	for i in [1, 2, 3, 4, 6, 8]:
		leaked = leaked or (desk.is_open(i) and not office)
	_check(not leaked, "%s: government windows %s when asked to open" % [tag, "abrem" if office else "não abrem"])
	for i in [1, 2, 3, 4, 6, 8]:
		desk.close(i)
	await _wait(20)


func _run() -> void:
	await _wait(5)
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirm").pressed.emit()
	await _wait()
	# Starts in opposition: chooses "oposição" and a party that does not govern.
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
	_check(not w.in_office, "the match starts in opposition")
	hud.refresh(true)
	await _wait()

	# --- Opposition ---
	await _check_role(hud, false, "oposição")
	_check((hud.get_node("%player_name") as Label).text.contains("oposição"), "the player's name says opposition:" + (hud.get_node("%player_name") as Label).text)
	await _shot("o1_mapa_opposition")
	for i in [0, 7, 11]:
		dock.item_for_window(i).pressed.emit()
		await _wait(14)
	_check(desk.is_open(0) and desk.is_open(7) and desk.is_open(11), "panel, politics and oversight open from the dock")
	var panel: OppositionPanel = hud.get_node("%opposition")
	_check((panel.get_node("%ruling_label") as Label).text.begins_with("Governo:") and (panel.get_node("%v_approval") as Label).text.ends_with("%"), "the oversight shows the government and its numbers")
	desk.window(0).position = Vector2(10, 10)
	desk.window(7).position = Vector2(480, 10)
	desk.window(11).position = Vector2(980, 10)
	await _shot("o2_janelas_opposition")
	hud.show_country(w.by_iso["USA"])
	await _wait(3)
	_check(not hud.find_child("dossier_talk", true, false).visible and not hud.find_child("ProposeTreaty", true, false).visible, "opposition: another country's dossier has no conversation or treaty")
	_check(not hud.find_child("action_war", true, false).is_visible_in_tree(), "opposition: no foreign policy in the dossier")
	_check(hud.find_child("OppositionNote", true, false).visible, "opposition: the dossier explains why there are no actions")
	await _shot("o3_dossie_opposition")
	hud.show_country(null)
	desk.close_all()
	await _wait(20)

	# --- Government: everything comes back, without reloading ---
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
	_check(hud.find_child("dossier_talk", true, false).visible and hud.find_child("ProposeTreaty", true, false).visible, "government: another country's dossier has conversation and treaty")
	_check(not hud.find_child("OppositionNote", true, false).visible, "government: no opposition note in the dossier")
	await _shot("g3_dossie_governo")
	hud.show_country(null)

	# --- Losing office with the budget window open closes the window ---
	_check(desk.is_open(1), "the budget is open in government")
	w.enter_opposition("Teste.", "Derrota")
	hud.refresh(true)
	await _wait(20)
	await _any_modal_closed()
	_check(not w.in_office and not desk.is_open(1) and desk.window(1).locked, "on falling, the budget window closes and does not reopen")
	_check(not _item(dock, "dock_fiscal").visible and _item(dock, "dock_opposition").visible, "on falling, the dock becomes the opposition's")
	_check(desk.is_open(0) and desk.window(0).title == "Painel da oposição", "the panel stays open, now with the opposition's name")
	await _shot("o4_depois_da_derrota")
