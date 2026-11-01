class_name MapView
extends Node2D
## Mapa-múndi: polígonos por país, câmera com zoom/arraste, seleção, modos de mapa,
## rótulos e sobreposições (guerras, fluxos de comércio).

signal country_clicked(c: Country)
signal country_hovered(c: Country)
signal unit_clicked(id: int)
signal unit_hovered(id: int)
signal draft_changed
signal draft_closed(points: PackedVector2Array)
signal draft_rejected(msg: String)
signal draft_cancelled

const CLOSE_RADIUS_PX := 12.0
const BASE_LINES_ZOOM := 0.9
const BASE_LABEL_ZOOM := 1.5
const MUN_LINES_ZOOM := 1.6
const MUN_LABEL_ZOOM := 5.0
const CAPITAL_ZOOM := 1.6
const FOREIGN_CAPITAL_ZOOM := 1.1
const CAPITAL_NAME_ZOOM := 2.4
const OCEAN := Color("0a1520")
const OCEAN_LINE := Color(0.32, 0.5, 0.6, 0.10)
const BORDER := Color(0.03, 0.07, 0.10, 0.95)
const NEUTRAL := Color("2b363e")
const ANTARCTICA := Color("1a242c")
const ROB_X := [1, 0.9986, 0.9954, 0.99, 0.9822, 0.973, 0.96, 0.9427, 0.9216, 0.8962, 0.8679, 0.835, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322]
const ROB_Y := [0, 0.062, 0.124, 0.186, 0.248, 0.31, 0.372, 0.434, 0.4958, 0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1]

## Modos: chave -> [rótulo, baixo, alto, cor-baixa, cor-alta, descrição do intervalo]
const MODES := {
	"politico": ["Político"],
	"relacoes": ["Relações"],
	"crescimento": ["Crescimento"],
	"inflacao": ["Inflação"],
	"desemprego": ["Desemprego"],
	"divida": ["Dívida"],
	"renda": ["Renda"],
	"estabilidade": ["Estabilidade"],
	"militar": ["Militar"],
}

var world: GameWorld
var mode := "politico"
var selected: Country
var hovered: Country
var features: Array = []
var width := 2000.0

var _camera: Camera2D
var _overlay: Node2D
var _borders: Node2D
var _labels: Node2D
var _border_points := PackedVector2Array()
var _graticule := PackedVector2Array()
var _land_nodes: Node2D
var _dragging := false
var _drag_moved := 0.0
var _time := 0.0
var _target_zoom := 1.0
var _min_zoom := 0.5
var _palette_cache := {}
var interactive := true
var _last_cam := Vector2.INF
var _last_zoom := Vector2.ZERO

## Com a aba Divisões aberta, clicar em uma unidade seleciona a unidade em vez do país.
var unit_pick := false
var selected_unit := -1
var drawing := false
var draft := PackedVector2Array()
var _draft_color := Color.WHITE
var _draft_mouse := Vector2.ZERO
var _hover_unit := -1
var _native_borders: Node2D
var _cession_layer: Node2D
var draft_owner := "units"
var marked_units: Array = []
var _pending_claims: Array = []
var _pending_offers: Array = []
var _base_lines: Node2D
var _mun_lines: Node2D
var _lines_revision := -1
var _units_layer: Node2D
var _draft_layer: Node2D


func _ready() -> void:
	_build_graticule()
	_land_nodes = Node2D.new()
	add_child(_land_nodes)
	_native_borders = Node2D.new()
	_native_borders.draw.connect(_draw_native_borders)
	add_child(_native_borders)
	_cession_layer = Node2D.new()
	_cession_layer.draw.connect(_draw_cessions)
	add_child(_cession_layer)
	_base_lines = Node2D.new()
	_base_lines.draw.connect(_draw_base_lines)
	add_child(_base_lines)
	_mun_lines = Node2D.new()
	_mun_lines.draw.connect(_draw_mun_lines)
	_mun_lines.visible = false
	add_child(_mun_lines)
	_units_layer = Node2D.new()
	_units_layer.draw.connect(_draw_units)
	add_child(_units_layer)
	_borders = Node2D.new()
	_borders.draw.connect(_draw_borders)
	add_child(_borders)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_draft_layer = Node2D.new()
	_draft_layer.draw.connect(_draw_draft)
	add_child(_draft_layer)
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_labels = Node2D.new()
	_labels.draw.connect(_draw_labels)
	layer.add_child(_labels)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_camera.zoom = Vector2.ONE * _target_zoom


