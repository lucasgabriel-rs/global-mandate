extends Node
## Roteiro com cliques: bússola, ministros, conversa com líder, derrota eleitoral e volta ao poder.
## Uso: godot --path . -- --ui-statecraft --shots=/caminho/da/pasta

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
	print("ok: " if cond else "FALHA: ", what)


func _click(b: Control) -> void:
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
	var w: GameWorld = main.world
	var hud: Hud = main.hud
	var root: Control = main.modal_root
	match step:
		1:
			main._pick_start(w.by_iso["BRA"])
			main._start_button.pressed.emit()
		2:
			_click(_text(root, "Confirmar"))
		3:
			# A bússola só aparece para quem vai criar um partido.
			var compass: CompassView = _named(root, "my_compass")
			_check(compass != null and not compass.is_visible_in_tree(), "escolher um partido existente não pede bússola")
			(_named(root, "found_toggle") as Button).pressed.emit()
		4:
			var compass: CompassView = _named(root, "my_compass")
			_check(compass.is_visible_in_tree() and compass.interactive, "criar partido abre a bússola")
			var r := compass.get_global_rect()
			_click_at(r.position + Vector2(r.size.x * 0.9, r.size.y * 0.1))
			var me: Dictionary = compass.points[-1]
			_check(float(me.econ) > 0.5 and float(me.social) < -0.5, "clique marca direita e autoritário (%.2f, %.2f)" % [me.econ, me.social])
			_shot("s1_escolha")
			_click(_text(root, "assentos"))
		5:
			_check(main.playing, "partida começa")
			main._set_speed(0)
			_check(absf(float(w.leader.econ) - float(w.politics.player_party(w).econ)) < 0.2, "quem entra em um partido adota as ideias dele")
			var me := w.politics.player_politician(w)
			_check(me.get("player", false) and absf(float(me.econ) - float(w.leader.econ)) < 0.001, "o jogador é um político do partido")
			hud._gov_tabs.current_tab = hud._cabinet_tab
		6:
			_check(not hud._gov_tabs.get_tab_bar().get_offset_buttons_visible(), "as 9 abas cabem, sem setas")
			_check(hud._cabinet._rows.get_child_count() == Politics.PORTFOLIOS.size(), "uma linha por pasta")
			_shot("s2_ministros")
			_click(_named(hud._cabinet, "pick_finance"))
		7:
			_check(main.modal_open, "escolher abre a lista")
			_shot("s3_escolha_ministro")
			var first := _text(root, "competência")
			_check(first != null, "lista traz a competência: " + (first.text if first else ""))
			first.pressed.emit()
		8:
			_check(not main.modal_open and not w.politics.minister(w, "finance").is_empty(), "nomeia: " + hud._cabinet._status.text)
			hud._gov_tabs.current_tab = hud._politics_tab
		9:
			_shot("s4_politica")
			var party: Dictionary = w.politics.player_party(w)
			_click(_named(hud._politics, "party_%d" % int(party.id)))
		10:
			_check(main.modal_open and _named(root, "party_compass") != null, "partido mostra a bússola")
			_shot("s5_partido")
			var compass: CompassView = _named(root, "party_compass")
			var party: Dictionary = w.politics.player_party(w)
			_check(compass.points.size() == party.members.size() + 1, "um ponto por político, mais a média")
			_click(_text(root, "Fechar"))
		11:
			main.map.select(w.by_iso["ARG"])
			hud.show_country(w.by_iso["ARG"])
		12:
			_shot("s6_dossie")
			_check(hud._dossier_dyn.leader.text != "—", "dossiê mostra o líder: " + hud._dossier_dyn.leader.text)
			var talk: Button = hud._dossier_dyn.talk
			_check(talk.text.begins_with("Falar com"), talk.text)
			_click(talk)
		13:
			_check(main.modal_open and _named(root, "talk_compass") != null, "conversa abre com a bússola do líder")
			_shot("s7_conversa")
			mark = w.diplomacy.relation(w.player.idx, w.by_iso["ARG"].idx)
			_click(_named(root, "say_praise"))
		14:
			_check(w.diplomacy.relation(w.player.idx, w.by_iso["ARG"].idx) > mark, "elogiar melhora a relação")
			_check((_named(root, "talk_reply") as Label).text.begins_with("“"), "líder responde: " + (_named(root, "talk_reply") as Label).text)
			_shot("s8_resposta")
			_click(_named(root, "say_protest"))
		15:
			_click(_named(root, "say_protest"))
		16:
			_check(_named(root, "say_praise") == null, "depois de 3 falas a conversa termina")
			_click(_named(root, "say_end"))
		17:
			_check(not main.modal_open, "encerrar fecha a conversa")
			_check((hud._dossier_dyn.talk as Button).disabled, "uma conversa por mês")
			main.map.select(null)
			hud.show_country(null)
			# Perder a eleição.
			w.player.dem = 7.0
			w.player.approval = 0.02
			w.player.next_election = w.year_float()
			w.check_player_politics(w.player)
		18:
			_check(main.modal_open and not w.over, "eleição perdida abre o aviso, sem fim de jogo")
			_shot("s9_derrota")
			_dismiss()
		19:
			_check(not w.in_office and hud._player_name.text.contains("oposição"), "barra mostra a oposição: " + hud._player_name.text)
			_check(not (hud._sliders.sp_social as HSlider).editable, "controles travados")
			hud._gov_tabs.current_tab = hud._politics_tab
			w.player.next_election = 9999.0
		20:
			_check(hud._politics._opposition.visible, "ações da oposição aparecem")
			_shot("s10_oposicao")
			mark = w.player.approval
			_click(_text(hud._politics._opposition, "Criticar"))
		21:
			_check(w.player.approval < mark, "criticar derruba a aprovação: " + hud._politics._status.text)
			hud._gov_tabs.current_tab = hud._cabinet_tab
		22:
			_check(_named(hud._cabinet, "pick_finance") == null, "ministros travados na oposição")
			main.map.select(w.by_iso["ARG"])
			hud.show_country(w.by_iso["ARG"])
		23:
			_check((hud._dossier_dyn.talk as Button).disabled, "sem conversa na oposição")
			_shot("s11_oposicao_dossie")
			main.map.select(null)
			hud.show_country(null)
			# Avanço com a IA governando.
			mark = w.day_index
			main.start_skip(30)
			wait = 0.8
		24:
			_check(w.day_index == int(mark) + 30 and not main.modal_open, "tempo avança na oposição, sem janelas")
			main._save_game()
		25:
			main._load_game()
		26:
			_check(not w.in_office, "carregar mantém a oposição")
			_check(hud._player_name.text.contains("oposição"), "barra mantém a oposição")
			_check(not (hud._sliders.sp_social as HSlider).editable, "controles seguem travados")
			# Volta ao poder: partido do jogador forte contra um governo impopular.
			var data := w.politics.data_of(w.player.iso)
			w.politics.player_party(w).support = 0.6
			Politics._normalize(data)
			w.player.approval = 0.03
			w.player.next_election = w.year_float()
			w.check_player_politics(w.player)
			wait = 0.6
		27:
			_check(w.in_office, "eleição devolve o poder")
			_shot("s12_volta")
			_dismiss()
		28:
			hud.refresh(true)
			_check(not hud._player_name.text.contains("oposição"), "barra volta ao normal: " + hud._player_name.text)
			_check((hud._sliders.sp_social as HSlider).editable, "controles voltam")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			# Nova partida, já na oposição, com partido existente.
			main._restart()
		29:
			main._pick_start(w.by_iso["DEU"])
			main._start_button.pressed.emit()
		30:
			_click(_text(root, "Confirmar"))
		31:
			_check(_named(root, "role_government") != null and _named(root, "role_opposition") != null, "escolha de papel aparece")
			var ruling: Dictionary = w.politics.ruling_party("DEU")
			_check(not _text(root, ruling.name).disabled, "para governar, qualquer partido serve")
			_click(_named(root, "role_opposition"))
		32:
			var ruling: Dictionary = w.politics.ruling_party("DEU")
			_check(_text(root, ruling.name).disabled, "na oposição, o partido do governo fica indisponível")
			_shot("s13_papel_oposicao")
			mark = ruling.id
			var other: Dictionary = {}
			for p: Dictionary in w.politics.data_of("DEU").parties:
				if p.id != ruling.id:
					other = p
			_click(_text(root, other.name))
		33:
			_check(main.playing and not w.in_office and not w.over, "partida começa na oposição")
			_check(int(w.politics.ruling_party("DEU").id) == int(mark), "o governo segue o mesmo")
			_check(int(w.politics.player_party(w).id) != int(mark), "o jogador está em outro partido")
			_check(w.politics.data_of("DEU").get("cabinet", {}).is_empty(), "sem gabinete na oposição")
			_check(hud._player_name.text.contains("oposição"), "barra indica a oposição: " + hud._player_name.text)
			_check(not (hud._sliders.sp_social as HSlider).editable, "controles travados desde o início")
			main._set_speed(0)
			hud._gov_tabs.current_tab = hud._politics_tab
		34:
			_check(hud._politics._opposition.visible, "ações da oposição desde o início")
			_shot("s14_comeca_oposicao")
			main._restart()
		35:
			# Nova partida na oposição, com partido próprio.
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
			_check(main.playing and not w.in_office, "partido próprio na oposição")
			_check(w.politics.player_party(w).name == "Partido da Oposição Própria", "jogador lidera o partido criado")
			_check(w.politics.ruling_party("DEU").name != "Partido da Oposição Própria", "partido novo não governa")
			_check(w.politics.player_party(w).members[0].get("player", false), "jogador é o líder do partido novo")
			main._restart()
		39:
			# Partido próprio governando.
			main._pick_start(w.by_iso["DEU"])
			main._start_button.pressed.emit()
		40:
			_click(_text(root, "Confirmar"))
		41:
			(_named(root, "found_toggle") as Button).pressed.emit()
			(_named(root, "party_name") as LineEdit).text = "Partido do Governo Próprio"
			_text(root, "Fundar partido").pressed.emit()
		42:
			_check(main.playing and w.in_office, "partido próprio no governo")
			_check(w.politics.ruling_party("DEU").name == "Partido do Governo Próprio", "partido criado governa")
			_check(not w.politics.minister(w, "finance").is_empty(), "com gabinete")
			main._restart()
		43:
			# Regime fechado só permite governar.
			main._pick_start(w.by_iso["CHN"])
			main._start_button.pressed.emit()
		44:
			_click(_text(root, "Confirmar"))
		45:
			_check((_named(root, "role_opposition") as Button).disabled, "regime fechado não tem oposição jogável")
			_shot("s15_regime_fechado")
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)
