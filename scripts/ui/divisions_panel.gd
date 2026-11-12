class_name DivisionsPanel
extends VBoxContainer
## "Divisões" tab: the country's unit types, vertex drawing and unit tree.

signal confirm_requested(text: String, fn: Callable)
signal banner_changed(text: String, is_error: bool)

const ROW_INDENT := 14.0
const MAX_SEARCH_ROWS := 60
const TYPE_ROW := preload("res://scenes/ui/rows/type_row.tscn")
const TREE_ROW := preload("res://scenes/ui/rows/tree_row.tscn")
const HINT_LABEL := preload("res://scenes/ui/rows/hint_label.tscn")
const CAPITAL_LINK := preload("res://scenes/ui/rows/capital_link.tscn")
const CAPITAL_TOGGLE := preload("res://scenes/ui/rows/capital_toggle.tscn")
const COUNTRY_CAPITAL := preload("res://scenes/ui/rows/country_capital.tscn")
const UNIT_DETAIL := preload("res://scenes/ui/rows/unit_detail.tscn")
const MERGE_BOX := preload("res://scenes/ui/rows/merge_box.tscn")

var world: GameWorld
var map: MapView
var active_type := 0
var selected_unit := -1

var _dirty := false
var _focus_type := -1
var _draft_parent := -1
var _banner_error_time := 0.0
var _splitting := false
var _merging := false
var _merge_ids: Array = []
## Units with the list of children open. Brazil has thousands: the list starts collapsed.
var _expanded := {}


@onready var _types_box: VBoxContainer = %types_box
@onready var _tree_box: VBoxContainer = %tree_box
@onready var _detail_box: VBoxContainer = %detail_box
@onready var _draw_button: Button = %draw_button
@onready var _context: Label = %context
@onready var _status: Label = %status
@onready var _search: LineEdit = %search


func _ready() -> void:
	%NovoTipo.pressed.connect(_on_new_type)
	_draw_button.pressed.connect(toggle_drawing)
	_search.text_changed.connect(func(_t): _rebuild_tree())


func bind(w: GameWorld, m: MapView) -> void:
	world = w
	if map == null:
		map = m
		map.unit_clicked.connect(_on_map_clicked)
		map.draft_changed.connect(_update_banner)
		map.draft_closed.connect(_on_draft_closed)
		map.draft_rejected.connect(_on_draft_rejected)
		map.draft_cancelled.connect(_on_draft_cancelled)
	active_type = _first_type()
	selected_unit = -1
	_splitting = false
	_merging = false
	_merge_ids = []
	map.mark_units([])
	_status.text = ""
	banner_changed.emit("", false)
	_expanded.clear()
	_search.text = ""
	map.refresh_units(true)
	_rebuild()


func _process(delta: float) -> void:
	if world and world.busy:
		return
	# Hidden, the tab does not build the list: with thousands of municipalities, that would freeze the screen with nobody seeing.
	if _dirty and is_visible_in_tree():
		_dirty = false
		_rebuild()
	if _banner_error_time > 0.0:
		_banner_error_time -= delta
		if _banner_error_time <= 0.0:
			_update_banner()


func _first_type() -> int:
	var mine: Array = world.subdivisions.types_of(_iso())
	return int(mine[0].id) if not mine.is_empty() else -1


func _iso() -> String:
	return world.player.iso if world and world.player else ""


func _say(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiKit.RED if is_error else UiKit.GREEN)


func _country_name() -> String:
	return world.player.name if world and world.player else ""


func _parent_name(id: int) -> String:
	return world.subdivisions.units[id].name if world.subdivisions.units.has(id) else _country_name()


# --- Desenho ---------------------------------------------------------------------

func toggle_drawing() -> void:
	if map.drawing:
		map.cancel_draft()
	else:
		start_drawing()


func start_drawing() -> void:
	if map.drawing or world == null or world.player == null:
		return
	_draft_parent = selected_unit
	var t: Dictionary = world.subdivisions.get_type(active_type)
	map.begin_draft(t.color)
	_say("")
	_rebuild()
	_update_banner()


