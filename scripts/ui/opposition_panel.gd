class_name OppositionPanel
extends VBoxContainer
## "Fiscalização do governo" window, opposition only: who governs, the player's caucus, how much is missing
## for a majority, the election and the performance of the government they fight. It only reads what the political system already computes.

signal politics_requested
signal legislation_requested

var world: GameWorld

@onready var _ruling: Label = %ruling_label
@onready var _mine: Label = %mine_label
@onready var _gap: Label = %gap_label
@onready var _election: Label = %election_label
@onready var _values := {
	"approval": %v_approval, "growth": %v_growth, "infl": %v_infl, "unemp": %v_unemp,
	"debt": %v_debt, "balance": %v_balance, "rating": %v_rating,
}


func _ready() -> void:
	%open_politics.pressed.connect(politics_requested.emit)
	%open_legislation.pressed.connect(legislation_requested.emit)


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.player == null:
		return
	var c := world.player
	var politics := world.politics
	var data := politics.data_of(c.iso)
	var ruling: Dictionary = politics.ruling_party(c.iso)
	var mine := politics.player_party(world)
	var total: int = data.get("seats_total", 0)
	var gov_seats := politics.government_seats(c.iso)
	var opp_seats := total - gov_seats
	var majority := gov_seats * 2 > total
	_ruling.text = tr("Governo: %s  ·  %d de %d assentos (%s), %s") % [ruling.get("short", "—"), gov_seats, total, UiKit.pct(float(gov_seats) / maxf(total, 1.0), 0), tr("com maioria") if majority else tr("sem maioria")]
	_ruling.add_theme_color_override("font_color", UiKit.RED if majority else UiKit.GREEN)
	_mine.text = tr("Sua bancada: %s  ·  %d assentos  ·  %s nas pesquisas") % [mine.get("short", "—"), int(mine.get("seats", 0)), UiKit.pct(float(mine.get("support", 0.0)), 0)]
	if opp_seats * 2 > total:
		_gap.text = tr("A oposição soma %d de %d assentos: já dá para tentar uma moção de censura.") % [opp_seats, total]
		_gap.add_theme_color_override("font_color", UiKit.GREEN)
	else:
		_gap.text = tr("A oposição soma %d de %d assentos: faltam %d para a maioria que derruba o governo.") % [opp_seats, total, total / 2 + 1 - opp_seats]
		_gap.add_theme_color_override("font_color", UiKit.TEXT)
	if c.dem >= 4.0:
		var left := c.next_election - world.year_float()
		_election.text = tr("Próxima eleição em %s anos") % UiKit.num(maxf(left, 0.0), 1)
	else:
		_election.text = tr("Sem eleições neste regime")
	var v := _values
	v.approval.text = "%d%%" % int(c.approval * 100.0)
	v.approval.add_theme_color_override("font_color", UiKit.GREEN if c.approval < 0.4 else (UiKit.RED if c.approval > 0.55 else UiKit.TEXT))
	var g := c.growth_yoy()
	v.growth.text = UiKit.pct(g)
	v.growth.add_theme_color_override("font_color", UiKit.good_bad(g))
	v.infl.text = UiKit.pct(c.pi_yoy)
	v.infl.add_theme_color_override("font_color", UiKit.RED if c.pi_yoy > c.pi_target + 0.03 else UiKit.TEXT)
	v.unemp.text = UiKit.pct(c.unemp)
	v.debt.text = UiKit.pct(c.debt_ratio, 0)
	v.debt.add_theme_color_override("font_color", UiKit.RED if c.debt_ratio > c.debt_tol else UiKit.TEXT)
	var balance := -c.deficit / maxf(c.y_nominal(), 0.001)
	v.balance.text = "%s%.1f%%" % ["+" if balance > 0.0 else "", balance * 100.0]
	v.balance.add_theme_color_override("font_color", UiKit.RED if balance < -0.05 else (UiKit.GREEN if balance >= -0.01 else UiKit.TEXT))
	v.rating.text = c.rating
