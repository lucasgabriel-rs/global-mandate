class_name BorderPanel
extends PanelContainer
## Border demarcation with the same vertex drawing as the subnational units.
## It exists in only two situations: the player won a war and chooses what to keep,
## or peace came with no winner and both sides negotiate new borders.

signal banner_changed(text: String, is_error: bool)
signal finished

const COLOR_CLAIM := Color("f2b33d")
const COLOR_OFFER := Color("4fb3d9")

var world: GameWorld
var map: MapView
var active := false

var _session := {}
## Each closed area: {"claim": [rival's pieces], "offer": [player's pieces]}.
var _areas: Array = []

@onready var _info: Label = %info
@onready var _usage: Label = %usage
@onready var _feedback: Label = %feedback
@onready var _send: Button = %send
@onready var _title: Label = %title
@onready var _old: Button = %old
@onready var _undo: Button = %undo


func _ready() -> void:
	_undo.pressed.connect(_on_undo)
	_send.pressed.connect(_on_send)
	_old.pressed.connect(_on_decline)


func bind(w: GameWorld, m: MapView) -> void:
	world = w
	if map == null:
		map = m
		map.draft_closed.connect(_on_closed)
		map.draft_rejected.connect(_on_rejected)
		map.draft_cancelled.connect(_on_cancelled)
		map.draft_changed.connect(_update_banner)
	if active:
		_close()


## session: {"kind": "victory" | "negotiation", "war": Dictionary, "rival": Country, "budget": float}
func begin(session: Dictionary) -> void:
	_session = session
	_areas.clear()
	active = true
	visible = true
	var rival: Country = session.rival
	if session.kind == "victory":
		_title.text = tr("Demarcar conquistas")
		_info.text = tr("Você venceu %s. Desenhe as áreas que ficam com o seu país: clique no mapa para colocar vértices e no primeiro ponto para fechar. Pode desenhar várias. O que não for marcado volta para %s.") % [rival.name, rival.name]
		_send.text = tr("Confirmar novas fronteiras")
		_old.text = tr("Não ficar com território")
	else:
		_title.text = tr("Negociar fronteiras")
		_info.text = tr("A guerra terminou sem vencedor. Desenhe sobre %s o que pede e sobre o seu país o que oferece. %s decide com base na frente de batalha e no cansaço da guerra.") % [rival.name, rival.name]
		_send.text = tr("Enviar proposta")
		_old.text = tr("Restabelecer fronteiras antigas")
	_feedback.text = ""
	_refresh()
	_start_draft()


func _start_draft() -> void:
	map.begin_draft(COLOR_CLAIM, "border")
	_update_banner()


func _update_banner() -> void:
	if not active or map.draft_owner != "border":
		return
	var n := map.draft.size()
	var tail := tr("clique no primeiro ponto para fechar") if n >= 3 else tr("clique no mapa para colocar os vértices")
	banner_changed.emit(tr("%s  ·  %d vértice(s)  ·  %s  ·  botão direito desfaz") % [_title.text, n, tail], false)


func _on_closed(points: PackedVector2Array) -> void:
	if not active or map.draft_owner != "border":
		return
	var rival: Country = _session.rival
	var t := world.territories
	var claim := _minus_all(t.clip_to(points, rival, world), _all("claim"))
	var offer := []
	if _session.kind == "negotiation":
		offer = _minus_all(t.clip_to(points, world.player, world), _all("offer"))
		# A path is a claim or an offer, never both: the side where most of it falls counts.
		if Subdivisions.total_area(offer) > Subdivisions.total_area(claim):
			claim = []
		else:
			offer = []
	if claim.is_empty() and offer.is_empty():
		_feedback.text = tr("A área não cobre nenhum território disponível.") if _session.kind == "negotiation" else tr("Marque áreas dentro de %s.") % rival.name
	elif _session.kind == "victory" and _claim_share(claim) > float(_session.budget):
		_feedback.text = tr("Essa área passa do limite conquistado na guerra (%s).") % UiKit.pct(_session.budget)
	else:
		_feedback.text = ""
		_areas.append({"claim": claim, "offer": offer})
	_refresh()
	_start_draft()


static func _minus_all(pieces: Array, cuts: Array) -> Array:
	var out := pieces
	for cut: PackedVector2Array in cuts:
		out = Subdivisions.subtract(out, cut)
	return Subdivisions._clean(out)


func _all(key: String) -> Array:
	var out := []
	for area: Dictionary in _areas:
		out.append_array(area[key])
	return out


func _claim_share(extra: Array) -> float:
	var total := Subdivisions.total_area(_all("claim")) + Subdivisions.total_area(extra)
	return total / world.territories.area_of(_session.rival, world)


func _refresh() -> void:
	var rival: Country = _session.rival
	var claim := _claim_share([])
	if _session.kind == "victory":
		_usage.text = tr("Marcado: %s de %s  ·  limite %s") % [UiKit.pct(claim), rival.name, UiKit.pct(_session.budget)]
	else:
		var offer := Subdivisions.total_area(_all("offer")) / world.territories.area_of(world.player, world)
		_usage.text = tr("Pedido: %s de %s\nOferecido: %s de %s") % [UiKit.pct(claim), rival.name, UiKit.pct(offer), world.player.name]
	_undo.disabled = _areas.is_empty()
	_send.disabled = _areas.is_empty()
	map.set_pending(_all("claim"), _all("offer"))


func _on_undo() -> void:
	_areas.pop_back()
	_refresh()


func _on_send() -> void:
	var rival: Country = _session.rival
	if _session.kind == "victory":
		world.settle_victory(_session.war, rival, _all("claim"))
		_close()
		return
	var r: Dictionary = world.propose_borders(_session.war, rival, _all("claim"), _all("offer"))
	if r.ok:
		_close()
		return
	_feedback.text = r.msg
	_session["attempts"] = int(_session.get("attempts", 0)) + 1
	if int(_session.attempts) >= GameWorld.MAX_BORDER_PROPOSALS:
		world.settle_old_borders(_session.war, rival, tr("Sem acordo sobre novas fronteiras: as antigas voltam a valer."))
		_close()


func _on_decline() -> void:
	var rival: Country = _session.rival
	if _session.kind == "victory":
		world.settle_victory(_session.war, rival, [])
	else:
		world.settle_old_borders(_session.war, rival)
	_close()


func _on_rejected(msg: String) -> void:
	if active and map.draft_owner == "border":
		banner_changed.emit(msg, true)


## Esc only discards the polygon in progress; the session continues until the player decides.
func _on_cancelled() -> void:
	if active and map.draft_owner == "border":
		_start_draft()


func _close() -> void:
	active = false
	visible = false
	map.end_draft()
	map.set_pending([], [])
	banner_changed.emit("", false)
	finished.emit()
