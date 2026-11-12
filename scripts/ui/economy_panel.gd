class_name EconomyPanel
extends VBoxContainer
## "Economia" tab: sectors, ports and airports, companies, stock exchange and population, each in a sub-tab.

const SECTOR_ROW := preload("res://scenes/ui/rows/sector_row.tscn")

var world: GameWorld
var _sector_rows: Array = []

@onready var _tabs: TabContainer = %sub_tabs
@onready var _rows_box: VBoxContainer = %sector_rows
@onready var infra: InfraPanel = %infra
@onready var companies: CompaniesPanel = %companies
@onready var stock: StockPanel = %stock


func bind(w: GameWorld) -> void:
	world = w
	infra.bind(w)
	companies.bind(w)
	stock.bind(w)
	_tabs.tab_changed.connect(func(_i): refresh())


## In opposition there is no public work to run: the ports and airports sub-tab disappears.
func set_office(office: bool) -> void:
	_tabs.set_tab_hidden(1, not office)
	if not office and _tabs.current_tab == 1:
		_tabs.current_tab = 0


func refresh() -> void:
	if world == null or world.player == null:
		return
	match _tabs.current_tab:
		0: _refresh_sectors(world.player)
		1: infra.refresh()
		2: companies.refresh()
		3: stock.refresh()
		4: _refresh_population(world.player)


func _refresh_sectors(c: Country) -> void:
	if c.sector_share.size() != Sectors.COUNT:
		return
	if _sector_rows.is_empty():
		for i in Sectors.COUNT:
			var row: Control = SECTOR_ROW.instantiate()
			_rows_box.add_child(row)
			(row.get_node("%sector_name") as Label).text = tr(Sectors.NAMES[i])
			_sector_rows.append(row)
	var biggest := 0.0
	for i in Sectors.COUNT:
		biggest = maxf(biggest, c.sector_share[i])
	# From largest to smallest, so the country's structure jumps out.
	var order := range(Sectors.COUNT)
	order.sort_custom(func(a, b): return c.sector_share[a] > c.sector_share[b])
	for pos in order.size():
		var i: int = order[pos]
		var row: Control = _sector_rows[i]
		_rows_box.move_child(row, pos)
		(row.get_node("%sector_value") as Label).text = "%s  ·  %s" % [UiKit.money(Sectors.output_usd(c, i)), UiKit.pct(c.sector_share[i])]
		var g := Sectors.growth_of(c, i)
		var growth: Label = row.get_node("%sector_growth")
		growth.text = UiKit.pct(g)
		growth.add_theme_color_override("font_color", UiKit.good_bad(g))
		(row.get_node("%sector_bar") as ProgressBar).value = c.sector_share[i] / maxf(biggest, 0.001)


func _refresh_population(c: Country) -> void:
	Demography.ensure(c)
	(%pop_total as Label).text = tr("População: %s milhões") % UiKit.num(c.pop)
	for band: String in ["young", "adult", "old"]:
		var share: float = c.get(band)
		(get_node("%" + band + "_bar") as ProgressBar).value = share
		(get_node("%" + band + "_value") as Label).text = UiKit.pct(share)
	(%pop_rates as Label).text = tr("Natalidade %s · mortalidade %s · migração %s ao ano") % [
		UiKit.pct(c.birth), UiKit.pct(c.death), UiKit.pct(c.migration, 2)]
	(%pop_pension as Label).text = tr("Aposentadorias além da base: %s do PIB") % UiKit.pct(Demography.pension_extra(c))