func _fit() -> void:
	var size := get_viewport_rect().size
	_min_zoom = minf(size.x / (width * 1.06), size.y / (width * 0.56))
	_target_zoom = maxf(_target_zoom, _min_zoom) if _target_zoom != 1.0 else _min_zoom
	_camera.zoom = Vector2.ONE * _target_zoom


## Enquadra o mundo inteiro em uma faixa horizontal da tela (o resto fica sob painéis).
func frame_region(left: float, right: float) -> void:
	var size := get_viewport_rect().size
	var z := (right - left) / (width * 1.02)
	_min_zoom = minf(_min_zoom, z)
	_target_zoom = z
	_camera.zoom = Vector2.ONE * z
	_camera.position = Vector2((size.x * 0.5 - (left + right) * 0.5) / z, 0.0)


func reset_view() -> void:
	_target_zoom = 1.0
	_fit()


func _project(lon: float, lat: float) -> Vector2:
	var al := minf(absf(lat), 89.99)
	var i := int(al / 5.0)
	var f := al / 5.0 - i
	var px: float = lerpf(ROB_X[i], ROB_X[i + 1], f)
	var py: float = lerpf(ROB_Y[i], ROB_Y[i + 1], f)
	return Vector2(lon * px * width / 360.0, -signf(lat) * py * width * 0.2535)


func _build_graticule() -> void:
	for lat in range(-75, 90, 15):
		for lon in range(-180, 180, 5):
			_graticule.append(_project(lon, lat))
			_graticule.append(_project(lon + 5, lat))
	for lon in range(-180, 181, 30):
		for lat in range(-90, 90, 5):
			_graticule.append(_project(lon, lat))
			_graticule.append(_project(lon, lat + 5))


# Carregar o mapa acontece em etapas, para a tela nunca parar: ler o arquivo e triangular cada país rodam em
# outras threads, e só criar os nós fica na thread principal, em pedaços (ver load_features em main.gd).

var _raw_features: Array = []
var _prepared: Array = []
var _built_features := 0


## Thread de trabalho. Só mexe nos dados deste objeto, nunca nos nós.
func load_feature_data() -> void:
	var data := GameData.load_map()
	width = data.width
	# Cópia: a outra thread está lendo a mesma lista, e ordenar mexeria nela.
	var raw: Array = data.features.duplicate()
	raw.sort_custom(func(a, b): return float(a.area) > float(b.area))
	_raw_features = raw
	_prepared.resize(raw.size())


func feature_count() -> int:
	return _raw_features.size()


## Várias threads ao mesmo tempo, cada uma no próprio país: nenhuma escreve no que é da outra.
func prepare_feature(index: int) -> void:
	var feat: Dictionary = _raw_features[index]
	var rings: Array = []
	var holes: Array = []
	var border := PackedVector2Array()
	var verts := PackedVector2Array()
	var indices := PackedInt32Array()
	var rect := Rect2()
	var first := true
	var failed := []
	for shape: Array in feat.shapes:
		var ring := _to_points(shape[0])
		var ids := Geometry2D.triangulate_polygon(ring)
		var pieces := [ring]
		if ids.is_empty():
			# A simplificação pode gerar autointerseções: o Clipper devolve anéis limpos.
			pieces = Geometry2D.offset_polygon(ring, 0.05, Geometry2D.JOIN_MITER)
		var any_ok := false
		for piece: PackedVector2Array in pieces:
			var piece_ids := ids if piece == ring and not ids.is_empty() else Geometry2D.triangulate_polygon(piece)
			if piece_ids.is_empty():
				continue
			any_ok = true
			var offset := verts.size()
			verts.append_array(piece)
			for id in piece_ids:
				indices.append(id + offset)
		if not any_ok:
			failed.append("%s(%d)" % [feat.name, ring.size()])
			continue
		rings.append(ring)
		var r := _bounds(ring)
		rect = r if first else rect.merge(r)
		first = false
		for pi in shape.size():
			var pts := ring if pi == 0 else _to_points(shape[pi])
			if pi > 0:
				holes.append(pts)
			for k in pts.size():
				border.append(pts[k])
				border.append(pts[(k + 1) % pts.size()])
	_prepared[index] = {"rings": rings, "holes": holes, "border": border, "verts": verts, "indices": indices, "rect": rect, "failed": failed}


