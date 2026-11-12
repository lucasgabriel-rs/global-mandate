extends Node
## Records the geometry and style of each visible control on every screen, plus a capture of
## each one. Running before and after touching the scenes and comparing shows whether something moved.
## Uso: godot --path . -- --ui-layout --shots=DIR

const CONTAINERS := ["VBoxContainer", "HBoxContainer", "GridContainer", "CenterContainer", "MarginContainer", "ScrollContainer", "CanvasLayer"]

var main: Node
var out_dir := ""
var lines: PackedStringArray = []


func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _run()
	var f := FileAccess.open(out_dir.path_join("layout.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("RESULT: 0 failures")
	get_tree().quit()


func _style_text(c: Control, slot: String, kind: String) -> String:
	if not c.has_theme_stylebox(slot, kind):
		return ""
	var box := c.get_theme_stylebox(slot, kind)
	if box is StyleBoxFlat:
		return "%s/%s/%d" % [box.bg_color.to_html(), box.border_color.to_html(), int(box.content_margin_left)]
	return box.get_class()


func _dump_node(n: Node, out: PackedStringArray) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var c: Control = n
		var kind := c.get_class()
		var plain := kind == "Control" and c.get_script() == null
		if not plain and not CONTAINERS.has(kind):
			var r := c.get_global_rect()
			var label := kind
			if c.get_script():
				label = c.get_script().resource_path.get_file()
			var text := ""
			var extra := ""
			if c is Label:
				text = c.text
				extra = "%d %s" % [c.get_theme_font_size("font_size"), c.get_theme_color("font_color").to_html()]
			elif c is Button:
				text = c.text
				extra = "%d %s %s %s" % [c.get_theme_font_size("font_size"), c.get_theme_color("font_color").to_html(), _style_text(c, "normal", "Button"), str(c.disabled)]
			elif c is LineEdit:
				text = c.text + "|" + c.placeholder_text
			elif c is PanelContainer:
				extra = _style_text(c, "panel", "PanelContainer")
			elif c is ColorRect:
				extra = c.color.to_html()
			var tip := c.tooltip_text.replace("\n", " ")
			out.append("%s %d,%d %dx%d [%s] <%s> {%s}" % [label, roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y), text.replace("\n", " / "), tip, extra])
		if c is ColorPicker:
			return
	for child in n.get_children():
		_dump_node(child, out)


func _snap(screen: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out: PackedStringArray = []
	_dump_node(main.ui_layer, out)
	out.sort()
	lines.append("=== " + screen)
	lines.append_array(out)
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(screen + ".png"))


func _close() -> void:
	var dim: Node = main.modal_root.get_child(main.modal_root.get_child_count() - 1)
	main.modal_root.remove_child(dim)
	dim.queue_free()
	main.modal_open = false
	main.map.interactive = true
	await get_tree().process_frame


func _run() -> void:
	SaveService.delete_files()
	await _snap("inicio")
	var world: GameWorld = Game.world
	var brazil: Country = world.by_iso["BRA"]
	var usa: Country = world.by_iso["USA"]
	main._pick_start(brazil)
	await _snap("inicio_pais")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ch := Character.random(rng)
	main._open_creator(ch, func(_c): pass)
	await _snap("criador")
	await _close()
	main._open_party_picker(brazil, true, func(_c): pass)
	await _snap("partido_inicio")
	await _close()
	main._begin(ch, {})
	main._set_speed(0)
	var hud: Hud = main.hud
	for i in hud._desk.get_tab_count():
		hud._desk.current_tab = i
		hud.refresh(true)
		await _snap("aba_%d" % i)
	hud._desk.current_tab = 0
	hud.show_country(usa)
	await _snap("dossie_outro")
	hud.show_country(brazil)
	await _snap("dossie_proprio")
	hud.show_country(null)
	var hint := {"title": "Decisão", "text": "Texto da decisão", "options": [{"label": "Opção A", "hint": "Dica A"}, {"label": "Opção B"}]}
	main._open_menu()
	await _snap("pausa")
	await _close()
	main._show_help()
	await _snap("ajuda")
	await _close()
	main._confirm("Confirma isto?", func(): pass)
	await _snap("confirmar")
	await _close()
	main._show_prompt(hint)
	await _snap("decisao")
	await _close()
	var party_id: int = world.politics.player_party(world).id
	main._open_party_detail(party_id)
	await _snap("partido_detalhe")
	await _close()
	main._open_minister_picker(String(Politics.PORTFOLIOS[0].id))
	await _snap("ministro")
	await _close()
	main._open_talk(usa)
	await _snap("conversa")
	await _close()
	main._open_party_picker(brazil, false, func(_c): pass)
	await _snap("partido_jogo")
	await _close()
	main._on_game_ended({"reason": "eleicao", "text": "Fim", "score": 100.0, "years": 4.0, "mandates": 1})
	await _snap("fim_de_jogo")
	await _close()
	hud.debug.toggle()
	await _snap("debug")
	hud.debug.toggle()
	hud.show_skip_summary(7, hud.skip_snapshot(), [["Fato A", "guerra"], ["Fato B", "economia"]])
	await _snap("resumo_dias")
	hud._skip_card.visible = false
	world.emit_news("Notícia de crise", "guerra", usa)
	await _snap("noticia")
	hud._toast.visible = false
	world.do_action("war", world.by_iso["ARG"])
	hud._desk.current_tab = 4
	hud.refresh(true)
	await _snap("guerra")
	var state: Dictionary = {"kind": "negotiation", "war": {}, "rival": usa, "budget": 0.1}
	hud.border.bind(world, main.map)
	hud.border.begin(state)
	await _snap("fronteira_negociar")
	hud.border._close()
	state.kind = "victory"
	hud.border.begin(state)
	await _snap("fronteira_vitoria")
	hud.border._close()
	hud._desk.current_tab = hud._divisions_tab
	hud.refresh(true)
	await _snap("divisoes_pais")
	var unit: int = world.subdivisions.roots_of("BRA")[0]
	hud._divisions.select_unit(unit)
	await _snap("divisoes_unidade")
	hud._divisions._search.text = "rio"
	hud._divisions._rebuild_tree()
	await _snap("divisoes_busca")
	hud._divisions._search.text = ""
	hud._divisions.start_merge()
	await _snap("divisoes_fusao")
	hud._divisions._end_merge()
	world.start_in_opposition()
	hud.refresh(true)
	hud._desk.current_tab = hud._politics_tab
	hud.refresh(true)
	await _snap("oposicao_politica")
	hud._desk.current_tab = hud._cabinet_tab
	hud.refresh(true)
	await _snap("oposicao_ministros")
