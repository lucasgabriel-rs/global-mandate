extends Node
## Old saves (written by v0.1.2, tests/fixtures) through the real interface: Load Game in the start menu and in
## the pause menu, the world matching the old game, the simulation running, and a save and load round trip.
## Uses the interface tests' own save file, never the player's.
## Usage: godot --path . -- --ui-saves

const DIR := "res://tests/fixtures/"

var main: Node
var failures := 0


func _ready() -> void:
	main = get_parent()
	await _run()
	SaveService.delete_files()
	print("RESULT: %d failures" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _install(tag: String, damaged_main_file := false) -> void:
	SaveService.delete_files()
	var src := FileAccess.get_file_as_bytes(DIR + tag + (".bak" if damaged_main_file else ".save"))
	var target: String = SaveService.backup_path if damaged_main_file else SaveService.path
	var f := FileAccess.open(target, FileAccess.WRITE)
	f.store_buffer(src)
	f.close()
	if damaged_main_file:
		f = FileAccess.open(SaveService.path, FileAccess.WRITE)
		f.store_string("not a save")
		f.close()


func _matches(tag: String) -> String:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + tag + ".json"))
	var w: GameWorld = Game.world
	var p := w.politics.player_party(w)
	var got := {"iso": w.player.iso, "day_index": w.day_index, "in_office": w.in_office, "party": String(p.name),
		"norms": w.legislation.norms.size(), "leader": String(w.leader.name), "parties": w.politics.data_of(w.player.iso).parties.size()}
	for k: String in got:
		if str(got[k]) != str(expected[k]) and not (expected[k] is float and int(expected[k]) == int(got[k])):
			return "%s: %s != %s" % [k, got[k], expected[k]]
	if not is_equal_approx(w.politics.party_fund(w), float(expected.fund)) and absf(w.politics.party_fund(w) - float(expected.fund)) > 0.001:
		return "fund"
	return ""


func _days(n: int) -> void:
	var w: GameWorld = Game.world
	var start := w.day_index
	main.start_skip(n)
	var guard := 0
	while w.day_index < start + n and guard < 2000:
		guard += 1
		await _frames(2)
		if not main.prompts.is_empty() or main.modal_open:
			break
	main.join_sim()


func _run() -> void:
	await _frames(5)
	for tag in ["government", "opposition"]:
		# Start menu: Load Game.
		_install(tag)
		main._close_main_menu()
		main._build_main_menu()
		var load_button: Button = main.main_menu.get_node("%load_game")
		_check(not load_button.disabled, "%s: Load Game is enabled with a save" % tag)
		load_button.pressed.emit()
		for i in 600:
			await get_tree().process_frame
			if main.playing and not main.loading:
				break
		main.join_sim()
		_check(main.playing and main.main_menu == null, "%s: the old save loads from the start menu" % tag)
		var diff := _matches(tag)
		_check(diff == "", "%s: country, day, role, party, norms, leader and fund match %s" % [tag, diff])
		_check(main.hud.visible and (main.hud._date as Label).text != "", "%s: the HUD shows the match" % tag)
		var day0: int = Game.world.day_index
		await _days(7)
		_check(Game.world.day_index >= day0 + 7, "%s: the simulation runs a few days (%d -> %d)" % [tag, day0, Game.world.day_index])
		# Save with the new code, then load it from the pause menu.
		main._save_game()
		main.join_sim()
		_check(FileAccess.file_exists(SaveService.path), "%s: the new save is written" % tag)
		var saved_day: int = Game.world.day_index
		var saved_fund: float = Game.world.politics.party_fund(Game.world)
		await _days(3)
		main._open_menu()
		await _frames(2)
		var pause: Control = main.modal_root.get_child(main.modal_root.get_child_count() - 1)
		var pause_load: Button = pause.get_node("%LoadGame")
		_check(pause_load.visible, "%s: the pause menu offers Load Game" % tag)
		pause_load.pressed.emit()
		for i in 600:
			await get_tree().process_frame
			if Game.world.day_index == saved_day and not main.loading:
				break
		main.join_sim()
		_check(Game.world.day_index == saved_day and is_equal_approx(Game.world.politics.party_fund(Game.world), saved_fund), "%s: round trip through the pause menu keeps day and fund" % tag)
		_check(Game.world.in_office == (tag == "government"), "%s: role kept after the round trip" % tag)
		await _days(3)
		_check(Game.world.day_index >= saved_day + 3, "%s: the simulation runs after the round trip" % tag)
	# A damaged main file falls back to the backup copy.
	_install("government", true)
	main._load_game()
	for i in 600:
		await get_tree().process_frame
		if main.playing and not main.loading:
			break
	main.join_sim()
	_check(_matches("government") == "", "the damaged save falls back to the backup copy")
