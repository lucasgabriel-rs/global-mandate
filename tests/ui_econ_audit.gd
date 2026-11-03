extends Node
## Joga como o usuário: avança anos pelo "pular 30 dias" (na thread de simulação), responde às decisões
## e fotografa cada aba econômica, as subabas da Economia e o dossiê de outro país. Confere que os números
## andam, que nenhum rótulo fica vazio e que os sliders do orçamento valem.
## Uso: godot --path . -- --ui-econ-audit --iso=BRA --years=4 --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var iso := "BRA"
var years := 4
var failures := 0


func _ready() -> void:
	Legislation.skip_unit_approval = true
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
		elif a.begins_with("--iso="):
			iso = a.trim_prefix("--iso=")
		elif a.begins_with("--years="):
			years = int(a.trim_prefix("--years="))
	DirAccess.make_dir_recursive_absolute(out)
	await _run()
	print("RESULTADO: %d falhas" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _wait(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name_: String) -> void:
	await _wait(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, iso.to_lower(), name_])


func _top() -> Control:
	return main.modal_root.get_child(main.modal_root.get_child_count() - 1)


func _dismiss() -> void:
	if main.hud.border.active:
		main.hud.border._on_decline()
	for dim in main.modal_root.get_children():
		if dim is ColorRect:
			var btn := _first_button(dim)
			if btn:
				btn.pressed.emit()


func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and child.visible and not child.disabled:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null


## Avança como o botão "30 dias": a simulação roda na thread de trabalho e para em cada decisão.
func _advance(days: int) -> void:
	var w: GameWorld = main.world
	var target: int = w.day_index + days
	var guard := 0
	while w.day_index < target and not w.over and guard < 4000:
		guard += 1
		# O líder não morre nem perde o cargo no meio da auditoria: o que interessa é a economia.
		w.player.next_election = maxf(w.player.next_election, w.year_float() + 1.0)
		if main._skip_left == 0 and not main.modal_open and main.prompts.is_empty():
			main.start_skip(mini(30, target - w.day_index))
		await _wait(2)
		_dismiss()
	main.join_sim()
	_dismiss()


## Texto de todos os rótulos dinâmicos de uma aba: um "—", "nan" ou "inf" ali é número faltando.
func _labels_of(prefix: String) -> Dictionary:
	var out_ := {}
	for key: String in main.hud._dyn:
		var n: Node = main.hud._dyn[key]
		if key.begins_with(prefix + "_") and n is Label:
			out_[key] = (n as Label).text
	return out_


func _bad_text(t: String) -> bool:
	var words := t.to_lower().replace("%", " ").split(" ", false)
	return t.strip_edges() == "" or t.strip_edges() == "—" or "nan" in words or "inf" in words or "-inf" in words


func _audit_labels(prefix: String, tab: String) -> Dictionary:
	var labels := _labels_of(prefix)
	var bad := []
	for k: String in labels:
		if _bad_text(labels[k]):
			bad.append("%s=%s" % [k, labels[k]])
	_check(bad.is_empty(), "%s: nenhum rótulo vazio ou inválido %s" % [tab, str(bad)])
	print("  %s: %s" % [tab, labels])
	return labels


func _tab(i: int) -> void:
	main.hud._desk.current_tab = i
	main.hud.refresh(true)
	await _wait()