func _update_banner() -> void:
	if map.draft_owner != "units":
		return
	if not map.drawing or _banner_error_time > 0.0:
		if not map.drawing:
			banner_changed.emit("", false)
		return
	var t: Dictionary = world.subdivisions.get_type(active_type)
	var n := map.draft.size()
	var tail := tr("clique no primeiro ponto para fechar") if n >= 3 else tr("clique no mapa para colocar os vértices")
	if _splitting:
		banner_changed.emit(tr("Desmembrar %s: contorne a parte que vai se separar  ·  %d vértice(s)  ·  %s  ·  Esc cancela") % [_parent_name(_draft_parent), n, tail], false)
		return
	banner_changed.emit(tr("%s em %s  ·  %d vértice(s)  ·  %s  ·  botão direito desfaz  ·  Esc cancela") % [tr(t.name), _parent_name(_draft_parent), n, tail], false)


func _on_draft_closed(points: PackedVector2Array) -> void:
	if map.draft_owner != "units":
		return
	if _splitting:
		_finish_split(points)
		return
	if world.legislation.units_need_approval(world):
		_send_unit_to_parliament(points)
		return
	var r: Dictionary = world.subdivisions.create_unit(points, active_type, _draft_parent, map.territory_of(world.player), world.player.region, world.player.iso)
	if r.ok:
		var u: Dictionary = world.subdivisions.units[r.id]
		var clip_note := tr(", recortada pelos limites existentes") if r.clipped else ""
		_say(tr("%s (%s) criada em %s%s.") % [u.name, tr(world.subdivisions.get_type(u.type).name), _parent_name(u.parent), clip_note])
	else:
		_say(r.msg, true)
	map.refresh_units()
	_rebuild()
	banner_changed.emit("", false)


## In a democracy, the path only becomes a unit after parliament and the plebiscite.
func _send_unit_to_parliament(points: PackedVector2Array) -> void:
	var check: Dictionary = world.subdivisions.create_unit(points, active_type, _draft_parent, map.territory_of(world.player), world.player.region, world.player.iso, true)
	if not check.ok:
		_say(check.msg, true)
	elif not world.in_office:
		_say(tr("Na oposição, você não propõe novas unidades."), true)
	else:
		var r: Dictionary = world.legislation.present_unit(world, {"kind": "new_unit", "points": points, "type": active_type, "parent": _draft_parent}, tr("Criação de %s em %s") % [tr(world.subdivisions.get_type(active_type).name), _parent_name(_draft_parent)])
		_say(r.msg)
	_rebuild()
	banner_changed.emit("", false)


func _on_draft_rejected(msg: String) -> void:
	if map.draft_owner != "units":
		return
	banner_changed.emit(msg, true)
	_banner_error_time = 2.5


func _on_draft_cancelled() -> void:
	if map.draft_owner != "units":
		return
	_splitting = false
	_banner_error_time = 0.0
	banner_changed.emit("", false)
	_rebuild()


# --- Tipos -----------------------------------------------------------------------

func _on_new_type() -> void:
	var id: int = world.subdivisions.add_type("", _iso())
	active_type = id
	_focus_type = id
	map.set_draft_color(world.subdivisions.get_type(id).color)
	_rebuild()
	_update_banner()


func _commit_type(id: int, edit: LineEdit) -> void:
	var t: Dictionary = world.subdivisions.get_type(id)
	if t.is_empty() or edit.text == t.name:
		return
	var r: Dictionary = world.subdivisions.rename_type(id, edit.text)
	if not r.ok:
		_say(r.msg, true)
	_dirty = true
	_update_banner()


func _remove_type(id: int) -> void:
	var r: Dictionary = world.subdivisions.remove_type(id)
	if not r.ok:
		_say(r.msg, true)
		return
	if active_type == id:
		active_type = _first_type()
		map.set_draft_color(world.subdivisions.get_type(active_type).color)
	_say("")
	_rebuild()
	_update_banner()


