extends Node
## Menu inicial e configurações: os quatro botões, a janela de configurações e o que ela guarda.
## Usa um arquivo de opções só do teste, para não mexer nas do jogador.
## Uso: godot --path . -- --ui-menu --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var failures := 0


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)
	GameSettings.path = "user://settings_test.cfg"
	await _run()
	DirAccess.remove_absolute(GameSettings.path)
	GameSettings.reset()
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


func _run() -> void:
	await main.idle()
	await _wait()
	var menu: Control = main.main_menu
	_check(menu != null and main.start_screen == null, "o jogo abre no menu inicial")
	var labels := {"%novo_jogo": "Novo Jogo", "%carregar_jogo": "Carregar Jogo", "%configuracoes": "Configurações", "%sair_do_jogo": "Sair do Jogo"}
	for key: String in labels:
		var b: Button = menu.get_node(key)
		_check(b.text == labels[key] and b.is_visible_in_tree(), "botão %s" % labels[key])
	_check((menu.get_node("%carregar_jogo") as Button).disabled == not SaveService.has_save(), "Carregar só liga com save")
	_check(main.modal_open and not main.map.interactive, "o mapa fica parado atrás do menu")
	await _shot("menu_inicial")

	(menu.get_node("%configuracoes") as Button).pressed.emit()
	await _wait()
	var settings: SettingsMenu = null
	for c in main.modal_root.get_children():
		if c is SettingsMenu:
			settings = c
	_check(settings != null, "Configurações abre")
	await _shot("configuracoes")
	var vsync: CheckButton = settings.get_node("%vsync")
	vsync.button_pressed = false
	_check(not GameSettings.vsync, "sincronia vertical desligada")
	var scale: HSlider = settings.get_node("%ui_scale")
	scale.value = 1.25
	scale.drag_ended.emit(true)
	await _wait()
	_check(is_equal_approx(get_tree().root.content_scale_factor, 1.25), "escala da interface aplicada")
	await _shot("configuracoes_escala")
	var cfg := ConfigFile.new()
	_check(cfg.load(GameSettings.path) == OK and not cfg.get_value("video", "vsync", true) and is_equal_approx(float(cfg.get_value("interface", "scale", 1.0)), 1.25), "as opções ficam gravadas")
	(settings.get_node("%restaurar") as Button).pressed.emit()
	await _wait()
	_check(GameSettings.vsync and is_equal_approx(get_tree().root.content_scale_factor, 1.0), "restaurar padrões")
	(settings.get_node("%voltar") as Button).pressed.emit()
	await _wait()
	_check(main.main_menu != null and main.modal_open and not main.map.interactive, "voltar mostra o menu de novo")

	(menu.get_node("%novo_jogo") as Button).pressed.emit()
	await _wait()
	_check(main.main_menu == null and main.start_screen != null, "Novo Jogo leva à escolha do país")
	_check(not main.modal_open and main.map.interactive, "o mapa volta a responder")
	await _shot("novo_jogo")
