class_name CorruptionWindow
extends ColorRect
## Janela das ações de corrupção, pagas pelo fundo do partido: comprar votos, abafar escândalos, favorecer aliados,
## caixa dois e desvio. Mostra a percepção, a exposição ao escândalo e o andamento da investigação.

signal closed

const ROW := preload("res://scenes/ui/rows/corruption_action.tscn")
## As ações que não precisam de uma norma escolhida, na ordem da janela.
const PLAIN := ["hush", "favor", "embezzle", "skim"]

var world: GameWorld
var corruption: Corruption
var _buttons := {}

@onready var _status: Label = %status
@onready var _feedback: Label = %feedback
@onready var _norms: OptionButton = %norm_pick
@onready var _parties: OptionButton = %party_pick
@onready var _side: OptionButton = %side_pick
@onready var _bribe: Button = %bribe
@onready var _actions: VBoxContainer = %Acoes
@onready var _history: Label = %Historico


func setup(w: GameWorld) -> void:
	world = w
	corruption = w.corruption
	(%votos_titulo as Label).text = tr(Corruption.LABELS.bribe)
	(%votos_desc as Label).text = tr(Corruption.DESCRIPTIONS.bribe)
	_side.add_item(tr("A favor"))
	_side.add_item(tr("Contra"))
	for kind: String in PLAIN:
		var row: Control = ROW.instantiate()
		_actions.add_child(row)
		(row.get_node("%name") as Label).text = tr(Corruption.LABELS[kind])
		(row.get_node("%desc") as Label).text = tr(Corruption.DESCRIPTIONS[kind])
		var button: Button = row.get_node("%act")
		button.pressed.connect(_run.bind(kind))
		_buttons[kind] = button
	_bribe.pressed.connect(_buy)
	_norms.item_selected.connect(func(_i): _fill_parties())
	%Fechar.pressed.connect(func(): closed.emit())
	_fill_norms()
	refresh()


func _fill_norms() -> void:
	_norms.clear()
	var leg := world.legislation
	for norm: Dictionary in leg.list_norms():
		if leg.can_negotiate(norm):
			_norms.add_item("%s: %s" % [leg.norm_label(norm), tr(norm.title)])
			_norms.set_item_metadata(_norms.item_count - 1, int(norm.id))
	_fill_parties()


func _fill_parties() -> void:
	_parties.clear()
	var data: Dictionary = world.politics.data_of(world.player.iso)
	var ordered: Array = data.parties.filter(func(p): return int(p.seats) > 0 and int(p.id) != int(data.player_party))
	ordered.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	var norm := _norm()
	for p: Dictionary in ordered:
		var cost := corruption.quote(world, norm, int(p.id)) if not norm.is_empty() else 0.0
		_parties.add_item("%s  ·  %d  ·  %s" % [p.short, int(p.seats), UiKit.millions(cost)])
		_parties.set_item_metadata(_parties.item_count - 1, int(p.id))


func _norm() -> Dictionary:
	if _norms.selected < 0:
		return {}
	return world.legislation.norms.get(int(_norms.get_selected_metadata()), {})


func refresh() -> void:
	var c := world.player
	var can := corruption.can_act(world)
	var chance := corruption.scandal_chance(world, c)
	var lines := [
		tr("Fundo: %s  ·  Percepção de integridade: %d/100  ·  Instituições: %s") % [UiKit.millions(corruption.balance(world)), Corruption.perception_score(c), UiKit.pct(corruption.integrity(world, c), 0)],
		tr("Exposição: %s  ·  Risco de escândalo por mês: %s  ·  Escândalos: %d") % [UiKit.pct(corruption.heat, 0), UiKit.pct(chance, 0), corruption.scandals],
	]
	if corruption.investigation > 0:
		lines.append(tr("Investigação aberta: faltam %d meses. Peso do processo: %s.") % [corruption.investigation, UiKit.pct(corruption.case_load, 0)])
	if corruption.stash > 0.0:
		lines.append(tr("Patrimônio desviado: %s") % UiKit.millions(corruption.stash))
	_status.text = "\n".join(lines)
	_status.add_theme_color_override("font_color", UiKit.RED if chance > 0.1 or corruption.investigation > 0 else UiKit.GREEN)
	for kind: String in PLAIN:
		var button: Button = _buttons[kind]
		var left := corruption.wait_left(world, kind)
		var cost := corruption.price(world, kind)
		button.text = tr("Fazer (%s)") % UiKit.millions(cost) if cost > 0.0 else tr("Fazer")
		if left > 0:
			button.text = tr("Espere %d meses") % left
		button.disabled = not can or left > 0
	_bribe.disabled = not can or _norms.item_count == 0 or _parties.item_count == 0
	_history.text = "\n".join(corruption.history.map(func(h): return "· " + String(h.text)))
	_history.visible = not corruption.history.is_empty()


func _run(kind: String) -> void:
	var r: Dictionary = {}
	match kind:
		"hush": r = corruption.hush(world)
		"favor": r = corruption.favor_allies(world)
		"embezzle": r = corruption.embezzle(world)
		"skim": r = corruption.skim(world)
	_show(r)


func _buy() -> void:
	var norm := _norm()
	if norm.is_empty() or _parties.selected < 0:
		return
	_show(corruption.bribe_votes(world, norm, int(_parties.get_selected_metadata()), _side.selected == 0))
	_fill_norms()


func _show(r: Dictionary) -> void:
	_feedback.text = r.get("msg", "")
	_feedback.add_theme_color_override("font_color", UiKit.GREEN if r.get("ok", false) and r.get("accepted", true) else UiKit.RED)
	refresh()
