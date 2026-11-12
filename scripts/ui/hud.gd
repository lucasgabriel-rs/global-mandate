class_name Hud
extends Control
## Game interface: top bar, government panel, dossier of the selected country,
## news feed and map mode selector.

signal speed_requested(speed: int)
signal menu_requested
signal character_requested
signal party_requested
signal legislation_requested
signal agenda_requested
signal corruption_requested
signal tax_law_requested
signal treaty_requested(target: Country)
signal election_requested
signal party_detail_requested(id: int)
signal minister_pick_requested(post: String)
signal talk_requested(target: Country)
signal skip_requested(days: int)

const NEWS_ITEM := preload("res://scenes/ui/rows/news_item.tscn")
const LIST_BUTTON := preload("res://scenes/ui/rows/list_button.tscn")
const WAR_CARD := preload("res://scenes/ui/rows/war_card.tscn")
## Fields of the tab that each control changes immediately, without going through the budget.
const DIRECT_SLIDERS := ["mon_fin", "rate_set", "mobilization"]

var world: GameWorld
var map: MapView
var selected: Country

var _top_values := {}
var _speed_buttons: Array[Button] = []
var _speed := 1
var _skip_buttons: Array[Button] = []
var _dossier_built_for: Country
var _dossier_dyn := {}
var _action_buttons := {}
var _action_names := {}
var _toast_time := 0.0
var _mode_buttons := {}
var _commodity_labels: Array[Label] = []
var _dyn := {}
var _sliders := {}
var _slider_labels := {}
var _syncing := false
var _wars_sig := ""
var _partners_tick := 0
var _tick := 0
## The legislative center window comes after the ten government ones.
const LEGISLATION_WINDOW := 10

var _divisions_tab := -1
var _politics_tab := -1
var _cabinet_tab := -1
## Last role applied to the windows: 1 government, 0 opposition, -1 none yet (forces applying when a match starts).
var _office_shown := -1
var _hover_country: Country
var _hover_unit := -1

@onready var _date: Label = %date
@onready var _rate_label: Label = %rate_label
@onready var _skip_card: PanelContainer = %skip_card
@onready var _skip_title: Label = %skip_title
@onready var _skip_body: Label = %skip_body
@onready var _player_name: Label = %player_name
## The government's floating windows; the index of each is that of the old tabs.
@onready var _desk: WindowDesk = %desk
@onready var _dock: Dock = %dock
@onready var _dossier: PanelContainer = %dossier
@onready var _dossier_body: VBoxContainer = %dossier_body
@onready var _news_box: VBoxContainer = %news_box
@onready var _toast: PanelContainer = %toast
@onready var _toast_label: Label = %toast_label
@onready var _legend: Label = %legend
@onready var _hover_label: Label = %hover_label
@onready var _wars_peace: Label = %wars_peace
@onready var _war_cards: VBoxContainer = %war_cards
@onready var _partners_box: VBoxContainer = %partners_box
@onready var _world_box: VBoxContainer = %world_box
@onready var _divisions: DivisionsPanel = %divisions
@onready var border: BorderPanel = %border
@onready var debug: DebugMenu = %debug
@onready var _portrait: Countryball = %portrait
@onready var _leader_view: Countryball = %leader_view
@onready var _leader_name: Label = %leader_name
@onready var _politics: PoliticsPanel = %politics
@onready var _cabinet: CabinetPanel = %cabinet
@onready var _oposicao: OppositionPanel = %oposicao
@onready var economy: EconomyPanel = %economy
@onready var _banner: PanelContainer = %banner
@onready var _banner_label: Label = %banner_label


func _ready() -> void:
	_collect(self)
	_connect_buttons()
	_divisions_tab = _tab_of(_divisions)
	_politics_tab = _tab_of(_politics)
	_cabinet_tab = _tab_of(_cabinet)
	_set_mode_style("politico")


## The values the game updates are found by node name, so they can be moved in the scene freely.
func _collect(from: Node) -> void:
	for n: Node in from.get_children():
		# Windows and dock are their own scenes; the HUD content can live inside them.
		if n.owner != self:
			_collect(n)
			continue
		var id := String(n.name)
		if id.begins_with("top_"):
			_top_values[id.trim_prefix("top_")] = n
		elif id.begins_with("slider_value_"):
			_slider_labels[id.trim_prefix("slider_value_")] = n
		elif id.begins_with("slider_"):
			_sliders[id.trim_prefix("slider_")] = n
		elif id.begins_with("mode_"):
			_mode_buttons[id.trim_prefix("mode_")] = n
		elif id.begins_with("action_"):
			_action_buttons[id.trim_prefix("action_")] = n
			_action_names[id.trim_prefix("action_")] = (n as Button).text
		elif id.begins_with("dossier_"):
			_dossier_dyn[id.trim_prefix("dossier_")] = n
		elif n.unique_name_in_owner and id.get_slice("_", 0) in ["o", "f", "m", "t", "w", "g", "c", "mc"]:
			_dyn[id] = n
		_collect(n)


func _tab_of(content: Control) -> int:
	for i in _desk.get_tab_count():
		var page := _desk.get_tab_control(i)
		if page != null and (page == content or page.is_ancestor_of(content)):
			return i
	return -1