func _set_active_type(id: int) -> void:
	active_type = id
	map.set_draft_color(world.subdivisions.get_type(id).color)
	_rebuild()
	_update_banner()


# --- Unidades --------------------------------------------------------------------

func _on_unit_clicked(id: int) -> void:
	if _merging:
		_toggle_merge(id)
	else:
		select_unit(id)


## The map reports the most specific unit under the click. The first click selects the highest
## level; clicking again inside the selected one goes down a level: state, then municipality.
func _on_map_clicked(id: int) -> void:
	if id < 0:
		if not _merging:
			select_unit(-1)
		return
	var chain := world.subdivisions.chain_of(id)
	if _merging:
		var level: int = world.subdivisions.units[_merge_ids[0]].parent
		for link: int in chain:
			if world.subdivisions.units[link].parent == level:
				_toggle_merge(link)
				return
		_toggle_merge(id)
		return
	var at := chain.find(selected_unit)
	select_unit(chain[mini(at + 1, chain.size() - 1)])


# --- Fundir e desmembrar ---------------------------------------------------------

func start_merge() -> void:
	if not world.subdivisions.units.has(selected_unit) or map.drawing:
		return
	_merging = true
	_merge_ids = [selected_unit]
	map.mark_units(_merge_ids)
	_say("")
	_rebuild()


func _toggle_merge(id: int) -> void:
	var subs: Subdivisions = world.subdivisions
	if not subs.units.has(id):
		return
	if id in _merge_ids:
		if _merge_ids.size() > 1:
			_merge_ids.erase(id)
	elif subs.units[id].parent != subs.units[_merge_ids[0]].parent:
		_say(tr("%s está em outro nível da hierarquia.") % subs.units[id].name, true)
		return
	else:
		_merge_ids.append(id)
	map.mark_units(_merge_ids)
	_say("")
	_rebuild()


func confirm_merge() -> void:
	var subs: Subdivisions = world.subdivisions
	var names := []
	for id: int in _merge_ids:
		names.append(subs.units[id].name)
	var r: Dictionary = subs.merge_units(_merge_ids)
	if not r.ok:
		_say(r.msg, true)
		return
	_end_merge()
	_say(tr("%s agora formam %s.") % [", ".join(names), subs.units[r.id].name])
	select_unit(r.id)
	map.refresh_units()


func _end_merge() -> void:
	_merging = false
	_merge_ids = []
	map.mark_units([])
	_rebuild()


func start_split() -> void:
	if not world.subdivisions.units.has(selected_unit) or map.drawing:
		return
	_splitting = true
	_draft_parent = selected_unit
	map.begin_draft(world.subdivisions.get_type(world.subdivisions.units[selected_unit].type).color)
	_say("")
	_rebuild()
	_update_banner()


func _finish_split(points: PackedVector2Array) -> void:
	_splitting = false
	var subs: Subdivisions = world.subdivisions
	if world.legislation.units_need_approval(world):
		var check: Dictionary = subs.split_unit(_draft_parent, points, world.player.region, true)
		if not check.ok:
			_say(check.msg, true)
		elif not world.in_office:
			_say(tr("Na oposição, você não propõe novas unidades."), true)
		else:
			_say(world.legislation.present_unit(world, {"kind": "split_unit", "unit": _draft_parent, "points": points}, tr("Desmembramento de %s") % subs.units[_draft_parent].name).msg)
		_rebuild()
		banner_changed.emit("", false)
		return
	var r: Dictionary = subs.split_unit(_draft_parent, points, world.player.region)
	if r.ok:
		_say(tr("%s se separou de %s.") % [subs.units[r.id].name, subs.units[_draft_parent].name])
		map.refresh_units()
	else:
		_say(r.msg, true)
	_rebuild()
	banner_changed.emit("", false)


func select_unit(id: int) -> void:
	selected_unit = id
	map.select_unit(id)
	for link: int in world.subdivisions.chain_of(id).slice(0, -1):
		_expanded[link] = true
	_rebuild()


