extends Node
## Roteiro com cliques reais: criador de personagem, fundir, desmembrar, demarcar e negociar.
## Uso: godot --path . -- --ui-borders --shots=/caminho/da/pasta

const COUNTRYBALL := preload("res://scenes/ui/countryball.tscn")

var main: Node
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var merged_id := -1
var war: Dictionary
var pop0 := 0.0


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


func _click(screen: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.position = screen
		ev.global_position = screen
		ev.pressed = pressed
		get_viewport().push_input(ev)


## Posição na tela de um ponto do mapa.
func _at(world_pos: Vector2) -> Vector2:
	return main.map.get_canvas_transform() * world_pos


func _polygon(center: Vector2, r_px: float) -> void:
	var c := _at(center)
	var corners := [c + Vector2(-r_px, -r_px), c + Vector2(r_px, -r_px), c + Vector2(r_px, r_px), c + Vector2(-r_px, r_px)]
	for p: Vector2 in corners:
		_click(p)
	_click(corners[0])


func _press(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Button and child.text == text:
			child.pressed.emit()
			return true
		if _press(child, text):
			return true
	return false


func _press_containing(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Button and child.text.contains(text):
			child.pressed.emit()
			return true
		if _press_containing(child, text):
			return true
	return false


func _press_named(node: Node, name_: String) -> bool:
	for child in node.get_children():
		if child is Button and child.name == name_:
			child.pressed.emit()
			return true
		if _press_named(child, name_):
			return true
	return false


func _unit(s: Subdivisions, iso: String, name_: String) -> int:
	for id: int in s.roots_of(iso):
		if s.units[id].name == name_:
			return id
	return -1


func _center(iso: String, name_: String) -> Vector2:
	var s: Subdivisions = main.world.subdivisions
	return s.units[_unit(s, iso, name_)].center


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	wait -= delta
	if wait > 0.0:
		return
	step += 1
	wait = 0.5
	var w: GameWorld = main.world
	var hud: Hud = main.hud
	var map: MapView = main.map
	var panel: DivisionsPanel = hud._divisions
	var s: Subdivisions = w.subdivisions
	match step:
		1:
			main._pick_start(w.by_iso["BRA"])
			main._start_button.pressed.emit()
		2:
			_check(main.modal_open, "assumir o governo abre o criador")
			_shot("c1_criador")
			_press_named(main.modal_root, "gender_f")
		3:
			_shot("c2_alterado")
			# Uma countryball de cada país, para conferir todas as bandeiras em uma galeria.
			_gallery()
		4:
			_shot("c3_galeria")
			_clear_gallery()
			_press(main.modal_root, "Confirmar")
			# O partido é obrigatório: escolhe o primeiro da lista.
			_press_containing(main.modal_root, "assentos")
		5:
			_check(main.playing and not w.leader.is_empty(), "confirmar inicia a partida com o personagem")
			_check(not main.modal_open, "criador fecha")
			main._set_speed(0)
		6:
			_shot("c4_jogo")
			map._camera.position = w.player.center
			map._camera.zoom = Vector2.ONE * 3.2
			hud._desk.current_tab = hud._divisions_tab
		7:
			_click(_at(_center("BRA", "Pará")))
			_check(s.units[panel.selected_unit].name == "Pará", "seleciona o Pará")
			_press(panel, "Fundir com...")
		8:
			_check(panel._merging, "entra no modo de fusão")
			_click(_at(_center("BRA", "Amazonas")))
			_check(panel._merge_ids.size() == 2, "clique acrescenta a vizinha")
		9:
			_shot("f1_fusao")
			_press(panel, "Confirmar fusão")
		10:
			merged_id = panel.selected_unit
			_check(merged_id >= 0 and s.units[merged_id].name == "Pará" and _unit(s, "BRA", "Amazonas") == -1, "fusão pela interface")
			_shot("f2_fundido")
			_press(panel, "Desmembrar")
		11:
			_check(map.drawing and panel._splitting, "desmembrar abre o desenho")
			_polygon(s.units[merged_id].center, 26.0)
		12:
			_check(s.custom_ids.size() >= 2 and not map.drawing, "desmembrar pela interface")
			print("status: ", panel._status.text)
			_shot("f3_desmembrado")
			hud._desk.current_tab = 0
			panel.select_unit(-1)
			# Guerra vencida contra a Argentina.
			var arg: Country = w.by_iso["ARG"]
			w.diplomacy.declare_war(w.player, arg, w)
			war = w.diplomacy.war_between(w.player.idx, arg.idx)
			pop0 = arg.pop
			main.prompts.clear()
			war.front = 98.0
			w.diplomacy._capitulation(war, w.player, arg, w)
		13:
			_check(main.modal_open, "vitória abre a decisão")
			_shot("b1_decisao")
			_press(main.modal_root, "Demarcar novas fronteiras")
		14:
			wait = 0.8
			_check(hud.border.active and map.drawing, "demarcação ativa")
			map._camera.position = _center("ARG", "Córdoba")
			map._camera.zoom = Vector2.ONE * 3.0
		15:
			main._set_speed(3)
			hud.border.set_meta("clock", w.day_index * 1440 + w.minute)
			_polygon(_center("ARG", "Córdoba"), 40.0)
		16:
			_check(int(hud.border.get_meta("clock")) == w.day_index * 1440 + w.minute, "relógio parado durante a demarcação")
			_check(hud.border._areas.size() == 1, "área marcada")
			_polygon(_center("ARG", "Mendoza"), 60.0)
		17:
			_check(hud.border._areas.size() == 2, "segunda área marcada")
			_shot("b2_demarcando")
			_press(hud.border, "Desfazer última área")
		18:
			_check(hud.border._areas.size() == 1, "desfazer remove a última")
			_press(hud.border, "Confirmar novas fronteiras")
		19:
			var arg: Country = w.by_iso["ARG"]
			_check(not hud.border.active and not map.drawing, "sessão encerrada")
			_check(not w.diplomacy.wars.has(war) and arg.alive, "guerra encerrada, rival vivo")
			_check(w.territories.owner_at(_center("ARG", "Mendoza") if _unit(s, "ARG", "Mendoza") >= 0 else Vector2.ZERO, w) == null, "o que foi desfeito não muda de mão")
			_check(arg.pop < pop0, "território leva a população")
			main._set_speed(0)
		20:
			_shot("b3_fronteira_nova")
			main.map.select(w.player)
			main.hud.show_country(w.player)
		21:
			_shot("b4_selecionado")
			main.map.select(null)
			main.hud.show_country(null)
			# Paz sem vencedor com o Paraguai.
			var pry: Country = w.by_iso["PRY"]
			w.diplomacy.declare_war(w.player, pry, w)
			war = w.diplomacy.war_between(w.player.idx, pry.idx)
			main.prompts.clear()
			war.front = 1.0
			pry.war_exhaustion = 1.0
			w._offer_negotiation(war, pry)
		22:
			_check(main.modal_open, "paz sem vencedor abre a negociação")
			_shot("n1_escolha")
			_press(main.modal_root, "Propor novas fronteiras")
		23:
			map._camera.position = w.by_iso["PRY"].center
			map._camera.zoom = Vector2.ONE * 3.0
		24:
			# Pedido exagerado: boa parte do Paraguai, sem oferecer nada.
			_polygon(w.by_iso["PRY"].center, 60.0)
		25:
			_shot("n2_pedido")
			print(hud.border._usage.text)
			_press(hud.border, "Enviar proposta")
		26:
			_check(hud.border.active and w.diplomacy.wars.has(war), "rival recusa pedido exagerado")
			print("resposta: ", hud.border._feedback.text)
			_shot("n3_recusa")
			_press(hud.border, "Desfazer última área")
			_polygon(w.by_iso["PRY"].center + Vector2(0, -6), 8.0)
		27:
			_press(hud.border, "Enviar proposta")
		28:
			_check(not hud.border.active and not w.diplomacy.wars.has(war), "proposta razoável é aceita")
			_shot("n4_acordo")
			main._save_game()
		29:
			var count: int = w.territories.cessions.size()
			hud.set_meta("count", count)
			main._load_game()
		30:
			_check(main.world.territories.cessions.size() == int(hud.get_meta("count")), "carregar restaura as fronteiras")
			_check(not main.world.leader.is_empty(), "carregar restaura o personagem")
			_shot("n5_carregado")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)


var _gallery_root: Control


func _gallery() -> void:
	_gallery_root = ColorRect.new()
	(_gallery_root as ColorRect).color = Color("20323e")
	_gallery_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.modal_root.add_child(_gallery_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var grid := GridContainer.new()
	grid.columns = 15
	_gallery_root.add_child(grid)
	for c: Country in main.world.countries:
		var v: Countryball = COUNTRYBALL.instantiate()
		v.custom_minimum_size = Vector2(72, 72)
		var who := Character.random(rng, c.iso)
		v.show_person(who, c.iso)
		v.tooltip_text = c.iso
		grid.add_child(v)


func _clear_gallery() -> void:
	main.modal_root.remove_child(_gallery_root)
	_gallery_root.queue_free()
