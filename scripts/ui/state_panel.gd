class_name StatePanel
extends VBoxContainer
## "Painel da unidade" window: the governed unit's standing, economy and accounts. It only reads what StateGov computes.

var world: GameWorld

@onready var _unit: Label = %unit_label
@onready var _party: Label = %party_label
@onready var _approval: Label = %approval_label
@onready var _election: Label = %election_label
@onready var _gdp: Label = %gdp_label
@onready var _pop: Label = %pop_label
@onready var _revenue: Label = %revenue_label
@onready var _spending: Label = %spending_label
@onready var _debt: Label = %debt_label


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.governor == null:
		return
	var gov := world.governor
	var office := world.office_title() if gov.in_office else tr("Presidente do diretório")
	_unit.text = "%s · %s · %s" % [gov.unit(world).get("name", "—"), office, gov.union(world).name]
	_party.text = tr("Partido: %s") % world.politics.party_of(gov.union_iso, gov.party_id).get("name", "—")
	_approval.text = tr("Aprovação do governo da unidade: %d%%") % int(gov.approval * 100.0)
	_approval.add_theme_color_override("font_color", UiKit.RED if gov.approval < 0.4 else (UiKit.GREEN if gov.approval > 0.55 else UiKit.TEXT))
	if gov.next_election < 0.0:
		_election.text = tr("Sem eleições neste regime")
	else:
		_election.text = tr("Próxima eleição em %s anos") % UiKit.num(maxf(gov.next_election - world.year_float(), 0.0), 1)
	var gdp := gov.gdp(world)
	_gdp.text = tr("PIB: %s") % UiKit.money(gdp)
	_pop.text = tr("População: %s mi") % UiKit.num(gov.pop(world), 1)
	_revenue.text = tr("Receita: %s por ano (repasses: %s)") % [UiKit.money(gov.revenue(world)), UiKit.money(gov.transfers_in)]
	_spending.text = tr("Despesa: %s por ano") % UiKit.money(gov.spending(world))
	_debt.text = tr("Dívida: %s (%s do PIB)") % [UiKit.money(gov.debt), UiKit.pct(gov.debt / maxf(gdp, 0.001), 0)]
