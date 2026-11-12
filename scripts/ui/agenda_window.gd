class_name AgendaWindow
extends ColorRect
## Contact book: leaders of all parliament parties and of all countries, with search.
## "Conversar" opens the conversation with the chosen leader, without waiting for them to show up.

const ROW := preload("res://scenes/ui/rows/agenda_row.tscn")
const HEADING := preload("res://scenes/ui/chat/chat_heading.tscn")

var main: Node
var world: GameWorld
var chat: ChatWindow

@onready var _list: VBoxContainer = %list
@onready var _search: LineEdit = %search


func setup(owner_main: Node, from_chat: ChatWindow = null) -> void:
	main = owner_main
	world = Game.world
	chat = from_chat
	%close.pressed.connect(func(): main._close_modal(self))
	_search.text_changed.connect(func(_t: String): _fill())
	_fill()


func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var parties: Array = PartyTalk.contacts(world).filter(func(p): return _matches(query, [PartyTalk.leader_of(p).get("name", ""), p.name, p.short]))
	if not parties.is_empty():
		_heading(tr("LÍDERES PARTIDÁRIOS"))
	for party: Dictionary in parties:
		var key := ChatLog.party_key(int(party.id))
		_row(key, String(PartyTalk.leader_of(party).get("name", party.name)), "%s  ·  %s" % [party.name, PartyTalk.tags(world, party).get_slice("  ·  ", 2)], party.color, "party_%d" % int(party.id), true)
	var countries: Array = world.countries.filter(func(c: Country): return c.alive and c != world.player and _matches(query, [Dialogue.leader_of(world, c).get("name", ""), c.name, c.iso]))
	countries.sort_custom(func(a: Country, b: Country): return a.y_usd() > b.y_usd())
	if not countries.is_empty():
		_heading(tr("LÍDERES DE PAÍSES"))
	for c: Country in countries:
		var leader := Dialogue.leader_of(world, c)
		_row(ChatLog.country_key(c.iso), String(leader.get("name", tr("o líder"))), "%s  ·  %s" % [c.name, _status(c)], Color("f2b33d"), "country_" + c.iso, _can_talk(c))


func _matches(query: String, fields: Array) -> bool:
	if query == "":
		return true
	for f: Variant in fields:
		if String(f).to_lower().contains(query):
			return true
	return false


func _can_talk(c: Country) -> bool:
	return world.in_office


func _status(c: Country) -> String:
	if not world.in_office:
		return tr("Na oposição você não fala pelo país")
	if not Proposals.pending(world, c).is_empty():
		return tr("Proposta em aberto")
	if Dialogue.turns_left(world, c) > 0:
		return tr("Conversa em curso")
	if Dialogue.wait_months(world, c) > 0:
		return tr("Nova conversa no mês que vem")
	return tr("Disponível")


func _heading(text: String) -> void:
	var h: Control = HEADING.instantiate()
	h.get_node("%text").text = text
	_list.add_child(h)


func _row(key: String, label: String, info: String, color: Color, node_name: String, enabled: bool) -> void:
	var row: Control = ROW.instantiate()
	row.name = "agenda_" + node_name
	(row.get_node("%name") as Label).text = label
	(row.get_node("%info") as Label).text = info
	(row.get_node("%chip") as ColorRect).color = color
	var talk: Button = row.get_node("%talk")
	# Whoever is not in government can still read the history, just cannot start a new conversation with a country.
	talk.text = tr("Conversar") if enabled else tr("Histórico")
	talk.pressed.connect(func():
		main.call_contact(key, chat)
		main._close_modal(self))
	_list.add_child(row)
