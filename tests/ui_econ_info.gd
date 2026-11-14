extends Node
## Economic information (Economy tab > Information): chart comparing countries, bulletin of market
## expectations and IMF forecasts, after a year of game.
## Usage: godot --path . -- --ui-econ-info --shots=/path/to/folder

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
	# Dialogs the game opens by itself (conversation requests etc.) would cover the panel.
	for m in main.modal_root.get_children():
		m.queue_free()
	await _wait(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


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
	for i in 400:
		w.tick_day()
	var hud: Hud = main.hud
	var desk: WindowDesk = hud._desk
	desk.current_tab = 9
	var economy: EconomyPanel = hud.economy
	(economy.get_node("%sub_tabs") as TabContainer).current_tab = 6
	hud.refresh(true)
	await _wait()
	var info: InfoPanel = economy.info
	_check(info.is_visible_in_tree(), "the Information sub-tab shows up")
	var tabs: TabContainer = info.get_node("%info_tabs")
	# Charts: Brazil's inflation against the US and Argentina.
	(info.get_node("%series_pick") as OptionButton).selected = 1
	info.pick_country(0, "USA")
	info.pick_country(1, "ARG")
	await _wait()
	var chart: CompareChart = info.get_node("%compare_chart")
	_check(chart._series.size() == 3, "three countries on the chart: %d" % chart._series.size())
	_check(chart._series[0].size() >= 12, "the series has a year of data: %d" % chart._series[0].size())
	_check((info.get_node("%chart_note") as Label).text.contains("%"), "the note shows the latest data point")
	await _shot("i1_charts")
	# Market expectations.
	tabs.current_tab = 1
	await _wait()
	var cell: Label = info.get_node("%fc_infl_0")
	_check(cell.text.contains("%"), "expected inflation: " + cell.text)
	_check((info.get_node("%year_0") as Label).text == str(w.year), "the current year in the header")
	var m := Outlook.market(w.player, w)
	_check(absf(m.infl[2] - w.player.pi_target) < absf(m.infl[0] - w.player.pi_target) + 0.0001, "expected inflation converges to the target")
	await _shot("i2_expectations")
	# IMF.
	tabs.current_tab = 2
	await _wait()
	var rows: VBoxContainer = info.get_node("%imf_rows")
	_check(rows.get_child_count() >= 5, "world, the country and the large economies: %d rows" % rows.get_child_count())
	_check((rows.get_child(1).get_node("%imf_name") as Label).text == tr(w.player.name), "the player comes right after the world")
	_check(not (info.get_node("%imf_risks") as Label).text.is_empty(), "the IMF assesses the country")
	await _shot("i3_imf")
	get_window().size = Vector2i(1100, 700)
	await _wait(8)
	await _shot("i4_window_smaller")
