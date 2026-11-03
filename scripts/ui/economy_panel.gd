class_name EconomyPanel
extends VBoxContainer
## Aba "Economia": setores, portos e aeroportos, empresas e bolsa, cada um em uma subaba.

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


func refresh() -> void:
	if world == null or world.player == null:
		return
	match _tabs.current_tab:
		0: _refresh_sectors(world.player)
		1: infra.refresh()
		2: companies.refresh()
		3: stock.refresh()


func _refresh_sectors(c: Country) -> void:
	if c.sector_share.size() != Sectors.COUNT:
		return
	if _sector_rows.is_empty():
		for i in Sectors.COUNT:
			var row: Control = SECTOR_ROW.instantiate()
			_rows_box.add_child(row)
			(row.get_node("%sector_name") as Label).text = Sectors.NAMES[i]
			_sector_rows.append(row)
	var biggest := 0.0
	for i in Sectors.COUNT:
		biggest = maxf(biggest, c.sector_share[i])
	# Do maior para o menor, para a estrutura do país saltar aos olhos.
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
