extends Node
## Roteiro do relógio com o jogo rodando: mede as velocidades em tempo real e usa os botões de avanço.
## Uso: godot --path . -- --ui-clock --shots=/caminho/da/pasta

const MEASURE_SECONDS := 3.0

var main: Node
var out := "user://shots"
var step := 0
var wait := 1.0
var failures := 0
var start_clock := 0
var start_shown := 0
var start_time := 0
var measuring := -1
var day0 := 0
var minute0 := 0
var skip_phase := 0


func _ready() -> void:
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
	print("ok: " if cond else "FALHA: ", what)


func _clock() -> int:
	return main.world.day_index * 1440 + main.world.minute


## O que o jogador lê na barra, e não o valor interno: "07 Fev 2025  08:13".
func _shown_minutes() -> int:
	# A barra mostra só a data; a hora fica nos ponteiros do relógio redondo.
	return main.hud._day_clock.minute


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	get_viewport().push_input(e)


func _click(b: Control) -> void:
	var at := b.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = pressed
		get_viewport().push_input(ev)


func _begin_measure(key: Key) -> void:
	_key(key)
	wait = 0.3


func _rate_ok(expected: float) -> void:
	_clock_shot("r%d_b" % step)
	_check(main.hud._day_clock.minute == main.world.minute, "ponteiros acompanham o relógio")
	var real := (Time.get_ticks_msec() - start_time) / 1000.0
	var rate := (_clock() - start_clock) / real
	_check(absf(rate - expected) <= expected * 0.08, "%.1f minutos por segundo (esperado %.0f)" % [rate, expected])
	var shown := posmod(_shown_minutes() - start_shown, 1440) / real
	_check(absf(shown - expected) <= expected * 0.08, "relógio na tela: %.1f minutos por segundo" % shown)
	_check(main.hud._rate_label.text == "%d min/s" % int(expected) or absf(int(main.hud._rate_label.text.split(" ")[0]) - expected) <= expected * 0.1, "indicador mostra: " + main.hud._rate_label.text)


