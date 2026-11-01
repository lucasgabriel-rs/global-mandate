class_name CabinetPanel
extends VBoxContainer
## Aba "Ministros": cada pasta com o titular, a competência e a bússola dele.

signal pick_requested(post: String)

const MINISTER_ROW := preload("res://scenes/ui/rows/minister_row.tscn")

var world: GameWorld
var _signature := ""

@onready var _rows: VBoxContainer = %rows
@onready var _status: Label = %status
@onready var _opposition_note: Label = %opposition_note


func bind(w: GameWorld) -> void:
	world = w
	_signature = ""
	_status.text = ""


func say(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiKit.RED if is_error else UiKit.GREEN)


func refresh() -> void:
	if world == null or world.player == null:
		return
	var signature := "%d/%s" % [world.politics.revision, str(world.in_office)]
	if signature == _signature:
		return
	_signature = signature
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_opposition_note.visible = not world.in_office
	_rows.visible = world.in_office
	if not world.in_office:
		return
	for portfolio: Dictionary in world.politics.portfolios(world):
		_rows.add_child(_row(portfolio))


func _row(portfolio: Dictionary) -> Control:
	var box: Control = MINISTER_ROW.instantiate()
	var title: Label = box.get_node("%title")
	title.text = portfolio.label
	title.tooltip_text = portfolio.desc
	var who := world.politics.minister(world, portfolio.id)
	var vacant_post := who.is_empty()
	var change: Button = box.get_node("%change")
	change.text = "Escolher" if vacant_post else "Trocar"
	change.name = "pick_" + String(portfolio.id)
	change.pressed.connect(pick_requested.emit.bind(portfolio.id))
	var fire: Button = box.get_node("%fire")
	fire.visible = not vacant_post
	fire.name = "fire_" + String(portfolio.id)
	fire.pressed.connect(func():
		world.politics.dismiss_minister(world, portfolio.id)
		refresh())
	var vacant: Label = box.get_node("%vacant")
	vacant.visible = vacant_post
	vacant.text = "Pasta vaga. %s" % portfolio.desc
	var person: Control = box.get_node("%person")
	person.visible = not vacant_post
	if not vacant_post:
		(box.get_node("%face") as CharacterView).character = Character.for_politician(who)
		var party: Dictionary = world.politics.party_of(world.player.iso, world.politics.data_of(world.player.iso).cabinet[portfolio.id].party)
		(box.get_node("%who") as Label).text = "%s, %d anos  ·  %s\nCompetência: %d%%%s" % [who.name, People.age_of(who, world), party.short, int(float(who.competence) * 100.0), "" if not who.has("illness") else "  ·  doente"]
		(box.get_node("%compass") as CompassView).points = [{"econ": who.econ, "social": who.social, "color": Color.WHITE, "big": true}]
	return box
