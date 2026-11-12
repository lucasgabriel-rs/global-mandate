extends Node
## New screens: age in the creator, party choice, treaty, election, unit with a rite, ministry by law,
## end of career with a new character, leader asking for a conversation and resizable window.
## Usage: godot --path . -- --ui-society --shots=/path/to/folder

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


## The front screen: an open modal, or the legislative center window.
func _top() -> Control:
	var n: int = main.modal_root.get_child_count()
	if not main.modal_open and main.legislation_center() != null:
		return main.legislation_center()
	return main.modal_root.get_child(n - 1)


func _run() -> void:
	await _wait(5)
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	# Criador: idade.
	var creator := _top()
	var slider: HSlider = creator.get_node("%age_slider")
	slider.value = 67
	await _wait()
	_check((creator.get_node("%age_label") as Label).text == "67 anos", "the creator shows the age")
	await _shot("v1_criador_idade")
	creator.get_node("%Confirm").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	_check(main.playing, "the match starts")
	_check(People.age_of(w.leader, w) == 67, "the age applies: %d" % People.age_of(w.leader, w))
	var hud: Hud = main.hud
	hud.refresh_leader()
	_check(hud._leader_name.text.contains("67 anos"), "the panel shows the age:" + hud._leader_name.text)
	# Dossier with the leader's age and treaty.
	var usa: Country = w.by_iso["USA"]
	main.map.select(usa)
	hud.show_country(usa)
	await _wait()
	_check(hud._dossier_dyn.leader.text.contains("anos"), "the dossier shows the leader's age:" + hud._dossier_dyn.leader.text)
	await _shot("v2_dossie")
	w.diplomacy.set_relation(w.player.idx, usa.idx, 95.0)
	hud.get_node("%ProposeTreaty").pressed.emit()
	await _wait()
	var treaty := _top()
	_check(main.modal_open and treaty.get_node("%type_pick").item_count == Treaties.TYPES.size(), "the treaty window lists the types")
	var pick: OptionButton = treaty.get_node("%type_pick")
	for i in pick.item_count:
		if pick.get_item_metadata(i) == "climate":
			pick.select(i)
			pick.item_selected.emit(i)
	treaty.get_node("%propose").pressed.emit()
	await _wait()
	_check((treaty.get_node("%feedback") as Label).text != "", "o outro lado responde: " + (treaty.get_node("%feedback") as Label).text)
	await _shot("v3_tratado")
	treaty.get_node("%close").pressed.emit()
	await _wait()
	main.map.select(null)
	hud.show_country(null)
	# Election: report.
	Game.world.politics.player_election(w)
	Game.world.politics.revision += 1
	hud._desk.current_tab = hud._politics_tab
	hud.refresh(true)
	await _wait()
	var last: Button = hud._politics.get_node("%LastElection")
	_check(not last.disabled, "there is an election result")
	last.pressed.emit()
	await _wait()
	var report := _top()
	_check((report.get_node("%report") as RichTextLabel).text.contains("deputados"), "the report shows the seats")
	await _shot("v4_eleicao")
	report.get_node("%close").pressed.emit()
	await _wait()
	# Centro legislativo: tratados.
	main.open_legislation(4)
	await _wait()
	var center := _top()
	_check(center.get_node("%treaty_rows").get_child_count() >= 1, "the Treaties tab lists the country's treaties")
	await _shot("v5_tratados")
	center.get_node("%close").pressed.emit()
	await _wait()
	# Editor: ministry block.
	var law: Dictionary = w.legislation.new_norm(w, "ordinaria")
	law.title = "Fusão"
	law.ementa = "Teste"
	var stack := LawProgram.add_stack(law.program, LawProgram.new_block(law.program, "ev_enact"), Vector2(40, 40))
	var block := LawProgram.new_block(law.program, "ad_min_merge")
	stack.blocks.append(block)
	main.open_law_editor(law)
	await _wait()
	var editor: LawEditor = _top()
	_check(not editor.last_compile.ok, "without choosing the ministries, it is an error")
	editor.select_block(int(block.id))
	await _wait()
	var option: OptionButton = editor.get_node("%props_box").get_child(0).get_node("%option")
	_check(option.visible and option.item_count >= 8, "the field lists the ministries")
	await _shot("v6_ministerio")
	block.fields.a = "Saúde"
	block.fields.b = "Educação"
	block.fields.name = "Saúde e Educação"
	editor.refresh()
	await _wait()
	_check(editor.last_compile.ok, "with the ministries chosen, it compiles: %s" % str(editor.last_compile.errors))
	editor.close_editor()
	await _wait()
	_top().get_node("%close").pressed.emit()
	await _wait()
	# Leader asking for a conversation.
	w.next_talk_month = 0
	w.request_talk(usa)
	await _wait(6)
	_check(main.modal_open, "the conversation request appears")
	await _shot("v7_pedido_conversa")
	var dim := _top()
	dim.get_node("%col").get_child(dim.get_node("%col").get_child_count() - 2).get_node("%pick").pressed.emit()
	await _wait()
	_check(_top().find_child("talk_compass", true, false) != null, "answering opens the conversation")
	await _shot("v8_conversa")
	_top().get_node("%say_end").pressed.emit()
	await _wait()
	# Janela.
	_check(not get_window().unresizable, "the window can be resized")
	var size0 := get_window().size
	get_window().size = Vector2i(1100, 700)
	await _wait(8)
	_check(get_window().size.x <= 1200, "o tamanho muda: %s" % str(get_window().size))
	hud._desk.current_tab = 0
	await _shot("v9_janela_menor")
	get_window().size = size0
	await _wait(8)
	# Resignation and new character.
	main._open_menu()
	await _wait()
	var menu := _top()
	await _shot("v10_pausa")
	menu.get_node("%Resign").pressed.emit()
	await _wait()
	_top().get_node("%Confirm").pressed.emit()
	await _wait(6)
	_check(w.over and main.modal_open, "renunciar encerra a carreira")
	var end := _top()
	await _shot("v11_fim")
	_check(end.get_node("%NewCharacter") != null and end.get_node("%NewGame") != null, "one can choose between the two exits")
	end.get_node("%NewCharacter").pressed.emit()
	await _wait()
	var next_creator := _top()
	(next_creator.get_node("%first_name_edit") as LineEdit).text = "Maria"
	(next_creator.get_node("%first_name_edit") as LineEdit).text_changed.emit("Maria")
	(next_creator.get_node("%last_name_edit") as LineEdit).text = "Sucessora"
	(next_creator.get_node("%last_name_edit") as LineEdit).text_changed.emit("Sucessora")
	next_creator.get_node("%Confirm").pressed.emit()
	await _wait()
	_check(not w.over and w.leader.name == "Maria Sucessora", "the same match continues with another person")
	_top().get_node("%cancel").pressed.emit()
	await _wait()
	_check(not main.modal_open and Game.world == w, "o jogo continua")
	hud.refresh(true)
	await _shot("v12_novo_personagem")
	main._set_speed(3)
	await _wait(30)
	main.join_sim()
	main._set_speed(0)
	_check(not w.over, "o tempo volta a andar")