func _connect_buttons() -> void:
	for i in 4:
		var b: Button = get_node("%%speed_%d" % i)
		b.pressed.connect(speed_requested.emit.bind(i))
		_speed_buttons.append(b)
	for days: int in [7, 30]:
		var skip: Button = get_node("%%skip_%d" % days)
		skip.pressed.connect(skip_requested.emit.bind(days))
		_skip_buttons.append(skip)
	for i in 4:
		_commodity_labels.append(get_node("%%commodity_%d" % i))
	%Menu.pressed.connect(menu_requested.emit)
	%skip_close.pressed.connect(func(): _skip_card.visible = false)
	%EditarPersonagem.pressed.connect(character_requested.emit)
	_desk.tab_changed.connect(_on_tab_changed)
	_dock.desk = _desk
	_dock.item_pressed.connect(_on_dock_item)
	_cabinet.pick_requested.connect(func(post): minister_pick_requested.emit(post))
	_oposicao.politics_requested.connect(func(): _desk.open(_politics_tab))
	_oposicao.legislation_requested.connect(func(): legislation_requested.emit())
	_politics.party_requested.connect(func(): party_requested.emit())
	_politics.legislation_requested.connect(func(): legislation_requested.emit())
	_politics.corruption_requested.connect(func(): corruption_requested.emit())
	_politics.party_detail_requested.connect(func(id): party_detail_requested.emit(id))
	_politics.values_changed.connect(func(): refresh(true))
	_divisions.confirm_requested.connect(func(text, fn): confirm_requested.emit(text, fn))
	_divisions.banner_changed.connect(_on_banner)
	border.banner_changed.connect(_on_banner)
	for key: String in _sliders:
		(_sliders[key] as HSlider).value_changed.connect(_on_slider.bind(key))
		_sliders[key].set_meta("tip", _sliders[key].tooltip_text)
	%LegislarTributos.pressed.connect(tax_law_requested.emit)
	%LegislarTarifa.pressed.connect(tax_law_requested.emit)
	%PedirSocorroAoFMI.pressed.connect(_on_imf)
	%AlternarRegraDeTaylorJuro.pressed.connect(_on_toggle_taylor)
	%AlternarFlutuanteAncoraNoDolar.pressed.connect(_on_toggle_peg)
	for key: String in _mode_buttons:
		(_mode_buttons[key] as Button).pressed.connect(_on_mode.bind(key))
	%dossier_close.pressed.connect(func():
		map.select(null)
		show_country(null))
	(_dossier_dyn.talk as Button).pressed.connect(func(): talk_requested.emit(selected))
	%ProporTratado.pressed.connect(func(): treaty_requested.emit(selected))
	_politics.election_requested.connect(func(): election_requested.emit())
	for act: String in _action_buttons:
		(_action_buttons[act] as Button).pressed.connect(_on_action.bind(act))


# --- Advancing days ----------------------------------------------------------------

func refresh_clock() -> void:
	if world:
		var text := world.date_string()
		if _date.text != text:
			_date.text = text


func set_rate_display(rate: float, expected: float) -> void:
	_rate_label.text = tr("parado") if expected <= 0.0 else tr("%s dia/s") % UiKit.num(rate, 1)
	_rate_label.add_theme_color_override("font_color", UiKit.RED if expected > 0.0 and absf(rate - expected) > expected * 0.25 else UiKit.DIM)


func skip_snapshot() -> Dictionary:
	var c := world.player
	return {
		"gdp": c.y_usd(), "growth": c.growth_yoy(), "infl": c.pi_yoy, "unemp": c.unemp, "debt": c.debt_ratio,
		"approval": c.approval, "stability": c.stability, "fund": world.politics.party_fund(world), "oil": world.markets.price[Markets.OIL],
		"date": world.date_string(),
	}


func set_skipping(on: bool) -> void:
	for b: Button in _skip_buttons:
		b.disabled = on
	if on:
		_skip_card.visible = false


func show_skip_summary(days: int, before: Dictionary, news: Array) -> void:
	var c := world.player
	var lines := [
		tr("PIB: %s → %s") % [UiKit.money(before.gdp), UiKit.money(c.y_usd())],
		tr("Crescimento: %s → %s  ·  Inflação: %s → %s") % [UiKit.pct(before.growth), UiKit.pct(c.growth_yoy()), UiKit.pct(before.infl), UiKit.pct(c.pi_yoy)],
		tr("Desemprego: %s → %s  ·  Dívida/PIB: %s → %s") % [UiKit.pct(before.unemp), UiKit.pct(c.unemp), UiKit.pct(before.debt, 0), UiKit.pct(c.debt_ratio, 0)],
		tr("Aprovação: %d%% → %d%%  ·  Estabilidade: %d%% → %d%%") % [int(before.approval * 100.0), int(c.approval * 100.0), int(before.stability * 100.0), int(c.stability * 100.0)],
		tr("Fundo do partido: %s → %s  ·  Petróleo: $%.0f → $%.0f") % [UiKit.millions(before.fund), UiKit.millions(world.politics.party_fund(world)), before.oil, world.markets.price[Markets.OIL]],
	]
	_skip_title.text = tr("Resumo de %d dias") % days
	lines.append("")
	if news.is_empty():
		lines.append(tr("Nenhum acontecimento no noticiário."))
	else:
		lines.append(tr("%d acontecimento(s) no noticiário:") % news.size())
		# Wars and crises first: they are what changes the course of the game.
		var ordered := news.filter(func(n): return n[1] in ["guerra", "crise"]) + news.filter(func(n): return not n[1] in ["guerra", "crise"])
		for n: Array in ordered.slice(0, 6):
			lines.append("• " + String(n[0]))
		if ordered.size() > 6:
			lines.append(tr("e mais %d no noticiário.") % (ordered.size() - 6))
	_skip_body.text = "\n".join(lines)
	_skip_card.visible = true


func begin_demarcation(session: Dictionary) -> void:
	map.select(null)
	show_country(null)
	_toast.visible = false
	_toast_time = 0.0
	border.begin(session)
	map.focus_on(session.rival)


func refresh_leader() -> void:
	if world == null:
		return
	_portrait.show_person(world.leader, world.player.iso)
	_leader_view.show_person(world.leader, world.player.iso)
	var sick: Dictionary = world.leader.get("illness", {})
	_leader_name.text = tr("%s, %d anos%s") % [world.leader.get("name", ""), People.age_of(world.leader, world), "" if sick.is_empty() else tr(" (enfrenta %s)") % tr(sick.name)]
	_portrait.tooltip_text = _leader_name.text


func bind(w: GameWorld, m: MapView) -> void:
	world = w
	if map == null:
		m.unit_hovered.connect(set_hover_unit)
	map = m
	_divisions.bind(w, m)
	_politics.bind(w)
	_cabinet.bind(w)
	_oposicao.bind(w)
	_office_shown = -1
	economy.bind(w)
	border.bind(w, m)
	refresh_leader()
	map.unit_pick = _desk.current_tab == _divisions_tab
	selected = null
	_dossier.visible = false
	_dossier_built_for = null
	for child in _news_box.get_children():
		child.queue_free()
	if not world.news_posted.is_connected(_on_news):
		world.news_posted.connect(_on_news)
	_player_name.text = world.player.name if world.player else ""
	_wars_sig = "?"
	_sync_sliders()
	refresh(true)


