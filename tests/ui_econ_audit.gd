extends Node
## Plays like the user: advances years through "skip 30 days" (on the simulation thread), answers the decisions
## and photographs each economic tab, the Economy sub-tabs and another country's dossier. Checks that the numbers
## move, that no label stays empty and that the budget sliders work.
## Usage: godot --path . -- --ui-econ-audit --iso=BRA --years=4 --shots=/path/to/folder

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


## Advances like the "30 dias" button: the simulation runs on the worker thread and stops at each decision.
func _advance(days: int) -> void:
	var w: GameWorld = Game.world
	var target: int = w.day_index + days
	var guard := 0
	while w.day_index < target and not w.over and guard < 4000:
		guard += 1
		# The leader does not die or lose office in the middle of the audit: what matters is the economy.
		w.player.next_election = maxf(w.player.next_election, w.year_float() + 1.0)
		if main._skip_left == 0 and not main.modal_open and main.prompts.is_empty():
			main.start_skip(mini(30, target - w.day_index))
		await _wait(2)
		_dismiss()
	main.join_sim()
	_dismiss()


## Text of all the dynamic labels of a tab: a "—", "nan" or "inf" there is a missing number.
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
	_check(bad.is_empty(), "%s: no empty or invalid label %s" % [tab, str(bad)])
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
		_check(ch.series.size() >= 1, "Panel: chart %s with data (%d)" % [key, ch.series.size()])
	await _shot(tag + "_0_painel")
	await _tab(1)
	all.merge(_audit_labels("f", "Fiscal"))
	await _shot(tag + "_1_fiscal")
	await _tab(2)
	all.merge(_audit_labels("m", "Moeda"))
	for key in ["mc_rate", "mc_infl", "mc_fx", "mc_yield"]:
		var ch: MiniChart = hud._dyn[key]
		_check(ch.series.size() >= 1, "Currency: chart %s with data (%d)" % [key, ch.series.size()])
	var c: Country = Game.world.player
	if not hud._can_set_rate(c):
		var shown: String = (hud._slider_labels.rate_set as Label).text
		_check(shown == UiKit.num(c.rate * 100.0, 1) + "%", "Currency: the target rate shows the rate in use (%s, rate %.2f%%)" % [shown, c.rate * 100.0])
	var peg: Button = hud.get_node("%TogglePeg")
	_check(peg.disabled == (c == Game.world.usa or c.peg == 2), "Currency: dollar peg only for those with their own currency that is not the dollar")
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
	var other: Country = Game.world.by_iso["ARG" if iso != "ARG" else "CHL"]
	main.map.select(other)
	hud.show_country(other)
	await _wait()
	var dossier_bad := []
	for k: String in hud._dossier_dyn:
		var n: Node = hud._dossier_dyn[k]
		# "feedback" only has text after an action; "nukes" shows "—" for those with no warheads.
		if n is Label and not k in ["nukes", "feedback"] and _bad_text((n as Label).text):
			dossier_bad.append(k)
	_check(dossier_bad.is_empty(), "dossier of %s without empty labels %s" % [other.name, str(dossier_bad)])
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
	var w: GameWorld = Game.world
	main._pick_start(w.by_iso[iso])
	main._start_button.pressed.emit()
	await _wait()
	_top().get_node("%Confirm").pressed.emit()
	await _wait()
	_top().get_node("%party_rows").get_child(0).get_node("%pick").pressed.emit()
	await _wait()
	main._set_speed(0)
	_check(main.playing, "the match starts as %s" % iso)
	var hud: Hud = main.hud
	var c: Country = w.player
	var econ_news := []
	w.news_posted.connect(func(t, k, who): if who == c and k in ["economia", "crise"]: econ_news.append(t))
	var first := await _snapshot_all("a0")
	_check(not String(first.get("f_rev", "")).begins_with("US$ 0"), "the Fiscal tab already shows revenue on the first day:" + String(first.get("f_rev", "")))

	# Budget sliders: moving through the control changes the field and the accounts.
	await _tab(1)
	var slider: HSlider = hud._sliders.sp_infra
	var before := c.sp_infra
	slider.value = (before + 0.02) * 100.0
	await _wait()
	_check(absf(c.sp_infra - (before + 0.02)) < 0.0005 or not w.legislation.budget_lock("sp_infra").is_empty(), "the infrastructure slider changes spending: %.3f -> %.3f" % [before, c.sp_infra])
	var sp_after_slider := c.sp_infra

	var history := [first]
	for y in years:
		await _advance(365)
		if w.over:
			print("fim de jogo em ", w.date_string(), ": ", w.final_result if "final_result" in w else "")
			break
		_check(absf(c.sp_infra - sp_after_slider) < 0.003 or not w.legislation.budget_lock("sp_infra").is_empty(), "year %d: the spending chosen on the slider holds (%.3f)" % [y + 1, c.sp_infra])
		history.append(await _snapshot_all("a%d" % (y + 1)))
	if history.size() >= 2:
		var a: Dictionary = history[0]
		var b: Dictionary = history[history.size() - 1]
		var frozen := []
		var keys := ["o_gdp_pc", "o_res", "o_yield", "o_stock", "f_rev", "f_sp", "f_int", "f_debt", "m_rate", "m_pie", "t_exp", "t_imp", "g_gdp"]
		# The dollar is the exchange rate's own reference.
		if c != w.usa:
			keys.append("m_fx")
		for k: String in keys:
			if history.all(func(h): return h.get(k, "") == a.get(k, "")):
				frozen.append("%s=%s" % [k, a.get(k, "")])
		_check(frozen.is_empty(), "the numbers move over the years (stuck: %s)" % str(frozen))
		_check(a["_comm"] != b["_comm"], "the top commodities change: %s -> %s" % [a["_comm"], b["_comm"]])
		_check(a["_top"].gdp != b["_top"].gdp, "the top GDP changes")
	_check(econ_news.size() > 0, "the country's economic news shows up in the news feed: %s" % str(econ_news.slice(0, 4)))
