class_name PoliticsPanel
extends VBoxContainer
## Aba "Política": o partido do jogador, o plenário, a coalizão e os projetos em votação.

signal party_requested
signal legislation_requested
signal corruption_requested
signal election_requested
signal values_changed
signal party_detail_requested(id: int)

const PARTY_ROW := preload("res://scenes/ui/rows/party_row.tscn")
const BILL_ROW := preload("res://scenes/ui/rows/bill_row.tscn")

var world: GameWorld
var _signature := ""

@onready var _party_label: Label = %party_label
@onready var _hemicycle: Hemicycle = %hemicycle
@onready var _hemicycle_upper: Hemicycle = %hemicycle_upper
@onready var _house_tabs: TabContainer = %house_tabs
@onready var _fund: Label = %fund_label
@onready var _bill_pick: OptionButton = %bill_poll_pick
@onready var _compass: CompassView = %compass
@onready var _opposition: VBoxContainer = %opposition
@onready var _majority: Label = %majority
@onready var _rows: VBoxContainer = %rows
@onready var _bills: VBoxContainer = %bills
@onready var _status: Label = %status


func _ready() -> void:
	%SuasIdeiasTrocarOuFundar.pressed.connect(party_requested.emit)
	%CentroLegislativo.pressed.connect(legislation_requested.emit)
	%CaixaDois.pressed.connect(corruption_requested.emit)
	%UltimaEleicao.pressed.connect(election_requested.emit)
	_connect_opposition(%CriticarOGoverno6, func(): return world.politics.criticize(world))
	_connect_opposition(%FazerCampanha10, func(): return world.politics.campaign(world))
	_connect_opposition(%MocaoDeCensura15, func(): return world.politics.censure(world))
	for b: Dictionary in Politics.BILLS:
		_bill_pick.add_item(b.name)
		_bill_pick.set_item_metadata(_bill_pick.item_count - 1, b.id)
	_bill_pick.item_selected.connect(func(_i): (%poll as PollBox).clear_result())


func _connect_opposition(button: Button, action: Callable) -> void:
	button.pressed.connect(func():
		var r: Dictionary = action.call()
		say(r.msg, not r.ok or not r.get("passed", true))
		_signature = ""
		refresh()
		values_changed.emit())


func bind(w: GameWorld) -> void:
	world = w
	_signature = ""
	_status.text = ""
	(%poll as PollBox).setup(w, func():
		return w.legislation.bill_probe(String(_bill_pick.get_item_metadata(_bill_pick.selected))))


func say(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiKit.RED if is_error else UiKit.GREEN)


func refresh() -> void:
	if world == null or world.player == null:
		return
	var politics := world.politics
	var signature := "%d/%d/%d/%d/%s" % [politics.revision, world.months_elapsed, world.player.idx, int(politics.party_fund(world) * 10.0), str(world.in_office)]
	if signature == _signature:
		return
	_signature = signature
	_rebuild()


func _rebuild() -> void:
	var politics := world.politics
	var iso := world.player.iso
	var data := politics.data_of(iso)
	var mine := politics.player_party(world)
	_party_label.text = "%s (%s)  ·  %s" % [mine.name, mine.short, tr(Politics.FAMILIES[mine.family].label)]
	_fill_houses(data)
	var fund := politics.party_fund(world)
	_fund.text = tr("Fundo de %s: %s  ·  entra %s por mês") % [mine.short, UiKit.millions(fund), UiKit.millions(politics.fund_income(world, mine))]
	(%CriticarOGoverno6 as Button).text = tr("Criticar o governo (%s)") % UiKit.millions(politics.fund_price(world, "criticize"))
	(%FazerCampanha10 as Button).text = tr("Fazer campanha (%s)") % UiKit.millions(politics.fund_price(world, "campaign"))
	(%MocaoDeCensura15 as Button).text = tr("Moção de censura (%s)") % UiKit.millions(politics.fund_price(world, "censure"))
	(%poll as PollBox).refresh()
	(%UltimaEleicao as Button).disabled = not data.has("last_election")
	var dots := []
	for p: Dictionary in data.parties:
		dots.append({"econ": p.econ, "social": p.social, "color": p.color, "big": true})
	var me := politics.player_politician(world)
	if not me.is_empty():
		dots.append({"econ": me.econ, "social": me.social, "color": Color.WHITE})
	_compass.points = dots
	_opposition.visible = not world.in_office
	var seats := politics.government_seats(iso)
	var total: int = data.seats_total
	var majority := seats * 2 > total
	_majority.text = tr("Governo: %d de %d assentos (%s), %s") % [seats, total, UiKit.pct(float(seats) / total, 0), tr("com maioria") if majority else tr("sem maioria")]
	if not world.in_office:
		_majority.text += "\n" + tr("Sua bancada: %d assentos. A oposição soma %d.") % [int(mine.get("seats", 0)), total - seats]
	_majority.add_theme_color_override("font_color", UiKit.GREEN if majority else UiKit.RED)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var ordered: Array = data.parties.duplicate()
	ordered.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	for p: Dictionary in ordered:
		_rows.add_child(_party_row(p, data))
	for child in _bills.get_children():
		_bills.remove_child(child)
		child.queue_free()
	for b: Dictionary in Politics.BILLS:
		_bills.add_child(_bill_row(b))