func set_speed_display(s: int) -> void:
	_speed = s
	for i in _speed_buttons.size():
		var b := _speed_buttons[i]
		b.add_theme_color_override("font_color", UiKit.ACCENT if i == s else UiKit.TEXT)
		b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.95, 0.7, 0.24, 0.2) if i == s else Color(1, 1, 1, 0.05), UiKit.ACCENT if i == s else UiKit.LINE, 3, 4))


# --- Barra superior ------------------------------------------------------------

# --- Government panel ---------------------------------------------------------

func _on_tab_changed(_i: int) -> void:
	if map:
		map.unit_pick = _desk.current_tab == _divisions_tab
	refresh(true)


func _on_dock_item(item: DockItem) -> void:
	if item.action == "agenda":
		agenda_requested.emit()
		return
	if item.action == "legislation":
		# The center is rebuilt on every opening; clicking it when it is in front minimizes it.
		if _desk.is_open(LEGISLATION_WINDOW) and _desk.current_tab == LEGISLATION_WINDOW:
			_desk.toggle(LEGISLATION_WINDOW, _dock.item_center(item))
		else:
			_desk.window(LEGISLATION_WINDOW).origin = _dock.item_center(item)
			legislation_requested.emit()
	elif item.window_index >= 0:
		_desk.toggle(item.window_index, _dock.item_center(item))


func show_legislation(center: LegislationCenter) -> void:
	_desk.window(LEGISLATION_WINDOW).set_content(center)
	_desk.open(LEGISLATION_WINDOW)


func close_legislation() -> void:
	_desk.close(LEGISLATION_WINDOW)


func legislation_center() -> LegislationCenter:
	var w := _desk.window(LEGISLATION_WINDOW)
	return w.content() as LegislationCenter if w.is_open else null


func start_drawing() -> void:
	if border.active or not world.in_office:
		return
	_desk.current_tab = _divisions_tab
	_divisions.start_drawing()


## Spending changes immediately, unless a law requires the value; then the control is locked.
func _on_slider(v: float, key: String) -> void:
	if not _syncing and world and world.player and world.in_office:
		if key in DIRECT_SLIDERS:
			world.player.set(key, v / 100.0)
		else:
			var r: Dictionary = world.politics.set_budget(world, key, v / 100.0)
			if not r.ok:
				_sync_budget_sliders(world.player)
	_label_slider(key, v / 100.0)


func _label_slider(key: String, value: float) -> void:
	var label: Label = _slider_labels[key]
	var fixed: bool = world != null and world.player != null and Politics.BUDGET_LABELS.has(key) and not world.legislation.budget_lock(key).is_empty()
	label.text = (tr("Por lei: ") if fixed else "") + UiKit.num(value * 100.0, 1) + "%"
	label.add_theme_color_override("font_color", UiKit.ACCENT if fixed else UiKit.TEXT)


func _on_imf() -> void:
	if world.player.imf_program <= 0.0 and world.in_office:
		Economy.apply_imf(world.player, world)


func _on_toggle_taylor() -> void:
	var c := world.player
	if c.peg == 0 and world.in_office and not c.cb_independent:
		c.rate_manual = not c.rate_manual
		c.rate_set = c.rate
		c.cred = clampf(c.cred - (0.04 if c.rate_manual else -0.02), 0.05, 0.97)
		_sync_sliders()
		refresh(true)


func _on_toggle_peg() -> void:
	var c := world.player
	if not world.in_office:
		return
	if c == world.usa:
		return
	if c.peg == 2:
		world.emit_news(tr("Membros do euro não têm moeda própria."), "economia", c)
	elif c.peg == 1:
		c.peg = 0
		world.emit_news(tr("%s adota câmbio flutuante.") % c.name, "economia", c)
	elif c.reserves > c.imports / 12.0 * 4.0:
		c.peg = 1
		c.rate_manual = false
		world.emit_news(tr("%s ancora a moeda no dólar.") % c.name, "economia", c)
	else:
		world.emit_news(tr("Reservas insuficientes para sustentar uma âncora (mínimo de 4 meses de importação)."), "economia", c)
	_sync_sliders()
	refresh(true)


# --- Dossier of the selected country --------------------------------------------------

func show_country(c: Country) -> void:
	debug.set_target(c)
	selected = c
	_dossier.visible = c != null
	if c != _dossier_built_for:
		_build_dossier_for(c)
	refresh(true)


## The parts that only apply to another country stay in the scene's foreign_only group.
func _build_dossier_for(c: Country) -> void:
	_dossier_built_for = c
	if c == null:
		return
	(%dossier_title as Label).text = c.name
	_apply_role()
	_set_feedback("")


func _on_action(act: String) -> void:
	if selected == null:
		return
	if act == "war":
		var pl := world.player
		var msg := tr("Declarar guerra a %s? O mundo vai reagir e pactos de defesa podem ser acionados.") % selected.name
		var target := selected
		confirm_requested.emit(msg, func():
			var r := world.do_action("war", target)
			if not r.ok:
				_set_feedback(r.msg)
			pl.stance_offensive = true
			refresh(true))
		return
	var r := world.do_action(act, selected)
	_set_feedback(r.msg)
	refresh(true)


signal confirm_requested(text: String, fn: Callable)


func _set_feedback(text: String) -> void:
	_dossier_dyn.feedback.text = text