func _snapshot_all(tag: String) -> Dictionary:
	var hud: Hud = main.hud
	var all := {}
	await _tab(0)
	all.merge(_audit_labels("o", "Painel"))
	for key in ["c_growth", "c_infl", "c_unemp", "c_debt", "c_approval", "c_stability"]:
		var ch: MiniChart = hud._dyn[key]
		_check(ch.series.size() >= 1, "Painel: gráfico %s com dados (%d)" % [key, ch.series.size()])
	await _shot(tag + "_0_painel")
	await _tab(1)
	all.merge(_audit_labels("f", "Fiscal"))
	await _shot(tag + "_1_fiscal")
	await _tab(2)
	all.merge(_audit_labels("m", "Moeda"))
	for key in ["mc_rate", "mc_infl", "mc_fx", "mc_yield"]:
		var ch: MiniChart = hud._dyn[key]
		_check(ch.series.size() >= 1, "Moeda: gráfico %s com dados (%d)" % [key, ch.series.size()])
	var c: Country = main.world.player
	if not hud._can_set_rate(c):
		var shown: String = (hud._slider_labels.rate_set as Label).text
		_check(shown == UiKit.num(c.rate * 100.0, 1) + "%", "Moeda: o juro alvo mostra a taxa praticada (%s, juro %.2f%%)" % [shown, c.rate * 100.0])
	var peg: Button = hud.get_node("%AlternarFlutuanteAncoraNoDolar")
	_check(peg.disabled == (c == main.world.usa or c.peg == 2), "Moeda: âncora no dólar só para quem tem moeda própria e não é o dólar")
	await _shot(tag + "_2_moeda")
	await _tab(3)
	all.merge(_audit_labels("t", "Comércio"))
	await _shot(tag + "_3_comercio")
	await _tab(5)
	all.merge(_audit_labels("g", "Mundo"))
	await _shot(tag + "_5_mundo")
	await _tab(9)
	var sub: TabContainer = hud.economy.get_node("%sub_tabs")
	for t in sub.get_tab_count():
		sub.current_tab = t
		hud.refresh(true)
		await _wait()
		await _shot("%s_9_economia_%d" % [tag, t])
	sub.current_tab = 0
	await _tab(0)
	var other: Country = main.world.by_iso["ARG" if iso != "ARG" else "CHL"]
	main.map.select(other)
	hud.show_country(other)
	await _wait()
	var dossier_bad := []
	for k: String in hud._dossier_dyn:
		var n: Node = hud._dossier_dyn[k]
		# "feedback" só tem texto depois de uma ação; "nukes" mostra "—" para quem não tem ogivas.
		if n is Label and not k in ["nukes", "feedback"] and _bad_text((n as Label).text):
			dossier_bad.append(k)
	_check(dossier_bad.is_empty(), "dossiê de %s sem rótulos vazios %s" % [other.name, str(dossier_bad)])
	await _shot(tag + "_dossie")
	main.map.select(null)
	hud.show_country(null)
	all["_top"] = {}
	for k: String in hud._top_values:
		all["_top"][k] = (hud._top_values[k] as Label).text
	print("  topo: ", all["_top"])
	var comm := []
	for l: Label in hud._commodity_labels:
		comm.append(l.text)
	all["_comm"] = comm
	print("  commodities: ", comm)
	return all


func _run() -> void:
	await _wait(5)
	var w: GameWorld = main.world
	main._pick_start(w.by_iso[iso])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirmar").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	_check(main.playing, "a partida começa como %s" % iso)
	var hud: Hud = main.hud
	var c: Country = w.player
	var econ_news := []
	w.news_posted.connect(func(t, k, who): if who == c and k in ["economia", "crise"]: econ_news.append(t))
	var first := await _snapshot_all("a0")
	_check(not String(first.get("f_rev", "")).begins_with("US$ 0"), "a aba Fiscal já mostra a receita no primeiro dia: " + String(first.get("f_rev", "")))

	# Sliders do orçamento: mexer pelo controle muda o campo e as contas.
	await _tab(1)
	var slider: HSlider = hud._sliders.sp_infra
	var before := c.sp_infra
	slider.value = (before + 0.02) * 100.0
	await _wait()
	_check(absf(c.sp_infra - (before + 0.02)) < 0.0005 or not w.legislation.budget_lock("sp_infra").is_empty(), "o slider de infraestrutura muda o gasto: %.3f -> %.3f" % [before, c.sp_infra])
	var sp_after_slider := c.sp_infra

	var history := [first]
	for y in years:
		await _advance(365)
		if w.over:
			print("fim de jogo em ", w.date_string(), ": ", w.final_result if "final_result" in w else "")
			break
		_check(absf(c.sp_infra - sp_after_slider) < 0.003 or not w.legislation.budget_lock("sp_infra").is_empty(), "ano %d: o gasto escolhido no slider se mantém (%.3f)" % [y + 1, c.sp_infra])
		history.append(await _snapshot_all("a%d" % (y + 1)))
	if history.size() >= 2:
		var a: Dictionary = history[0]
		var b: Dictionary = history[history.size() - 1]
		var frozen := []
		var keys := ["o_gdp_pc", "o_res", "o_yield", "o_stock", "f_rev", "f_sp", "f_int", "f_debt", "m_rate", "m_pie", "t_exp", "t_imp", "g_gdp"]
		# O dólar é a própria referência do câmbio.
		if c != w.usa:
			keys.append("m_fx")
		for k: String in keys:
			if history.all(func(h): return h.get(k, "") == a.get(k, "")):
				frozen.append("%s=%s" % [k, a.get(k, "")])
		_check(frozen.is_empty(), "os números andam ao longo dos anos (parados: %s)" % str(frozen))
		_check(a["_comm"] != b["_comm"], "as commodities do topo mudam: %s -> %s" % [a["_comm"], b["_comm"]])
		_check(a["_top"].gdp != b["_top"].gdp, "o PIB do topo muda")
	_check(econ_news.size() > 0, "notícias econômicas do país aparecem no noticiário: %s" % str(econ_news.slice(0, 4)))
