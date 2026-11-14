class_name DirectoryPanel
extends VBoxContainer
## "Diretório do partido" window, for a governor who lost the post: the unit's incumbent, the election, the national
## party line and the share of the party fund the directory may spend on criticism and campaigns.

var world: GameWorld

@onready var _incumbent: Label = %incumbent_label
@onready var _election: Label = %election_label
@onready var _line: Label = %line_label
@onready var _fund: Label = %fund_label
@onready var _feedback: Label = %directory_feedback


func _ready() -> void:
	%criticize.pressed.connect(func(): _act(world.politics.criticize(world)))
	%campaign.pressed.connect(func(): _act(world.politics.campaign(world)))


func _act(result: Dictionary) -> void:
	_feedback.text = String(result.msg)
	refresh()


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.governor == null:
		return
	var gov := world.governor
	var rival: Dictionary = world.politics.party_of(gov.union_iso, gov.incumbent_party)
	_incumbent.text = tr("Governa a unidade: %s  ·  aprovação %d%%") % [rival.get("name", "—"), int(gov.approval * 100.0)]
	if gov.next_election < 0.0:
		_election.text = tr("Sem eleições neste regime")
	else:
		_election.text = tr("Próxima eleição em %s anos") % UiKit.num(maxf(gov.next_election - world.year_float(), 0.0), 1)
	_line.text = tr("A direção nacional veta sua candidatura.") if world.politics.national_veto(world) else tr("Você está alinhado com a direção nacional do partido.")
	_fund.text = tr("Verba do diretório: %s (do fundo do partido: %s)") % [UiKit.millions(world.politics.directory_fund(world)), UiKit.millions(world.politics.party_fund(world))]
