class_name Territories
extends RefCounted
## Fronteiras alteradas por guerras e tratados. O mapa de base não muda: cada cessão é uma
## área com dono novo, desenhada por cima dele. Cessões nunca se sobrepõem, e uma área que
## volta ao país de origem simplesmente deixa de ser cessão.

var cessions: Array = []
var next_id := 0
## Sobe a cada mudança, para o mapa saber quando redesenhar.
var revision := 0

var _outlines := {}


func owner_at(pos: Vector2, world: GameWorld) -> Country:
	for i in range(cessions.size() - 1, -1, -1):
		var c: Dictionary = cessions[i]
		if not (c.rect as Rect2).has_point(pos):
			continue
		for piece: PackedVector2Array in c.pieces:
			if Geometry2D.is_point_in_polygon(pos, piece):
				return world.resolve_owner(c.to)
	return null


## Contornos atuais do país: terras originais e anexadas, mais o que ganhou; "holes" é o que
## perdeu e os enclaves estrangeiros (Lesoto na África do Sul).
func territory_of(c: Country, world: GameWorld) -> Dictionary:
	var rings := []
	var holes := []
	var all := GameData.native_rings()
	var own := world.owned_isos(c)
	for iso: String in own:
		rings.append_array(all.get(iso, []))
	var native := rings.duplicate()
	for iso: String in own:
		for enclave: Dictionary in GameData.native_enclaves(iso):
			if not enclave.iso in own:
				holes.append(enclave.ring)
	for cession: Dictionary in cessions:
		if world.resolve_owner(cession.to) == c:
			rings.append_array(cession.pieces)
			continue
		for piece: PackedVector2Array in cession.pieces:
			if _inside_any(Subdivisions._label_point([piece]), native):
				holes.append(piece)
	return {"rings": rings, "holes": holes}


func area_of(c: Country, world: GameWorld) -> float:
	var t := territory_of(c, world)
	var total := Subdivisions.total_area(t.rings)
	for hole: PackedVector2Array in t.holes:
		total -= Subdivisions.polygon_area(hole)
	return maxf(total, 0.001)


## Recorta um polígono desenhado pelo território atual do país.
func clip_to(points: PackedVector2Array, c: Country, world: GameWorld) -> Array:
	var t := territory_of(c, world)
	var pieces := Subdivisions.intersect_all(points, t.rings)
	for hole: PackedVector2Array in t.holes:
		pieces = Subdivisions.subtract(pieces, hole)
	return Subdivisions._clean(pieces)


## Passa as peças de from para to, com as unidades subnacionais. Devolve a fração do território perdida.
func apply(pieces: Array, from: Country, to: Country, world: GameWorld) -> float:
	if pieces.is_empty():
		return 0.0
	var share := clampf(Subdivisions.total_area(pieces) / area_of(from, world), 0.0, 1.0)
	for cession: Dictionary in cessions.duplicate():
		var left: Array = cession.pieces
		for cut: PackedVector2Array in pieces:
			left = Subdivisions.subtract(left, cut)
		left = Subdivisions._clean(left)
		if left.is_empty():
			cessions.erase(cession)
		else:
			_set_pieces(cession, left)
	var remaining := pieces
	var all := GameData.native_rings()
	for iso: String in world.owned_isos(to):
		for ring: PackedVector2Array in all.get(iso, []):
			remaining = Subdivisions.subtract(remaining, ring)
	remaining = Subdivisions._clean(remaining)
	if not remaining.is_empty():
		var cession := {"id": next_id, "from": from.iso, "to": to.iso}
		next_id += 1
		_set_pieces(cession, remaining)
		cessions.append(cession)
	var capital: int = world.subdivisions.capital_of(from.iso)
	var capital_name: String = world.subdivisions.units[capital].name if capital >= 0 else ""
	world.subdivisions.transfer_area(pieces, world.owned_isos(from), to.iso)
	if capital >= 0 and world.subdivisions.capital_of(from.iso) < 0:
		world.emit_news(tr("%s perde a capital, %s, para %s.") % [from.name, capital_name, to.name], "guerra", from)
	revision += 1
	_outlines.clear()
	world.refresh_map = true
	return share


func _set_pieces(cession: Dictionary, pieces: Array) -> void:
	cession["pieces"] = pieces
	cession["rect"] = Subdivisions._bounds_all(pieces)
	cession["outline"] = Subdivisions._outline(pieces)


## Tratado entre nações da IA ou imposto ao jogador: cede unidades inteiras, das mais próximas
## do vencedor para as mais distantes, até chegar perto da fração. Devolve a fração cedida.
func auto_cede(from: Country, to: Country, share: float, world: GameWorld) -> float:
	var subs := world.subdivisions
	var target := share * area_of(from, world)
	var options := []
	for iso: String in world.owned_isos(from):
		for id: int in subs.roots_of(iso):
			options.append(subs.units[id])
	options.sort_custom(func(a, b): return (a.center as Vector2).distance_squared_to(to.center) < (b.center as Vector2).distance_squared_to(to.center))
	var pieces := []
	var taken := 0.0
	for u: Dictionary in options:
		if taken >= target:
			break
		# Mantém o país vivo: nunca entrega a última unidade.
		if float(u.area) + taken <= target * 1.4 and pieces.size() < options.size() - 1:
			pieces.append_array(u.pieces)
			taken += float(u.area)
	return apply(pieces, from, to, world)


## Contorno do país em pares de pontos, considerando o que ele ganhou e perdeu.
## Devolve vazio quando as fronteiras dele são as originais.
func changed_outline(c: Country, world: GameWorld) -> PackedVector2Array:
	if _outlines.has(c.iso):
		return _outlines[c.iso]
	var touched := false
	for cession: Dictionary in cessions:
		var from: Country = world.resolve_owner(cession.from)
		if from == c or world.resolve_owner(cession.to) == c:
			touched = true
			break
	var out := PackedVector2Array()
	if touched:
		var t := territory_of(c, world)
		var pieces: Array = t.rings
		for hole: PackedVector2Array in t.holes:
			pieces = Subdivisions.subtract(pieces, hole)
		out = Subdivisions._outline(pieces)
	_outlines[c.iso] = out
	return out


static func _inside_any(p: Vector2, rings: Array) -> bool:
	for ring: PackedVector2Array in rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false


func to_dict() -> Dictionary:
	return {"cessions": cessions, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	cessions = d.get("cessions", [])
	next_id = d.get("next_id", 0)
	revision += 1
	_outlines.clear()
