class_name CompaniesPanel
extends VBoxContainer
## Empresas do país, de capital aberto e fechado, filtráveis por setor e por tipo de capital.

const COMPANY_ROW := preload("res://scenes/ui/rows/company_row.tscn")
const CAPITAL_ALL := 0
const CAPITAL_OPEN := 1
const CAPITAL_CLOSED := 2
const CAPITAL_STATE := 3

var world: GameWorld
var _rows: Array = []

@onready var _sector_filter: OptionButton = %sector_filter
@onready var _capital_filter: OptionButton = %capital_filter
@onready var _summary: Label = %summary
@onready var _rows_box: VBoxContainer = %company_rows
@onready var _empty: Label = %empty


func _ready() -> void:
	_sector_filter.add_item(tr("Todos os setores"))
	_sector_filter.set_item_metadata(0, -1)
	for i in Sectors.COUNT:
		_sector_filter.add_item(tr(Sectors.NAMES[i]))
		_sector_filter.set_item_metadata(_sector_filter.item_count - 1, i)
	for label: String in [tr("Capital aberto e fechado"), tr("Só capital aberto"), tr("Só capital fechado"), tr("Com participação do Estado")]:
		_capital_filter.add_item(label)
	_sector_filter.item_selected.connect(func(_i): refresh())
	_capital_filter.item_selected.connect(func(_i): refresh())


func bind(w: GameWorld) -> void:
	world = w


## Mostra só as empresas de um setor (-1: todos) e de um tipo de capital (CAPITAL_*).
func set_filters(sector: int, capital: int) -> void:
	for i in _sector_filter.item_count:
		if int(_sector_filter.get_item_metadata(i)) == sector:
			_sector_filter.select(i)
	_capital_filter.select(capital)
	refresh()


func refresh() -> void:
	if world == null or world.player == null:
		return
	var c := world.player
	var sector := int(_sector_filter.get_selected_metadata()) if _sector_filter.selected >= 0 else -1
	var capital := maxi(_capital_filter.selected, 0)
	var all: Array = world.corporate.companies_of(c.iso)
	var shown := all.filter(func(co): return _passes(co, sector, capital))
	shown.sort_custom(func(a, b): return float(a.value) > float(b.value))
	var open := 0
	var total_value := 0.0
	var total_rev := 0.0
	for co: Dictionary in shown:
		total_value += float(co.value)
		total_rev += float(co.rev)
		if co.listed:
			open += 1
	_summary.text = tr("%d empresas (%d abertas) · receita %s · valor %s") % [shown.size(), open, UiKit.money(total_rev), UiKit.money(total_value)]
	while _rows.size() < shown.size():
		var row: Control = COMPANY_ROW.instantiate()
		_rows_box.add_child(row)
		_rows.append(row)
	for i in _rows.size():
		var row: Control = _rows[i]
		row.visible = i < shown.size()
		if row.visible:
			_fill(row, shown[i], c)
	_empty.visible = shown.is_empty()


static func _passes(co: Dictionary, sector: int, capital: int) -> bool:
	if sector >= 0 and int(co.sector) != sector:
		return false
	match capital:
		CAPITAL_OPEN: return co.listed
		CAPITAL_CLOSED: return not co.listed
		CAPITAL_STATE: return float(co.state) > 0.0
	return true


func _fill(row: Control, co: Dictionary, c: Country) -> void:
	(row.get_node("%company_name") as Label).text = String(co.name)
	(row.get_node("%company_value") as Label).text = UiKit.money(float(co.value))
	var control := Corporate.control_of(co)
	if float(co.state) > 0.0 and float(co.state) < 1.0:
		control += tr(" (Estado: %s)") % UiKit.pct(float(co.state), 0)
	var exchange: String = world.corporate.market_of(c.iso).get("exchange", "")
	var capital := tr("Capital aberto · %s") % exchange if co.listed else tr("Capital fechado")
	(row.get_node("%company_info") as Label).text = "%s · %s · %s" % [tr(Sectors.NAMES[int(co.sector)]), control, capital]
	(row.get_node("%company_rev") as Label).text = tr("Receita %s") % UiKit.money(float(co.rev))
	var profit: Label = row.get_node("%company_profit")
	profit.text = tr("Lucro %s") % UiKit.money(float(co.profit))
	profit.add_theme_color_override("font_color", UiKit.GREEN if float(co.profit) > 0.0 else UiKit.RED)
	var change: Label = row.get_node("%company_change")
	var extra: Label = row.get_node("%company_extra")
	if co.listed:
		change.visible = true
		change.text = _signed(float(co.ch))
		change.add_theme_color_override("font_color", UiKit.good_bad(float(co.ch)))
		var pe := Corporate.pe_of(co)
		var dy := float(co.div) / maxf(float(co.value), 0.001)
		extra.text = tr("P/L %s · div. %s") % [UiKit.num(pe, 0) if pe > 0.0 else "—", UiKit.pct(dy)]
	else:
		change.visible = false
		extra.text = tr("valor estimado")


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "") + UiKit.pct(v)