func _commit_unit(id: int, edit: LineEdit) -> void:
	if not world.subdivisions.units.has(id) or edit.text == world.subdivisions.units[id].name:
		return
	var r: Dictionary = world.subdivisions.rename_unit(id, edit.text)
	if not r.ok:
		_say(r.msg, true)
	_dirty = true
	map.refresh_units()


func _ask_delete(id: int) -> void:
	var u: Dictionary = world.subdivisions.units[id]
	var below: int = world.subdivisions.count_descendants(id)
	var text := tr("Apagar %s?") % u.name
	if below > 0:
		text = tr("Apagar %s e as %d unidade(s) dentro dela?") % [u.name, below]
	confirm_requested.emit(text, func():
		if map.drawing:
			map.cancel_draft()
		world.subdivisions.delete_unit(id)
		_say(tr("%s apagada.") % u.name)
		select_unit(-1)
		map.refresh_units())


# --- Building the list ---------------------------------------------------------

func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _rebuild() -> void:
	if world == null or _types_box == null:
		return
	if not is_visible_in_tree():
		_dirty = true
		return
	var subs: Subdivisions = world.subdivisions
	if not subs.units.has(selected_unit):
		selected_unit = -1
		map.select_unit(-1)
	# A cession or a merge may take units out of the selection in progress.
	_merge_ids = _merge_ids.filter(func(id): return subs.units.has(id))
	if _merging and _merge_ids.is_empty():
		_merging = false
	map.mark_units(_merge_ids)
	_rebuild_types()
	_rebuild_tree()
	_rebuild_detail()
	var t: Dictionary = subs.get_type(active_type)
	_context.text = tr("Próxima unidade: %s em %s") % [tr(t.get("name", "")), _parent_name(selected_unit)]
	_draw_button.text = tr("Cancelar desenho (Esc)") if map.drawing else tr("Desenhar unidade (N)")


func _rebuild_types() -> void:
	_clear(_types_box)
	var subs: Subdivisions = world.subdivisions
	var counts := subs.type_counts()
	for t: Dictionary in subs.types_of(_iso()):
		var id: int = t.id
		var row: Control = TYPE_ROW.instantiate()
		var on := id == active_type
		var pick: Button = row.get_node("%pick")
		pick.pressed.connect(_set_active_type.bind(id))
		pick.add_theme_color_override("font_color", t.color)
		pick.add_theme_color_override("font_hover_color", t.color)
		pick.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.95, 0.7, 0.24, 0.2) if on else Color(1, 1, 1, 0.05), UiKit.ACCENT if on else UiKit.LINE, 3, 4))
		var edit: LineEdit = row.get_node("%edit")
		edit.text = t.name
		edit.text_submitted.connect(func(_s):
			edit.release_focus())
		edit.focus_exited.connect(_commit_type.bind(id, edit))
		(row.get_node("%count") as Label).text = str(counts.get(id, 0))
		row.get_node("%remove").pressed.connect(_remove_type.bind(id))
		_types_box.add_child(row)
		if id == _focus_type:
			_focus_type = -1
			edit.call_deferred("grab_focus")
			edit.call_deferred("select_all")


func _hint(box: Control, text: String) -> void:
	var label: Label = HINT_LABEL.instantiate()
	label.text = text
	box.add_child(label)


func _tree_row(text: String, depth: int, id: int, color: Color) -> void:
	var row: Control = TREE_ROW.instantiate()
	(row.get_node("%pad") as Control).custom_minimum_size.x = ROW_INDENT * depth
	var kids: int = world.subdivisions.children_of(id).size() if id >= 0 else 0
	var arrow: Button = row.get_node("%arrow")
	arrow.visible = kids > 0
	if kids > 0:
		var open: bool = _expanded.has(id)
		arrow.text = "▾" if open else "▸"
		arrow.tooltip_text = tr("Recolher") if open else tr("Mostrar %d unidade(s) dentro desta") % kids
		arrow.pressed.connect(_toggle_expanded.bind(id))
	var b: Button = row.get_node("%unit")
	b.text = text
	b.pressed.connect(_on_unit_clicked.bind(id))
	b.add_theme_color_override("font_color", color)
	if id in _merge_ids:
		b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.31, 0.7, 0.85, 0.22), UiKit.CYAN, 3, 4))
	elif id == selected_unit:
		b.add_theme_stylebox_override("normal", UiKit.panel_style(Color(0.95, 0.7, 0.24, 0.2), UiKit.ACCENT, 3, 4))
	_tree_box.add_child(row)