func _refresh_dossier() -> void:
	var c := selected
	if c == null or not _dossier.visible:
		return
	if not c.alive:
		show_country(null)
		return
	var d := world.diplomacy
	var regime := tr("Democracia") if c.dem >= 6.0 else (tr("Regime híbrido") if c.dem >= 4.0 else tr("Regime autoritário"))
	var blocs := " · ".join(c.blocs)
	_dossier_dyn.sub.text = regime + ("  ·  " + blocs if blocs != "" else "")
	_dossier_dyn.gdp.text = UiKit.money(c.y_usd())
	_dossier_dyn.pc.text = tr("US$ %s") % UiKit.thousand(c.gdp_pc())
	_dossier_dyn.pop.text = tr("%s mi") % UiKit.num(c.pop, 1)
	var g := c.growth_yoy()
	_dossier_dyn.growth.text = UiKit.pct(g)
	_dossier_dyn.growth.add_theme_color_override("font_color", UiKit.good_bad(g))
	_dossier_dyn.infl.text = UiKit.pct(c.pi_yoy)
	_dossier_dyn.unemp.text = UiKit.pct(c.unemp)
	_dossier_dyn.rate.text = UiKit.pct(c.rate, 2)
	_dossier_dyn.debt.text = UiKit.pct(c.debt_ratio, 0)
	_dossier_dyn.rating.text = tr("D (moratória)") if world.year_float() < c.default_until else c.rating
	_dossier_dyn.stability.text = "%d%%" % int(c.stability * 100.0)
	_dossier_dyn.approval.text = "%d%%" % int(c.approval * 100.0)
	_dossier_dyn.power.text = UiKit.num(100.0 * c.military_power() / maxf(world.usa.military_power(), 0.01), 1)
	_dossier_dyn.nukes.text = UiKit.thousand(c.nukes) if c.nukes > 0 else "—"
	_dossier_dyn.exports.text = UiKit.money(c.exports)
	_dossier_dyn.units.text = str(world.subdivisions.roots_of(c.iso).size())
	_dossier_dyn.capital.text = _capital_name(c)
	var ruling: Dictionary = world.politics.ruling_party(c.iso)
	_dossier_dyn.leader.text = String(world.leader.get("name", "—")) if c == world.player and world.in_office else _leader_text(world.politics.leader_of(c.iso))
	if c != world.player:
		var talk: Button = _dossier_dyn.talk
		var wait: int = Dialogue.wait_months(world, c)
		talk.disabled = not world.in_office or wait > 0
		talk.text = tr("Falar com %s") % String(world.politics.leader_of(c.iso).get("name", tr("o líder"))) if wait == 0 else tr("Nova conversa no mês que vem")
	_dossier_dyn.gov_party.text = String(ruling.get("short", "—"))
	_dossier_dyn.gov_party.tooltip_text = String(ruling.get("name", ""))
	var seats_total: int = world.politics.data_of(c.iso).get("seats_total", 0)
	_dossier_dyn.gov_seats.text = tr("%d de %d") % [world.politics.government_seats(c.iso), seats_total]
	_dossier_dyn.parliament.text = _parliament_text(c)
	_dossier_dyn.ch_growth.set_data(c.hist.get("growth", PackedFloat32Array()))
	_dossier_dyn.ch_infl.set_data(c.hist.get("infl", PackedFloat32Array()))
	var pl := world.player
	if pl == null or c == pl:
		return
	var rel := d.relation(pl.idx, c.idx)
	_dossier_dyn.rel_bar.value = rel
	_dossier_dyn.rel_val.text = "%+d" % int(rel)
	_dossier_dyn.rel_val.add_theme_color_override("font_color", UiKit.good_bad(rel))
	var flags := []
	var at_war := d.at_war(pl.idx, c.idx)
	var allied := d.allied(pl.idx, c.idx)
	if at_war:
		flags.append(tr("EM GUERRA"))
	if allied:
		flags.append(tr("Aliado de defesa"))
	if d.has_fta(pl.idx, c.idx, world):
		flags.append(tr("Livre comércio"))
	var lvl := d.sanction_level(pl.idx, c.idx)
	if lvl > 0:
		flags.append(tr("Você aplica embargo") if lvl >= 2 else tr("Você aplica sanções"))
	var lvl2 := d.sanction_level(c.idx, pl.idx)
	if lvl2 > 0:
		flags.append(tr("Sancionado por este país"))
	var share := d.shares[pl.idx * d.n + c.idx] * d.factor[pl.idx * d.n + c.idx]
	flags.append(tr("%s das suas exportações") % UiKit.pct(share))
	_dossier_dyn.status.text = "  ·  ".join(flags)
	var labels := {
		"alliance": tr("Cancelar pacto") if allied else tr("Pacto de defesa"),
		"sanction": tr("Suspender sanções") if lvl >= 1 else tr("Sanções"),
		"embargo": tr("Reduzir embargo") if lvl >= 2 else tr("Embargo total"),
		"tariff": tr("Remover tarifa") if d.tariffs.has(d.key(pl.idx, c.idx)) else tr("Tarifa de 20%"),
	}
	for act: String in _action_buttons:
		var b: Button = _action_buttons[act]
		var base: String = labels.get(act, _action_names[act])
		var pause := world.action_wait(act, c)
		b.text = base if pause == 0 else tr("%s (%d dias)") % [base, pause]
		var off: bool = pause > 0 or not world.in_office
		if act == "peace":
			off = off or not at_war
		elif act == "war":
			off = off or at_war
		elif act in ["fta", "arms", "aid", "mission"]:
			off = off or at_war
		if act == "fta" and d.has_fta(pl.idx, c.idx, world):
			off = true
		b.disabled = off


# --- Parte inferior --------------------------------------------------------------

func _on_mode(key: String) -> void:
	map.set_mode(key)
	_set_mode_style(key)


func _set_mode_style(key: String) -> void:
	for k: String in _mode_buttons:
		var b: Button = _mode_buttons[k]
		var on := k == key
		b.add_theme_color_override("font_color", UiKit.ACCENT if on else UiKit.TEXT)
		b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.08, 0.13, 0.17, 0.95), UiKit.ACCENT if on else UiKit.LINE, 3, 5))
	var legends := {
		"politico": "", "relacoes": tr("vermelho hostil · verde amigo · azul aliado"),
		"crescimento": "-3% a +8%", "inflacao": "0% a 30%+", "desemprego": "2% a 22%",
		"divida": tr("relativa ao limite do país"), "renda": tr("US$ 300 a 90 mil per capita"),
		"estabilidade": tr("vermelho instável"), "militar": tr("em relação aos EUA"),
	}
	_legend.text = "  " + str(legends.get(key, ""))


func set_hover(c: Country) -> void:
	_hover_country = c
	_update_hover()


func set_hover_unit(id: int) -> void:
	_hover_unit = id
	_update_hover()


