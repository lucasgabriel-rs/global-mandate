extends Node
## Troca o idioma para inglês e espanhol e fotografa a tela inicial, o HUD, o centro legislativo e o
## editor de blocos. Também procura português nos textos visíveis (ã, õ, ç e palavras comuns).
## Uso: godot --path . -- --ui-locale --shots=/caminho/da/pasta

const LANGS := ["en", "es"]
## Sinais de texto em português que não aparecem em inglês nem em espanhol.
const PT_MARKS := ["ã", "õ", "ç", "Ã", "Õ", "Ç", " não ", " você", " então "]

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
	Lang.apply(Lang.DEFAULT, false)
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
	await _wait(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


## Textos visíveis em português dentro de `root`.
func _portuguese(root: Node) -> Array:
	var found := []
	_scan(root, found)
	return found


func _scan(node: Node, found: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	var shown := ""
	if node is RichTextLabel:
		shown = (node as RichTextLabel).get_parsed_text()
	elif node is Label or node is Button:
		shown = node.atr(node.text) if node.can_auto_translate() else node.text
	elif node is LineEdit or node is TextEdit:
		shown = node.text if not node.text.is_empty() else node.atr(node.placeholder_text)
	for mark: String in PT_MARKS:
		if mark in " %s " % shown:
			found.append(shown.substr(0, 80))
			break
	for child in node.get_children():
		_scan(child, found)


func _no_portuguese(root: Node, what: String) -> void:
	var found := _portuguese(root)
	for text: String in found.slice(0, 8):
		print("   português: ", text)
	_check(found.is_empty(), "%s sem português (%d textos)" % [what, found.size()])


func _run() -> void:
	await _wait(5)
	main._pick_start(main.world.by_iso["USA"])
	for lang: String in LANGS:
		Lang.apply(lang, false)
		await _wait(6)
		_check(Lang.current() == lang, "idioma %s ativo" % lang)
		await _shot("%s_1_inicio" % lang)
		_no_portuguese(main.start_screen, "tela inicial (%s)" % lang)
		var picker: OptionButton = main.start_screen.find_child("language", true, false)
		_check(picker != null and picker.selected == Lang.CODES.find(lang), "o seletor mostra o idioma ativo (%s)" % lang)
		_check(main.world.by_iso["DEU"].name == ("Germany" if lang == "en" else "Alemania"), "nomes de país traduzidos (%s)" % lang)
	Lang.apply("en", false)
	await _wait(4)
	main._begin(Character.random(main.world.rng, "USA", main.world.by_iso["USA"].region), {})
	main._set_speed(0)
	await _wait(8)
	for lang: String in LANGS:
		Lang.apply(lang, false)
		await _wait(8)
		var hud: Hud = main.hud
		hud.refresh(true)
		await _shot("%s_2_hud" % lang)
		_no_portuguese(hud, "HUD (%s)" % lang)
		main.open_legislation()
		await _wait(6)
		var center: LegislationCenter = main.legislation_center()
		_check(center != null, "centro legislativo abre (%s)" % lang)
		await _shot("%s_3_centro" % lang)
		if center:
			_no_portuguese(center, "centro legislativo (%s)" % lang)
		main.close_legislation()
		await _wait(4)
		main.open_law_editor(main.world.legislation.start_code_bill(main.world, "tributario"))
		await _wait(10)
		var editor: LawEditor = null
		for child in main.modal_root.get_children():
			if child is LawEditor:
				editor = child
		_check(editor != null, "editor de blocos abre (%s)" % lang)
		await _shot("%s_4_editor" % lang)
		if editor:
			_no_portuguese(editor, "editor de blocos (%s)" % lang)
			main._drop_law_screens()
			main._sync_modal_state()
		await _wait(4)
	# Troca com o centro aberto: a janela se refaz no idioma novo.
	main.open_legislation()
	await _wait(6)
	Lang.apply("en", false)
	await _wait(8)
	var reopened: LegislationCenter = main.legislation_center()
	_check(reopened != null and (reopened.get_node("%role_note") as Label).text.begins_with("You act as"), "o centro aberto se refaz ao trocar o idioma")
	await _shot("en_5_troca_com_centro")
	main.close_legislation()
	_check(UiKit.thousand(1234567) == "1,234,567", "milhares com vírgula em inglês (%s)" % UiKit.thousand(1234567))
	Lang.apply("es", false)
	_check(UiKit.thousand(1234567) == "1.234.567", "milhares com ponto em espanhol (%s)" % UiKit.thousand(1234567))
