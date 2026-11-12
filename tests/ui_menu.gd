extends Node
## Start menu and settings: the four buttons, the settings window and what it stores.
## Uses an options file of the test only, so as not to touch the player's.
## Usage: godot --path . -- --ui-menu --shots=/path/to/folder

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
	GameSettings.reset()
	DirAccess.remove_absolute(GameSettings.path)
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
	_check(menu != null and main.start_screen == null, "the game opens at the start menu")
	var labels := {"%new_game": "Novo Jogo", "%load_game": "Carregar Jogo", "%settings": "Configurações", "%quit_game": "Sair do Jogo"}
	for key: String in labels:
		var b: Button = menu.get_node(key)
		_check(b.text == labels[key] and b.is_visible_in_tree(), "button %s" % labels[key])
	_check((menu.get_node("%load_game") as Button).disabled == not SaveService.has_save(), "Load only turns on with a save")
	_check(main.modal_open and not main.map.interactive, "the map stays still behind the menu")
	await _shot("menu_initial")

	(menu.get_node("%settings") as Button).pressed.emit()
	await _wait()
	var settings: SettingsMenu = null
	for c in main.modal_root.get_children():
		if c is SettingsMenu:
			settings = c
	_check(settings != null, "Settings opens")
	await _shot("settings")
	var vsync: CheckButton = settings.get_node("%vsync")
	vsync.button_pressed = false
	_check(not GameSettings.vsync, "sincronia vertical desligada")
	var scale: HSlider = settings.get_node("%ui_scale")
	scale.value = 1.25
	scale.drag_ended.emit(true)
	await _wait()
	_check(is_equal_approx(get_tree().root.content_scale_factor, 1.25), "interface scale applied")
	await _shot("settings_scale")
	var cfg := ConfigFile.new()
	_check(cfg.load(GameSettings.path) == OK and not cfg.get_value("video", "vsync", true) and is_equal_approx(float(cfg.get_value("interface", "scale", 1.0)), 1.25), "the options are saved")
	(settings.get_node("%restore") as Button).pressed.emit()
	await _wait()
	_check(GameSettings.vsync and is_equal_approx(get_tree().root.content_scale_factor, 1.0), "restore defaults")
	(settings.get_node("%back") as Button).pressed.emit()
	await _wait()
	_check(main.main_menu != null and main.modal_open and not main.map.interactive, "back shows the menu again")

	(menu.get_node("%new_game") as Button).pressed.emit()
	await _wait()
	_check(main.main_menu == null and main.start_screen != null, "New Game leads to the country choice")
	_check(not main.modal_open and main.map.interactive, "the map responds again")
	await _shot("new_game")
