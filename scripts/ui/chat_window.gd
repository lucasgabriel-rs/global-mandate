class_name ChatWindow
extends ColorRect
## Janela de conversas estilo mensageiro: contatos à esquerda (líderes partidários e de outros países),
## o histórico em balões no meio e as falas disponíveis como respostas rápidas embaixo.

const BUBBLE := preload("res://scenes/ui/chat/chat_bubble.tscn")
const CONTACT := preload("res://scenes/ui/chat/chat_contact.tscn")
const HEADING := preload("res://scenes/ui/chat/chat_heading.tscn")
const OPTION := preload("res://scenes/ui/rows/talk_option.tscn")

var main: Node
var world: GameWorld
var current := ""
var _buttons := {}

@onready var _contacts: VBoxContainer = %contacts
@onready var _thread: VBoxContainer = %thread
@onready var _choices: VBoxContainer = %choices
@onready var _scroll: ScrollContainer = %scroll
@onready var _remaining: Label = %remaining


func setup(owner_main: Node, key: String) -> void:
	main = owner_main
	world = main.world
	%say_end.pressed.connect(func(): main._close_modal(self))
	%info_toggle.toggled.connect(func(on: bool): (%info_panel as Control).visible = on)
	select(key)


# --- Contatos --------------------------------------------------------------------

func _fill_contacts() -> void:
	for child in _contacts.get_children():
		_contacts.remove_child(child)
		child.queue_free()
	_buttons.clear()
	var heading: Control = HEADING.instantiate()
	heading.get_node("%text").text = tr("LÍDERES PARTIDÁRIOS")
	_contacts.add_child(heading)
	for party: Dictionary in PartyTalk.contacts(world):
		var key := ChatLog.party_key(int(party.id))
		_add_contact(key, String(PartyTalk.leader_of(party).get("name", party.name)), _preview(party.short, ChatLog.last_text(world, key)), party.color, "contact_party_%d" % int(party.id))
	var countries: Array = []
	for key: String in world.chats:
		if key.begins_with("pais:") or key == current:
			countries.append(key)
	if current.begins_with("pais:") and not current in countries:
		countries.append(current)
	if not countries.is_empty():
		var h2: Control = HEADING.instantiate()
		h2.get_node("%text").text = tr("PAÍSES")
		_contacts.add_child(h2)
	for key: String in countries:
		var c: Country = world.by_iso.get(key.trim_prefix("pais:"))
		if c == null:
			continue
		_add_contact(key, String(Dialogue.leader_of(world, c).get("name", c.name)), _preview(c.name, ChatLog.last_text(world, key)), Color("f2b33d"), "contact_" + c.iso)


func _preview(label: String, last: String) -> String:
	return "%s  ·  %s" % [label, last] if last != "" else label


func _add_contact(key: String, label: String, preview: String, color: Color, node_name: String) -> void:
	var b: Button = CONTACT.instantiate()
	b.name = node_name
	(b.get_node("%name") as Label).text = label
	(b.get_node("%preview") as Label).text = preview
	(b.get_node("%chip") as ColorRect).color = color
	b.button_pressed = key == current
	b.pressed.connect(select.bind(key))
	_buttons[key] = b
	_contacts.add_child(b)


# --- Conversa --------------------------------------------------------------------

func select(key: String) -> void:
	current = key
	if key.begins_with("partido:"):
		var party := PartyTalk.party_by_id(world, int(key.trim_prefix("partido:")))
		if party.is_empty():
			return
		if ChatLog.thread(world, key).is_empty():
			ChatLog.add(world, key, false, PartyTalk.greeting(world, party))
		_header_party(party)
	else:
		var target: Country = world.by_iso.get(key.trim_prefix("pais:"))
		if target == null:
			return
		_header_country(target)
	_fill_contacts()
	_fill_thread()
	_fill_choices()


