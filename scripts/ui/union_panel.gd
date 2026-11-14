class_name UnionPanel
extends VBoxContainer
## "Relações com a União" window: who runs the country the unit belongs to, how close the governor is to it,
## the transfers it sends, who decides each area, and a request for extra money.

const AREA_NAMES := {"health": "Saúde", "education": "Educação", "public_security": "Segurança pública", "infrastructure": "Infraestrutura", "taxes": "Tributos"}
const OWNER_NAMES := {"state": "Unidade", "union": "União", "shared": "Compartilhada"}

var world: GameWorld

@onready var _union: Label = %union_label
@onready var _affinity: Label = %affinity_label
@onready var _transfer: Label = %transfer_label
@onready var _competences: Label = %competences_label
@onready var _feedback: Label = %request_feedback


func _ready() -> void:
	%request_funds.pressed.connect(func():
		if world and world.governor:
			_feedback.text = world.governor.request_funds(world).msg
			refresh())


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.governor == null:
		return
	var gov := world.governor
	var ruling: Dictionary = world.politics.ruling_party(gov.union_iso)
	_union.text = tr("Governo federal: %s  ·  no poder: %s") % [gov.union(world).name, ruling.get("name", "—")]
	_affinity.text = tr("Afinidade com o governo federal: %d%%") % int(gov.affinity(world) * 100.0)
	_transfer.text = tr("Repasses: %s por ano") % UiKit.money(gov.transfers_in)
	var lines := []
	var table := Competences.for_country(gov.union_iso)
	for area: String in Competences.AREAS:
		lines.append("%s: %s" % [tr(AREA_NAMES[area]), tr(OWNER_NAMES[table[area]])])
	_competences.text = "\n".join(lines)