## Thread principal: cria os nós já com os dados prontos, até gastar o tempo do quadro. true: terminou.
func build_features_slice(budget_usec: int) -> bool:
	var start := Time.get_ticks_usec()
	while _built_features < _raw_features.size():
		var feat: Dictionary = _raw_features[_built_features]
		var ready: Dictionary = _prepared[_built_features]
		_built_features += 1
		if not ready.failed.is_empty():
			print("MapView: polígonos não triangulados: ", ready.failed)
		_border_points.append_array(ready.border)
		if not ready.verts.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = ready.verts
			arrays[Mesh.ARRAY_INDEX] = ready.indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
			var node := MeshInstance2D.new()
			node.mesh = mesh
			_land_nodes.add_child(node)
			features.append({
				"iso": feat.iso, "name": feat.name, "label": feat.label, "area": float(feat.area),
				"center": Vector2(feat.center[0], feat.center[1]), "rings": ready.rings, "holes": ready.holes, "rect": ready.rect, "node": node,
			})
		if Time.get_ticks_usec() - start > budget_usec:
			break
	if _built_features < _raw_features.size():
		return false
	_raw_features = []
	_prepared = []
	_native_borders.queue_redraw()
	return true


func _to_points(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(flat.size() / 2)
	for i in pts.size():
		pts[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
	return pts


func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


func _draw() -> void:
	draw_rect(Rect2(-width * 2.0, -width * 2.0, width * 4.0, width * 4.0), OCEAN)
	draw_multiline(_graticule, OCEAN_LINE, -1.0)


func _draw_native_borders() -> void:
	_native_borders.draw_multiline(_border_points, BORDER, -1.0)


## Áreas que mudaram de país, por cima do mapa de base, com a cor do dono atual e fronteira própria.
func _draw_cessions() -> void:
	if world == null:
		return
	for cession: Dictionary in world.territories.cessions:
		var c: Country = world.resolve_owner(cession.to)
		var col := NEUTRAL if c == null else color_for(c)
		for piece: PackedVector2Array in cession.pieces:
			_cession_layer.draw_colored_polygon(piece, col)
		_cession_layer.draw_multiline(cession.outline, BORDER, -1.0)


func _draw_borders() -> void:
	if world == null:
		return
	var z := _camera.zoom.x
	if hovered and hovered != selected:
		_outline(_borders, hovered, Color(1, 1, 1, 0.45), 1.2 / z)
	if selected:
		_outline(_borders, selected, Color("f2b33d"), 2.2 / z)
	if world.player and world.player != selected:
		_outline(_borders, world.player, Color(1, 1, 1, 0.75), 1.4 / z)


func _outline(canvas: Node2D, c: Country, color: Color, w: float) -> void:
	var changed := world.territories.changed_outline(c, world)
	if not changed.is_empty():
		canvas.draw_multiline(changed, color, w)
		return
	for f: Dictionary in features:
		if _owner_of(f) != c:
			continue
		for ring: PackedVector2Array in f.rings:
			var pts := ring.duplicate()
			pts.append(ring[0])
			canvas.draw_polyline(pts, color, w)


func _owner_of(f: Dictionary) -> Country:
	if world == null or f.iso == "":
		return null
	var c: Country = world.by_iso.get(f.iso)
	while c and not c.alive and c.annexed_by >= 0:
		c = world.countries[c.annexed_by]
	return c


func _draw_overlay() -> void:
	if world == null:
		return
	var z := _camera.zoom.x
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	if selected and selected.alive:
		for pair: Array in world.diplomacy.top_partners(selected, 7, world):
			var o: Country = world.countries[pair[0]]
			_arc(selected.center, o.center, Color(0.31, 0.7, 0.85, 0.2 + 2.0 * float(pair[1])), (0.8 + 14.0 * float(pair[1])) / z)
	for w: Dictionary in world.diplomacy.wars:
		var a: Country = world.countries[w.main_a]
		var d: Country = world.countries[w.main_d]
		_arc(a.center, d.center, Color(0.92, 0.3, 0.22, 0.45 + 0.5 * pulse), 2.4 / z)
		var r := (5.0 + 3.0 * pulse) / z
		_overlay.draw_arc(d.center, r * 1.5, 0.0, TAU, 24, Color(0.92, 0.3, 0.22, 0.9), 1.6 / z)
		_overlay.draw_circle(d.center, r * 0.4, Color(0.95, 0.35, 0.25, 1.0))


func _arc(from: Vector2, to: Vector2, color: Color, w: float) -> void:
	var mid := (from + to) * 0.5 + Vector2(0.0, -from.distance_to(to) * 0.18)
	var pts := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	_overlay.draw_polyline(pts, color, w, true)


func _draw_units() -> void:
	if world == null:
		return
	var subs: Subdivisions = world.subdivisions
	var z := _camera.zoom.x
	if mode == "politico":
		for id: int in subs.custom_ids:
			if subs.units[id].get("plain", false):
				continue
			var col := subs.unit_color(subs.units[id])
			col.a = 0.42
			for piece: PackedVector2Array in subs.units[id].pieces:
				_units_layer.draw_colored_polygon(piece, col)
	for id: int in subs.custom_ids:
		var u: Dictionary = subs.units[id]
		if u.get("plain", false):
			var mine: bool = world.player != null and world.resolve_owner(u.owner) == world.player
			_units_layer.draw_multiline(subs.outline_of(u), Color(0.95, 0.97, 1.0, 0.5) if mine else Color(0.03, 0.07, 0.10, 0.55), -1.0)
			continue
		var w := maxf(2.0 - float(subs.depth_of(id)) * 0.5, 0.8) / z
		_units_layer.draw_multiline(subs.outline_of(u), subs.unit_color(u).lightened(0.35), w)
	if subs.units.has(_hover_unit):
		_units_layer.draw_multiline(subs.outline_of(subs.units[_hover_unit]), Color(1, 1, 1, 0.7), 1.6 / z)
	if subs.units.has(selected_unit):
		_units_layer.draw_multiline(subs.outline_of(subs.units[selected_unit]), Color("f2b33d"), 2.6 / z)
	for id: int in marked_units:
		if subs.units.has(id):
			_units_layer.draw_multiline(subs.outline_of(subs.units[id]), Color("4fb3d9"), 2.6 / z)


## Divisas do cenário: uma camada estática, redesenhada só quando as unidades mudam.
## O país do jogador aparece mais forte. Uma divisa some quando as duas unidades foram apagadas.
func _draw_base_lines() -> void:
	if world == null:
		return
	var subs: Subdivisions = world.subdivisions
	_draw_arcs(_base_lines, subs.arcs, Color(0.02, 0.05, 0.07, 0.95), Color(0.03, 0.07, 0.10, 0.55))


## Municípios: camada própria, mais fina, que só aparece com zoom.
func _draw_mun_lines() -> void:
	if world == null:
		return
	_draw_arcs(_mun_lines, world.subdivisions.mun_arcs, Color(0.95, 0.97, 1.0, 0.24), Color(0.03, 0.07, 0.10, 0.28))


func _draw_arcs(canvas: Node2D, arcs: Array, mine_color: Color, other_color: Color) -> void:
	var subs: Subdivisions = world.subdivisions
	var mine := PackedVector2Array()
	var others := PackedVector2Array()
	var is_mine := {}
	for arc: Array in arcs:
		var u: Dictionary = subs.units.get(arc[0], subs.units.get(arc[1], {}))
		if u.is_empty():
			continue
		if not is_mine.has(u.owner):
			is_mine[u.owner] = world.player != null and world.resolve_owner(u.owner) == world.player
		var pts: PackedVector2Array = arc[2]
		var target := mine if is_mine[u.owner] else others
		for i in pts.size() - 1:
			target.append(pts[i])
			target.append(pts[i + 1])
	if not others.is_empty():
		canvas.draw_multiline(others, other_color, -1.0)
	if not mine.is_empty():
		canvas.draw_multiline(mine, mine_color, -1.0)


func _draw_draft() -> void:
	for piece: PackedVector2Array in _pending_claims:
		_draft_layer.draw_colored_polygon(piece, Color(0.95, 0.7, 0.24, 0.55))
	for piece: PackedVector2Array in _pending_offers:
		_draft_layer.draw_colored_polygon(piece, Color(0.31, 0.7, 0.85, 0.55))
	if not drawing or draft.is_empty():
		return
	var z := _camera.zoom.x
	var line := _draft_color.lightened(0.3)
	if draft.size() >= 2:
		_draft_layer.draw_polyline(draft, line, 2.0 / z, true)
	var last := draft[draft.size() - 1]
	var closing := _near_first(_draft_mouse)
	var target := draft[0] if closing else _draft_mouse
	var bad := Subdivisions.crosses(draft, last, target, closing)
	_draft_layer.draw_line(last, target, UiKit.RED if bad else Color(line, 0.7), 1.6 / z, true)
	for p in draft:
		_draft_layer.draw_circle(p, 3.0 / z, line)
	var first_r := (8.0 if closing else 5.5) / z
	_draft_layer.draw_circle(draft[0], first_r, Color.WHITE if closing else UiKit.ACCENT)
	_draft_layer.draw_arc(draft[0], first_r + 2.0 / z, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 1.2 / z)


func _unit_label(u: Dictionary, font: Font, xf: Transform2D, z: float, vp: Rect2, placed: Array[Rect2], color: Color) -> void:
	var screen_size := sqrt(float(u.area)) * z
	var pos: Vector2 = xf * (u.center as Vector2)
	if not vp.has_point(pos):
		return
	var fs := int(clampf(screen_size * 0.13, 10.0, 16.0))
	var txt: String = u.name
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > screen_size * 1.5:
		return
	var box := Rect2(pos.x - tw * 0.5 - 2.0, pos.y - fs * 0.6, tw + 4.0, fs * 1.2)
	for r in placed:
		if r.intersects(box):
			return
	placed.append(box)
	var bl := Vector2(pos.x - tw * 0.5, pos.y + fs * 0.35)
	_labels.draw_string_outline(font, bl, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.02, 0.05, 0.07, 0.8))
	_labels.draw_string(font, bl, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Capital do país do jogador: estrela grande, sempre visível. As de outros países e as de unidades
## aparecem com zoom. Devolve os nomes que só entram depois dos rótulos dos países.
func _draw_capitals(font: Font, xf: Transform2D, z: float, vp: Rect2, placed: Array[Rect2]) -> Array:
	var subs: Subdivisions = world.subdivisions
	var drawn := {}
	var late := []
	var my_isos: Array = world.owned_isos(world.player) if world.player else []
	for national: bool in [true, false]:
		for holder: Variant in subs.capitals:
			if (holder is String) != national or drawn.has(subs.capitals[holder]):
				continue
			var mine: bool = holder is String and holder in my_isos
			if national and not mine:
				var foreign: Country = world.resolve_owner(holder)
				if z < FOREIGN_CAPITAL_ZOOM or foreign == null or foreign.iso != holder:
					continue
				var spot: Vector2 = xf * (subs.units[subs.capitals[holder]].center as Vector2)
				drawn[subs.capitals[holder]] = true
				if vp.has_point(spot):
					_star(spot, 4.0, Color("f2b33d"))
					if z >= CAPITAL_NAME_ZOOM:
						late.append([subs.units[subs.capitals[holder]].name, spot, 11])
				continue
			var low: bool = holder is int and int(subs.units[holder].parent) >= 0
			if not national and z < (MUN_LABEL_ZOOM if low else CAPITAL_ZOOM):
				continue
			var id: int = subs.capitals[holder]
			drawn[id] = true
			var pos: Vector2 = xf * (subs.units[id].center as Vector2)
			if vp.has_point(pos):
				_star(pos, 7.0 if national else 4.5, Color("f2b33d") if national else Color(1.0, 0.97, 0.88))
				if z >= (CAPITAL_NAME_ZOOM if not national else 1.2):
					_capital_name(subs.units[id].name, pos, 13 if national else 11, font, placed)
	return late


func _star(pos: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(pos + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	_labels.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	_labels.draw_polyline(pts, Color(0.02, 0.05, 0.07, 0.9), 1.0, true)


func _capital_name(text: String, pos: Vector2, fs: int, font: Font, placed: Array[Rect2]) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bl := pos + Vector2(9.0, fs * 0.35)
	var box := Rect2(bl.x - 2.0, bl.y - fs, tw + 4.0, fs * 1.2)
	for r in placed:
		if r.intersects(box):
			return
	placed.append(box)
	_labels.draw_string_outline(font, bl, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.02, 0.05, 0.07, 0.85))
	_labels.draw_string(font, bl, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.97, 0.88))


func _draw_custom_labels(font: Font, xf: Transform2D, z: float, vp: Rect2, placed: Array[Rect2]) -> void:
	var subs: Subdivisions = world.subdivisions
	for id: int in subs.custom_ids:
		if sqrt(float(subs.units[id].area)) * z >= 34.0:
			_unit_label(subs.units[id], font, xf, z, vp, placed, Color(1.0, 0.95, 0.8, 0.95))


## Rótulos do cenário só aparecem com zoom e depois dos países. A lista vem da maior para a menor.
func _draw_base_labels(font: Font, xf: Transform2D, z: float, vp: Rect2, placed: Array[Rect2]) -> void:
	if z < BASE_LABEL_ZOOM:
		return
	var drawn := placed.size()
	for u: Dictionary in world.subdivisions.by_area():
		if sqrt(float(u.area)) * z < 40.0 or placed.size() - drawn > 160:
			break
		if u.base and (int(u.parent) < 0 or z >= MUN_LABEL_ZOOM):
			_unit_label(u, font, xf, z, vp, placed, Color(0.85, 0.9, 0.93, 0.8))


func _draw_labels() -> void:
	if world == null:
		return
	var font := ThemeDB.fallback_font
	var xf := get_viewport().get_canvas_transform()
	var z := _camera.zoom.x
	var vp := get_viewport_rect()
	var placed: Array[Rect2] = []
	var late_names := _draw_capitals(font, xf, z, vp, placed)
	_draw_custom_labels(font, xf, z, vp, placed)
	for f: Dictionary in features:
		if String(f.label) == "":
			continue
		var c: Country = world.by_iso.get(f.iso)
		if c == null or not c.alive:
			continue
		var screen_size := sqrt(float(f.area)) * z
		if screen_size < 30.0:
			continue
		var pos: Vector2 = xf * f.center
		if not vp.has_point(pos):
			continue
		var fs := int(clampf(screen_size * 0.15, 10.0, 20.0))
		var txt: String = c.name
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(pos.x - tw * 0.5 - 2.0, pos.y - fs * 0.6, tw + 4.0, fs * 1.2)
		var clash := false
		for r in placed:
			if r.intersects(box):
				clash = true
				break
		if clash:
			continue
		placed.append(box)
		var bl := Vector2(pos.x - tw * 0.5, pos.y + fs * 0.35)
		_labels.draw_string_outline(font, bl, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.02, 0.05, 0.07, 0.75))
		_labels.draw_string(font, bl, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.95, 0.97, 0.92))
	for item: Array in late_names:
		_capital_name(item[0], item[1], item[2], font, placed)
	_draw_base_labels(font, xf, z, vp, placed)


