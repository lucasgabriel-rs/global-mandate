class_name InfoPanel
extends VBoxContainer
## Economic information: historical charts comparing countries, market expectations (in the style of the
## Focus Bulletin) and IMF forecasts. The numbers come from Outlook and the `Country.hist` series.

const IMF_ROW := preload("res://scenes/ui/rows/imf_row.tscn")
## `hist` series and format of each %series_pick item, in the same order.
const SERIES := [
	["growth", "pct"], ["infl", "pct"], ["unemp", "pct"], ["rate", "pct"], ["yield", "pct"], ["debt", "pct"],
	["deficit", "pct"], ["ca", "pct"], ["fx", "num2"], ["gdp", "num0"], ["stock", "num0"],
]
const PERIODS := [12, 60, 120, 480]
## Economies the IMF highlights, besides the player.
const IMF_MAJORS := ["USA", "CHN", "DEU", "JPN", "IND", "GBR", "FRA", "BRA", "RUS", "ITA", "CAN", "MEX"]
const FOCUS_KEYS := ["infl", "growth", "rate", "fx"]

var world: GameWorld
var _pickers: Array[OptionButton] = []
var _filled := false

@onready var _tabs: TabContainer = %info_tabs
@onready var _series_pick: OptionButton = %series_pick
@onready var _period_pick: OptionButton = %period_pick
@onready var _chart: CompareChart = %compare_chart
@onready var _chart_note: Label = %chart_note
@onready var _focus_country: Label = %focus_country
@onready var _focus_note: Label = %focus_note
@onready var _imf_rows: VBoxContainer = %imf_rows
@onready var _imf_risks: Label = %imf_risks


func bind(w: GameWorld) -> void:
	world = w
	_pickers = [%country_1, %country_2, %country_3]
	_period_pick.selected = 2
	_tabs.tab_changed.connect(func(_i): refresh())
	_series_pick.item_selected.connect(func(_i): refresh())
	_period_pick.item_selected.connect(func(_i): refresh())
	for p in _pickers:
		p.item_selected.connect(func(_i): refresh())


func refresh() -> void:
	if world == null or world.player == null:
		return
	if not _filled:
		_fill_pickers()
	match _tabs.current_tab:
		0: _refresh_chart()
		1: _refresh_focus(world.player)
		2: _refresh_imf(world.player)


## Countries in GDP order; the first two that are not the player come pre-selected.
func _fill_pickers() -> void:
	_filled = true
	var list: Array = world.countries.filter(func(c: Country): return c.alive and c != world.player)
	list.sort_custom(func(a: Country, b: Country): return a.y_usd() > b.y_usd())
	for p in _pickers:
		p.clear()
		p.add_item(tr("Nenhum"))
		p.set_item_metadata(0, "")
		for c: Country in list:
			p.add_item(tr(c.name))
			p.set_item_metadata(p.item_count - 1, c.iso)
	for i in _pickers.size():
		_pickers[i].selected = i + 1 if i < 2 and list.size() > i else 0


## Selects a country in one of the pickers (also used by the test).
func pick_country(slot: int, iso: String) -> void:
	var p := _pickers[slot]
	for i in p.item_count:
		if p.get_item_metadata(i) == iso:
			p.selected = i
	refresh()


func _refresh_chart() -> void:
	var spec: Array = SERIES[_series_pick.selected]
	var countries: Array[Country] = [world.player]
	for p in _pickers:
		var iso: String = p.get_item_metadata(p.selected) if p.selected >= 0 else ""
		var c: Country = world.by_iso.get(iso)
		if c != null and c not in countries:
			countries.append(c)
	var data: Array[PackedFloat32Array] = []
	var names := PackedStringArray()
	for c in countries:
		data.append(c.hist.get(spec[0], PackedFloat32Array()))
		names.append(tr(c.name))
	_chart.format = spec[1]
	_chart.window = PERIODS[_period_pick.selected]
	_chart.end_year = world.year + float(world.month) / 12.0
	_chart.set_data(data, names)
	var parts := PackedStringArray()
	for i in countries.size():
		var s := data[i]
		if not s.is_empty():
			parts.append("%s: %s" % [names[i], _chart._value_text(s[s.size() - 1])])
	_chart_note.text = tr("Último dado: %s") % "  ·  ".join(parts)


