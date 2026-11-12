extends Node
## Presses every command of the debug menu, one at a time, advancing a few days after each one.
## Script errors stay in the log right after the line "debug: <command>".
## Usage: godot --path . -- --ui-debug --shots=/path/to/folder

var main: Node
var want_start := false
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var index := 0
var menu: DebugMenu
var restarts := 0
var phase := 0


func _ready() -> void:
	Legislation.skip_unit_approval = true
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)


func _shot(name_: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])
	print("shot: ", name_)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _start_game() -> void:
	main._pick_start(Game.world.by_iso["BRA"])
	main._begin()
	main._set_speed(0)
	menu = main.hud.debug
	menu.main = main
	if not menu.visible:
		menu.toggle()


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	get_viewport().push_input(e)


func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and not child.disabled:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null


func _command(label: String) -> int:
	for i in menu.commands.size():
		if menu.commands[i].label == label:
			return i
	failures += 1
	print("FAIL: comando não existe: ", label)
	return 0


## Cleans up what the command opened, as a player would: window, demarcation or drawing.
func _settle() -> void:
	var guard := 0
	while guard < 12:
		guard += 1
		var opened := false
		for dim in main.modal_root.get_children():
			if dim is ColorRect and not dim.is_queued_for_deletion():
				var b := _last_choice(dim)
				if b:
					b.pressed.emit()
					opened = true
		if main.hud.border.active:
			main.hud.border._on_decline()
			opened = true
		if main.map.drawing:
			main.map.cancel_draft()
		if main.prompts.is_empty() and not opened:
			break
		if not main.prompts.is_empty() and not main.modal_open:
			main._show_prompt(main.prompts.pop_front())


## Closes the window for real: the creator opens with arrows, so "Confirmar" comes before the first option.
func _last_choice(dim: Node) -> Button:
	var confirm := _named(dim, "Confirmar")
	return confirm if confirm else _first_button(dim)


