extends Node
## Legislative center script with real drag and drop in the block editor.
## Usage: godot --path . -- --ui-legislation --shots=/path/to/folder

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


func _mouse(at: Vector2, pressed: Variant = null) -> void:
	# The engine looks for the drag target at the cursor's real position, so it needs to follow.
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


## Drags as the mouse does: presses, moves in steps and releases.
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
	var found := _find_library(editor.get_node("%library_list"), type)
	if found and not found.is_visible_in_tree():
		var group := editor.library_group_of(found)
		if group:
			(group.get_node("%toggle") as Button).button_pressed = true
	return found


func _find_library(from: Node, type: String) -> LawBlockView:
	for child in from.get_children():
		if child is LawBlockView and child.block.type == type:
			return child
		if not child is LawBlockView:
			var deep := _find_library(child, type)
			if deep:
				return deep
	return null


func _show_in_library(editor: LawEditor, view: Control) -> void:
	var scroll: ScrollContainer = (editor.get_node("%library_list") as Control).get_parent()
	scroll.ensure_control_visible(view)
	await _wait(3)
	scroll.scroll_horizontal = 0
	await _wait(3)


func _run() -> void:
	await _wait(5)
	main._pick_start(Game.world.by_iso["BRA"])
	main._begin(Character.random(Game.world.rng), {})
	main._set_speed(0)
	await _wait(5)
	var hud: Hud = main.hud
	hud._desk.current_tab = hud._politics_tab
	hud.refresh(true)
	await _wait()
	var tabs: TabContainer = hud._politics.get_node("%house_tabs")
	await _shot("l0_parliament_lower_house")
	_check(tabs.tabs_visible and tabs.get_tab_title(0) == "Câmara" and tabs.get_tab_title(1) == "Senado", "Brazil has one tab per house")
	tabs.current_tab = 1
	await _shot("l0_parliament_senate")
	_check(not hud._politics.get_node("%hemicycle_upper")._seats.is_empty(), "the senate has its own chamber")
	tabs.current_tab = 0
	var open_button: Button = hud._politics.get_node("%LegislativeCenter")
	await _click(open_button)
	var center := _top()
	_check(center is LegislationCenter, "the Politics tab button opens the legislative center")
	_check(main.legislation_center() != null, "the center opens as a floating window")
	await _shot("l1_center")
	for tab in 5:
		center.get_node("%tabs").current_tab = tab
		await _shot("l1_aba_%d" % tab)
	center.get_node("%tabs").current_tab = 0
	await _wait()

	# Codes: one card per code, and "Alterar" opens the editor with only the blocks of that area.
	var cards: Control = center.get_node("%code_cards")
	_check(cards.get_child_count() == LawCodes.all().size(), "one card per code: %d" % cards.get_child_count())
	var tax_card: Control = cards.get_node("code_tributario")
	_check((tax_card.get_node("%articles") as Label).text.contains("artigo"), "the tax card shows the articles:" + (tax_card.get_node("%articles") as Label).text)
	await _click(tax_card.get_node("%alter"))
	var code_editor: LawEditor = _top()
	_check(code_editor is LawEditor and code_editor.code_id == "tributario", "the card opens the Tax Code editor")
	_check(int(code_editor.norm.get("amends", -1)) >= 0, "it is a project that amends the code in force")
	var lib: Control = code_editor.get_node("%library_list")
	_check(lib.has_node("cat_events") and not lib.has_node("cat_flow") and not lib.has_node("cat_direitos"), "the palette shows only the code and the events")
	var adv: Control = lib.get_node("group_avançado")
	_check(not (adv.get_node("%items") as Control).visible, "the advanced ones start collapsed")
	await _shot("l2_code_tax")
	# The tax palette is long: scrolls to the group's button before clicking.
	var lib_scroll := lib.get_parent() as ScrollContainer
	if lib_scroll:
		lib_scroll.ensure_control_visible(adv.get_node("%toggle"))
		await _wait()
	await _click(adv.get_node("%toggle"))
	_check((adv.get_node("%items") as Control).visible, "one click opens the Advanced group")
	await _shot("l2_code_advanced_open")
	await _click(adv.get_node("%toggle"))
	# Names: exemption picks the tax from a list, with "Outro nome" only to create.
	var tax_program: Dictionary = code_editor.norm_program()
	var exempt := LawProgram.new_block(tax_program, "ec_exempt")
	tax_program.stacks[0].blocks.append(exempt)
	code_editor.refresh()
	code_editor.select_block(int(exempt.id))
	await _wait()
	var ref_row: Control = (code_editor.get_node("%props_box") as Control).get_child(0)
	var ref_option: OptionButton = ref_row.get_node("%option")
	_check(ref_option.visible and ref_option.get_item_text(ref_option.item_count - 1) == LawEditor.REF_NEW, "tax comes from a list, with Another name at the end")
	_check(not (ref_row.get_node("%edit") as Control).visible, "no free text until asking for a new name")
	await _shot("l2_list_of_names")
	tax_program.stacks[0].blocks.erase(exempt)
	code_editor.selected_id = -1
	# Raises the corporate income tax by five points and sends.
	for b: Dictionary in tax_program.stacks[0].blocks:
		if b.type == "tr_irpj":
			b.fields.aliquota = float(b.fields.aliquota) + 5.0
	code_editor.refresh()
	await _wait()
	_check(code_editor.last_compile.ok, "the code amendment compiles: %s" % str(code_editor.last_compile.errors))
	await _click(code_editor.get_node("%present"))
	var review: LawReview = code_editor.get_node("%review")
	_check(review.visible, "presenting first shows the expected effects")
	_check((review.get_node("%rv_budget") as Label).text.contains("US$"), "the panel shows the effect on the budget:" + (review.get_node("%rv_budget") as Label).text)
	_check((review.get_node("%rv_groups") as RichTextLabel).text.contains("Trabalhadores"), "and the reaction of the social groups")
	_check((review.get_node("%rv_parties") as RichTextLabel).text.contains("tende a"), "and that of the parties")
	var review_track: ProcessTrack = review.get_node("%rv_track")
	_check((review_track.get_node("%chips") as Control).get_child_count() >= 4, "and the path in parliament")
	_check((review_track.get_node("%rule") as Label).text.contains("maioria"), "a line explains the norm type:" + (review_track.get_node("%rule") as Label).text)
	await _shot("l2_effects_expected")
	var tax_bill: Dictionary = code_editor.norm
	await _click(review.get_node("%rv_send"))
	_check(tax_bill.state == Legislation.STATE_PROCESS, "the code amendment enters procedure: %s" % tax_bill.state)
	center = _top()
	_check(center is LegislationCenter, "goes back to the legislative center")
	var tax_row: Control = center.get_node("%process_rows").get_node("process_%d" % int(tax_bill.id))
	var track: ProcessTrack = tax_row.get_node("%track")
	var chips: Control = track.get_node("%chips")
	_check((chips.get_child(0).get_node("%chip_name") as Label).text == "Comissão", "the step by step starts at the committee")
	_check((track.get_node("%chance") as Label).text.contains("Chance de aprovação"), "shows the chance of approval:" + (track.get_node("%chance") as Label).text)
	_check((track.get_node("%now") as Label).text.contains("dias"), "and the days left:" + (track.get_node("%now") as Label).text)
	await _shot("l2_procedure_steps")
	# Rights and duties: concrete blocks, no typed names.
	(center.get_node("%Scroll") as ScrollContainer).scroll_vertical = 0
	await _wait()
	await _click(center.get_node("%code_cards").get_node("code_direitos").get_node("%alter"))
	var rights_editor: LawEditor = _top()
	_check(rights_editor is LawEditor and rights_editor.code_id == "direitos", "the card opens the Rights and duties editor")
	_check(_library_block(rights_editor, "dr_military") != null and _library_block(rights_editor, "dr_censor") != null, "the palette has military service and censorship")
	for b: Dictionary in LawProgram.all_blocks(rights_editor.norm_program()):
		if b.type == "dr_military":
			rights_editor.select_block(int(b.id))
	await _shot("l2_code_rights")
	await _click(rights_editor.get_node("%delete_draft"))
	center = _top()
	_check(center is LegislationCenter, "deleting the draft goes back to the center")

	# Editor: new norm, of an ordinary law.
	var types: OptionButton = center.get_node("%new_type")
	for i in types.item_count:
		if types.get_item_metadata(i) == "ordinaria":
			types.select(i)
	(center.get_node("%Scroll") as ScrollContainer).ensure_control_visible(center.get_node("%new_norm"))
	await _wait()
	await _shot("l1_law_standalone")
	await _click(center.get_node("%new_norm"))
	var editor: LawEditor = _top()
	_check(editor is LawEditor, "opens the block editor")
	_check(editor.code_id == "" and (editor.get_node("%library_list").get_node("group_avançado").get_node("%items") as Control).visible, "standalone law shows the advanced ones open")
	await _shot("l2_editor_empty")
	_check((editor.get_node("%present") as Button).disabled, "an empty norm cannot be presented")
	var canvas: LawCanvas = editor.canvas
	var program: Dictionary = editor.norm_program()

	# Event: real drag from the library to the area.
	var ev := _library_block(editor, "ev_fiscal")
	await _show_in_library(editor, ev)
	await _drag(ev.get_global_rect().position + Vector2(20, 10), canvas.get_global_rect().position + Vector2(40, 40))
	_check(program.stacks.size() == 1 and program.stacks[0].blocks[0].type == "ev_fiscal", "dragging from the library creates an article")

	# For each: dropped below the event.
	var loop := _library_block(editor, "fl_foreach")
	await _show_in_library(editor, loop)
	var target: LawBlockView = _find_view(canvas, "ev_fiscal")
	await _drag(loop.get_global_rect().position + Vector2(20, 10), target.get_global_rect().get_center() + Vector2(0, 8))
	_check(program.stacks[0].blocks.size() == 2 and program.stacks[0].blocks[1].type == "fl_foreach", "a control block fits below the event")

	# If: inside the "for each".
	var cond_block := _library_block(editor, "fl_if")
	await _show_in_library(editor, cond_block)
	var slot: LawSlot = _find_slot(_find_view(canvas, "fl_foreach"))
	await _drag(cond_block.get_global_rect().position + Vector2(10, 10), slot.get_global_rect().get_center())
	var foreach: Dictionary = program.stacks[0].blocks[1]
	_check(foreach.slots.do.size() == 1 and foreach.slots.do[0].type == "fl_if", "block goes into the inside")
	await _shot("l3_building")
	_check(not editor.last_compile.ok, "\"If\" with no condition is a validation error")
	_check((editor.get_node("%validation_list") as Control).get_child_count() >= 1, "the validation lists the problem")

	# Condition in the "if" fit.
	var owner := _library_block(editor, "cd_owner")
	await _show_in_library(editor, owner)
	var socket: LawSocket = _find_socket(_find_view(canvas, "fl_if"), "cond")
	await _drag(owner.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	var if_block: Dictionary = foreach.slots.do[0]
	_check(if_block.plugs.has("cond") and if_block.plugs.cond.type == "cd_owner", "condition fits into the field")

	# A number cannot go into a condition field: tries with "citizen's age" in another "if" field.
	var charge := _library_block(editor, "ac_obligation")
	await _show_in_library(editor, charge)
	slot = _find_slot(_find_view(canvas, "fl_if"))
	await _drag(charge.get_global_rect().position + Vector2(10, 10), slot.get_global_rect().get_center())
	_check(if_block.slots.do.size() == 1 and if_block.slots.do[0].type == "ac_obligation", "action goes into the \"if\"")

	# 5% tax on the taxable value, fitted into the value of the obligation.
	var tax := _library_block(editor, "ec_calc")
	await _show_in_library(editor, tax)
	socket = _find_socket(_find_view(canvas, "ac_obligation"), "amount")
	await _drag(tax.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	var obligation: Dictionary = if_block.slots.do[0]
	_check(obligation.plugs.has("amount"), "calculation fits into the value")
	var value := _library_block(editor, "sb_value")
	await _show_in_library(editor, value)
	socket = _find_socket(_find_view(canvas, "ec_calc"), "base")
	await _drag(value.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	_check(obligation.plugs.amount.plugs.has("base"), "taxable value fits into the base")

	# Wrong type is refused.
	var wrong := _library_block(editor, "op_and")
	await _show_in_library(editor, wrong)
	socket = _find_socket(_find_view(canvas, "ec_calc"), "rate")
	await _drag(wrong.get_global_rect().position + Vector2(10, 10), socket.get_global_rect().get_center())
	_check(not obligation.plugs.amount.plugs.has("rate"), "condition does not go into a number field")
	program.stacks = program.stacks.filter(func(s): return s.blocks[0].type == "ev_fiscal")
	editor.refresh()
	await _wait()
	_check(editor.last_compile.ok, "the norm compiles: %s" % str(editor.last_compile.errors))

	# Properties: clicking a block shows the parameters, and changing the value changes the norm.
	var calc_view := _find_view(canvas, "ec_calc")
	await _click(calc_view.get_child(0).get_child(0).get_child(0))
	_check(editor.selected_id == int(obligation.plugs.amount.id), "clicar seleciona o bloco")
	var row: Control = (editor.get_node("%props_box") as Control).get_child(0)
	var edit: LineEdit = row.get_node("%edit")
	_check(edit.text == "5", "panel shows the rate")
	edit.text = "150"
	edit.text_changed.emit("150")
	await _wait()
	_check(not editor.last_compile.ok, "150% is an impossible operation")
	edit.text = "5"
	edit.text_changed.emit("5")
	await _wait()
	_check(editor.last_compile.ok, "volta a compilar")

	# Documento.
	(editor.get_node("%doc_name") as LineEdit).text = "IPTU nacional"
	(editor.get_node("%doc_name") as LineEdit).text_changed.emit("IPTU nacional")
	(editor.get_node("%doc_summary") as TextEdit).text = "Imposto anual de 5% sobre propriedades."
	(editor.get_node("%doc_summary") as TextEdit).text_changed.emit()
	await _shot("l4_norm_ready")
	_check((editor.get_node("%legal_text") as Control).size.x > 100.0, "the norm's text takes up the panel's width")

	# Simulator of the document's example.
	await _click(editor.get_node("%simulate"))
	var sim: LawSimulator = editor.get_node("%simulator")
	_check(sim.visible, "opens the simulator")
	var fund: float = Game.world.politics.party_fund(Game.world)
	var bucket: float = Game.world.player.law_rev_bucket
	await _click(sim.get_node("%sim_run"))
	var result: String = (sim.get_node("%sim_result") as RichTextLabel).text
	print(result)
	_check(result.contains("100000,00") and result.contains("5000,00") and result.contains("Obrigação tributária criada"), "simulator shows the calculation")
	_check(Game.world.player.law_rev_bucket == bucket and Game.world.politics.party_fund(Game.world) == fund, "simulating does not charge anything")
	await _shot("l5_simulator")
	await _click(sim.get_node("%sim_close"))

	# Present: the norm leaves the editor and enters procedure.
	var norm: Dictionary = editor.norm
	await _click(editor.get_node("%present"))
	await _click(editor.get_node("%review").get_node("%rv_send"))
	_check(norm.state == Legislation.STATE_PROCESS, "norm presented: %s" % norm.state)
	center = _top()
	_check(center is LegislationCenter and center.get_node("%tabs").current_tab == 0, "goes back to the first tab, with the procedure")
	await _shot("l6_procedure")
	# Negotiation with the caucuses, through the procedure buttons.
	var process_row: Control = center.get_node("%process_rows").get_node("process_%d" % int(norm.id))
	(center.get_node("%Scroll") as ScrollContainer).ensure_control_visible(process_row)
	await _wait()
	# Conversation with a party leader: the request and the answer become bubbles.
	await _click(process_row.get_node("%chat"))
	var chat: ChatWindow = main.modal_root.get_child(main.modal_root.get_child_count() - 1)
	_check(chat is ChatWindow and chat.current.begins_with("partido:"), "opens the conversation with a party's leader")
	var party_chat := PartyTalk.party_by_id(Game.world, int(chat.current.trim_prefix("partido:")))
	var ask_chat: Button = chat.find_child("say_ask_yes_%d" % int(norm.id), true, false)
	_check(ask_chat != null, "the conversation offers asking for support for the law")
	(chat.find_child("ChoicesScroll", true, false) as ScrollContainer).ensure_control_visible(ask_chat)
	await _wait()
	await _click(ask_chat)
	_check(ChatLog.thread(Game.world, chat.current).size() == 3 and (chat.get_node("%thread") as Control).get_child_count() == 3, "request and answer appear in the conversation")
	_check(norm.get("chat_asked", {}).has(str(party_chat.id)), "the request is recorded in the law")
	await _shot("l6_conversation_party")
	await _click(chat.get_node("%say_end"))
	await _wait()
	await _click(process_row.get_node("%negotiate"))
	var deal: NegotiationScreen = _top()
	_check(deal is NegotiationScreen, "opens the vote negotiation")
	await _shot("l6_negotiation")
	var data: Dictionary = Game.world.politics.data_of("BRA")
	var other_party: int = -1
	for p: Dictionary in data.parties:
		if int(p.id) != int(data.player_party) and int(p.seats) > 0:
			other_party = int(p.id)
			break
	var ask: Button = deal.get_node("%rows").find_child("yes_%d" % other_party, true, false)
	await _click(ask)
	_check((deal.get_node("%feedback") as Label).text != "", "the party answers:" + (deal.get_node("%feedback") as Label).text)
	_check(norm.get("asked", {}).has(str(other_party)), "the answer is recorded")
	await _shot("l6_negotiation_answer")
	await _click(deal.get_node("%close"))
	center = _top()
	_check(center is LegislationCenter, "back returns to the procedure")
	center.get_node("%close").pressed.emit()
	await _wait()
	_check(main.legislation_center() == null and not main.modal_open, "closing removes the window")
	for i in 150:
		Game.world.player.next_election = 9999.0
		Game.world.tick_day()
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			break
	print("  state: ", norm.state)
	_check(norm.state == Legislation.STATE_IN_FORCE or norm.state == Legislation.STATE_REJECTED, "the procedure ends: %s" % norm.state)
	main.open_norm(norm)
	await _shot("l7_consultation")
	var page: NormPage = _top()
	_check(page.get_node("%law_text").text.contains("Art. 1º"), "the consultation shows the text")
	if norm.state == Legislation.STATE_IN_FORCE:
		page.get_node("%view_program").pressed.emit()
		await _wait()
		var reader: LawEditor = _top()
		_check(reader.read_only, "published version opens read-only")
		var before := var_to_str(norm.versions[0].program)
		reader.drop({"law": true, "new": "ac_register", "kind": "statement"}, {"kind": "canvas", "pos": Vector2(300, 300)})
		await _wait()
		_check(var_to_str(norm.versions[0].program) == before, "published version does not change")
		await _shot("l8_reading")
		reader.close_editor()
		await _wait()

	# Emenda.
	main.reopen_legislation(0)
	await _wait()
	center = _top()
	center.get_node("%new_amendment").pressed.emit()
	await _wait()
	var amendment: AmendmentEditor = _top()
	_check(amendment is AmendmentEditor, "opens the amendment editor")
	var mandate := {}
	for a: Dictionary in Game.world.legislation.constitution.articles:
		if a.param == "mandate":
			mandate = a
	amendment.get_node("%article_list").get_child(3).get_node("%select").pressed.emit()
	await _wait()
	(amendment.get_node("%value_edit") as LineEdit).text = "5"
	amendment.get_node("%add_op").pressed.emit()
	await _wait()
	_check(amendment.norm.ops.size() == 1 and int(amendment.norm.ops[0].value) == 5, "the change enters the amendment")
	var diff: RichTextLabel = amendment.get_node("%op_list").get_child(0).get_node("%diff")
	_check(diff.text.contains("[s]4[/s]"), "compares with the previous text: %s" % diff.text)
	await _shot("l9_amendment")
	# Creating and deleting articles, with the buttons in view.
	amendment.get_node("%new_article").pressed.emit()
	await _wait()
	(amendment.get_node("%new_text") as TextEdit).text = "O ensino básico é gratuito."
	amendment.get_node("%add_op").pressed.emit()
	await _wait()
	_check(amendment.norm.ops.size() == 2 and amendment.norm.ops[1].op == "add", "new article enters the amendment")
	amendment.get_node("%article_list").get_child(5).get_node("%delete").pressed.emit()
	await _wait()
	_check(amendment.norm.ops.size() == 3 and amendment.norm.ops[2].op == "suppress", "deleting an article enters the amendment")
	_check(amendment.get_node("%article_list").get_child(0).get_node("%delete").disabled, "an entrenched clause has no deletion")
	await _shot("l9_amendment_create_delete")
	amendment.get_node("%delete_draft").pressed.emit()
	await _wait()

	# Teclado, save e carga.
	var center2 := _top()
	center2.get_node("%close").pressed.emit()
	await _wait()
	main._save_game()
	main.join_sim()
	var count: int = Game.world.legislation.norms.size()
	await main._load_game()
	_check(Game.world.legislation.norms.size() == count, "norms come back from the save")
	_check(FileAccess.file_exists(SaveService.path), "the save stayed in place")
	main._save_game()
	main.join_sim()
	_check(FileAccess.file_exists(SaveService.backup_path), "the previous save becomes a backup copy")
	SaveService.delete_files()
	

## The front screen: an open modal, or the legislative center window.
func _top() -> Control:
	var n: int = main.modal_root.get_child_count()
	if not main.modal_open and main.legislation_center() != null:
		return main.legislation_center()
	return main.modal_root.get_child(n - 1)


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

