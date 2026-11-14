class_name EconomyPanel
extends VBoxContainer
## "Economia" tab: sectors, ports and airports, companies, stock exchange and population, each in a sub-tab.

const SECTOR_ROW := preload("res://scenes/ui/rows/sector_row.tscn")
const FORMULA_WINDOW := preload("res://scenes/ui/modals/formula_window.tscn")

var world: GameWorld
var _sector_rows: Array = []

@onready var _tabs: TabContainer = %sub_tabs
@onready var _rows_box: VBoxContainer = %sector_rows
@onready var infra: InfraPanel = %infra
@onready var companies: CompaniesPanel = %companies
@onready var stock: StockPanel = %stock
@onready var _formula_buttons: GridContainer = %formula_buttons


func bind(w: GameWorld) -> void:
	world = w
	infra.bind(w)
	companies.bind(w)
	stock.bind(w)
	_tabs.tab_changed.connect(func(_i): refresh())
	for b: Button in _formula_buttons.get_children():
		var key := String(b.name)
		b.pressed.connect(func(): show_formula(key))


## Opens the "How it works" window of the indicator `key` with the player country's current numbers.
func show_formula(key: String) -> Control:
	if world == null or world.player == null:
		return null
	var info := FormulaExplain.build(key, world.player, world)
	var dim: Control = FORMULA_WINDOW.instantiate()
	var main := get_tree().current_scene
	var host: Node = main.get("modal_root") if main != null and main.get("modal_root") != null else get_tree().root
	host.add_child(dim)
	(dim.get_node("%title") as Label).text = info.title
	(dim.get_node("%formula") as Label).text = info.formula
	(dim.get_node("%numbers") as Label).text = info.numbers
	(dim.get_node("%body") as Label).text = info.body
	dim.get_node("%Close").pressed.connect(dim.queue_free)
	return dim


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