func _update_hover() -> void:
	var subs: Subdivisions = world.subdivisions
	if subs.units.has(_hover_unit):
		var u: Dictionary = subs.units[_hover_unit]
		var land: Country = world.by_iso.get(u.owner)
		var text := tr("%s  ·  %s  ·  %s  ·  cerca de %s mi de habitantes") % [subs.path_of(_hover_unit), tr(subs.get_type(u.type).name), land.name if land else "", UiKit.num((land.pop if land else 0.0) * subs.pop_share(_hover_unit), 2)]
		for holder: Variant in subs.holders_of(_hover_unit):
			text += tr("  ·  capital de %s") % (world.by_iso[holder].name if holder is String else subs.units[holder].name)
		_hover_label.text = text
		return
	var c := _hover_country
	if c == null:
		_hover_label.text = ""
		return
	var txt := tr("%s  ·  PIB %s  ·  cresc. %s  ·  infl. %s") % [c.name, UiKit.money(c.y_usd()), UiKit.pct(c.growth_yoy()), UiKit.pct(c.pi_yoy)]
	if world.player and c != world.player:
		txt += tr("  ·  relação %+d") % int(world.diplomacy.relation(world.player.idx, c.idx))
	_hover_label.text = txt


func _on_banner(text: String, is_error: bool) -> void:
	_banner.visible = text != ""
	_banner_label.text = text
	_banner.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.2, 0.05, 0.03, 0.96) if is_error else UiKit.BG, UiKit.RED if is_error else UiKit.ACCENT, 3, 7))


func _on_news(text: String, kind: String, country: Country) -> void:
	var colors := {"guerra": UiKit.RED, "crise": Color("f08a4b"), "economia": UiKit.CYAN, "diplomacia": UiKit.GREEN, "politica": UiKit.ACCENT}
	var b: Button = NEWS_ITEM.instantiate()
	b.text = "%s  %s" % [world.date_string(), text]
	b.add_theme_color_override("font_color", colors.get(kind, UiKit.TEXT))
	if country:
		b.pressed.connect(func():
			if country.alive:
				map.select(country)
				map.focus_on(country)
				show_country(country))
	_news_box.add_child(b)
	_news_box.move_child(b, 0)
	while _news_box.get_child_count() > 60:
		var last := _news_box.get_child(_news_box.get_child_count() - 1)
		_news_box.remove_child(last)
		last.queue_free()
	var big := country != null and country.y_usd() > world.world_gdp() * 0.01
	var involves_player := country == world.player
	if kind == "guerra" or (kind == "crise" and (big or involves_player)):
		_toast_label.text = text
		_toast.visible = true
		_toast_time = 5.0


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false


# --- Update -----------------------------------------------------------------------

func _sync_sliders() -> void:
	var c := world.player
	if c == null:
		return
	_syncing = true
	for f: String in ["mon_fin", "mobilization"]:
		var s: HSlider = _sliders[f]
		s.value = float(c.get(f)) * 100.0
		_label_slider(f, float(c.get(f)))
	_sync_budget_sliders(c)
	var rs: HSlider = _sliders.rate_set
	rs.value = c.rate_set * 100.0
	rs.editable = _can_set_rate(c)
	_syncing = false


## Shows the value in force and locks what a law requires. Laws and events also change these fields.
func _sync_budget_sliders(c: Country) -> void:
	var was_syncing := _syncing
	_syncing = true
	for f: String in Politics.BUDGET_LABELS:
		var slider: HSlider = _sliders[f]
		var lock: Dictionary = world.legislation.budget_lock(f)
		slider.set_value_no_signal(float(c.get(f)) * 100.0)
		slider.editable = world.in_office and lock.is_empty()
		slider.tooltip_text = tr("Fixado por lei em vigor. Para mudar, altere ou revogue a lei.") if not lock.is_empty() else String(slider.get_meta("tip", slider.tooltip_text))
		_label_slider(f, float(c.get(f)))
	_syncing = was_syncing


## Shows only what suits the player's role. Scene nodes mark what belongs to each role through the groups
## gov_only (government only), opposition_only (opposition only) and foreign_only (only in another country's dossier);
## role_text swaps the text (or the window title, or the dock icon name) for the metadata
## opposition_text while the player is in opposition. Windows of the other role close and do not open.
func _apply_role() -> void:
	var office := world.in_office
	var foreign: bool = world.player != null and selected != null and selected != world.player
	var seen := {}
	for group: String in ["gov_only", "opposition_only", "foreign_only"]:
		for n: Node in get_tree().get_nodes_in_group(group):
			if seen.has(n) or not is_ancestor_of(n):
				continue
			seen[n] = true
			var shown := not (n.is_in_group("gov_only") and not office) and not (n.is_in_group("opposition_only") and office) and not (n.is_in_group("foreign_only") and not foreign)
			if n is FloatWindow:
				var w: FloatWindow = n
				w.locked = not shown
				if not shown and w.is_open:
					w.close()
			else:
				(n as CanvasItem).visible = shown
	for n: Node in get_tree().get_nodes_in_group("role_text"):
		if not is_ancestor_of(n) or not n.has_meta("opposition_text"):
			continue
		var prop := "title" if n is FloatWindow else ("label" if n is DockItem else "text")
		if not n.has_meta("office_text"):
			n.set_meta("office_text", n.get(prop))
		n.set(prop, n.get_meta("office_text" if office else "opposition_text"))


## In government everything is available; in opposition, the controls only show what the AI decides.
func _refresh_office() -> void:
	var office := world.in_office
	if world.player:
		_player_name.text = world.player.name if office else tr("%s · oposição") % world.player.name
	if int(office) == _office_shown:
		return
	_office_shown = int(office)
	_apply_role()
	economy.set_office(office)
	for key: String in _sliders:
		if key != "rate_set":
			(_sliders[key] as HSlider).editable = office
	_sync_sliders()
	_dossier_built_for = null
	if selected:
		_build_dossier_for(selected)


