extends Node
## Roteiro com cliques: criador stickman, roda de cor, pele, escolha de partido e parlamento.
## Uso: godot --path . -- --ui-politics --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var leader := {}
var income0 := 0.0
var health0 := 0.0
var infra0 := 0.0


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
	var at := b.get_global_rect().get_center()
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
			_check(main.modal_open, "criador abriu")
			_shot("p1_criador")
			for key: String in ["first_name_edit", "last_name_edit", "gender_m", "gender_f", "roll_name", "age_slider"]:
				_check(_named(root, key) != null, "opção " + key)
			var view := _view(root)
			leader = view.character
			_check(view.iso == "BRA", "a bola veste a bandeira do país escolhido")
			(_named(root, "first_name_edit") as LineEdit).text = "Palito"
			(_named(root, "first_name_edit") as LineEdit).text_changed.emit("Palito")
			_click(_named(root, "gender_f"))
		3:
			_check(leader.gender == "f" and leader.first_name == "Palito", "gênero troca e o nome digitado fica")
			_check(_view(root).is_female(), "a bola mostra o laço")
		4:
			_shot("p2_personalizado")
			_click(_text(root, "Confirmar"))
		5:
			_check(main.modal_open and not main.playing, "partido é obrigatório antes de começar")
			_shot("p3_partidos")
			_check(not (_named(root, "my_compass") as Control).is_visible_in_tree(), "sem criar partido, não há bússola para escolher")
			(_named(root, "found_toggle") as Button).pressed.emit()
			_check((_named(root, "my_compass") as Control).is_visible_in_tree(), "criar partido abre a bússola")
			(_named(root, "party_name") as LineEdit).text = ""
			_text(root, "Fundar partido").pressed.emit()
		6:
			_check(not main.playing, "nome vazio não funda")
			var data: Dictionary = w.politics.data_of("BRA")
			(_named(root, "party_name") as LineEdit).text = data.parties[0].name
			_click(_text(root, "Fundar partido"))
		7:
			_check(not main.playing, "nome repetido não funda")
			(_named(root, "party_name") as LineEdit).text = "Partido do Palito"
			_click(_text(root, "Fundar partido"))
		8:
			_check(main.playing, "fundar inicia a partida")
			w = main.world
			_check(w.politics.player_party(w).name == "Partido do Palito", "jogador pertence ao partido fundado")
			_check(w.leader.first_name == "Palito" and w.leader.gender == "f", "personagem chega à partida")
			main._set_speed(0)
			hud._desk.current_tab = hud._politics_tab
		9:
			_shot("p4_parlamento")
			_check(hud._dock.items().size() == hud._desk.get_tab_count(), "o dock tem um ícone por janela")
			_check(not hud._politics._hemicycle._seats.is_empty(), "plenário desenhado")
			var total: int = w.politics.data_of("BRA").seats_total
			_check(hud._politics._hemicycle._seats.size() == total, "um ponto por assento")
			_check(hud._politics._hemicycle.seat_positions(total).size() == total, "uma posição por assento")
			# A lista fica abaixo da dobra da aba: na interface real, o jogador rola até ela.
			_text(hud._politics._bills, "Plano nacional").pressed.emit()
		10:
			var status: String = hud._politics._status.text
			_check(status.contains("Plano nacional") and status.contains("parlamento"), "o projeto vai ao parlamento: " + status)
			_check(_text(hud._politics._bills, "Plano nacional").disabled, "projeto votado sai da pauta")
			hud._politics.party_requested.emit()
		11:
			_check(main.modal_open, "trocar partido abre a escolha")
			_shot("p5_trocar")
			_check(_text(root, "Ficar em Partido do Palito") != null, "partido atual aparece como ficar")
			_click(_text(root, "Cancelar"))
		12:
			_check(not main.modal_open, "cancelar fecha a janela")
			main.map.select(w.by_iso["ARG"])
			hud.show_country(w.by_iso["ARG"])
		13:
			_check(hud._dossier_dyn.gov_party.text != "—", "dossiê mostra o partido no governo: " + hud._dossier_dyn.gov_party.text)
			_shot("p6_dossie")
			main.map.select(null)
			hud.show_country(null)
			# Orçamento direto pelos controles da aba Fiscal.
			hud._desk.current_tab = 1
			income0 = w.player.sp_social
			(hud._sliders.sp_social as HSlider).value = income0 * 100.0 + 2.0
		14:
			_check(absf(w.player.sp_social - income0 - 0.02) < 0.002, "o controle muda o gasto na hora: %s" % w.player.sp_social)
			_check(not hud._sliders.has("tax_income") and not hud._sliders.has("tariff"), "tributos não têm controle deslizante")
			_check(hud._dyn.f_rate_tax_income.text.ends_with("%"), "a aba mostra a alíquota em vigor: " + hud._dyn.f_rate_tax_income.text)
			_shot("p7_orcamento")
		15:
			# Uma lei obriga o valor e trava o controle.
			var lock_law: Dictionary = w.legislation.new_norm(w, "ordinaria")
			lock_law.title = "Piso"
			lock_law.ementa = "Teste"
			lock_law.program = LawTemplates.budget_law("sp_health", 9.0)
			lock_law.process = {"steps": ["publish"], "at": 0, "due": 0, "log": []}
			w.legislation._publish(w, lock_law)
			hud._sync_sliders()
			hud.refresh(true)
		16:
			_check(not (hud._sliders.sp_health as HSlider).editable, "lei trava o controle")
			_check(hud._slider_labels.sp_health.text.begins_with("Por lei"), "controle diz que é por lei: " + hud._slider_labels.sp_health.text)
			_check(absf(w.player.sp_health - 0.09) < 0.001, "o gasto segue a lei")
			_shot("p8_aprovado")
			# Projeto de lei aprovado também aparece no controle.
			hud._desk.current_tab = hud._politics_tab
		17:
			infra0 = (hud._sliders.sp_infra as HSlider).value
			_text(hud._politics._bills, "Pacote de infraestrutura").pressed.emit()
		18:
			for i in 90:
				w.player.next_election = 9999.0
				w.tick_day()
			hud._sync_sliders()
			_check((hud._sliders.sp_infra as HSlider).value > infra0, "projeto aprovado aparece no controle")
			main._save_game()
		19:
			main._load_game()
		20:
			_check(main.world.politics.player_party(main.world).name == "Partido do Palito", "carregar mantém o partido")
			_check(main.world.leader.first_name == "Palito" and main.world.leader.gender == "f", "carregar mantém o personagem")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)


func _view(root: Node) -> Countryball:
	for child in root.find_children("*", "Control", true, false):
		if child is Countryball:
			return child
	return null
