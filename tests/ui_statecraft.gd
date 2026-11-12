extends Node
## Script with clicks: compass, ministers, conversation with a leader, electoral defeat and return to power.
## Usage: godot --path . -- --ui-statecraft --shots=/path/to/folder

var main: Node
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var mark := 0.0


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)


func _shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])
	print("shot: ", name_)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _click(b: Control) -> void:
	# In the windows the content scrolls: brings the target into the visible area before the click.
	var scroll := b.get_parent()
	while scroll and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll:
		(scroll as ScrollContainer).ensure_control_visible(b)
		scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_click_at(b.get_global_rect().get_center())


func _click_at(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = pressed
		get_viewport().push_input(ev)


func _named(node: Node, name_: String) -> Node:
	return node.find_child(name_, true, false)


func _text(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.contains(text):
			return child
		var found := _text(child, text)
		if found:
			return found
	return null


func _dismiss() -> void:
	for dim in main.modal_root.get_children():
		if dim is ColorRect and not dim.is_queued_for_deletion():
			for label: String in ["Liderar a oposição", "Assumir o governo", "Seguir"]:
				var b := _text(dim, label)
				if b:
					b.pressed.emit()
					break


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	wait -= delta
	if wait > 0.0:
		return
	step += 1
	wait = 0.4
	var w: GameWorld = Game.world
	var hud: Hud = main.hud
	var root: Control = main.modal_root
	match step:
		1:
			main._pick_start(w.by_iso["BRA"])
			main._start_button.pressed.emit()
		2:
			_click(_text(root, "Confirmar"))
		3:
			# The compass only appears for whoever is going to create a party.
			var compass: CompassView = _named(root, "my_compass")
			_check(compass != null and not compass.is_visible_in_tree(), "choosing an existing party does not ask for a compass")
			(_named(root, "found_toggle") as Button).pressed.emit()
		4:
			var compass: CompassView = _named(root, "my_compass")
			_check(compass.is_visible_in_tree() and compass.interactive, "creating a party opens the compass")
			var r := compass.get_global_rect()
			_click_at(r.position + Vector2(r.size.x * 0.9, r.size.y * 0.1))
			var me: Dictionary = compass.points[-1]
			_check(float(me.econ) > 0.5 and float(me.social) < -0.5, "click marks right and authoritarian (%.2f, %.2f)" % [me.econ, me.social])
			_shot("s1_choice")
			_click(_text(root, "assentos"))
		5:
			_check(main.playing, "match starts")
			main._set_speed(0)
			_check(absf(float(w.leader.econ) - float(w.politics.player_party(w).econ)) < 0.2, "whoever joins a party adopts its ideas")
			var me := w.politics.player_politician(w)
			_check(me.get("player", false) and absf(float(me.econ) - float(w.leader.econ)) < 0.001, "the player is a politician of the party")
			hud._desk.current_tab = hud._cabinet_tab
		6:
			_check(hud._dock.items().filter(func(i): return i.window_index >= 0).size() == hud._desk.get_tab_count(), "the dock has one icon per window")
			_check(hud._cabinet._rows.get_child_count() == Politics.PORTFOLIOS.size(), "one row per portfolio")
			_shot("s2_ministers")
			_click(_named(hud._cabinet, "pick_finance"))
		7:
			_check(main.modal_open, "choosing opens the list")
			_shot("s3_choice_minister")
			var first := _text(root, "competência")
			_check(first != null, "list brings the competence:" + (first.text if first else ""))
			first.pressed.emit()
		8:
			_check(not main.modal_open and not w.politics.minister(w, "finance").is_empty(), "nomeia: " + hud._cabinet._status.text)
			hud._desk.current_tab = hud._politics_tab
		9:
			_shot("s4_politics")
			var party: Dictionary = w.politics.player_party(w)
			_click(_named(hud._politics, "party_%d" % int(party.id)))
		10:
			_check(main.modal_open and _named(root, "party_compass") != null, "party shows the compass")
			_shot("s5_party")
			var compass: CompassView = _named(root, "party_compass")
			var party: Dictionary = w.politics.player_party(w)
			_check(compass.points.size() == party.members.size() + 1, "one dot per politician, plus the average")
			_click(_text(root, "Fechar"))
		11:
			main.map.select(w.by_iso["ARG"])
			hud.show_country(w.by_iso["ARG"])
		12:
			_shot("s6_dossier")
			_check(hud._dossier_dyn.leader.text != "—", "dossier shows the leader:" + hud._dossier_dyn.leader.text)
			var talk: Button = hud._dossier_dyn.talk
			_check(talk.text.begins_with("Falar com"), talk.text)
			_click(talk)
		13:
			_check(main.modal_open and _named(root, "talk_compass") != null, "conversation opens with the leader's compass")
			_shot("s7_conversation")
			mark = w.diplomacy.relation(w.player.idx, w.by_iso["ARG"].idx)
			_click(_named(root, "say_praise"))
		14:
			_check(w.diplomacy.relation(w.player.idx, w.by_iso["ARG"].idx) > mark, "praising improves the relation")
			var thread: Array = ChatLog.thread(w, ChatLog.country_key("ARG"))
			_check(thread.size() == 3 and thread[1].me and not thread[2].me, "the line and the answer become bubbles:" + str(thread.size()))
			_check((_named(root, "thread") as Control).get_child_count() == 3, "the conversation shows one bubble per message")
			_check(_named(root, "contact_party_%d" % int(PartyTalk.contacts(w)[0].id)) != null, "party leaders appear as contacts")
			_shot("s8_answer")
			_click(_named(root, "say_protest"))
		15:
			_click(_named(root, "say_protest"))
		16:
			_check(_named(root, "say_praise") == null, "after 3 lines the conversation ends")
			_click(_named(root, "say_end"))
		17:
			_check(not main.modal_open, "ending closes the conversation")
			_check((hud._dossier_dyn.talk as Button).disabled, "one conversation a month")
			main.map.select(null)
			hud.show_country(null)
			# Losing the election.
			w.player.dem = 7.0
			w.player.approval = 0.02
			w.player.next_election = w.year_float()
			w.check_player_politics(w.player)
		18:
			_check(main.modal_open and not w.over, "lost election opens the notice, without game over")
			_shot("s9_defeat")
			_dismiss()
		19:
			_check(not w.in_office and hud._player_name.text.contains("oposição"), "bar shows the opposition:" + hud._player_name.text)
			_check(not (hud._sliders.sp_social as HSlider).editable, "controles travados")
			hud._desk.current_tab = hud._politics_tab
			w.player.next_election = 9999.0
		20:
			_check(hud._politics._opposition.visible, "opposition actions appear")
			_shot("s10_opposition")
			mark = w.player.approval
			_click(_text(hud._politics._opposition, "Criticar"))
		21:
			_check(w.player.approval < mark, "criticizing brings down approval:" + hud._politics._status.text)
			hud._desk.current_tab = hud._cabinet_tab
		22:
			# The window of another role does not open, so the panel keeps its old rows hidden; nothing can be clicked.
			var pick := _named(hud._cabinet, "pick_finance")
			_check(not hud._desk.is_open(hud._cabinet_tab) and (pick == null or not pick.is_visible_in_tree()), "ministers locked in opposition")
			main.map.select(w.by_iso["ARG"])
			hud.show_country(w.by_iso["ARG"])
		23:
			_check((hud._dossier_dyn.talk as Button).disabled, "no conversation in opposition")
			_shot("s11_opposition_dossier")
			main.map.select(null)
			hud.show_country(null)
			# Advance with the AI governing.
			mark = w.day_index
			main.start_skip(30)
			wait = 0.8
		24:
			_check(w.day_index == int(mark) + 30 and not main.modal_open, "time advances in opposition, with no windows")
			main._save_game()
		25:
			main._load_game()
		26:
			_check(not w.in_office, "loading keeps the opposition")
			_check(hud._player_name.text.contains("oposição"), "bar keeps the opposition")
			_check(not (hud._sliders.sp_social as HSlider).editable, "controles seguem travados")
			# Return to power: the player's strong party against an unpopular government.
			var data := w.politics.data_of(w.player.iso)
			w.politics.player_party(w).support = 0.6
			Politics._normalize(data)
			w.player.approval = 0.03
			w.player.next_election = w.year_float()
			w.check_player_politics(w.player)
			wait = 0.6
		27:
			_check(w.in_office, "election returns power")
			_shot("s12_return")
			_dismiss()
		28:
			hud.refresh(true)
			_check(not hud._player_name.text.contains("oposição"), "bar goes back to normal:" + hud._player_name.text)
			_check((hud._sliders.sp_social as HSlider).editable, "controles voltam")
			SaveService.delete_files()
			# New match, already in opposition, with an existing party.
			main._restart()
		29:
			main._pick_start(w.by_iso["DEU"])
			main._start_button.pressed.emit()
		30:
			_click(_text(root, "Confirmar"))
		31:
			_check(_named(root, "role_government") != null and _named(root, "role_opposition") != null, "role choice appears")
			var ruling: Dictionary = w.politics.ruling_party("DEU")
			_check(not _text(root, ruling.name).disabled, "to govern, any party will do")
			_click(_named(root, "role_opposition"))
		32:
			var ruling: Dictionary = w.politics.ruling_party("DEU")
			_check(_text(root, ruling.name).disabled, "in opposition, the government party is unavailable")
			_shot("s13_role_opposition")
			mark = ruling.id
			var other: Dictionary = {}
			for p: Dictionary in w.politics.data_of("DEU").parties:
				if p.id != ruling.id:
					other = p
			_click(_text(root, other.name))
		33:
			_check(main.playing and not w.in_office and not w.over, "match starts in opposition")
			_check(int(w.politics.ruling_party("DEU").id) == int(mark), "the government stays the same")
			_check(int(w.politics.player_party(w).id) != int(mark), "the player is in another party")
			_check(w.politics.data_of("DEU").get("cabinet", {}).is_empty(), "no cabinet in opposition")
			_check(hud._player_name.text.contains("oposição"), "bar indicates the opposition:" + hud._player_name.text)
			_check(not (hud._sliders.sp_social as HSlider).editable, "controls locked from the start")
			main._set_speed(0)
			hud._desk.current_tab = hud._politics_tab
		34:
			_check(hud._politics._opposition.visible, "opposition actions from the start")
			_shot("s14_starts_opposition")
			main._restart()
		35:
			# New match in opposition, with their own party.
			main._pick_start(w.by_iso["DEU"])
			main._start_button.pressed.emit()
		36:
			_click(_text(root, "Confirmar"))
		37:
			_click(_named(root, "role_opposition"))
			(_named(root, "found_toggle") as Button).pressed.emit()
			(_named(root, "party_name") as LineEdit).text = "Partido da Oposição Própria"
			_text(root, "Fundar partido").pressed.emit()
		38:
			_check(main.playing and not w.in_office, "own party in opposition")
			_check(w.politics.player_party(w).name == "Partido da Oposição Própria", "player leads the created party")
			_check(w.politics.ruling_party("DEU").name != "Partido da Oposição Própria", "new party does not govern")
			_check(w.politics.player_party(w).members[0].get("player", false), "player is the leader of the new party")
			main._restart()
		39:
			# Own party governing.
			main._pick_start(w.by_iso["DEU"])
			main._start_button.pressed.emit()
		40:
			_click(_text(root, "Confirmar"))
		41:
			(_named(root, "found_toggle") as Button).pressed.emit()
			(_named(root, "party_name") as LineEdit).text = "Partido do Governo Próprio"
			_text(root, "Fundar partido").pressed.emit()
		42:
			_check(main.playing and w.in_office, "own party in government")
			_check(w.politics.ruling_party("DEU").name == "Partido do Governo Próprio", "created party governs")
			_check(not w.politics.minister(w, "finance").is_empty(), "with a cabinet")
			main._restart()
		43:
			# A closed regime only allows governing.
			main._pick_start(w.by_iso["CHN"])
			main._start_button.pressed.emit()
		44:
			_click(_text(root, "Confirmar"))
		45:
			_check((_named(root, "role_opposition") as Button).disabled, "a closed regime has no playable opposition")
			_shot("s15_regime_closed")
			print("RESULT: ", failures, " failures")
			get_tree().quit(1 if failures > 0 else 0)
