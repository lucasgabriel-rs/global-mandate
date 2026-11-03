extends Node
## Roteiro do centro legislativo com arrastar e soltar de verdade no editor de blocos.
## Uso: godot --path . -- --ui-legislation --shots=/caminho/da/pasta

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
	print("RESULTADO: %d falhas" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _wait(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name_: String) -> void:
	await _wait(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


func _mouse(at: Vector2, pressed: Variant = null) -> void:
	# O motor procura o alvo do arrasto na posição real do cursor, então ele precisa acompanhar.
	Input.warp_mouse(at)
	if pressed == null:
		var move := InputEventMouseMotion.new()
		move.position = at
		move.global_position = at
		move.relative = at - _last
		_last = at
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _down else 0
		get_viewport().push_input(move)
	else:
		var ev := InputEventMouseButton.new()
		ev.position = at
		ev.global_position = at
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		_down = pressed
		get_viewport().push_input(ev)
	await get_tree().process_frame


var _down := false
var _last := Vector2.ZERO


## Arrasta como o mouse faz: aperta, move em passos e solta.
func _drag(from: Vector2, to: Vector2) -> void:
	await _mouse(from)
	await _mouse(from, true)
	for i in range(1, 9):
		await _mouse(from.lerp(to, i / 8.0))
	await _mouse(to, false)
	await _wait(5)


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _mouse(at)
	await _mouse(at, true)
	await _mouse(at, false)
	await _wait(3)


func _library_block(editor: LawEditor, type: String) -> LawBlockView:
	for child in (editor.get_node("%library_list") as Control).get_children():
		if child is LawBlockView and child.block.type == type:
			return child
	return null


func _show_in_library(editor: LawEditor, view: Control) -> void:
	var scroll: ScrollContainer = (editor.get_node("%library_list") as Control).get_parent()
	scroll.ensure_control_visible(view)
	await _wait(3)
	scroll.scroll_horizontal = 0
	await _wait(3)


func _run() -> void:
	await _wait(5)
	main._pick_start(main.world.by_iso["BRA"])
	main._begin(Character.random(main.world.rng), {})
	main._set_speed(0)
	await _wait(5)
	var hud: Hud = main.hud
	hud._desk.current_tab = hud._politics_tab
	hud.refresh(true)
	await _wait()
	var tabs: TabContainer = hud._politics.get_node("%house_tabs")
	await _shot("l0_parlamento_camara")
	_check(tabs.tabs_visible and tabs.get_tab_title(0) == "Câmara" and tabs.get_tab_title(1) == "Senado", "o Brasil tem uma aba por casa")
	tabs.current_tab = 1
	await _shot("l0_parlamento_senado")
	_check(not hud._politics.get_node("%hemicycle_upper")._seats.is_empty(), "o senado tem plenário próprio")
	tabs.current_tab = 0
	var open_button: Button = hud._politics.get_node("%CentroLegislativo")
	await _click(open_button)
	var center := _top()
	_check(center is LegislationCenter, "o botão da aba Política abre o centro legislativo")
	_check(main.modal_open, "o tempo para com a janela aberta")
	await _shot("l1_centro")
	for tab in 5:
		center.get_node("%tabs").current_tab = tab
		await _shot("l1_aba_%d" % tab)
	center.get_node("%tabs").current_tab = 0
	await _wait()

	# Editor: norma nova, de lei ordinária.
	var types: OptionButton = center.get_node("%new_type")
	for i in types.item_count:
		if types.get_item_metadata(i) == "ordinaria":
			types.select(i)
	await _click(center.get_node("%new_norm"))
	var editor: LawEditor = _top()
	_check(editor is LawEditor, "abre o editor de blocos")
	await _shot("l2_editor_vazio")
	_check((editor.get_node("%present") as Button).disabled, "norma vazia não pode ser apresentada")
	var canvas: LawCanvas = editor.canvas
	var program: Dictionary = editor.norm_program()

	# Evento: arrasto real da biblioteca para a área.
	var ev := _library_block(editor, "ev_fiscal")
	await _show_in_library(editor, ev)
	await _drag(ev.get_global_rect().position + Vector2(20, 10), canvas.get_global_rect().position + Vector2(40, 40))
	_check(program.stacks.size() == 1 and program.stacks[0].blocks[0].type == "ev_fiscal", "arrastar da biblioteca cria um artigo")

	# Para cada: solto abaixo do evento.
	var loop := _library_block(editor, "fl_foreach")
	await _show_in_library(editor, loop)
	var target: LawBlockView = _find_view(canvas, "ev_fiscal")
	await _drag(loop.get_global_rect().position + Vector2(20, 10), target.get_global_rect().get_center() + Vector2(0, 8))
	_check(program.stacks[0].blocks.size() == 2 and program.stacks[0].blocks[1].type == "fl_foreach", "bloco de controle encaixa embaixo do evento")

	# Se: dentro do "para cada".
	var cond_block := _library_block(editor, "fl_if")
	await _show_in_library(editor, cond_block)
	var slot: LawSlot = _find_slot(_find_view(canvas, "fl_foreach"))
	await _drag(cond_block.get_global_rect().position + Vector2(10, 10), slot.get_global_rect().get_center())
	var foreach: Dictionary = program.stacks[0].blocks[1]
	_check(foreach.slots.do.size() == 1 and foreach.slots.do[0].type == "fl_if", "bloco entra na parte de dentro")
	await _shot("l3_montando")
	_check(not editor.last_compile.ok, "\"Se\" sem condição é erro na validação")
	_check((editor.get_node("%validation_list") as Control).get_child_count() >= 1, "a validação lista o problema")

	# Condição no encaixe do "se".
	var owner := _library_block(editor, "cd_owner")
	await _show_in_library(editor, owner)
	var socket: LawSocket = _find_socket(_find_view(canvas, "fl_if"), "cond")
	await _drag(owner.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	var if_block: Dictionary = foreach.slots.do[0]
	_check(if_block.plugs.has("cond") and if_block.plugs.cond.type == "cd_owner", "condição encaixa no campo")

	# Número não pode entrar em campo de condição: tenta com "idade do cidadão" no campo de outro "se".
	var charge := _library_block(editor, "ac_obligation")
	await _show_in_library(editor, charge)
	slot = _find_slot(_find_view(canvas, "fl_if"))
	await _drag(charge.get_global_rect().position + Vector2(10, 10), slot.get_global_rect().get_center())
	_check(if_block.slots.do.size() == 1 and if_block.slots.do[0].type == "ac_obligation", "ação entra no \"se\"")

	# Imposto de 5% sobre o valor tributável, encaixado no valor da obrigação.
	var tax := _library_block(editor, "ec_calc")
	await _show_in_library(editor, tax)
	socket = _find_socket(_find_view(canvas, "ac_obligation"), "amount")
	await _drag(tax.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	var obligation: Dictionary = if_block.slots.do[0]
	_check(obligation.plugs.has("amount"), "cálculo encaixa no valor")
	var value := _library_block(editor, "sb_value")
	await _show_in_library(editor, value)
	socket = _find_socket(_find_view(canvas, "ec_calc"), "base")
	await _drag(value.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	_check(obligation.plugs.amount.plugs.has("base"), "valor tributável encaixa na base")

	# Tipo errado é recusado.
	var wrong := _library_block(editor, "op_and")
	await _show_in_library(editor, wrong)
	socket = _find_socket(_find_view(canvas, "ec_calc"), "rate")
	await _drag(wrong.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	_check(not obligation.plugs.amount.plugs.has("rate"), "condição não entra em campo de número")
	program.stacks = program.stacks.filter(func(s): return s.blocks[0].type == "ev_fiscal")
	editor.refresh()
	await _wait()
	_check(editor.last_compile.ok, "a norma compila: %s" % str(editor.last_compile.errors))

	# Propriedades: clicar em um bloco mostra os parâmetros, e mudar o valor muda a norma.
	var calc_view := _find_view(canvas, "ec_calc")
	await _click(calc_view.get_child(0).get_child(0).get_child(0))
	_check(editor.selected_id == int(obligation.plugs.amount.id), "clicar seleciona o bloco")
	var row: Control = (editor.get_node("%props_box") as Control).get_child(0)
	var edit: LineEdit = row.get_node("%edit")
	_check(edit.text == "5", "painel mostra a alíquota")
	edit.text = "150"
	edit.text_changed.emit("150")
	await _wait()
	_check(not editor.last_compile.ok, "150% é operação impossível")
	edit.text = "5"
	edit.text_changed.emit("5")
	await _wait()
	_check(editor.last_compile.ok, "volta a compilar")

	# Documento.
	(editor.get_node("%doc_name") as LineEdit).text = "IPTU nacional"
	(editor.get_node("%doc_name") as LineEdit).text_changed.emit("IPTU nacional")
	(editor.get_node("%doc_ementa") as TextEdit).text = "Imposto anual de 5% sobre propriedades."
	(editor.get_node("%doc_ementa") as TextEdit).text_changed.emit()
	await _shot("l4_norma_pronta")
	_check((editor.get_node("%legal_text") as Control).size.x > 100.0, "o texto da norma ocupa a largura do painel")

	# Simulador do exemplo do documento.
	await _click(editor.get_node("%simulate"))
	var sim: LawSimulator = editor.get_node("%simulator")
	_check(sim.visible, "abre o simulador")
	var fund: float = main.world.politics.party_fund(main.world)
	var bucket: float = main.world.player.law_rev_bucket
	await _click(sim.get_node("%sim_run"))
	var result: String = (sim.get_node("%sim_result") as RichTextLabel).text
	print(result)
	_check(result.contains("100000,00") and result.contains("5000,00") and result.contains("Obrigação tributária criada"), "simulador mostra o cálculo")
	_check(main.world.player.law_rev_bucket == bucket and main.world.politics.party_fund(main.world) == fund, "simular não cobra nada")
	await _shot("l5_simulador")
	await _click(sim.get_node("%sim_close"))

	# Apresentar: a norma sai do editor e entra em tramitação.
	var norm: Dictionary = editor.norm
	await _click(editor.get_node("%present"))
	_check(norm.state == Legislation.STATE_PROCESS, "norma apresentada: %s" % norm.state)
	center = _top()
	_check(center is LegislationCenter and center.get_node("%tabs").current_tab == 1, "volta à aba de tramitação")
	await _shot("l6_tramitacao")
	# Negociação com as bancadas, pelos botões da tramitação.
	var process_row: Control = center.get_node("%process_rows").get_child(0)
	await _click(process_row.get_node("%negotiate"))
	var deal: NegotiationScreen = _top()
	_check(deal is NegotiationScreen, "abre a negociação de votos")
	await _shot("l6_negociacao")
	var data: Dictionary = main.world.politics.data_of("BRA")
	var other_party: int = -1
	for p: Dictionary in data.parties:
		if int(p.id) != int(data.player_party) and int(p.seats) > 0:
			other_party = int(p.id)
			break
	var ask: Button = deal.get_node("%rows").find_child("yes_%d" % other_party, true, false)
	await _click(ask)
	_check((deal.get_node("%feedback") as Label).text != "", "o partido responde: " + (deal.get_node("%feedback") as Label).text)
	_check(norm.get("asked", {}).has(str(other_party)), "a resposta fica registrada")
	await _shot("l6_negociacao_resposta")
	await _click(deal.get_node("%close"))
	center = _top()
	_check(center is LegislationCenter, "voltar retorna à tramitação")
	center.get_node("%close").pressed.emit()
	await _wait()
	_check(not main.modal_open, "fechar devolve o tempo")
	for i in 150:
		main.world.player.next_election = 9999.0
		main.world.tick_day()
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			break
	print("  estado: ", norm.state)
	_check(norm.state == Legislation.STATE_IN_FORCE or norm.state == Legislation.STATE_REJECTED, "a tramitação termina: %s" % norm.state)
	main.open_norm(norm)
	await _shot("l7_consulta")
	var page: NormPage = _top()
	_check(page.get_node("%law_text").text.contains("Art. 1º"), "a consulta mostra o texto")
	if norm.state == Legislation.STATE_IN_FORCE:
		page.get_node("%view_program").pressed.emit()
		await _wait()
		var reader: LawEditor = _top()
		_check(reader.read_only, "versão publicada abre só para leitura")
		var before := var_to_str(norm.versions[0].program)
		reader.drop({"law": true, "new": "ac_register", "kind": "statement"}, {"kind": "canvas", "pos": Vector2(300, 300)})
		await _wait()
		_check(var_to_str(norm.versions[0].program) == before, "versão publicada não muda")
		await _shot("l8_leitura")
		reader.close_editor()
		await _wait()

	# Emenda.
	main.reopen_legislation(0)
	await _wait()
	center = _top()
	center.get_node("%new_amendment").pressed.emit()
	await _wait()
	var amendment: AmendmentEditor = _top()
	_check(amendment is AmendmentEditor, "abre o editor de emendas")
	var mandate := {}
	for a: Dictionary in main.world.legislation.constitution.articles:
		if a.param == "mandate":
			mandate = a
	amendment.get_node("%article_list").get_child(3).get_node("%select").pressed.emit()
	await _wait()
	(amendment.get_node("%value_edit") as LineEdit).text = "5"
	amendment.get_node("%add_op").pressed.emit()
	await _wait()
	_check(amendment.norm.ops.size() == 1 and int(amendment.norm.ops[0].value) == 5, "a mudança entra na emenda")
	var diff: RichTextLabel = amendment.get_node("%op_list").get_child(0).get_node("%diff")
	_check(diff.text.contains("[s]4[/s]"), "compara com o texto anterior: %s" % diff.text)
	await _shot("l9_emenda")
	# Criar e excluir artigos, com os botões à vista.
	amendment.get_node("%new_article").pressed.emit()
	await _wait()
	(amendment.get_node("%new_text") as TextEdit).text = "O ensino básico é gratuito."
	amendment.get_node("%add_op").pressed.emit()
	await _wait()
	_check(amendment.norm.ops.size() == 2 and amendment.norm.ops[1].op == "add", "novo artigo entra na emenda")
	amendment.get_node("%article_list").get_child(5).get_node("%delete").pressed.emit()
	await _wait()
	_check(amendment.norm.ops.size() == 3 and amendment.norm.ops[2].op == "suppress", "excluir artigo entra na emenda")
	_check(amendment.get_node("%article_list").get_child(0).get_node("%delete").disabled, "cláusula pétrea não tem exclusão")
	await _shot("l9_emenda_criar_excluir")
	amendment.get_node("%delete_draft").pressed.emit()
	await _wait()

	# Teclado, save e carga.
	var center2 := _top()
	center2.get_node("%close").pressed.emit()
	await _wait()
	main._save_game()
	main.join_sim()
	var count: int = main.world.legislation.norms.size()
	await main._load_game()
	_check(main.world.legislation.norms.size() == count, "as normas voltam do save")
	_check(FileAccess.file_exists(main.SAVE_PATH), "o save ficou no lugar")
	main._save_game()
	main.join_sim()
	_check(FileAccess.file_exists(main.BACKUP_PATH), "o save anterior vira cópia de segurança")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.BACKUP_PATH))


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _find_view(from: Node, type: String) -> LawBlockView:
	for child in from.get_children():
		if child is LawBlockView and child.block.type == type and not child.in_library:
			return child
		var deep := _find_view(child, type)
		if deep:
			return deep
	return null


func _find_slot(view: LawBlockView) -> LawSlot:
	for child in view.get_node("%col").get_children():
		if child is LawSlot:
			return child
	return null


func _find_socket(view: LawBlockView, field: String) -> LawSocket:
	for child in view.get_node("%head").get_children():
		if child is LawSocket and child.field == field:
			return child
	return null

