extends Node
## Interface test script: plays on its own, exercises each tab and saves screenshots.
## Usage: godot --path . -- --ui-test --shots=/path/to/folder

var main: Node
var out := "user://shots"
var step := 0
var wait := 0.0
var failures := 0
var saved_day := 0


func _ready() -> void:
	Legislation.skip_unit_approval = true
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)
	wait = 1.0


func _shot(name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name_])
	print("shot: ", name_)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	wait -= delta
	if wait > 0.0:
		return
	step += 1
	wait = 0.6
	var w: GameWorld = Game.world
	match step:
		1:
			_shot("01_start")
			main._pick_start(w.by_iso["BRA"])
		2:
			_shot("02_choice")
			_check(not main._start_button.disabled, "start button enabled")
			main._begin()
			main._set_speed(3)
			main.start_skip(60)
		3:
			_check(main.playing, "partida iniciada")
		4:
			wait = 6.0
		5:
			_dismiss_prompts()
			_shot("03_panel")
			# A random decision may pause the game already in the first month.
			_check(w.day_index > 25, "tempo passou (dia %d)" % w.day_index)
			main.hud._desk.current_tab = 1
		6:
			_dismiss_prompts()
			_shot("04_fiscal")
			main.hud._desk.current_tab = 2
		7:
			_dismiss_prompts()
			_shot("05_currency")
			main.hud._desk.current_tab = 3
		8:
			_dismiss_prompts()
			_shot("06_trade")
			main.hud._desk.current_tab = 4
		9:
			_dismiss_prompts()
			_shot("07_military")
			main.hud._desk.current_tab = 5
		10:
			_dismiss_prompts()
			_shot("08_world")
			main.hud._desk.current_tab = 0
			main.map.select(w.by_iso["CHN"])
			main.hud.show_country(w.by_iso["CHN"])
		11:
			_dismiss_prompts()
			_shot("09_dossier")
			var rel: float = w.diplomacy.relation(w.player.idx, w.by_iso["CHN"].idx)
			main.hud._on_action("mission")
			_check(w.action_wait("mission", w.by_iso["CHN"]) > 0, "the same action only repeats after an interval")
			_check(w.diplomacy.relation(w.player.idx, w.by_iso["CHN"].idx) > rel, "mission improves relation")
			main.hud._on_mode("inflation")
		12:
			_dismiss_prompts()
			_shot("10_mode_inflation")
			main.hud._on_mode("relations")
		13:
			_dismiss_prompts()
			_shot("11_mode_relations")
			main.hud._on_mode("political")
			w.offer_alliance(w.by_iso["PER"])
			w.diplomacy.declare_war(w.by_iso["IND"], w.by_iso["BGD"], w)
			main.map.select(w.by_iso["ARG"])
			main.hud.show_country(w.by_iso["ARG"])
			main.hud._desk.current_tab = 4
		14:
			_shot("11b_decision")
			_dismiss_prompts()
			_shot("12_war_foreign")
			_dismiss_prompts()
			var r: Dictionary = w.do_action("war", w.by_iso["ARG"])
			_check(r.ok, "player declares war")
		15:
			wait = 3.0
		16:
			_dismiss_prompts()
			_shot("13_war_player")
			main._save_game()
			main.join_sim()
			_check(FileAccess.file_exists(SaveService.path), "arquivo salvo")
			main._set_speed(0)
			saved_day = w.day_index
		17:
			var y0: float = w.player.y
			main._load_game()
			_check(Game.world.day_index == saved_day, "carregamento restaura a data (%d)" % Game.world.day_index)
			_check(absf(Game.world.player.y - y0) < 0.001 * y0 + 5.0, "carregamento restaura o PIB")
			_check(Game.world.player.iso == "BRA", "carregamento restaura o jogador")
		18:
			main._set_speed(3)
			main.start_skip(30)
			wait = 3.0
		19:
			_dismiss_prompts()
			_check(Game.world.day_index > 0, "game goes on after loading")
			_shot("14_after_of_load")
			Game.world.player.approval = 0.02
			Game.world.player.next_election = Game.world.year_float()
			Game.world.player.dem = 7.0
			main.start_skip(60)
		20, 21, 22, 23, 24, 25, 26:
			# Only the game over modal may remain open.
			wait = 0.8
			main._set_speed(3)
			if not Game.world.over:
				_dismiss_prompts()
		27:
			_shot("15_end")
			_check(not Game.world.in_office and not Game.world.over, "electoral defeat leads to opposition (next election %.2f, year %.2f)" % [Game.world.player.next_election, Game.world.year_float()])
			print("RESULT: ", failures, " failures")
			get_tree().quit(1 if failures > 0 else 0)


func _dismiss_prompts() -> void:
	# The demarcation stops the clock until the player decides: here they give up the territory.
	if main.hud.border.active:
		print("demarcation open during the script: ending with no territory")
		main.hud.border._on_decline()
	# Closes pending decisions by choosing the first option, as a player would.
	for dim in main.modal_root.get_children():
		if dim is ColorRect:
			var btn := _first_button(dim)
			if btn:
				btn.pressed.emit()


func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null
