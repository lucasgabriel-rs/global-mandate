extends Node
## Criador de personagem com a countryball: gênero, laço, nome e sobrenome, sorteio e os retratos no jogo.
## Uso: godot --path . -- --ui-creator --shots=/caminho/da/pasta

const COUNTRYBALL := preload("res://scenes/ui/countryball.tscn")

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
	print("RESULTADO: ", failures, " falhas")
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FALHOU: ", what)
	else:
		print("ok: ", what)


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(name_: String) -> Image:
	await _frames()
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name_ + ".png"))
	return img


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _close() -> void:
	var dim := _top()
	main.modal_root.remove_child(dim)
	dim.queue_free()
	main.modal_open = false
	main.map.interactive = true
	await get_tree().process_frame


## Pixels do laço (rosa) dentro do retrato: só as bolas femininas têm.
func _pink_pixels(img: Image, view: Control) -> int:
	var r := view.get_global_rect()
	var count := 0
	for y in range(int(r.position.y), int(r.end.y), 2):
		for x in range(int(r.position.x), int(r.end.x), 2):
			var p := img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
			if absf(p.r - Countryball.BOW.r) < 0.06 and absf(p.g - Countryball.BOW.g) < 0.06 and absf(p.b - Countryball.BOW.b) < 0.06:
				count += 1
	return count


func _type(edit: LineEdit, text: String) -> void:
	edit.text = text
	edit.text_changed.emit(text)


func _run() -> void:
	await _frames(5)
	var w: GameWorld = main.world
	main._pick_start(w.by_iso["BRA"])
	main._start_button.pressed.emit()
	await _frames()
	var dim := _top()
	_check(main.modal_open and dim.has_node("%first_name_edit"), "o criador abre")
	var view: Countryball = dim.get_node("%view")
	var first: LineEdit = dim.get_node("%first_name_edit")
	var last: LineEdit = dim.get_node("%last_name_edit")
	var ch: Dictionary = view.character
	_check(view.iso == "BRA", "a bola veste a bandeira do Brasil")
	_check(first.text == ch.first_name and last.text == ch.last_name and first.text != "" and last.text != "", "campos de nome e sobrenome preenchidos")
	_check((dim.get_node("%country_label") as Label).text.contains("Brasil"), "o país aparece embaixo da bola")

	(dim.get_node("%gender_m") as Button).pressed.emit()
	var img := await _shot("criador_masculino")
	_check(ch.gender == "m" and String(ch.first_name) in Names.GROUPS.pt.m, "masculino com prenome masculino: %s" % ch.first_name)
	_check(first.text == ch.first_name, "o campo mostra o prenome novo")
	_check(_pink_pixels(img, view) == 0, "sem laço no masculino")

	(dim.get_node("%gender_f") as Button).pressed.emit()
	img = await _shot("criador_feminino")
	_check(ch.gender == "f" and String(ch.first_name) in Names.GROUPS.pt.f, "feminino com prenome feminino: %s" % ch.first_name)
	_check((dim.get_node("%gender_f") as Button).button_pressed and not (dim.get_node("%gender_m") as Button).button_pressed, "botão do gênero marcado")
	var pink := _pink_pixels(img, view)
	_check(pink > 30, "laço rosa no feminino (%d pixels)" % pink)

	for i in 12:
		(dim.get_node("%roll_name") as Button).pressed.emit()
		if not String(ch.first_name) in Names.GROUPS.pt.f or not String(ch.last_name) in Names.GROUPS.pt.last:
			_check(false, "sorteio fora das listas femininas: %s" % ch.name)
	_check(first.text == ch.first_name and last.text == ch.last_name, "sortear atualiza os dois campos")

	_type(first, "Joana")
	_type(last, "Teixeira Lima")
	_check(ch.name == "Joana Teixeira Lima" and ch.first_name == "Joana" and ch.last_name == "Teixeira Lima", "nome e sobrenome digitados formam o nome inteiro")
	(dim.get_node("%gender_m") as Button).pressed.emit()
	_check(ch.first_name == "Joana" and ch.last_name == "Teixeira Lima" and first.text == "Joana", "trocar o gênero não mexe no nome digitado")
	(dim.get_node("%roll_name") as Button).pressed.emit()
	_check(String(ch.first_name) in Names.GROUPS.pt.m, "sortear depois de digitar sorteia conforme o gênero: %s" % ch.first_name)
	(dim.get_node("%gender_f") as Button).pressed.emit()
	_check(String(ch.first_name) in Names.GROUPS.pt.f, "e o sorteado volta a acompanhar o gênero")

	_type(first, "Helena")
	_type(last, "Moreira")
	var age: HSlider = dim.get_node("%age_slider")
	age.value = 47
	await _shot("criador_digitado")
	(dim.get_node("%Confirmar") as Button).pressed.emit()
	await _frames()
	await _close()

	# Outro país: a bola muda de bandeira e o sobrenome russo tem forma feminina.
	main._pick_start(w.by_iso["RUS"])
	var rus := Character.random(w.rng, "RUS")
	rus.gender = "m"
	Character.reroll_name(rus, "ru", w.rng)
	main._open_creator(rus, func(_c): pass)
	await _frames()
	dim = _top()
	view = dim.get_node("%view")
	_check(view.iso == "RUS", "a bola troca de bandeira com o país")
	Character.set_names(rus, rus.first_name, "Petrov")
	(dim.get_node("%gender_f") as Button).pressed.emit()
	_check(rus.last_name == "Petrova" and String(rus.first_name) in Names.GROUPS.ru.f, "russa: %s" % rus.name)
	await _shot("criador_russia_feminino")
	await _close()

	# No jogo: o retrato do HUD e os políticos também são countryballs.
	main._pick_start(w.by_iso["BRA"])
	main._begin(ch, {})
	main._set_speed(0)
	await _frames()
	var hud: Hud = main.hud
	_check(hud._portrait is Countryball and hud._portrait.iso == "BRA" and hud._portrait.is_female(), "retrato do HUD é a countryball com laço")
	_check(w.leader.name == "Helena Moreira" and w.politics.player_politician(w).get("gender", "") == "f", "o nome e o gênero chegam à partida")
	await _shot("hud_retrato")
	var party: Dictionary = w.politics.ruling_party("BRA")
	main._open_party_detail(int(party.id))
	await _frames()
	var balls := _top().find_children("*", "Countryball", true, false)
	var women := 0
	for b: Countryball in balls:
		women += 1 if b.is_female() else 0
	_check(balls.size() >= 3 and women > 0 and women < balls.size(), "políticos em countryball, de ambos os gêneros (%d de %d)" % [women, balls.size()])
	await _shot("partido_politicos")
	await _close()

	# Galeria com todas as bandeiras, alternando gêneros.
	var gallery := ColorRect.new()
	gallery.color = Color("20323e")
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.modal_root.add_child(gallery)
	var grid := GridContainer.new()
	grid.columns = 18
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	gallery.add_child(grid)
	var vp := get_viewport().get_visible_rect().size
	var cell := floorf(minf(vp.x / 18.0, vp.y / ceilf(w.countries.size() / 18.0))) - 2.0
	for i in w.countries.size():
		var c: Country = w.countries[i]
		var v: Countryball = COUNTRYBALL.instantiate()
		v.custom_minimum_size = Vector2(cell, cell)
		v.show_person({"gender": "f" if i % 4 == 3 else "m"}, c.iso)
		grid.add_child(v)
	await _shot("galeria_bandeiras")
	main.modal_root.remove_child(gallery)
	gallery.queue_free()
