class_name NegotiationScreen
extends ColorRect
## Negotiates with each caucus the vote on a proposal in procedure, for or against.

const ROW := preload("res://scenes/ui/legislation/negotiation_row.tscn")

var main: Node
var world: GameWorld
var leg: Legislation
var norm := {}

@onready var _rows: VBoxContainer = %rows
@onready var _feedback: Label = %feedback
@onready var _generous: CheckBox = %generous


func setup(owner_main: Node, target: Dictionary) -> void:
	main = owner_main
	world = main.world
	leg = world.legislation
	norm = target
	(%title as Label).text = tr("Negociar votos  ·  %s: %s") % [leg.norm_label(norm), tr(norm.title)]
	%chat.pressed.connect(func(): main.open_chat(PartyTalk.first_key(world)))
	%close.pressed.connect(func(): main.reopen_legislation(0))
	_generous.toggled.connect(func(_on): _fill())
	(%poll as PollBox).setup(world, func(): return norm)
	_fill()


func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var politics := world.politics
	var data: Dictionary = politics.data_of(leg.iso)
	(%fund as Label).text = tr("Fundo de %s: %s") % [politics.player_party(world).get("short", tr("seu partido")), UiKit.millions(politics.party_fund(world))]
	var deals: Dictionary = norm.get("deals", {})
	var asked: Dictionary = norm.get("asked", {})
	var open := leg.can_negotiate(norm)
	var ordered: Array = data.parties.filter(func(p): return int(p.seats) > 0)
	ordered.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	for party: Dictionary in ordered:
		var row: Control = ROW.instantiate()
		var id: int = party.id
		var mine: bool = id == int(data.player_party)
		(row.get_node("%chip") as ColorRect).color = party.color
		(row.get_node("%party") as Label).text = tr("%s%s  ·  %d assentos") % [party.short, tr(" (seu partido)") if mine else "", int(party.seats)]
		var state: Label = row.get_node("%state")
		if deals.has(str(id)):
			state.text = tr("Acordo: vota a favor") if deals[str(id)] else tr("Acordo: vota contra")
			state.add_theme_color_override("font_color", UiKit.GREEN)
		elif asked.has(str(id)):
			state.text = tr("Recusou negociar")
			state.add_theme_color_override("font_color", UiKit.RED)
		else:
			state.text = tr("Sem acordo")
		var yes: Button = row.get_node("%ask_yes")
		var no: Button = row.get_node("%ask_no")
		var post: Button = row.get_node("%offer_post")
		var price := leg.deal_price(world, party, _generous.button_pressed)
		yes.name = "yes_%d" % id
		no.name = "no_%d" % id
		yes.text = tr("Votar a favor") if mine else tr("A favor (%s)") % UiKit.millions(price)
		no.text = tr("Votar contra") if mine else tr("Contra (%s)") % UiKit.millions(price)
		var closed: bool = not open or (not mine and (asked.has(str(id)) or deals.has(str(id))))
		var poor: bool = not mine and politics.party_fund(world) < price
		yes.disabled = closed or poor
		no.disabled = closed or poor
		yes.pressed.connect(_ask.bind(id, true))
		no.pressed.connect(_ask.bind(id, false))
		post.visible = world.in_office and not mine and not id in data.coalition
		post.disabled = closed
		post.pressed.connect(_post.bind(id))
		_rows.add_child(row)
	(%poll as PollBox).refresh()


func _ask(id: int, want_yes: bool) -> void:
	_show(leg.negotiate(world, norm, id, want_yes, _generous.button_pressed))


func _post(id: int) -> void:
	_show(leg.offer_post(world, norm, id))


func _show(r: Dictionary) -> void:
	_feedback.text = r.msg
	_feedback.add_theme_color_override("font_color", UiKit.GREEN if r.get("accepted", false) else UiKit.RED)
	_fill()
