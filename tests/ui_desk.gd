extends Node
## Dock and floating windows: open from the dock, bring to the front, drag, resize, minimize,
## date without the hour and small window.
## Usage: godot --path . -- --ui-desk --shots=/path/to/folder

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


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _press(item: DockItem) -> void:
	item.pressed.emit()
	await _wait(14)


func _run() -> void:
	await _wait(5)
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirm").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	for i in 60:
		w.tick_day()
	var hud: Hud = main.hud
	var desk: WindowDesk = hud._desk
	var dock: Dock = hud._dock
	hud.refresh(true)
	await _wait()
	_check(not (hud.get_node("%date") as Label).text.contains(":"), "the date appears without the hour:" + (hud.get_node("%date") as Label).text)
	_check(desk.open_count() == 0, "the game starts with no open windows, with the map free")
	_check(dock.items().filter(func(i): return i.window_index >= 0).size() == desk.get_tab_count(), "the dock has one icon per window: %d" % dock.items().size())
	await _shot("d1_mapa_livre")

	# Open from the dock.
	await _press(dock.item_for_window(0))
	_check(desk.is_open(0) and desk.current_tab == 0, "the Panel icon opens the window")
	_check((desk.window(0).content() as Control).is_visible_in_tree(), "the Panel content is inside the window")
	await _press(dock.item_for_window(1))
	await _press(dock.item_for_window(9))
	_check(desk.open_count() == 3 and desk.current_tab == 9, "three open windows, the last in front")
	_check(dock.item_for_window(1)._dot.visible, "the dot marks the open windows in the dock")
	hud.refresh(true)
	await _shot("d2_tres_janelas")

	# Bring to the front and minimize.
	await _press(dock.item_for_window(1))
	_check(desk.current_tab == 1 and desk.open_count() == 3, "clicking the icon of a back window brings it to the front")
	await _press(dock.item_for_window(1))
	_check(not desk.is_open(1) and desk.current_tab == 9, "clicking again minimizes, and the one behind becomes the front")
	await _wait(20)
	_check(not desk.window(1).visible, "the minimized window disappears after the animation")

	# Drag and resize by the bar and by the corner.
	var win := desk.window(0)
	win.raise()
	var bar: Control = win.get_node("%title_bar")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = bar.get_global_rect().get_center()
	press.position = press.global_position
	Input.warp_mouse(press.global_position)
	await _wait(2)
	bar.gui_input.emit(press)
	var before := win.position
	Input.warp_mouse(press.global_position + Vector2(240, 60))
	await _wait(2)
	var motion := InputEventMouseMotion.new()
	bar.gui_input.emit(motion)
	press.pressed = false
	bar.gui_input.emit(press)
	_check(win.position.distance_to(before) > 40.0, "the window moves when dragging the bar: %s → %s" % [str(before), str(win.position)])
	win.size = Vector2(5000, 5000)
	win.fit()
	_check(win.get_rect().end.x <= desk.size.x + 1.0 and win.get_rect().end.y <= desk.size.y + 1.0, "the window does not go beyond the free area")
	win.size = win.default_size
	(win.get_node("%close") as Button).pressed.emit()
	await _wait(20)
	_check(not desk.is_open(0), "the red button closes the window")

	# Divisions: opening the window turns on unit selection on the map.
	desk.current_tab = hud._divisions_tab
	await _wait()
	_check(main.map.unit_pick, "the Divisions window in front turns on unit selection")
	desk.close(hud._divisions_tab)
	await _wait(20)
	_check(not main.map.unit_pick, "closed, the map goes back to normal")

	# Legislation opens the legislative center.
	for it in dock.items():
		if it.action == "legislation":
			await _press(it)
	_check(main.legislation_center() != null and desk.current_tab == hud.LEGISLATION_WINDOW, "the legislation icon opens the legislative center as a window")
	_check(not main.modal_open, "the center does not block the rest of the screen")
	var center_rect := desk.window(hud.LEGISLATION_WINDOW).get_rect()
	_check(absf(center_rect.get_center().x - desk.size.x * 0.5) < 60.0, "the window opens in the center of the screen")
	await _shot("d3_legislacao")
	for it in dock.items():
		if it.action == "legislation":
			await _press(it)
	_check(main.legislation_center() == null, "clicking the icon again minimizes the center")

	# Dock with the mouse over it: the icons grow.
	desk.current_tab = 7
	await _wait(14)
	var target := dock.item_for_window(2)
	Input.warp_mouse(target.get_global_rect().get_center())
	await _wait(30)
	_check(target.magnify > 1.3, "the icon under the mouse grows: %.2f" % target.magnify)
	hud.refresh(true)
	await _shot("d4_dock_ampliado")

	# Tela menor.
	get_window().size = Vector2i(1100, 680)
	await _wait(12)
	for i in desk.get_tab_count():
		if desk.is_open(i):
			var r := desk.window(i).get_rect()
			_check(r.end.x <= desk.size.x + 1.0 and r.end.y <= desk.size.y + 1.0, "window %d fits on the smaller screen" % i)
	await _shot("d5_tela_menor")