## Recorte só da barra com o relógio, para comparar o que foi desenhado no início e no fim da medição.
func _clock_shot(name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.get_region(Rect2i(0, 0, 620, 58)).save_png("%s/%s.png" % [out, name_])
	print("relógio ", name_, ": ", main.hud._date.text, " ponteiro em ", main.hud._day_clock.minute % 60, " min")


func _start_measure() -> void:
	_clock_shot("r%d_a" % step)
	start_clock = _clock()
	start_shown = _shown_minutes()
	start_time = Time.get_ticks_msec()
	wait = MEASURE_SECONDS


func _dismiss() -> void:
	for dim in main.modal_root.get_children():
		if dim is ColorRect and not dim.is_queued_for_deletion():
			var b := _first(dim)
			if b:
				b.pressed.emit()


func _first(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _first(child)
		if found:
			return found
	return null


func _process(delta: float) -> void:
	main.join_sim()
	if main.loading:
		return
	wait -= delta
	if wait > 0.0:
		return
	step += 1
	wait = 0.5
	var w: GameWorld = main.world
	var hud: Hud = main.hud
	match step:
		1:
			# Mesmo caminho do jogador: botão de assumir e criador de personagem.
			main._pick_start(w.by_iso["BRA"])
			main._start_button.pressed.emit()
		2:
			_confirm_creator()
		3:
			_check(main.speed == 1, "partida começa na velocidade normal")
			_check(hud._speed_buttons.size() == 4, "pausa e 3 velocidades")
			_begin_measure(KEY_1)
		4:
			_start_measure()
		5:
			_rate_ok(20.0)
			_shot("t1_normal")
			_key(KEY_2)
			wait = 0.3
		6:
			_check(main.speed == 2, "tecla 2 escolhe 2x")
			_start_measure()
		7:
			_rate_ok(40.0)
			_shot("t1b_2x")
			_click(hud._speed_buttons[3])
			wait = 0.3
		8:
			_check(main.speed == 3, "botão escolhe 4x")
			_start_measure()
		9:
			_rate_ok(80.0)
			_shot("t1c_4x")
			_click(hud._speed_buttons[2])
			wait = 0.3
		10:
			_check(main.speed == 2, "botão escolhe 2x")
			_start_measure()
		11:
			_rate_ok(40.0)
			_key(KEY_4)
			wait = 0.3
		12:
			_check(main.speed == 3, "tecla 4 também escolhe 4x")
			_key(KEY_3)
			wait = 0.2
		13:
			_check(main.speed == 3, "tecla 3 escolhe 4x")
			_key(KEY_SPACE)
			wait = 0.3
		14:
			_check(main.speed == 0, "espaço pausa")
			start_clock = _clock()
			wait = 1.2
		15:
			_check(_clock() == start_clock, "relógio parado na pausa")
			_check(hud._rate_label.text == "parado", "indicador mostra a pausa")
			day0 = w.day_index
			minute0 = w.minute
			_click(hud._skip_buttons[0])
			wait = 0.5
		16:
			_check(w.day_index == day0 + 7, "+7 dias avança 7 dias (%d)" % (w.day_index - day0))
			_check(w.minute == minute0, "hora não muda no avanço")
			_check(hud._skip_card.visible and hud._skip_title.text == "Resumo de 7 dias", "resumo aparece")
			_check(hud._date.text == w.date_string().get_slice("  ", 0), "data atualizada na barra")
			_shot("t2_resumo_7")
			day0 = w.day_index
			_click(hud._skip_buttons[1])
			wait = 0.6
		17:
			_check(w.day_index == day0 + 30, "+30 dias avança 30 dias (%d)" % (w.day_index - day0))
			_check(hud._skip_title.text == "Resumo de 30 dias", "resumo de 30 dias")
			_shot("t3_resumo_30")
			_check(_contains_gdp(hud), "resumo traz os indicadores")
			# Decisão no meio do avanço: para, espera a resposta e completa os dias.
			day0 = w.day_index
			var answered := {"done": false}
			main.start_skip(30)
			_check(hud._skip_buttons[0].disabled, "botões ficam desativados no avanço")
			w.ask_player({"title": "Teste", "text": "Decisão no meio do avanço", "options": [{"label": "Responder", "hint": "", "fn": func(): answered.done = true}]})
			set_meta("answered", answered)
			wait = 0.5
		18:
			_check(main.modal_open and main._skip_left == 30, "decisão interrompe o avanço (%d dias restantes)" % main._skip_left)
			_check(w.day_index == day0, "nenhum dia passa enquanto a decisão espera")
			_shot("t4_decisao")
			_dismiss()
			wait = 0.6
		19:
			_check(get_meta("answered").done, "resposta foi aplicada")
			_check(w.day_index == day0 + 30 and main._skip_left == 0, "avanço continua depois da resposta (%d)" % (w.day_index - day0))
			_check(not hud._skip_buttons[0].disabled, "botões voltam")
			main.start_skip(30)
			_check(main._skip_left == 30, "inicia outro")
			main.start_skip(7)
			_check(main._skip_left == 30, "segundo clique não soma enquanto avança")
			wait = 0.6
		20:
			# Salvar e carregar mantém a hora; a velocidade volta pausada.
			var m := w.minute
			w.minute = 725
			main._save_game()
			main.join_sim()
			w.minute = m
			main._load_game()
			wait = 0.3
		21:
			_check(main.world.minute == 725 and hud._day_clock.minute == 725, "carregar restaura a hora: %d" % hud._day_clock.minute)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(main.SAVE_PATH))
			print("RESULTADO: ", failures, " falhas")
			get_tree().quit(1 if failures > 0 else 0)


func _confirm_creator() -> void:
	if not main.modal_open:
		return
	for dim in main.modal_root.get_children():
		if dim is ColorRect and not dim.is_queued_for_deletion():
			var b := _named(dim, "Confirmar")
			if b:
				b.pressed.emit()
				# O partido é obrigatório: escolhe o primeiro da lista.
				var party := _containing(main.modal_root, "assentos")
				if party:
					party.pressed.emit()
				return


func _containing(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.contains(text):
			return child
		var found := _containing(child, text)
		if found:
			return found
	return null


func _named(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _named(child, text)
		if found:
			return found
	return null


func _contains_gdp(hud: Hud) -> bool:
	return hud._skip_body.text.contains("PIB:") and hud._skip_body.text.contains("Aprovação:")
