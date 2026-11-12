class_name PollBox
extends VBoxContainer
## Two poll buttons, each with its own price, paid for with the player's party fund.

var world: GameWorld
## Returns the proposal to poll, or an empty dictionary if there is nothing to poll yet.
var target: Callable
var _connected := false

@onready var _support: Button = %poll_support
@onready var _popularity: Button = %poll_popularity
@onready var _result: Label = %poll_result


func setup(owner_world: GameWorld, provider: Callable) -> void:
	world = owner_world
	target = provider
	if not _connected:
		_connected = true
		_support.pressed.connect(_run.bind("poll_support"))
		_popularity.pressed.connect(_run.bind("poll_popularity"))
	refresh()


func refresh() -> void:
	if world == null or world.player == null:
		return
	var politics := world.politics
	var empty: bool = target.call().is_empty()
	var fund := politics.party_fund(world)
	_support.text = tr("Pesquisar apoios no parlamento (%s)") % UiKit.millions(politics.fund_price(world, "poll_support"))
	_popularity.text = tr("Pesquisar popularidade (%s)") % UiKit.millions(politics.fund_price(world, "poll_popularity"))
	_support.disabled = empty or fund < politics.fund_price(world, "poll_support")
	_popularity.disabled = empty or fund < politics.fund_price(world, "poll_popularity")


func clear_result() -> void:
	_result.text = ""


func _run(kind: String) -> void:
	var proposal: Dictionary = target.call()
	if proposal.is_empty():
		return
	var r: Dictionary = world.legislation.poll(world, kind, proposal)
	_result.text = String(r.text) if r.ok else String(r.msg)
	_result.add_theme_color_override("font_color", UiKit.TEXT if r.ok else UiKit.RED)
	refresh()