func refresh(force := false) -> void:
	if world == null:
		return
	_refresh_office()
	_tick += 1
	_date.text = world.date_string().get_slice("  ", 0)
	var m := world.markets
	_commodity_labels[0].text = "$%.0f" % m.price[Markets.OIL]
	_commodity_labels[1].text = "$" + UiKit.num(m.price[Markets.GAS], 1)
	_commodity_labels[2].text = "$%.0f" % m.price[Markets.GRAIN]
	_commodity_labels[3].text = "%.0f" % m.price[Markets.CHIP]
	var trend := [Markets.OIL, Markets.GAS, Markets.GRAIN, Markets.CHIP]
	for i in trend.size():
		var rel := m.relative_price(trend[i], world)
		_commodity_labels[i].add_theme_color_override("font_color", UiKit.RED if rel > 1.35 else (UiKit.GREEN if rel < 0.8 else UiKit.TEXT))
	var tension: Label = _top_values.tension
	tension.text = "%d%%" % int(world.global_tension * 100.0)
	tension.add_theme_color_override("font_color", UiKit.RED if world.global_tension > 0.6 else (UiKit.ACCENT if world.global_tension > 0.35 else UiKit.TEXT))
	var c := world.player
	if c:
		if _tick % 16 == 0:
			refresh_leader()
		_refresh_top(c)
		_refresh_tab(c)
		if force or _tick % 8 == 0:
			_sync_mobilization(c)
			_sync_budget_sliders(c)
	_refresh_dossier()


func _sync_mobilization(c: Country) -> void:
	_syncing = true
	(_sliders.mobilization as HSlider).value = c.mobilization * 100.0
	_syncing = false


func _refresh_top(c: Country) -> void:
	var t := _top_values
	t.gdp.text = UiKit.money(c.y_usd())
	var g := c.growth_yoy()
	t.growth.text = UiKit.pct(g)
	t.growth.add_theme_color_override("font_color", UiKit.good_bad(g))
	t.infl.text = UiKit.pct(c.pi_yoy)
	t.infl.add_theme_color_override("font_color", UiKit.RED if c.pi_yoy > c.pi_target + 0.03 else UiKit.TEXT)
	t.unemp.text = UiKit.pct(c.unemp)
	t.debt.text = UiKit.pct(c.debt_ratio, 0)
	t.debt.add_theme_color_override("font_color", UiKit.RED if c.debt_ratio > c.debt_tol else UiKit.TEXT)
	t.approval.text = "%d%%" % int(c.approval * 100.0)
	t.approval.add_theme_color_override("font_color", UiKit.RED if c.approval < 0.4 else (UiKit.GREEN if c.approval > 0.55 else UiKit.TEXT))
	var balance := -c.deficit / maxf(c.y_nominal(), 0.001)
	t.budget.text = "%s%.1f%%" % ["+" if balance > 0.0 else "", balance * 100.0]
	t.budget.add_theme_color_override("font_color", UiKit.RED if balance < -0.05 else (UiKit.GREEN if balance >= -0.01 else UiKit.TEXT))


func _set_chart(key: String, c: Country) -> void:
	var ch: MiniChart = _dyn[key]
	ch.set_data(c.hist.get(ch.series_key, PackedFloat32Array()))


## Updates all open windows; closed ones cost nothing.
func _refresh_tab(c: Country) -> void:
	for i in _desk.open_windows():
		_refresh_window(i, c)


func _refresh_window(i: int, c: Country) -> void:
	match i:
		0: _refresh_overview(c)
		1: _refresh_fiscal(c)
		2: _refresh_monetary(c)
		3: _refresh_trade(c)
		4: _refresh_military(c)
		5: _refresh_world()
		7: _politics.refresh()
		8: _cabinet.refresh()
		9: economy.refresh()
		11: _oposicao.refresh()


func _leader_text(leader: Dictionary) -> String:
	if leader.is_empty():
		return "—"
	var sick: Dictionary = leader.get("illness", {})
	return tr("%s, %d anos, %s%s") % [leader.name, People.age_of(leader, world), Dialogue.temper(leader), "" if sick.is_empty() else tr(", doente")]


func _parliament_text(c: Country) -> String:
	if c.dem < Politics.FREE_PARLIAMENT_DEM:
		return tr("Sem parlamento livre: o líder governa por decreto.")
	var data: Dictionary = world.politics.data_of(c.iso)
	var lines := []
	var pending: Dictionary = data.get("pending_bill", {})
	if not pending.is_empty():
		lines.append(tr("Em debate: %s") % tr(Politics._world_bill(String(pending.id)).get("name", "")))
	for law: Dictionary in data.get("recent_laws", []):
		lines.append("%s  %s: %s (%s), %d a %d" % [law.date, tr("aprovado") if law.passed else tr("rejeitado"), tr(law.title), law.party, int(law.yes), int(law.total) - int(law.yes)])
	return "\n".join(lines) if not lines.is_empty() else tr("Nenhuma votação recente.")


func _capital_name(c: Country) -> String:
	var id: int = world.subdivisions.capital_of(c.iso)
	return world.subdivisions.units[id].name if id >= 0 else "—"


func _refresh_overview(c: Country) -> void:
	_dyn.o_capital.text = _capital_name(c)
	_dyn.o_party.text = String(world.politics.player_party(world).get("short", "—"))
	_dyn.o_seats.text = UiKit.pct(world.politics.government_share(c.iso), 0)
	_dyn.o_regime.text = tr("Democracia") if c.dem >= 6.0 else (tr("Regime híbrido") if c.dem >= 4.0 else tr("Autoritário"))
	if c.dem >= 4.0:
		var left := c.next_election - world.year_float()
		_dyn.o_next.text = tr("em %s anos") % UiKit.num(maxf(left, 0.0), 1)
		_dyn.o_next.add_theme_color_override("font_color", UiKit.ACCENT if left < 0.75 else UiKit.TEXT)
	else:
		_dyn.o_next.text = tr("sem eleições: cuide da estabilidade")
	var rank := world.rank_of(c, func(x: Country): return x.influence)
	_dyn.o_rank.text = tr("%dº  (%s pts)") % [rank, UiKit.num(c.influence, 1)]
	for key in ["c_growth", "c_infl", "c_unemp", "c_debt", "c_approval", "c_stability"]:
		_set_chart(key, c)
	_dyn.o_gdp_pc.text = tr("US$ %s") % UiKit.thousand(c.gdp_pc())
	_dyn.o_pop.text = tr("%s mi") % UiKit.num(c.pop, 1)
	_dyn.o_ca.text = UiKit.pct(c.ca_ratio)
	_dyn.o_res.text = UiKit.money(c.reserves)
	_dyn.o_rating.text = tr("D (moratória)") if world.year_float() < c.default_until else c.rating
	_dyn.o_yield.text = UiKit.pct(c.yield_gov, 2)
	_dyn.o_stock.text = UiKit.num(c.stock, 0)