func _header_country(target: Country) -> void:
	var theirs := Dialogue.leader_of(world, target)
	var mine: Dictionary = world.politics.player_party(world)
	(%contact_name as Label).text = String(theirs.get("name", tr("o líder")))
	(%contact_info as Label).text = tr("%s  ·  %s  ·  %d anos, %s") % [target.name, world.politics.ruling_party(target.iso).get("name", ""), People.age_of(theirs, world), Dialogue.temper(theirs)]
	(%face as Countryball).show_person(Character.for_politician(theirs), target.iso)
	(%talk_compass as CompassView).points = [{"econ": theirs.get("econ", 0.0), "social": theirs.get("social", 0.0), "color": Color("f2b33d"), "big": true}, {"econ": mine.get("econ", 0.0), "social": mine.get("social", 0.0), "color": Color.WHITE, "big": true}]
	(%legend as Label).text = tr("Dourado: %s. Branco: seu partido.") % theirs.get("name", tr("líder"))


func _header_party(party: Dictionary) -> void:
	var theirs := PartyTalk.leader_of(party)
	var mine: Dictionary = world.politics.player_party(world)
	(%contact_name as Label).text = String(theirs.get("name", party.name))
	(%contact_info as Label).text = tr("Líder  ·  %s") % PartyTalk.tags(world, party)
	(%face as Countryball).show_person(Character.for_politician(theirs), world.legislation.iso)
	(%talk_compass as CompassView).points = [{"econ": party.econ, "social": party.social, "color": party.color, "big": true}, {"econ": mine.get("econ", 0.0), "social": mine.get("social", 0.0), "color": Color.WHITE, "big": true}]
	(%legend as Label).text = tr("Cor do partido: %s. Branco: seu partido.") % party.short


func _fill_thread() -> void:
	for child in _thread.get_children():
		_thread.remove_child(child)
		child.queue_free()
	for message: Dictionary in ChatLog.thread(world, current):
		var bubble: ChatBubble = BUBBLE.instantiate()
		_thread.add_child(bubble)
		bubble.setup(message)
	_to_bottom.call_deferred()


func _to_bottom() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _fill_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	if current.begins_with("partido:"):
		_fill_party_choices()
	else:
		_fill_country_choices()


func _add_option(id: String, label: String, hint: String, action: Callable) -> void:
	var b: Button = OPTION.instantiate()
	b.name = "say_" + id.replace(":", "_")
	b.text = label
	b.tooltip_text = hint
	b.pressed.connect(action)
	_choices.add_child(b)


func _fill_country_choices() -> void:
	var target: Country = world.by_iso[current.trim_prefix("pais:")]
	var turns := Dialogue.turns_left(world, target)
	var going: bool = turns > 0 and target.alive and main.prompts.is_empty()
	if going:
		_remaining.text = tr("Falas restantes: %d") % turns
		for option: Dictionary in Dialogue.options(world, target):
			_add_option(String(option.id), option.label, option.hint, func():
				Dialogue.say(world, target, option.id)
				main.hud.refresh(true)
				select(current))
		return
	_remaining.text = tr("A conversa terminou.")
	if world.in_office and target.alive and Dialogue.wait_months(world, target) == 0 and main.prompts.is_empty():
		_add_option("start", tr("Chamar para uma nova conversa"), tr("Abre uma nova rodada de falas com este líder."), func():
			Dialogue.start(world, target)
			select(current))


func _fill_party_choices() -> void:
	var party := PartyTalk.party_by_id(world, int(current.trim_prefix("partido:")))
	var laws := PartyTalk.open_laws(world)
	if laws.is_empty():
		_remaining.text = tr("Nenhuma lei em votação no momento.")
		return
	_remaining.text = tr("Leis em votação: %d") % laws.size()
	for option: Dictionary in PartyTalk.options(world, party):
		_add_option(String(option.id), option.label, option.hint, func():
			PartyTalk.say(world, party, option.id)
			main.hud.refresh(true)
			select(current))
