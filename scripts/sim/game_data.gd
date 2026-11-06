class_name GameData
extends RefCounted
## Leitura dos dados estáticos: tabela de países e geometria do mapa.

const ADMIN1_CELL := 40.0

## População das unidades de primeiro nível, em milhões, onde o número é conhecido: censo do IBGE de 2022 e dos
## EUA de 2020, arredondados. O resto do mundo usa uma estimativa pela área (ver Subdivisions._population_weight).
const UNIT_POPULATION := {
	"BRA": {"São Paulo": 44.4, "Minas Gerais": 20.5, "Rio de Janeiro": 16.1, "Bahia": 14.1, "Paraná": 11.4, "Rio Grande do Sul": 10.9, "Pernambuco": 9.1, "Ceará": 8.8, "Pará": 8.1, "Santa Catarina": 7.6, "Goiás": 7.1, "Maranhão": 6.8, "Paraíba": 4.0, "Amazonas": 3.9, "Espírito Santo": 3.8, "Mato Grosso": 3.7, "Rio Grande do Norte": 3.3, "Piauí": 3.3, "Alagoas": 3.1, "Distrito Federal": 2.8, "Mato Grosso do Sul": 2.8, "Sergipe": 2.2, "Rondônia": 1.6, "Tocantins": 1.5, "Acre": 0.83, "Amapá": 0.73, "Roraima": 0.64},
	"USA": {"California": 39.5, "Texas": 29.1, "Florida": 21.5, "New York": 20.2, "Pennsylvania": 13.0, "Illinois": 12.8, "Ohio": 11.8, "Georgia": 10.7, "North Carolina": 10.4, "Michigan": 10.1, "New Jersey": 9.3, "Virginia": 8.6, "Washington": 7.7, "Arizona": 7.2, "Massachusetts": 7.0, "Tennessee": 6.9, "Indiana": 6.8, "Maryland": 6.2, "Missouri": 6.2, "Wisconsin": 5.9, "Colorado": 5.8, "Minnesota": 5.7, "South Carolina": 5.1, "Alabama": 5.0, "Louisiana": 4.7, "Kentucky": 4.5, "Oregon": 4.2, "Oklahoma": 4.0, "Connecticut": 3.6, "Utah": 3.3, "Iowa": 3.2, "Nevada": 3.1, "Arkansas": 3.0, "Mississippi": 3.0, "Kansas": 2.9, "New Mexico": 2.1, "Nebraska": 2.0, "Idaho": 1.8, "West Virginia": 1.8, "Hawaii": 1.5, "New Hampshire": 1.4, "Maine": 1.4, "Rhode Island": 1.1, "Montana": 1.1, "Delaware": 1.0, "South Dakota": 0.9, "North Dakota": 0.8, "Alaska": 0.7, "District of Columbia": 0.7, "Vermont": 0.6, "Wyoming": 0.6},
}
static var _map_cache := {}
## O mapa é lido por duas threads na abertura do jogo: a do mundo e a do mapa.
static var _map_lock := Mutex.new()
static var _admin1_cache := {}
static var _native_cache := {}
static var _native_rects := {}
static var _enclave_cache := {}


static func load_countries() -> Array:
	var f := FileAccess.open("res://data/countries.csv", FileAccess.READ)
	# Sem o CSV não há países: melhor um erro claro que uma queda na thread do mundo.
	if f == null:
		push_error("Dados dos países ausentes: res://data/countries.csv (%s)" % error_string(FileAccess.get_open_error()))
		return []
	var header := f.get_csv_line()
	var rows := []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < header.size():
			continue
		var row := {}
		for i in header.size():
			var k := header[i]
			if k in ["iso", "name", "region"]:
				row[k] = line[i]
			elif k == "blocs":
				row[k] = PackedStringArray(line[i].split("|", false))
			else:
				row[k] = line[i].to_float()
		rows.append(row)
	return rows


## O resultado é compartilhado: quem precisar mudar a lista deve trabalhar em uma cópia.
static func load_map() -> Dictionary:
	_map_lock.lock()
	if _map_cache.is_empty():
		var f := FileAccess.open("res://data/map.json", FileAccess.READ)
		_map_cache = JSON.parse_string(f.get_as_text())
	_map_lock.unlock()
	return _map_cache


## Contorno original de cada país no mapa: {iso: [anéis]}. Áreas neutras ficam em "".
static func native_rings() -> Dictionary:
	if _native_cache.is_empty():
		for feat: Dictionary in load_map().features:
			var iso: String = feat.iso
			if not _native_cache.has(iso):
				_native_cache[iso] = []
			for shape: Array in feat.shapes:
				_native_cache[iso].append(_flat_points(shape[0]))
	return _native_cache