func bind(w: GameWorld) -> void:
	world = w
	selected = null
	hovered = null
	selected_unit = -1
	_hover_unit = -1
	marked_units = []
	_pending_claims = []
	_pending_offers = []
	draft_owner = "units"
	drawing = false
	draft.clear()
	_draft_layer.queue_redraw()
	refresh_colors()
	_borders.queue_redraw()
	_overlay.queue_redraw()
	_labels.queue_redraw()


func set_mode(m: String) -> void:
	mode = m
	refresh_colors()


func refresh_colors() -> void:
	if world == null:
		return
	for f: Dictionary in features:
		var node: MeshInstance2D = f.node
		if f.name == "Antarctica":
			node.modulate = ANTARCTICA
			continue
		var c := _owner_of(f)
		node.modulate = NEUTRAL if c == null else color_for(c)
	_borders.queue_redraw()
	_cession_layer.queue_redraw()
	_units_layer.queue_redraw()


func _political(c: Country) -> Color:
	if _palette_cache.has(c.iso):
		return _palette_cache[c.iso]
	var hues := {"NAM": 0.58, "LAM": 0.36, "EUR": 0.62, "MEA": 0.09, "AFR": 0.14, "ASI": 0.98, "OCE": 0.47}
	var h: float = hues.get(c.region, 0.5)
	var seed_val := hash(c.iso)
	var hue := fposmod(h + (seed_val % 100) / 100.0 * 0.11 - 0.055, 1.0)
	var col := Color.from_hsv(hue, 0.28 + ((seed_val >> 8) % 100) / 100.0 * 0.16, 0.42 + ((seed_val >> 16) % 100) / 100.0 * 0.16)
	_palette_cache[c.iso] = col
	return col