func _toggle_expanded(id: int) -> void:
	if _expanded.has(id):
		_expanded.erase(id)
	else:
		_expanded[id] = true
	_rebuild_tree()


## Only the children of the open units: building a row for every municipality would freeze the tab.
func _visible_rows(ids: Array, depth: int, out: Array) -> void:
	var subs: Subdivisions = world.subdivisions
	for id: int in ids:
		out.append({"unit": subs.units[id], "depth": depth})
		if _expanded.has(id):
			var kids: Array = subs.children_of(id).duplicate()
			kids.sort_custom(func(a, b): return String(subs.units[a].name).naturalnocasecmp_to(subs.units[b].name) < 0)
			_visible_rows(kids, depth + 1, out)


func _search_rows(query: String) -> void:
	var subs: Subdivisions = world.subdivisions
	var found := []
	var total := 0
	for iso: String in world.owned_isos(world.player):
		for e: Dictionary in subs.walk_country(iso):
			if String(e.unit.name).to_lower().contains(query):
				total += 1
				if found.size() < MAX_SEARCH_ROWS:
					found.append(e.unit)
	for u: Dictionary in found:
		_tree_row("%s%s  ·  %s" % ["★ " if subs.is_capital(u.id) else "", subs.path_of(u.id), subs.get_type(u.type).name], 0, u.id, subs.unit_color(u).lightened(0.25))
	if total > found.size():
		_hint(_tree_box, tr("Mostrando %d de %d resultados.") % [found.size(), total])
	elif total == 0:
		_hint(_tree_box, tr("Nenhuma unidade com esse nome."))


func _rebuild_tree() -> void:
	_clear(_tree_box)
	var subs: Subdivisions = world.subdivisions
	var query := _search.text.strip_edges().to_lower()
	if query != "":
		_search_rows(query)
		return
	_tree_row(tr("%s  ·  país") % _country_name(), 0, -1, UiKit.TEXT)
	var roots := []
	for iso: String in world.owned_isos(world.player):
		roots.append_array(subs.roots_of(iso))
	roots.sort_custom(func(a, b): return String(subs.units[a].name).naturalnocasecmp_to(subs.units[b].name) < 0)
	var rows := []
	_visible_rows(roots, 0, rows)
	for e: Dictionary in rows:
		var u: Dictionary = e.unit
		_tree_row("%s%s  ·  %s" % ["★ " if subs.is_capital(u.id) else "", u.name, subs.get_type(u.type).name], int(e.depth) + 1, u.id, subs.unit_color(u).lightened(0.25))
	if subs.units.is_empty():
		_hint(_tree_box, tr("Nenhuma unidade criada ainda."))


func _rebuild_detail() -> void:
	_clear(_detail_box)
	var subs: Subdivisions = world.subdivisions
	if not subs.units.has(selected_unit):
		_add_country_capital()
		return
	if _merging:
		_rebuild_merge_box()
		return
	var id := selected_unit
	var u: Dictionary = subs.units[id]
	var box: Control = UNIT_DETAIL.instantiate()
	(box.get_node("%path") as Label).text = subs.path_of(id)
	var edit: LineEdit = box.get_node("%edit")
	edit.text = u.name
	edit.text_submitted.connect(func(_s):
		edit.release_focus())
	edit.focus_exited.connect(_commit_unit.bind(id, edit))
	var kind: OptionButton = box.get_node("%kind")
	var kinds := subs.types_of(u.owner)
	for i in kinds.size():
		kind.add_item(kinds[i].name, kinds[i].id)
		if kinds[i].id == u.type:
			kind.select(i)
	kind.item_selected.connect(func(index: int):
		u.type = kind.get_item_id(index)
		map.refresh_units()
		_dirty = true)
	var share := float(u.area) / world.territories.area_of(world.player, world)
	(box.get_node("%info") as Label).text = tr("≈ %s do território nacional  ·  cerca de %s mi de habitantes  ·  %d subunidade(s)") % [UiKit.pct(share), UiKit.num(world.player.pop * subs.pop_share(id), 2), subs.count_descendants(id)]
	_add_capital_controls(box, id)
	box.get_node("%focus").pressed.connect(func(): map.focus_on_point(u.center))
	box.get_node("%delete").pressed.connect(_ask_delete.bind(id))
	box.get_node("%merge").pressed.connect(start_merge)
	box.get_node("%split").pressed.connect(start_split)
	_detail_box.add_child(box)