## Anéis de outros países inteiramente dentro deste: [{"iso", "ring"}]. O mapa tem milhares de ilhas,
## então as caixas ficam guardadas e o resultado de cada país só é calculado uma vez.
static func native_enclaves(iso: String) -> Array:
	if _enclave_cache.has(iso):
		return _enclave_cache[iso]
	var all := native_rings()
	if _native_rects.is_empty():
		for key: String in all:
			var rects := []
			for ring: PackedVector2Array in all[key]:
				rects.append(Subdivisions._bounds(ring))
			_native_rects[key] = rects
	var out := []
	var own: Array = all.get(iso, [])
	var own_rects: Array = _native_rects.get(iso, [])
	for other: String in all:
		if other == iso:
			continue
		for i in all[other].size():
			var ring: PackedVector2Array = all[other][i]
			var box: Rect2 = _native_rects[other][i]
			for k in own.size():
				if (own_rects[k] as Rect2).encloses(box) and Geometry2D.is_point_in_polygon(Subdivisions._label_point([ring]), own[k]):
					out.append({"iso": other, "ring": ring})
					break
	_enclave_cache[iso] = out
	return out


static func admin1_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / ADMIN1_CELL), floori(pos.y / ADMIN1_CELL))


static func _flat_points(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(flat.size() / 2)
	for i in pts.size():
		pts[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
	return pts


## Unidades subnacionais do cenário. A leitura é única: as geometrias são compartilhadas entre partidas.
static func load_admin1() -> Dictionary:
	if not _admin1_cache.is_empty():
		return _admin1_cache
	var f := FileAccess.open("res://data/admin1.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	var units := []
	for src: Dictionary in raw.units:
		var pieces := []
		for flat: Array in src.s:
			pieces.append(_flat_points(flat))
		var b: Array = src.b
		units.append({
			"name": src.n, "owner": src.o, "type": src.t, "pieces": pieces, "area": float(src.a),
			"center": Vector2(src.c[0], src.c[1]),
			"rect": Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1])),
		})
	var arcs := []
	for a: Array in raw.arcs:
		arcs.append([int(a[0]), int(a[1]), _flat_points(a[2])])
	var mun_arcs := _load_municipios(units)
	var capitals := _load_capitals(units)
	# Grade de busca por ponto; em cada célula, da menor para a maior, para enclaves ganharem no clique.
	var order := range(units.size())
	order.sort_custom(func(x, y): return float(units[x].area) < float(units[y].area))
	var grid := {}
	for id: int in order:
		var r: Rect2 = units[id].rect
		var c0 := admin1_cell(r.position)
		var c1 := admin1_cell(r.end)
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var cell := Vector2i(cx, cy)
				if not grid.has(cell):
					grid[cell] = []
				grid[cell].append(id)
	_admin1_cache = {"units": units, "arcs": arcs, "mun_arcs": mun_arcs, "grid": grid, "capitals": capitals}
	return _admin1_cache


## Capitais nacionais: {iso: id da unidade}. Quando a capital não é uma província inteira, vira uma
## unidade pequena dentro dela, depois de todas as outras na lista.
static func _load_capitals(units: Array) -> Dictionary:
	var f := FileAccess.open("res://data/capitais.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	var out := {}
	for src: Dictionary in raw.capitals:
		if src.has("unit"):
			out[src.iso] = int(src.unit)
			units[int(src.unit)].name = src.n
			continue
		var pieces := []
		for flat: Array in src.s:
			pieces.append(_flat_points(flat))
		var b: Array = src.b
		out[src.iso] = units.size()
		units.append({
			"name": src.n, "owner": src.iso, "type": Subdivisions.CITY_TYPE, "city": true, "pieces": pieces, "area": float(src.a),
			"parent": int(src.parent), "center": Vector2(src.c[0], src.c[1]),
			"rect": Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1])),
		})
	return out


## Municípios do Brasil: entram na mesma lista, como filhos dos estados. Devolve as divisas entre eles.
static func _load_municipios(units: Array) -> Array:
	var f := FileAccess.open("res://data/municipios.json", FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	var states := {}
	for i in units.size():
		if units[i].owner == "BRA":
			states[units[i].name] = i
	var offset := units.size()
	for src: Dictionary in raw.units:
		var pieces := []
		for flat: Array in src.s:
			pieces.append(_flat_points(flat))
		var b: Array = src.b
		units.append({
			"name": src.n, "owner": "BRA", "type": "Município", "pieces": pieces, "area": float(src.a),
			"parent": states[src.uf], "center": Vector2(src.c[0], src.c[1]),
			"rect": Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1])),
		})
	var arcs := []
	for a: Array in raw.arcs:
		arcs.append([int(a[0]) + offset, int(a[1]) + offset, _flat_points(a[2])])
	return arcs


static func map_info() -> Dictionary:
	var out := {}
	for feat: Dictionary in load_map().features:
		var iso: String = feat.iso
		if iso == "" or String(feat.label) == "":
			continue
		out[iso] = {
			"center": Vector2(feat.center[0], feat.center[1]),
			"area": float(feat.area),
		}
	return out