static func ramp(t: float, stops: Array) -> Color:
	var x := clampf(t, 0.0, 1.0) * (stops.size() - 1)
	var i := mini(int(x), stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], x - i)


const RAMP_BAD_GOOD := [Color("b23a2f"), Color("c9803d"), Color("6d6f62"), Color("4f9a79"), Color("2f9e8a")]
const RAMP_GOOD_BAD := [Color("2f9e8a"), Color("4f9a79"), Color("8d8a5e"), Color("c9803d"), Color("b23a2f")]
const RAMP_SEQ := [Color("20323e"), Color("2c5a6c"), Color("3f8c94"), Color("7cbf9b"), Color("e6d98a")]


func color_for(c: Country) -> Color:
	match mode:
		"relacoes":
			if world.player == null:
				return _political(c)
			if c == world.player:
				return Color("f2b33d")
			var d := world.diplomacy
			if d.at_war(c.idx, world.player.idx):
				return Color("e0442f")
			if d.allied(c.idx, world.player.idx):
				return Color("3b9fd8")
			return ramp((d.relation(c.idx, world.player.idx) + 100.0) / 200.0, RAMP_BAD_GOOD)
		"crescimento":
			return ramp((c.growth_yoy() + 0.03) / 0.11, RAMP_BAD_GOOD)
		"inflacao":
			return ramp(pow(clampf(c.pi_yoy / 0.3, 0.0, 1.0), 0.6), RAMP_GOOD_BAD)
		"desemprego":
			return ramp((c.unemp - 0.02) / 0.2, RAMP_GOOD_BAD)
		"divida":
			return ramp(c.debt_ratio / maxf(c.debt_tol, 0.1) * 0.5, RAMP_GOOD_BAD)
		"renda":
			return ramp(log(maxf(c.gdp_pc(), 300.0) / 300.0) / log(300.0), RAMP_SEQ)
		"estabilidade":
			return ramp(c.stability, RAMP_BAD_GOOD)
		"militar":
			return ramp(pow(c.military_power() / maxf(world.usa.military_power(), 0.01), 0.45), RAMP_SEQ)
	return _political(c)