func _refresh_fiscal(c: Country) -> void:
	_dyn.f_rate_tax_income.text = UiKit.pct(c.tax_income)
	_dyn.f_rate_tax_consumption.text = UiKit.pct(c.tax_consumption)
	_dyn.f_rate_tax_corporate.text = UiKit.pct(c.tax_corporate)
	var f := maxf(c.y_nominal(), 0.001)
	_dyn.f_rev.text = "%s  (%s)" % [UiKit.money(c.revenue / c.e), UiKit.pct(c.revenue / f)]
	var primary := c.spending - c.interest
	_dyn.f_sp.text = "%s  (%s)" % [UiKit.money(primary / c.e), UiKit.pct(primary / f)]
	_dyn.f_int.text = "%s  (%s)" % [UiKit.money(c.interest / c.e), UiKit.pct(c.interest / f)]
	var dr := c.deficit / f
	_dyn.f_def.text = UiKit.pct(dr)
	_dyn.f_def.add_theme_color_override("font_color", UiKit.RED if dr > 0.05 else (UiKit.GREEN if dr <= 0.01 else UiKit.TEXT))
	_dyn.f_debt.text = UiKit.pct(c.debt_ratio, 0)
	_dyn.f_tol.text = UiKit.pct(c.debt_tol, 0)


func _can_set_rate(c: Country) -> bool:
	return c.rate_manual and c.peg == 0 and world.in_office and not c.cb_independent


func _refresh_monetary(c: Country) -> void:
	var status := tr("Banco central independente") if c.cb_independent else tr("Banco central subordinado, regra de Taylor")
	if c.peg == 2:
		status = tr("Zona do euro: decisão do BCE")
	elif c.peg == 1:
		status = tr("Âncora no dólar: segue o Fed")
	elif c.rate_manual:
		status = tr("Juro definido pelo governo")
	_dyn.m_status.text = status
	var rate_slider: HSlider = _sliders.rate_set
	rate_slider.editable = _can_set_rate(c)
	# Outside the manual rate, the control shows the rate that whoever decides (central bank, ECB or Fed) is applying.
	if not rate_slider.editable:
		rate_slider.set_value_no_signal(c.rate * 100.0)
		_label_slider("rate_set", c.rate)
	var peg_toggle: Button = %AlternarFlutuanteAncoraNoDolar
	peg_toggle.disabled = c == world.usa or c.peg == 2 or not world.in_office
	var toggle: Button = %AlternarRegraDeTaylorJuro
	toggle.disabled = c.cb_independent or c.peg != 0 or not world.in_office
	toggle.tooltip_text = tr("O banco central é independente: o governo não escolhe o juro. A Constituição pode mudar isso por emenda.") if c.cb_independent else tr("Manual dá controle direto, mas interferência reduz a credibilidade do banco central.")
	_dyn.m_rate.text = UiKit.pct(c.rate, 2)
	_dyn.m_real.text = UiKit.pct(c.rate - c.pi_e, 2)
	_dyn.m_neutral.text = UiKit.pct(c.r_n, 2)
	_dyn.m_target.text = UiKit.pct(c.pi_target)
	_dyn.m_pie.text = UiKit.pct(c.pi_e)
	_dyn.m_cred.text = "%d%%" % int(c.cred * 100.0)
	_dyn.m_fx.text = UiKit.num(c.e, 2)
	_dyn.m_rer.text = UiKit.num(c.rer, 2)
	_refresh_fx_reserves(c)
	_refresh_fund(c)
	for key in ["mc_rate", "mc_infl", "mc_fx", "mc_yield", "mc_res", "mc_swf"]:
		_set_chart(key, c)


## Reserves, intervention, capital controls, flight, dollarization and uncovered parity.
func _refresh_fx_reserves(c: Country) -> void:
	var cover := c.reserves / maxf(c.imports / 12.0, 0.001)
	_dyn.m_res.text = tr("%s  (%s meses)") % [UiKit.money(c.reserves), UiKit.num(cover, 1)]
	_dyn.m_res.add_theme_color_override("font_color", UiKit.RED if cover < 3.0 else UiKit.TEXT)
	if c == world.usa or c.peg == 2:
		_dyn.m_interv.text = tr("não se aplica")
	else:
		_dyn.m_interv.text = (tr("vende %s") if c.fx_interv >= 0.0 else tr("compra %s")) % UiKit.money(absf(c.fx_interv))
	var lean := tr("câmbio fixo") if c.peg == 1 else (tr("forte") if c.fx_lean >= 0.5 else (tr("suave") if c.fx_lean >= 0.15 else tr("flutuação livre")))
	_dyn.m_lean.text = tr("euro") if c.peg == 2 else lean
	_dyn.m_controls.text = tr("nenhum") if c.cap_controls < 0.05 else UiKit.pct(c.cap_controls, 0)
	_dyn.m_flight.text = UiKit.money(c.cap_flight)
	_dyn.m_flight.add_theme_color_override("font_color", UiKit.RED if c.cap_flight > 0.01 * c.y_usd() else UiKit.TEXT)
	_dyn.m_dollar.text = UiKit.pct(c.dollarization, 0)
	_dyn.m_uip.text = UiKit.pct(c.uip_dep, 1) if c.peg == 0 and c != world.usa else tr("não se aplica")


## Sovereign fund: balance, flows of the year, withdrawal rule and return.
func _refresh_fund(c: Country) -> void:
	var share := c.swf / maxf(c.y_usd(), 0.001)
	if c.swf_active:
		_dyn.m_swf_status.text = tr("ativo")
	elif c.swf > 0.0:
		_dyn.m_swf_status.text = tr("fora da lei: só rende")
	else:
		_dyn.m_swf_status.text = tr("sem fundo: crie pela Lei Cambial")
	_dyn.m_swf.text = tr("%s  (%s do PIB)") % [UiKit.money(c.swf), UiKit.pct(share, 0)]
	_dyn.m_swf_in.text = UiKit.money(c.swf_in / maxf(c.e, 0.001))
	_dyn.m_swf_out.text = UiKit.money(c.swf_out / maxf(c.e, 0.001))
	var draw := c.swf_out / maxf(c.swf * c.e, 0.001) if c.swf > 0.0 else 0.0
	_dyn.m_swf_out.add_theme_color_override("font_color", UiKit.RED if draw > Economy.SWF_SAFE_DRAW else UiKit.TEXT)
	_dyn.m_swf_rule.text = tr("até %s do saldo ao ano") % UiKit.pct(c.swf_limit, 1) if c.swf_active else "—"
	_dyn.m_swf_ret.text = UiKit.pct(c.swf_return, 1) if c.swf > 0.0 else "—"


