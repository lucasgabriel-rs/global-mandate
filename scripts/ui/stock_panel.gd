class_name StockPanel
extends VBoxContainer
## A bolsa de valores do país: índice, valor de mercado, maiores altas e baixas do mês e movimentos recentes.

const STOCK_ROW := preload("res://scenes/ui/rows/stock_row.tscn")
const MOVERS := 5
const EVENTS := 8
const EVENT_LABELS := {
	"ipo": "IPO", "fechamento": "Fechou o capital", "falencia": "Falência", "socorro": "Socorro do governo",
	"privatizacao": "Privatização", "estatizacao": "Estatização", "nova": "Nova empresa",
}

var world: GameWorld
var _pools := {}

@onready var _exchange: Label = %exchange
@onready var _index_value: Label = %index_value
@onready var _index_month: Label = %index_month
@onready var _index_year: Label = %index_year
@onready var _index_chart: MiniChart = %index_chart
@onready var _cap_chart: MiniChart = %cap_chart
@onready var _total_cap: Label = %total_cap
@onready var _cap_gdp: Label = %cap_gdp
@onready var _pe: Label = %pe
@onready var _dy: Label = %dy
@onready var _listed: Label = %listed
@onready var _state_cap: Label = %state_cap
@onready var _gainers: VBoxContainer = %gainers
@onready var _losers: VBoxContainer = %losers
@onready var _events: VBoxContainer = %events
@onready var _events_empty: Label = %events_empty
@onready var _no_exchange: Label = %no_exchange


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.player == null:
		return
	var c := world.player
	var m: Dictionary = world.corporate.market_of(c.iso)
	var has_exchange := String(m.get("exchange", "")) != ""
	_exchange.text = String(m.get("exchange", "")) if has_exchange else "Sem bolsa de valores"
	_no_exchange.visible = not has_exchange
	var hist: PackedFloat32Array = c.hist.get("stock", PackedFloat32Array())
	_index_value.text = UiKit.num(c.stock, 0)
	_set_change(_index_month, _change(hist, 1), "no mês")
	_set_change(_index_year, _change(hist, 12), "em 12 meses")
	_index_chart.set_data(hist)
	_cap_chart.set_data(c.hist.get("mcap", PackedFloat32Array()))
	var cap := float(m.get("cap", 0.0))
	_total_cap.text = "Valor de mercado: %s" % UiKit.money(cap)
	_cap_gdp.text = "%s do PIB" % UiKit.pct(cap / maxf(c.y_usd(), 0.001), 0)
	var pe := float(m.get("pe", 0.0))
	_pe.text = "P/L médio: %s" % (UiKit.num(pe, 1) if pe > 0.0 else "—")
	_dy.text = "Dividendos: %s ao ano" % UiKit.pct(float(m.get("dy", 0.0)))
	var listed: Array = world.corporate.companies_of(c.iso).filter(func(co): return co.listed)
	var state_value := 0.0
	for co: Dictionary in world.corporate.companies_of(c.iso):
		state_value += float(co.value) * float(co.state)
	_listed.text = "%d grandes listadas" % listed.size()
	_state_cap.text = "Fatia do Estado: %s" % UiKit.money(state_value)
	listed.sort_custom(func(a, b): return float(a.ch) > float(b.ch))
	var up := listed.filter(func(co): return float(co.ch) > 0.0).slice(0, MOVERS)
	var down := listed.filter(func(co): return float(co.ch) < 0.0)
	down.reverse()
	down = down.slice(0, MOVERS)
	_fill_movers(_gainers, up)
	_fill_movers(_losers, down)
	var events: Array = m.get("events", []).slice(0, EVENTS)
	var rows := _pool(_events, events.size())
	for i in events.size():
		var e: Dictionary = events[i]
		_set_row(rows[i], String(e.name), "%s · %s" % [EVENT_LABELS.get(e.kind, e.kind), e.date], UiKit.money(float(e.value)), UiKit.TEXT)
	_events_empty.visible = events.is_empty()


func _fill_movers(box: VBoxContainer, list: Array) -> void:
	var rows := _pool(box, maxi(list.size(), 1))
	if list.is_empty():
		_set_row(rows[0], "Nenhuma", "", "", UiKit.DIM)
		return
	for i in list.size():
		var co: Dictionary = list[i]
		var ch := float(co.ch)
		_set_row(rows[i], String(co.name), UiKit.money(float(co.value)), ("+" if ch >= 0.0 else "") + UiKit.pct(ch), UiKit.good_bad(ch))


## Linhas reaproveitadas: cria as que faltam e esconde as que sobram.
func _pool(box: VBoxContainer, count: int) -> Array:
	var rows: Array = _pools.get_or_add(box, [])
	while rows.size() < count:
		var row: Control = STOCK_ROW.instantiate()
		box.add_child(row)
		rows.append(row)
	for i in rows.size():
		(rows[i] as Control).visible = i < count
	return rows


static func _set_row(row: Control, name_: String, detail: String, value: String, color: Color) -> void:
	(row.get_node("%stock_name") as Label).text = name_
	(row.get_node("%stock_detail") as Label).text = detail
	var v: Label = row.get_node("%stock_value")
	v.text = value
	v.add_theme_color_override("font_color", color)


static func _change(s: PackedFloat32Array, months: int) -> float:
	if s.size() <= months:
		return 0.0
	return s[s.size() - 1] / maxf(s[s.size() - 1 - months], 0.0001) - 1.0


static func _set_change(label: Label, v: float, suffix: String) -> void:
	label.text = "%s%s %s" % ["+" if v >= 0.0 else "", UiKit.pct(v), suffix]
	label.add_theme_color_override("font_color", UiKit.good_bad(v))
