extends Node
## Governor mode in the interface: the start screen offers the units, the dock shows only what a
## non-sovereign head can do, and the office title follows the unit type.
## Usage: godot --path . -- --ui-governor --shots=/path/to/folder

var main: Node
var out := "user://shots"
var failures := 0

## Dock items that a country head has and a governor does not.
const HIDDEN_ITEMS := ["dock_ministers", "dock_fiscal", "dock_currency", "dock_trade", "dock_military", "dock_divisions", "dock_opposition", "dock_world", "dock_panel", "dock_politics", "dock_legislation", "dock_economy"]


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


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _item(dock: Dock, name_: String) -> DockItem:
	return dock.find_child(name_, true, false) as DockItem


func _any_modal_closed() -> void:
	main.prompts.clear()
	while main.modal_open and main.modal_root.get_child_count() > 0:
		main._close_modal(_top())
		await _wait(2)


func _run() -> void:
	await _wait(5)
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso["BRA"])
	var picker: OptionButton = main.start_screen.get_node("%start_unit")
	_check(picker.visible and picker.item_count == 1 + w.subdivisions.roots_of("BRA").size(), "the start screen lists the whole country and its first-level units")
	var unit_id := -1
	for i in range(1, picker.item_count):
		if picker.get_item_text(i).begins_with("São Paulo"):
			unit_id = int(picker.get_item_metadata(i))
			picker.select(i)
			picker.item_selected.emit(i)
	_check(unit_id >= 0, "São Paulo is on the list")
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirm").pressed.emit()
	await _wait(6)
	main._set_speed(0)
	await _any_modal_closed()
	var hud: Hud = main.hud
	var dock: Dock = hud._dock
	_check(w.role() == "governor" and w.governor.unit_id == unit_id, "the match starts as the governor of the chosen unit")
	hud.refresh(true)
	await _wait()
	for n: String in HIDDEN_ITEMS:
		_check(not _item(dock, n).visible, "%s is not in a governor's dock" % n)
	var label: Label = hud.find_child("player_name", true, false)
	_check(label.text.contains("Governador"), "the top bar names the office: %s" % label.text)
	# The office title follows the unit type.
	var type_id := int(w.subdivisions.units[unit_id].type)
	w.subdivisions.set_office(type_id, "Intendente")
	hud.refresh(true)
	await _wait()
	_check(label.text.contains("Intendente"), "a renamed office shows up: %s" % label.text)
	# Nothing sovereign opens when asked.
	hud._desk.open(hud._divisions_tab)
	await _wait(3)
	_check(not hud._desk.is_open(hud._divisions_tab), "the divisions window does not open for a governor")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/governor.png" % out)