func country_at(pos: Vector2) -> Country:
	if world:
		var moved := world.territories.owner_at(pos, world)
		if moved:
			return moved
	for i in range(features.size() - 1, -1, -1):
		var f: Dictionary = features[i]
		if not (f.rect as Rect2).has_point(pos):
			continue
		for ring: PackedVector2Array in f.rings:
			if Geometry2D.is_point_in_polygon(pos, ring):
				return _owner_of(f)
	return null


func select(c: Country) -> void:
	selected = c
	_borders.queue_redraw()
	_overlay.queue_redraw()


func focus_on(c: Country) -> void:
	if c:
		focus_on_point(c.center)


func focus_on_point(pos: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(_camera, "position", pos, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- Unidades subnacionais -------------------------------------------------------

## Contornos de tudo que pertence ao país, incluindo territórios anexados.
## Enclaves estrangeiros (Lesoto na África do Sul) são feições próprias e entram como furos.
func territory_of(c: Country) -> Dictionary:
	return world.territories.territory_of(c, world)


## force: o jogador mudou, e com ele a cor das divisas.
func refresh_units(force := false) -> void:
	var revision: int = world.subdivisions.revision
	if force or revision != _lines_revision:
		_lines_revision = revision
		_base_lines.queue_redraw()
		_mun_lines.queue_redraw()
	_units_layer.queue_redraw()
	_labels.queue_redraw()


func select_unit(id: int) -> void:
	selected_unit = id
	_units_layer.queue_redraw()


func begin_draft(color: Color, owner := "units") -> void:
	draft_owner = owner
	drawing = true
	draft.clear()
	_draft_color = color
	_draft_layer.queue_redraw()


func set_draft_color(color: Color) -> void:
	_draft_color = color
	_draft_layer.queue_redraw()


## Encerra sem avisar ninguém: usado por quem já está fechando a própria sessão.
func end_draft() -> void:
	drawing = false
	draft.clear()
	draft_owner = "units"
	_draft_layer.queue_redraw()


func set_pending(claims: Array, offers: Array) -> void:
	_pending_claims = claims
	_pending_offers = offers
	_draft_layer.queue_redraw()


func mark_units(ids: Array) -> void:
	marked_units = ids
	_units_layer.queue_redraw()


func cancel_draft() -> void:
	drawing = false
	draft.clear()
	_draft_layer.queue_redraw()
	draft_cancelled.emit()


func undo_vertex() -> void:
	if draft.is_empty():
		cancel_draft()
		return
	draft.remove_at(draft.size() - 1)
	_draft_layer.queue_redraw()
	draft_changed.emit()


func _near_first(pos: Vector2) -> bool:
	return not draft.is_empty() and draft[0].distance_to(pos) * _camera.zoom.x <= CLOSE_RADIUS_PX


func _draft_click(pos: Vector2) -> void:
	if _near_first(pos):
		if draft.size() < 3:
			draft_rejected.emit("São necessários pelo menos 3 vértices para fechar o polígono.")
			return
		if Subdivisions.crosses(draft, draft[draft.size() - 1], draft[0], true):
			draft_rejected.emit("O fechamento cruzaria o próprio traçado.")
			return
		var closed := draft.duplicate()
		drawing = false
		draft.clear()
		_draft_layer.queue_redraw()
		draft_closed.emit(closed)
		return
	if not draft.is_empty():
		var last := draft[draft.size() - 1]
		if last.distance_to(pos) * _camera.zoom.x < 3.0:
			return
		if Subdivisions.crosses(draft, last, pos):
			draft_rejected.emit("As arestas não podem se cruzar. Escolha outro ponto.")
			return
	draft.append(pos)
	_draft_layer.queue_redraw()
	draft_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if world == null or not interactive or world.busy:
		return
	if drawing and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			undo_vertex()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.pressed:
			get_viewport().gui_release_focus()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.14)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.14)
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				if _dragging and _drag_moved < 5.0:
					_on_click(event.button_index, get_canvas_transform().affine_inverse() * event.position)
				_dragging = false
	elif event is InputEventMouseMotion:
		var at: Vector2 = get_canvas_transform().affine_inverse() * event.position
		_draft_mouse = at
		if _dragging:
			_drag_moved += event.relative.length()
			_camera.position -= event.relative / _camera.zoom.x
			_clamp_camera()
			_labels.queue_redraw()
		else:
			var c := country_at(at)
			if c != hovered:
				hovered = c
				country_hovered.emit(c)
				_borders.queue_redraw()
			var u: int = world.subdivisions.unit_at(at)
			if u != _hover_unit:
				_hover_unit = u
				unit_hovered.emit(u)
				_units_layer.queue_redraw()