func _fmt(key: String, v: float) -> String:
	return UiKit.num(v, 2) if key == "fx" else UiKit.pct(v, 2 if key == "rate" else 1)


func _refresh_focus(c: Country) -> void:
	_focus_country.text = tr("Boletim de expectativas: %s") % tr(c.name)
	var now := Outlook.market(c, world)
	var before := Outlook.market(c, world, 1)
	for k in Outlook.YEARS:
		(get_node("%%year_%d" % k) as Label).text = str(world.year + k)
	for key: String in FOCUS_KEYS:
		var cur: PackedFloat32Array = now[key]
		var old: PackedFloat32Array = before[key]
		for k in Outlook.YEARS:
			var cell: Label = get_node("%%fc_%s_%d" % [key, k])
			var diff := cur[k] - old[k]
			var tol := 0.005 if key == "fx" else 0.0005
			var arrow := "▲" if diff > tol else ("▼" if diff < -tol else "=")
			cell.text = "%s %s" % [_fmt(key, cur[k]), arrow]
			cell.tooltip_text = tr("Há um mês: %s") % _fmt(key, old[k])
			# For whoever reads the bulletin, rising inflation, interest and dollar is bad news; rising GDP, good.
			var good := diff > 0.0 if key == "growth" else diff < 0.0
			cell.add_theme_color_override("font_color", UiKit.TEXT if arrow == "=" else (UiKit.GREEN if good else UiKit.RED))
	var pi: PackedFloat32Array = now.infl
	_focus_note.text = tr("Meta de inflação: %s. O mercado espera %s em %d.") % [UiKit.pct(c.pi_target), UiKit.pct(pi[0]), world.year]
	if c.peg != 0:
		_focus_note.text += " " + tr("O câmbio é fixo; o mercado não projeta desvalorização.")


func _refresh_imf(c: Country) -> void:
	for n in ["imf_g0", "imf_g1"]:
		(get_node("%" + n) as Label).text = tr("PIB %d") % (world.year + int(n.right(1)))
	for n in ["imf_p0", "imf_p1"]:
		(get_node("%" + n) as Label).text = tr("Infl. %d") % (world.year + int(n.right(1)))
	(get_node("%imf_d2") as Label).text = tr("Dívida %d") % (world.year + 2)
	var list: Array[Country] = [c]
	for iso: String in IMF_MAJORS:
		var other: Country = world.by_iso.get(iso)
		if other != null and other.alive and other not in list:
			list.append(other)
	var w := Outlook.imf_world(world)
	var rows := list.size() + 1
	while _imf_rows.get_child_count() < rows:
		_imf_rows.add_child(IMF_ROW.instantiate())
	_fill_row(_imf_rows.get_child(0), tr("Mundo"), w.growth, w.infl, -1.0, false)
	var mine := {}
	for i in list.size():
		var f := Outlook.imf(list[i], world)
		if i == 0:
			mine = f
		_fill_row(_imf_rows.get_child(i + 1), tr(list[i].name), f.growth, f.infl, f.debt[Outlook.YEARS - 1], i == 0)
	_imf_risks.text = "• " + "\n• ".join(Outlook.imf_risks(c, mine))


func _fill_row(row: Control, label: String, g: PackedFloat32Array, p: PackedFloat32Array, debt: float, mine: bool) -> void:
	var name_label: Label = row.get_node("%imf_name")
	name_label.text = label
	name_label.add_theme_color_override("font_color", UiKit.ACCENT if mine else UiKit.TEXT)
	for k in 2:
		var gl: Label = row.get_node("%%imf_g%d" % k)
		gl.text = UiKit.pct(g[k])
		gl.add_theme_color_override("font_color", UiKit.good_bad(g[k]))
		(row.get_node("%%imf_p%d" % k) as Label).text = UiKit.pct(p[k])
	(row.get_node("%imf_d2") as Label).text = "—" if debt < 0.0 else UiKit.pct(debt, 0)
