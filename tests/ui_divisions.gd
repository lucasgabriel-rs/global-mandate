extends Node
## Roteiro da aba Divisões: usa as unidades do cenário e desenha novas com cliques reais no mapa.
## Uso: godot --path . -- --ui-divisions --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var state_id := -1
var child_id := -1
var coast_id := -1
var state_name := ""
var mun_id := -1
var frame_sum := 0.0
var frame_max := 0.0
var frame_count := 0


func _ready() -> void:
	Legislation.skip_unit_approval = true
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


func _screen(offset: Vector2) -> Vector2:
	return Vector2(800, 400) + offset


func _click(screen: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.position = screen
		ev.global_position = screen
		ev.pressed = pressed
		get_viewport().push_input(ev)


func _move(screen: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen
	ev.global_position = screen
	get_viewport().push_input(ev)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	get_viewport().push_input(e)


func _state_center(s: Subdivisions, state: String) -> Vector2:
	for id: int in s.roots_of("BRA"):
		if s.units[id].name == state:
			return s.units[id].center
	return Vector2.ZERO


func _polygon(offsets: Array) -> void:
	for o: Vector2 in offsets:
		_click(_screen(o))
	_click(_screen(offsets[0]))


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	if step == 24:
		frame_sum += delta
		frame_max = maxf(frame_max, delta)
		frame_count += 1
	wait -= delta
	if wait > 0.0:
		return
	# Os passos com captura extra do mapa ficam fora da sequência normal.
	if step == 17:
		step = 169
	elif step == 171:
		step = 17
	step += 1
	wait = 0.5
	var w: GameWorld = main.world
	var hud: Hud = main.hud
	var map: MapView = main.map
	var panel: DivisionsPanel = hud._divisions if hud else null
	var subs: Subdivisions = w.subdivisions
	match step:
		1:
			main._pick_start(w.by_iso["BRA"])
		2:
			_shot("d0_inicio")
			main._begin()
			main._set_speed(0)
		3:
			_shot("d0b_mundo")
			# As duas fontes de fronteiras devem concordar sobre quem controla cada unidade.
			var differ := []
			for u: Dictionary in subs.units.values():
				var land: Country = map.country_at(u.center)
				if land and land.iso != u.owner:
					differ.append("%s(%s/%s)" % [u.name, u.owner, land.iso])
			print("unidades em país diferente no mapa: %d  %s" % [differ.size(), ", ".join(differ.slice(0, 40))])
			_check(differ.size() < subs.base_count * 0.02, "unidades coincidem com os países do mapa")
			map._camera.position = w.player.center
			map._camera.zoom = Vector2.ONE * 3.2
			hud._gov_tabs.current_tab = hud._divisions_tab
		4:
			_check(map.unit_pick, "aba Divisões ativa a seleção de unidades")
			_check(panel._tree_box.get_child_count() == 28, "árvore lista o país e as 27 unidades do Brasil")
			_check(subs.get_type(panel.active_type).owner == "BRA", "tipos do painel são do país do jogador")
			_shot("d1_cenario")
			panel._on_new_type()
		5:
			var mine := subs.types_of("BRA")
			var edit: LineEdit = panel._types_box.get_child(mine.size() - 1).get_child(1)
			_check(edit.has_focus(), "novo tipo abre com o nome em edição")
			edit.text = "Região Autônoma"
			edit.release_focus()
		6:
			_check(subs.get_type(panel.active_type).name == "Região Autônoma", "tipo renomeado pelo campo")
			_key(KEY_N)
		7:
			_check(map.drawing, "tecla N inicia o desenho")
			_click(_screen(Vector2(-90, -90)))
			_click(_screen(Vector2(90, -90)))
			_click(_screen(Vector2(90, 0)))
			_click(_screen(Vector2(0, 40)))
			_check(map.draft.size() == 4, "vértices colocados por clique")
			_move(_screen(Vector2(-60, -40)))
		8:
			_shot("d2_desenhando")
			_click(_screen(Vector2(40, 40)), MOUSE_BUTTON_RIGHT)
			_check(map.draft.size() == 3, "botão direito desfaz o último vértice")
			_key(KEY_ESCAPE)
		9:
			_check(not map.drawing and subs.custom_ids.is_empty(), "Esc cancela sem criar unidade")
			_check(not main.modal_open, "Esc no desenho não abre o menu")
			hud.start_drawing()
			_click(_screen(Vector2(-100, -100)))
			_click(_screen(Vector2(-100, -100)))
			_check(map.draft.size() == 1 and map.drawing, "fechar com 1 vértice é recusado")
			_click(_screen(Vector2(100, -100)))
			_click(_screen(Vector2(100, 0)))
			_click(_screen(Vector2(0, -160)))
			_check(map.draft.size() == 3, "aresta cruzada é recusada")
		10:
			_shot("d3_recusa")
			_click(_screen(Vector2(-100, 0)))
			_click(_screen(Vector2(-100, -100)))
			_check(subs.custom_ids.is_empty() and not map.drawing, "polígono sobre estados existentes é recusado no nível do país")
			_check(panel._status.text.contains("Selecione uma unidade"), "mensagem orienta o jogador")
		11:
			# O primeiro clique seleciona o estado e o segundo, o município; desenha dentro dele.
			_click(_screen(Vector2.ZERO))
			state_id = panel.selected_unit
			_check(state_id >= 0 and subs.units[state_id].owner == "BRA" and subs.units[state_id].parent == -1, "primeiro clique seleciona o estado")
			state_name = subs.units[state_id].name
			print("estado: ", state_name)
			_click(_screen(Vector2.ZERO))
			mun_id = panel.selected_unit
			_check(subs.units[mun_id].parent == state_id, "segundo clique desce para o município: " + String(subs.units[mun_id].name))
			_check(panel._expanded.has(state_id), "lista abre o estado do município selecionado")
			_click(_screen(Vector2.ZERO))
			_check(panel.selected_unit == mun_id, "terceiro clique continua no município")
			hud.start_drawing()
			_polygon([Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)])
		12:
			_check(subs.custom_ids.size() == 1 and not map.drawing, "voltar ao primeiro ponto cria a unidade")
			child_id = subs.custom_ids[0]
			var child: Dictionary = subs.units[child_id]
			print("criada: ", child.name)
			_check(child.parent == mun_id, "unidade fica dentro do município selecionado")
			_check(subs.get_type(child.type).name == "Região Autônoma", "unidade usa o tipo ativo")
			panel.select_unit(child_id)
			panel._set_active_type(int(subs.types_of("BRA")[0].id))
		13:
			hud.start_drawing()
			_polygon([Vector2(-15, -15), Vector2(15, -15), Vector2(15, 15), Vector2(-15, 15)])
		14:
			_check(subs.custom_ids.size() == 2 and subs.depth_of(subs.custom_ids[1]) == 3, "quarto nível criado")
			# Município do litoral: o polígono avança sobre o oceano e fica só a parte em terra.
			_click(_screen(Vector2(290, 0)))
			_click(_screen(Vector2(290, 0)))
			coast_id = panel.selected_unit
			_check(coast_id >= 0 and subs.units[coast_id].parent != -1 and subs.chain_of(coast_id)[0] != state_id and subs.units[coast_id].base, "seleciona um município de outro estado")
			hud.start_drawing()
			_polygon([Vector2(270, -20), Vector2(420, -20), Vector2(420, 40), Vector2(270, 40)])
		15:
			_check(subs.custom_ids.size() == 3, "unidade no litoral criada")
			var coast: Dictionary = subs.units[subs.custom_ids[2]]
			var raw := 150.0 * 60.0 / pow(map._camera.zoom.x, 2.0)
			print("costa: área %.1f do polígono de %.1f" % [coast.area, raw])
			_check(coast.area < raw * 0.9, "polígono é recortado pelo município")
			# Busca pelo nome e lista recolhida.
			panel.select_unit(-1)
			panel._search.text = "Belém"
			panel._rebuild_tree()
			_check(panel._tree_box.get_child_count() >= 1 and panel._tree_box.get_child_count() < 10, "busca acha Belém (%d)" % panel._tree_box.get_child_count())
			_shot("d3b_busca")
			panel._search.text = ""
			panel._rebuild_tree()
			# Estado estrangeiro: passar o mouse identifica, clicar abre o dossiê e não seleciona.
			panel.select_unit(state_id)
			_move(_screen(Vector2(-260, 150)))
		16:
			_check(hud._hover_label.text.contains("Bolívia") or hud._hover_label.text.contains("Peru"), "hover mostra unidade estrangeira: " + hud._hover_label.text)
			_click(_screen(Vector2(-260, 150)))
			_check(panel.selected_unit == -1 and hud._dossier.visible, "clique em unidade estrangeira abre o dossiê")
			_check(hud._dossier_dyn.units.text != "0", "dossiê mostra as unidades do país: " + hud._dossier_dyn.units.text)
			panel.select_unit(state_id)
		17:
			_shot("d4_hierarquia")
			map._camera.position = _state_center(subs, "São Paulo")
			map._camera.zoom = Vector2.ONE * 7.0
		170:
			pass
		171:
			_shot("d4a_sao_paulo")
			map._camera.zoom = Vector2.ONE * 1.6
			map._camera.position = w.by_iso["DEU"].center
		18:
			_shot("d4b_europa")
			map._camera.zoom = Vector2.ONE * 1.8
			map._camera.position = w.usa.center
		19:
			_shot("d4c_eua")
			map._camera.position = w.player.center
			map._camera.zoom = Vector2.ONE * 3.2
			subs.rename_unit(coast_id, "Litoral Renomeado")
			main._save_game()
		20:
			var f := FileAccess.open(main.SAVE_PATH, FileAccess.READ)
			print("save: %d KB" % (f.get_length() / 1024))
			f.close()
			main._load_game()
		21:
			var s2: Subdivisions = main.world.subdivisions
			_check(s2.custom_ids.size() == 3 and s2.units.size() == s2.base_count + 3, "carregar restaura cenário e unidades")
			_check(s2.depth_of(s2.custom_ids[1]) == 3, "carregar restaura a hierarquia")
			_check(s2.units[coast_id].name == "Litoral Renomeado", "carregar restaura o nome editado")
			hud._gov_tabs.current_tab = hud._divisions_tab
			hud._on_mode("inflacao")
		22:
			_shot("d5_carregado_modo_dados")
			hud._on_mode("politico")
			panel.select_unit(state_id)
			panel._ask_delete(panel.selected_unit)
		23:
			_shot("d6_confirmar")
			for dim in main.modal_root.get_children():
				if dim is ColorRect:
					_press(dim, "Confirmar")
		24:
			var s2: Subdivisions = main.world.subdivisions
			_check(not s2.units.has(state_id) and s2.custom_ids.size() == 1, "apagar o estado remove as unidades dentro dele")
			# País e os 26 estados que sobraram, recolhidos.
			_check(panel._tree_box.get_child_count() == 27, "árvore atualizada (%d)" % panel._tree_box.get_child_count())
			_shot("d7_apagado")
			main._set_speed(3)
			wait = 4.0
		25:
			_dismiss()
			print("fps com o jogo correndo: ", Engine.get_frames_per_second())
			print("tempo por quadro: médio %.1f ms, máximo %.1f ms em %d quadros" % [frame_sum / maxi(frame_count, 1) * 1000.0, frame_max * 1000.0, frame_count])
			main._set_speed(0)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)


func _dismiss() -> void:
	for dim in main.modal_root.get_children():
		if dim is ColorRect:
			var b := _first(dim)
			if b:
				b.pressed.emit()


func _first(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _first(child)
		if found:
			return found
	return null


func _press(node: Node, text: String) -> void:
	for child in node.get_children():
		if child is Button and child.text == text:
			child.pressed.emit()
			return
		_press(child, text)