func _on_click(button: int, at: Vector2) -> void:
	if drawing:
		if button == MOUSE_BUTTON_LEFT:
			_draft_click(at)
		elif button == MOUSE_BUTTON_RIGHT:
			undo_vertex()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if unit_pick:
		var u: int = world.subdivisions.unit_at(at)
		if not world.owns_unit(world.player, u):
			u = -1
		unit_clicked.emit(u)
		if u >= 0:
			return
	country_clicked.emit(country_at(at))


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen
	var nz := clampf(_camera.zoom.x * factor, _min_zoom, 14.0)
	_camera.zoom = Vector2.ONE * nz
	_camera.force_update_transform()
	var after := get_canvas_transform().affine_inverse() * screen
	_camera.position += before - after
	_clamp_camera()
	_borders.queue_redraw()
	_overlay.queue_redraw()
	_labels.queue_redraw()


func _clamp_camera() -> void:
	_camera.position.x = clampf(_camera.position.x, -width * 0.5, width * 0.5)
	_camera.position.y = clampf(_camera.position.y, -width * 0.26, width * 0.26)


func _process(delta: float) -> void:
	_time += delta
	if world == null or world.busy:
		return
	var move := Vector2.ZERO
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
	if move != Vector2.ZERO:
		_camera.position += move * 520.0 * delta / _camera.zoom.x
		_clamp_camera()
		_labels.queue_redraw()
	if world.diplomacy.wars.size() > 0 or selected:
		_overlay.queue_redraw()
	if drawing:
		_draft_layer.queue_redraw()
	# Rótulos ficam em outra camada: redesenha quando a câmera muda (arraste, zoom, foco animado).
	if _camera.position != _last_cam or _camera.zoom != _last_zoom:
		if _camera.zoom != _last_zoom:
			_units_layer.queue_redraw()
			_borders.queue_redraw()
			_base_lines.modulate.a = clampf((_camera.zoom.x - BASE_LINES_ZOOM) / 0.8, 0.0, 1.0)
			_base_lines.visible = _base_lines.modulate.a > 0.0
			_mun_lines.modulate.a = clampf((_camera.zoom.x - MUN_LINES_ZOOM) / 1.2, 0.0, 1.0)
			_mun_lines.visible = _mun_lines.modulate.a > 0.0
		_last_cam = _camera.position
		_last_zoom = _camera.zoom
		_labels.queue_redraw()
	if world.refresh_map:
		world.refresh_map = false
		refresh_colors()
		refresh_units()
