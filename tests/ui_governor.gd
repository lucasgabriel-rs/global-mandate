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
	# --- The state windows ---
	for n: String in ["dock_state", "dock_state_budget", "dock_union"]:
		_check(_item(dock, n).visible, "%s is in the governor's dock" % n)
	_check(not _item(dock, "dock_directory").visible, "the directory is not in the dock while in office")
	var desk: WindowDesk = hud._desk
	for n: String in ["dock_state", "dock_state_budget", "dock_union"]:
		desk.open(_item(dock, n).window_index)
	await _wait(4)
	hud.refresh(true)
	await _wait(2)
	var state: Control = hud.find_child("state", true, false)
	_check((state.find_child("unit_label", true, false) as Label).text.contains("São Paulo"), "the state panel names the unit")
	_check((state.find_child("gdp_label", true, false) as Label).text != "—" and (state.find_child("election_label", true, false) as Label).text.contains("anos"), "the state panel shows the economy and the election")
	var budget: Control = hud.find_child("state_budget", true, false)
	var tax: HSlider = budget.find_child("tax_slider", true, false)
	_check(tax.editable, "a federal country lets the state set the tax rate")
	tax.value = 7.0
	await _wait(2)
	_check(is_equal_approx(w.governor.tax_rate, 0.07), "moving the tax slider changes the state's tax rate")
	# A unitary region has no say over the areas the union keeps.
	var kept_iso := w.governor.union_iso
	w.governor.union_iso = "FRA"
	hud.refresh(true)
	await _wait(2)
	_check(not (budget.find_child("sp_health", true, false) as HSlider).editable and not tax.editable, "a unitary region cannot set the union's areas")
	w.governor.union_iso = kept_iso
	hud.refresh(true)
	await _wait(2)
	var union: Control = hud.find_child("union", true, false)
	var ask: Button = union.find_child("request_funds", true, false)
	ask.pressed.emit()
	await _wait(2)
	var feedback: Label = union.find_child("request_feedback", true, false)
	_check(feedback.text != "", "asking the union for money gives an answer: %s" % feedback.text)
	ask.pressed.emit()
	await _wait(2)
	_check(feedback.text.contains("mês"), "asking again names the cooldown: %s" % feedback.text)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/governor.png" % out)
	# --- Out of office: the directory takes over ---
	w.governor.enter_unit_opposition(w, "Teste")
	main.prompts.clear()
	w.politics.player_party(w)["funds"] = 100.0
	hud.refresh(true)
	await _wait(3)
	_check(_item(dock, "dock_directory").visible and not _item(dock, "dock_state_budget").visible, "in the opposition the directory replaces the budget in the dock")
	desk.open(_item(dock, "dock_directory").window_index)
	await _wait(4)
	var directory: Control = hud.find_child("directory", true, false)
	var before := w.governor.approval
	(directory.find_child("criticize", true, false) as Button).pressed.emit()
	await _wait(2)
	_check(w.governor.approval < before and (directory.find_child("directory_feedback", true, false) as Label).text != "", "the directory criticizes the incumbent")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/governor_opposition.png" % out)