func _named(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _named(child, text)
		if found:
			return found
	return null


func _click(screen: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = screen
		ev.global_position = screen
		ev.pressed = pressed
		get_viewport().push_input(ev)


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	if want_start:
		want_start = false
		if not main.playing:
			_start_game()
		return
	wait -= delta
	if wait > 0.0:
		return
	wait = 0.05
	match phase:
		0:
			_start_game()
			phase = 1
			wait = 0.5
		1:
			_check(menu.visible, "menu aberto")
			_key(KEY_F12)
			phase = 2
		2:
			_check(not menu.visible, "F12 closes the menu")
			_key(KEY_F12)
			phase = 3
		3:
			_check(menu.visible, "F12 opens the menu")
			_shot("g1_menu")
			menu._search.text = "dilema"
			menu._apply_filter("dilema")
			phase = 4
			wait = 0.3
		4:
			_shot("g2_filtro")
			var shown := 0
			for row: Dictionary in menu._rows:
				for b: Button in row.buttons:
					if b.visible:
						shown += 1
			_check(shown == 9, "filter shows only the dilemmas (%d)" % shown)
			menu._search.text = ""
			menu._apply_filter("")
			phase = 40
		40:
			# Real click on a panel button.
			menu.set_meta("dp", float(Game.world.politics.party_fund(Game.world)))
			var b: Button = menu._rows[1].buttons[0]
			_click(b.get_global_rect().get_center())
			phase = 41
			wait = 0.2
		41:
			_check(Game.world.politics.party_fund(Game.world) > float(menu.get_meta("dp")), "clicking the button executes the command")
			# Click on a country on the map changes the target, with the menu open.
			var pos: Vector2 = main.map.get_canvas_transform() * Game.world.by_iso["USA"].center
			_click(pos)
			_check(menu.target == Game.world.by_iso["USA"], "clicking the map switches the target to USA (%s)" % (menu.target.name if menu.target else "nenhum"))
			_check(menu._options.get_item_text(menu._options.selected) == "Estados Unidos", "list shows the target")
			_shot("g3_alvo")
			phase = 42
		42:
			_click(main.map.get_canvas_transform() * Game.world.player.center)
			phase = 43
			wait = 0.3
		43:
			_shot("g4_proprio_pais")
			_own_country()
			phase = 5
		5:
			_effects()
			phase = 6
		6:
			_run_next()
		7:
			print("comandos executados: %d, reinícios: %d" % [menu.commands.size(), restarts])
			SaveService.delete_files()
			print("RESULT: ", failures, " failures")
			get_tree().quit(1 if failures > 0 else 0)


## The player's own country is a valid target, and each "Jogador" command changes what it promises.
func _own_country() -> void:
	var w: GameWorld = Game.world
	var me: Country = w.player
	_click(main.map.get_canvas_transform() * me.center)
	_check(menu.target == me, "clicking your own country makes it the target")
	_check(menu._options.get_item_text(menu._options.selected) == "%s (você)" % me.name, "list shows your own country")
	var war: Button = menu._buttons[_command("Declarar guerra ao alvo")]
	_check(war.disabled, "war against yourself is disabled")
	var relation: Button = menu._buttons[_command("Relação +100")]
	_check(relation.disabled, "relation with yourself is disabled")
	var wars: int = w.diplomacy.wars.size()
	menu.run(_command("Declarar guerra ao alvo"))
	_check(w.diplomacy.wars.size() == wars and menu._status.text.contains("outro país"), "comando recusado explica o motivo")
	var demand := me.demand_shock
	menu.run(_command("Recessão: Alvo"))
	_check(me.demand_shock < demand, "recession on the target hits your own country")
	menu.run(_command("Crise bancária: Alvo"))
	_check(me.crisis_cooldown > 0.0, "banking crisis on the target hits your own country")
	var cases := [
		["Aprovação 90%", func(): return me.approval == 0.9],
		["Aprovação 5%", func(): return me.approval == 0.05],
		["Estabilidade 90%", func(): return me.stability == 0.9],
		["Estabilidade 5%", func(): return me.stability == 0.05],
		["Virar democracia", func(): return me.dem == 8.0],
		["Virar regime autoritário", func(): return me.dem == 2.0],
		["Virar democracia", func(): return me.dem == 8.0],
	]
	for case: Array in cases:
		menu.run(_command(case[0]))
		_check(case[1].call(), "effect on your own country:" + String(case[0]))
	var reserves := me.reserves
	menu.run(_command("Reservas +US$ 500 bi"))
	_check(me.reserves == reserves + 500.0, "effect on your own country: reserves")
	var debt := me.debt_loc
	menu.run(_command("Dívida +50% do PIB"))
	_check(me.debt_loc > debt, "effect on your own country: debt")
	var troops := me.troops
	menu.run(_command("Tropas e equipamento x2"))
	_check(me.troops == troops * 2.0, "effect on your own country: troops")
	var nukes := me.nukes
	menu.run(_command("Dar 1.000 ogivas"))
	_check(me.nukes == nukes + 1000, "effect on your own country: warheads")
	menu.run(_command("Aprovação 90%"))
	menu.run(_command("Estabilidade 90%"))
	menu.set_target(w.by_iso["ARG"])
	_check(not war.disabled, "another country re-enables the commands")
	main.map.select(null)
	main.hud.show_country(null)


## Checks the real effect of the main commands.
func _effects() -> void:
	var w: GameWorld = Game.world
	menu.set_target(w.by_iso["ARG"])
	var fund: float = w.politics.party_fund(w)
	menu.run(_command("Fundo do partido +20 unidades"))
	_check(w.politics.party_fund(w) > fund, "o fundo sobe")
	var day := w.day_index
	menu.run(_command("Avançar 1 dia"))
	_check(w.day_index == day + 1, "advances 1 day")
	menu.run(_command("Crise bancária: Alvo"))
	_check(w.by_iso["ARG"].crisis_cooldown > 0.0, "banking crisis hits the target")
	menu.run(_command("Declarar guerra ao alvo"))
	_check(w.diplomacy.at_war(w.player.idx, w.by_iso["ARG"].idx), "war declared")
	_settle()
	menu.run(_command("Vitória por capitulação"))
	_check(not main.prompts.is_empty() or main.modal_open, "victory opens the decision")
	_settle()
	# The first victory option annexes Argentina: the target goes back to the player's own country.
	if not w.by_iso["ARG"].alive:
		menu.run(_command("Reservas +US$ 500 bi"))
		_check(menu.target == w.player, "annexed target goes back to your own country")
	menu.set_target(w.by_iso["URY"])
	menu.run(_command("Demarcar conquistas"))
	_check(main.hud.border.active and not menu.visible, "demarcation opens and the menu steps aside")
	main.hud.border._on_decline()
	menu.toggle()
	menu.run(_command("Ganhar 10% do alvo"))
	_check(not w.territories.cessions.is_empty() or menu._status.text.contains("não tem"), "gaining territory changes the map:" + menu._status.text)
	menu.run(_command("Pandemia"))
	_settle()
	menu.run(_command("Fundir duas vizinhas agora"))
	_check(not w.subdivisions.custom_ids.is_empty(), "direct merge creates the unit")
	_settle()


func _run_next() -> void:
	if index >= menu.commands.size():
		phase = 7
		return
	var w: GameWorld = Game.world
	# Commands that accept the player's own country run on it; the others, on a foreign country.
	var foreign: Country = w.by_iso.get("ARG")
	if foreign == null or not foreign.alive or foreign == w.player:
		for c: Country in w.countries:
			if c.alive and c != w.player:
				foreign = c
				break
	menu.set_target(foreign if menu.commands[index].target else w.player)
	if not menu.visible:
		menu.toggle()
	var cmd: Dictionary = menu.commands[index]
	# Skips the repetition of what ends the test session; the rest really runs.
	menu.run(index)
	index += 1
	if main.loading:
		# Carregar e voltar ao início rodam em outra thread: o teste segue quando terminarem.
		want_start = true
		return
	_settle()
	if main.loading:
		restarts += 1
		want_start = true
		return
	if Game.world.over or not main.playing:
		restarts += 1
		if main.playing:
			_settle()
			main._restart()
			want_start = true
			return
		_start_game()
		return
	# A few days later, the system must still be standing.
	for i in 3:
		if not Game.world.over:
			Game.world.tick_day()
	_settle()
	if main.loading:
		restarts += 1
		want_start = true
		return
	if Game.world.over:
		restarts += 1
		main._restart()
		want_start = true
		return
	_check(_sane(Game.world), "valid numeric state after:" + String(cmd.label))


func _sane(w: GameWorld) -> bool:
	for c: Country in w.countries:
		if c.alive and (is_nan(c.y) or is_inf(c.y) or is_nan(c.pop) or c.pop <= 0.0 or is_nan(c.e)):
			print("país inválido: ", c.iso)
			return false
	return true