func _refresh_trade(c: Country) -> void:
	_dyn.t_tariff.text = UiKit.pct(c.tariff)
	_dyn.t_exp.text = UiKit.money(c.exports)
	_dyn.t_imp.text = UiKit.money(c.imports)
	_dyn.t_ca.text = UiKit.pct(c.ca_ratio)
	_dyn.t_loss.text = ("+" if c.trade_loss >= 0.0 else "") + UiKit.pct(c.trade_loss)
	_dyn.t_loss.add_theme_color_override("font_color", UiKit.good_bad(c.trade_loss))
	for i in 5:
		var net := c.prod[i] * c.prod_factor[i] - c.use[i] * pow(c.y / c.y0, Markets.INCOME_ELAST[i])
		_dyn["t_comm_%d" % i].text = UiKit.money(world.markets.value_usd(i, net))
		_dyn["t_comm_%d" % i].add_theme_color_override("font_color", UiKit.good_bad(net))
	_partners_tick += 1
	if _partners_tick % 8 != 1 and _partners_box.get_child_count() > 0:
		return
	for child in _partners_box.get_children():
		_partners_box.remove_child(child)
		child.queue_free()
	for pair: Array in world.diplomacy.top_partners(c, 8, world):
		var o: Country = world.countries[pair[0]]
		var b: Button = LIST_BUTTON.instantiate()
		b.text = "%s   %s" % [o.name, UiKit.pct(pair[1])]
		b.pressed.connect(func():
			map.select(o)
			show_country(o))
		_partners_box.add_child(b)


func _refresh_military(c: Country) -> void:
	_dyn.w_power.text = UiKit.num(100.0 * c.military_power() / maxf(world.usa.military_power(), 0.01), 1)
	_dyn.w_rank.text = "%dº" % world.rank_of(c, func(x: Country): return x.military_power())
	_dyn.w_troops.text = tr("%s mil") % UiKit.thousand(c.troops)
	_dyn.w_stock.text = UiKit.money(c.mil_stock)
	_dyn.w_nukes.text = UiKit.thousand(c.nukes) if c.nukes > 0 else tr("nenhuma")
	_dyn.w_exhaust.text = "%d%%" % int(c.war_exhaustion * 100.0)
	var allies := []
	for o: Country in world.countries:
		if o != c and o.alive and world.diplomacy.allied(c.idx, o.idx):
			allies.append(o.name)
	_dyn.w_allies.text = ", ".join(allies) if not allies.is_empty() else tr("Nenhum")
	_refresh_wars(c)


func _refresh_wars(c: Country) -> void:
	var d := world.diplomacy
	var mine: Array = d.wars.filter(func(w): return c.idx in w.a or c.idx in w.d)
	var sig := str(mine.map(func(w): return w.id)) + str(c.stance_offensive)
	if sig != _wars_sig:
		_wars_sig = sig
		for child in _war_cards.get_children():
			_war_cards.remove_child(child)
			child.queue_free()
		_wars_peace.visible = mine.is_empty()
		_war_cards.visible = not mine.is_empty()
		for w: Dictionary in mine:
			var card: Control = WAR_CARD.instantiate()
			var att: bool = c.idx in w.a
			var enemy: Country = world.countries[w.main_d if att else w.main_a]
			(card.get_node("%enemy") as Label).text = tr("Contra %s") % enemy.name
			var stance: Button = card.get_node("%stance")
			stance.text = tr("Postura: ofensiva") if c.stance_offensive else tr("Postura: defensiva")
			stance.pressed.connect(func():
				if world.in_office:
					c.stance_offensive = not c.stance_offensive
				refresh(true))
			card.get_node("%peace").pressed.connect(func():
				var r := world.do_action("peace", enemy)
				if r.msg != "":
					world.emit_news(r.msg, "diplomacia", enemy)
				refresh(true))
			card.set_meta("war", w.id)
			_war_cards.add_child(card)
	for card in _war_cards.get_children():
		for w: Dictionary in mine:
			if w.id == card.get_meta("war"):
				(card.get_node("%bar") as ProgressBar).value = w.front
				var att: bool = c.idx in w.a
				var front: float = w.front
				(card.get_node("%txt") as Label).text = tr("Frente: %s do território de %s ocupado · baixas: %s / %s mil") % [
					UiKit.num(absf(front), 0) + "%",
					world.countries[w.main_d if front >= 0.0 else w.main_a].name,
					UiKit.num(float(w.loss_a) if att else float(w.loss_d), 0),
					UiKit.num(float(w.loss_d) if att else float(w.loss_a), 0)]


func _refresh_world() -> void:
	_dyn.g_gdp.text = UiKit.money(world.world_gdp())
	_dyn.g_risk.text = "%d%%" % int(world.global_risk * 100.0)
	for i in 5:
		(_dyn["g_comm_%d" % i] as MiniChart).set_data(world.markets.hist.get(i, PackedFloat32Array()))
	(_dyn.g_tension as MiniChart).set_data(world.global_hist.get("tension", PackedFloat32Array()))
	_partners_tick += 1
	if _partners_tick % 8 != 1 and _world_box.get_child_count() > 0:
		return
	for child in _world_box.get_children():
		_world_box.remove_child(child)
		child.queue_free()
	var ranked: Array = world.countries.filter(func(x): return x.alive)
	ranked.sort_custom(func(a, b): return a.y_usd() > b.y_usd())
	var pos := 1
	for o: Country in ranked.slice(0, 12):
		var b: Button = LIST_BUTTON.instantiate()
		b.text = "%d. %s  ·  %s  ·  %s" % [pos, o.name, UiKit.money(o.y_usd()), UiKit.pct(o.growth_yoy())]
		b.pressed.connect(func():
			map.select(o)
			map.focus_on(o)
			show_country(o))
		if o == world.player:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		_world_box.add_child(b)
		pos += 1