func _capital_link(link: Button, text: String, id: int) -> void:
	link.text = text
	link.pressed.connect(_on_unit_clicked.bind(id))


func _add_country_capital() -> void:
	var subs: Subdivisions = world.subdivisions
	if world.player == null:
		return
	var capital: int = subs.capital_of(_iso())
	var box: Control = COUNTRY_CAPITAL.instantiate()
	var link: Button = box.get_node("%link")
	var note: Label = box.get_node("%note")
	link.visible = capital >= 0
	note.visible = capital < 0
	if capital >= 0:
		_capital_link(link, "★ %s" % subs.path_of(capital), capital)
	else:
		note.text = tr("%s está sem capital. Selecione uma unidade para escolher.") % _country_name()
	_detail_box.add_child(box)


## A unit can be the capital of any unit that contains it and of the country.
func _add_capital_controls(box: Control, id: int) -> void:
	var subs: Subdivisions = world.subdivisions
	var list: Control = box.get_node("%capitals")
	var own: int = subs.capital_of(id)
	(box.get_node("%no_capital") as Label).visible = own < 0 and not subs.children_of(id).is_empty()
	if own >= 0:
		var link: Button = CAPITAL_LINK.instantiate()
		_capital_link(link, tr("★ Capital desta unidade: %s") % subs.units[own].name, own)
		list.add_child(link)
	var holders: Array = [_iso()]
	var chain := subs.chain_of(id).slice(0, -1)
	chain.reverse()
	holders = chain + holders
	for holder: Variant in holders:
		var holder_name: String = _country_name() if holder is String else String(subs.units[holder].name)
		var on: bool = subs.capital_of(holder) == id
		var b: Button = CAPITAL_TOGGLE.instantiate()
		b.text = tr("★ Capital de %s: remover") % holder_name if on else tr("Tornar capital de %s") % holder_name
		b.pressed.connect(_toggle_capital.bind(holder, id))
		if on:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		list.add_child(b)


func _toggle_capital(holder: Variant, id: int) -> void:
	var subs: Subdivisions = world.subdivisions
	var holder_name: String = _country_name() if holder is String else String(subs.units[holder].name)
	if subs.capital_of(holder) == id:
		subs.clear_capital(holder)
		_say(tr("%s deixou de ser capital de %s.") % [subs.units[id].name, holder_name])
	else:
		var r: Dictionary = subs.set_capital(holder, id)
		if not r.ok:
			_say(r.msg, true)
			return
		_say(tr("%s agora é capital de %s.") % [subs.units[id].name, holder_name])
	map.refresh_units()
	_rebuild()


func _rebuild_merge_box() -> void:
	var subs: Subdivisions = world.subdivisions
	var box: Control = MERGE_BOX.instantiate()
	var names := []
	for id: int in _merge_ids:
		names.append(subs.units[id].name)
	(box.get_node("%names") as Label).text = " + ".join(names)
	var ok: Button = box.get_node("%confirm")
	ok.disabled = _merge_ids.size() < 2
	ok.pressed.connect(confirm_merge)
	box.get_node("%cancel").pressed.connect(_end_merge)
	_detail_box.add_child(box)
