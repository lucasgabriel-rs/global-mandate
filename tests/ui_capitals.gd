extends Node
## Roteiro das capitais com cliques reais no mapa e nos botões da aba Divisões.
## Uso: godot --path . -- --ui-capitals --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0


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


func _click(screen: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = screen
		ev.global_position = screen
		ev.pressed = pressed
		get_viewport().push_input(ev)


func _find(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.contains(text):
			return child
		var found := _find(child, text)
		if found:
			return found
	return null


func _state(s: Subdivisions, state: String) -> int:
	for id: int in s.roots_of("BRA"):
		if s.units[id].name == state:
			return id
	return -1


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
			main._begin()
			main._set_speed(0)
			hud._desk.current_tab = 0
		2:
			_shot("k1_mundo")
			_check(hud._dyn.o_capital.text == "Brasília", "painel mostra a capital do país")
			map._camera.position = s.units[_state(s, "São Paulo")].center
			map._camera.zoom = Vector2.ONE * 3.2
			hud._desk.current_tab = hud._divisions_tab
		3:
			_shot("k2_estados")
			_check(_find(panel._detail_box, "Brasília") != null, "aba mostra a capital do país")
			# Duplo nível: estado e depois o município sob o cursor.
			var at: Vector2 = map.get_canvas_transform() * (s.units[_state(s, "São Paulo")].center as Vector2)
			_click(at)
			_click(at)
		4:
			var mun: int = panel.selected_unit
			var state: int = s.chain_of(mun)[0]
			_check(s.units[mun].parent == state and s.units[state].name == "São Paulo", "município selecionado: " + String(s.units[mun].name))
			_check(s.capital_of(state) != mun, "ainda não é a capital")
			_shot("k3_controles")
			_click(_find(panel._detail_box, "Tornar capital de São Paulo").get_global_rect().get_center())
		5:
			var mun: int = panel.selected_unit
			var state: int = s.chain_of(mun)[0]
			_check(s.capital_of(state) == mun, "botão torna capital do estado: " + panel._status.text)
			_check(_find(panel._detail_box, "Capital de São Paulo: remover") != null, "botão vira remover")
			_click(_find(panel._detail_box, "Tornar capital de Brasil").get_global_rect().get_center())
		6:
			var mun: int = panel.selected_unit
			_check(s.capital_of("BRA") == mun, "botão torna capital do país")
			main.map.select(w.player)
			hud.show_country(w.player)
			_check(hud._dossier_dyn.capital.text == s.units[mun].name, "dossiê mostra a nova capital: " + hud._dossier_dyn.capital.text)
			main.map.select(null)
			hud.show_country(null)
			_shot("k4_nova_capital")
			var move := InputEventMouseMotion.new()
			move.position = map.get_canvas_transform() * (s.units[mun].center as Vector2)
			move.global_position = move.position
			get_viewport().push_input(move)
		7:
			_check(hud._hover_label.text.contains("capital de Brasil"), "hover informa a função: " + hud._hover_label.text)
			main._save_game()
			hud.set_meta("capital", s.capital_of("BRA"))
		8:
			main._load_game()
		9:
			_check(main.world.subdivisions.capital_of("BRA") == int(hud.get_meta("capital")), "carregar mantém a capital escolhida")
			hud._desk.current_tab = hud._divisions_tab
			panel.select_unit(int(hud.get_meta("capital")))
		10:
			_click(_find(panel._detail_box, "Capital de Brasil: remover").get_global_rect().get_center())
		11:
			var s2: Subdivisions = main.world.subdivisions
			_check(s2.capital_of("BRA") == -1, "botão remove a capital do país")
			panel.select_unit(-1)
		12:
			_check(_find(panel._detail_box, "Brasília") == null, "aba indica país sem capital")
			_shot("k5_sem_capital")
			main.map.select(main.world.player)
			hud.show_country(main.world.player)
			_check(hud._dossier_dyn.capital.text == "—", "dossiê indica país sem capital")
			main._set_speed(3)
			wait = 2.0
		13:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)