## Uma aba por casa. Com uma casa só, as abas somem e fica o plenário.
func _fill_houses(data: Dictionary) -> void:
	var houses: Array = world.politics.houses(world)
	var views := [[_hemicycle, %lower_info], [_hemicycle_upper, %upper_info]]
	for i in views.size():
		var has_house: bool = i < houses.size()
		_house_tabs.set_tab_hidden(i, not has_house)
		if not has_house:
			continue
		var house: Dictionary = houses[i]
		_house_tabs.set_tab_title(i, house.name)
		views[i][0].set_parties(house.parties, data.coalition)
		var seats := 0
		for p: Dictionary in house.parties:
			if p.id in data.coalition:
				seats += int(p.seats)
		views[i][1].text = tr("%d assentos  ·  governo com %d") % [int(house.total), seats]
	_house_tabs.tabs_visible = houses.size() > 1
	if houses.size() == 1:
		_house_tabs.current_tab = 0


func _party_row(p: Dictionary, data: Dictionary) -> Control:
	var row: Control = PARTY_ROW.instantiate()
	(row.get_node("%chip") as ColorRect).color = p.color
	var in_gov: bool = p.id in data.coalition
	var name_button: Button = row.get_node("%name_button")
	name_button.text = "%s  ·  %d  ·  %s" % [p.short, int(p.seats), UiKit.pct(p.support, 0)]
	name_button.tooltip_text = tr("%s. %s. Fundo: %s. Clique para ver os políticos e a bússola.") % [p.name, tr(Politics.FAMILIES[p.family].label), UiKit.millions(float(p.get("funds", 0.0)))]
	name_button.name = "party_%d" % int(p.id)
	name_button.pressed.connect(func(): party_detail_requested.emit(p.id))
	name_button.add_theme_color_override("font_color", UiKit.ACCENT if p.id == int(data.player_party) else UiKit.TEXT)
	var tag: Label = row.get_node("%tag")
	var dismiss: Button = row.get_node("%dismiss")
	var invite: Button = row.get_node("%invite")
	var ruling: bool = p.id == int(data.ruling)
	tag.visible = ruling or not world.in_office
	dismiss.visible = not ruling and world.in_office and in_gov
	invite.visible = not ruling and world.in_office and not in_gov
	if ruling:
		tag.text = tr("seu governo") if world.in_office else tr("governo")
	elif not world.in_office:
		tag.text = tr("seu partido") if p.id == int(data.player_party) else (tr("aliado do governo") if in_gov else tr("oposição"))
	dismiss.pressed.connect(_on_dismiss.bind(p.id))
	invite.text = tr("Convidar (%s)") % UiKit.millions(world.politics.fund_price(world, "invite"))
	invite.pressed.connect(_on_invite.bind(p.id))
	return row


func _bill_row(b: Dictionary) -> Control:
	var wait := world.politics.bill_wait(world, b.id)
	var button: Button = BILL_ROW.instantiate()
	button.text = tr(b.name) if wait == 0 else tr("%s (%d meses)") % [tr(b.name), wait]
	button.tooltip_text = b.desc
	button.pressed.connect(_on_vote.bind(b.id))
	button.disabled = not world.in_office or wait > 0 or (b.get("election", false) and world.player.dem < 4.0)
	return button


func _on_invite(id: int) -> void:
	var r := world.politics.invite(world, id)
	say(r.msg, not r.ok)
	_signature = ""
	refresh()


func _on_dismiss(id: int) -> void:
	var r := world.politics.dismiss(world, id)
	say(r.msg, not r.ok)
	_signature = ""
	refresh()


func _on_vote(id: String) -> void:
	var r := world.politics.vote(world, id)
	say(r.msg, not r.ok or not r.get("passed", false))
	_signature = ""
	refresh()
	values_changed.emit()
