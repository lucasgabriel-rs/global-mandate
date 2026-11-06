class_name Subdivisions
extends RefCounted
## Divisão interna dos países. O cenário traz as unidades de 1º nível de todos os países
## (data/admin1.json); o jogador cria novas dentro do próprio território.
## Cada país tem os próprios tipos de unidade. As formas ficam em coordenadas do mapa.
## Uma unidade desenhada é recortada pelo que a contém (território nacional e unidade-mãe)
## e pelas irmãs já existentes, sem sobreposição.

const MIN_PIECE_AREA := 0.01
const MIN_UNIT_AREA := 0.05
const GAP_CLOSE := 0.15
const MAX_GAP_AREA := 2.0
const SAVE_VERSION := 4
## Primeiro id de unidade criada pelo jogador em cada versão do save.
const OLD_BASE_COUNT := {2: 4220, 3: 9784}
const CITY_TYPE := "Cidade"
## Faixa própria para os tipos das capitais, sem colidir com os ids guardados em saves antigos.
const CITY_TYPE_FIRST_ID := 1000000
const DEFAULT_LOWER_TYPE := "Município"
## Capitais do cenário. Só o Brasil tem municípios, e portanto só ele tem capitais prontas.
const BRAZIL_CAPITAL := "Brasília"
const BRAZIL_STATE_CAPITALS := {
	"Acre": "Rio Branco", "Alagoas": "Maceió", "Amapá": "Macapá", "Amazonas": "Manaus", "Bahia": "Salvador",
	"Ceará": "Fortaleza", "Distrito Federal": "Brasília", "Espírito Santo": "Vitória", "Goiás": "Goiânia",
	"Maranhão": "São Luís", "Mato Grosso": "Cuiabá", "Mato Grosso do Sul": "Campo Grande",
	"Minas Gerais": "Belo Horizonte", "Pará": "Belém", "Paraíba": "João Pessoa", "Paraná": "Curitiba",
	"Pernambuco": "Recife", "Piauí": "Teresina", "Rio de Janeiro": "Rio de Janeiro", "Rio Grande do Norte": "Natal",
	"Rio Grande do Sul": "Porto Alegre", "Rondônia": "Porto Velho", "Roraima": "Boa Vista",
	"Santa Catarina": "Florianópolis", "São Paulo": "São Paulo", "Sergipe": "Aracaju", "Tocantins": "Palmas",
}
const PALETTE := [Color("f2b33d"), Color("4fb3d9"), Color("4cc794"), Color("e0719a"), Color("a78bfa"), Color("ec7a43"), Color("9ad14b"), Color("3fd0c9")]
const NAME_PARTS := {
	"NAM": [["Spring", "Oak", "Maple", "Clear", "River", "Stone", "Green", "Fair", "Lake", "Red", "Silver", "Cedar"], ["field", "ton", "wood", "dale", "ford", "ville", "land", "view", "brook"], ["New ", "Fort ", "North ", "West "]],
	"LAM": [["Ita", "Ara", "Pira", "Mara", "Tere", "Guara", "Cara", "Bela", "Sol", "Agua", "Mon", "Alva", "Pari"], ["tinga", "guaia", "rema", "nópolis", "lândia", "via", "tiba", "rama", "quara", "mirim"], ["Nova ", "Alto ", "Porto ", "Monte "]],
	"EUR": [["Alt", "Bran", "Val", "Mar", "Nor", "Kars", "Lin", "Ros", "Mont", "Wal", "Ber", "Sten"], ["burg", "heim", "ona", "stad", "ovia", "mark", "enza", "berg", "ania"], ["Nova ", "Alta ", "Nord "]],
	"MEA": [["Qas", "Sha", "Nah", "Zar", "Mas", "Jaz", "Har", "Kha", "Sal", "Riz"], ["ra", "bad", "mir", "iya", "far", "dun", "ein", "qan"], ["Al ", "Dar ", "Wadi ", "Bani "]],
	"AFR": [["Ka", "Mbo", "Nya", "Zu", "Lu", "Ta", "Oko", "Ba", "Ngo", "Ki", "Ama", "Sa"], ["nga", "mbe", "wanda", "lu", "goma", "ra", "dzi", "ti", "kuru"], []],
	"ASI": [["Shan", "Xin", "Hai", "Nam", "Kan", "Rao", "Tan", "Sin", "Yun", "Bao", "Mei", "Lan"], ["pur", "abad", "gawa", "zhou", "nan", "ling", "yama", "giri", "wan"], []],
	"OCE": [["Wai", "Tara", "Koro", "Mana", "Bay", "Ter", "Ara", "Kin", "Tama"], ["roa", "nui", "wick", "ton", "vale", "kawa", "ki", "ra"], ["New ", "Port "]],
}

var types := {}
var units := {}
## Unidades criadas pelo jogador, sempre com a mãe antes das filhas.
var custom_ids: Array = []
## Quem tem qual capital. Chave: id da unidade ou iso do país. Valor: id da unidade que é a capital.
var capitals := {}
var arcs: Array = []
var mun_arcs: Array = []
## Sobe quando unidades somem ou mudam de dono, os únicos casos em que as divisas precisam ser refeitas.
var revision := 0
var base_count := 0
var next_type_id := 0
var next_unit_id := 0
var name_counter := 0

var _roots := {}
var _kids := {}
var _grid := {}
var _by_area: Array = []
var _city_types := 0


# --- Cenário ---------------------------------------------------------------------

func load_base(data: Dictionary) -> void:
	var by_key := {}
	var totals := {}
	for src: Dictionary in data.units:
		if not src.has("parent"):
			totals[src.owner] = float(totals.get(src.owner, 0.0)) + float(src.area)
	var id := 0
	for src: Dictionary in data.units:
		var owner: String = src.owner
		var type_key: String = owner + "|" + String(src.type)
		if not by_key.has(type_key):
			by_key[type_key] = _add_city_type(owner) if src.get("city", false) else add_type(src.type, owner)
		units[id] = {
			"id": id, "name": src.name, "type": by_key[type_key], "type0": by_key[type_key], "parent": src.get("parent", -1), "owner": owner, "base": true,
			"pieces": src.pieces, "rect": src.rect, "center": src.center, "area": src.area,
			"share": float(src.area) / maxf(float(totals[owner]), 0.001),
			"pop_w": _population_weight(float(src.area), String(src.name)),
		}
		# Onde o censo é conhecido, vale o censo, para as unidades de primeiro nível.
		if not src.has("parent") and GameData.UNIT_POPULATION.has(owner) and GameData.UNIT_POPULATION[owner].has(src.name):
			units[id]["pop_w"] = float(GameData.UNIT_POPULATION[owner][src.name])
			units[id]["pop_known"] = true
		id += 1
	for owner: String in totals:
		if not by_key.has(owner + "|" + DEFAULT_LOWER_TYPE):
			add_type(DEFAULT_LOWER_TYPE, owner)
	base_count = id
	next_unit_id = id
	arcs = data.arcs
	mun_arcs = data.mun_arcs
	_grid = data.grid
	_reindex()
	_seed_capitals()
	for iso: String in data.capitals:
		capitals[iso] = data.capitals[iso]


func _add_city_type(owner: String) -> int:
	var id: int = CITY_TYPE_FIRST_ID + _city_types
	_city_types += 1
	types[id] = {"id": id, "name": CITY_TYPE, "owner": owner, "color": PALETTE[types_of(owner).size() % PALETTE.size()]}
	return id


func _seed_capitals() -> void:
	for id: int in roots_of("BRA"):
		var wanted: String = BRAZIL_STATE_CAPITALS.get(units[id].name, "")
		for kid: int in children_of(id):
			if units[kid].name == wanted:
				capitals[id] = kid
				if wanted == BRAZIL_CAPITAL:
					capitals["BRA"] = kid
				break


func _reindex() -> void:
	revision += 1
	_roots.clear()
	_kids.clear()
	for u: Dictionary in units.values():
		_link(u)
	_by_area.clear()
	_prune_capitals()


## Capital de unidade precisa existir e continuar dentro dela. Quem mudou de dono sai em _change_owner.
func _prune_capitals() -> void:
	for holder: Variant in capitals.keys():
		var id: int = capitals[holder]
		if not units.has(id):
			capitals.erase(holder)
		elif holder is int and (not units.has(holder) or holder == id or not holder in chain_of(id)):
			capitals.erase(holder)


func capital_of(holder: Variant) -> int:
	return capitals.get(holder, -1)


func is_capital(id: int) -> bool:
	return id in capitals.values()


## De quem esta unidade é capital: ids de unidades e isos de países.
func holders_of(id: int) -> Array:
	return capitals.keys().filter(func(holder): return capitals[holder] == id)


## Define ou troca a capital. A de uma unidade precisa estar dentro dela; a de um país, ser uma unidade dele.
func set_capital(holder: Variant, id: int) -> Dictionary:
	if not units.has(id):
		return {"ok": false, "msg": tr("Essa unidade não existe mais.")}
	if holder is int:
		if not units.has(holder):
			return {"ok": false, "msg": tr("Essa unidade não existe mais.")}
		if holder == id or not holder in chain_of(id):
			return {"ok": false, "msg": tr("%s não fica dentro de %s.") % [units[id].name, units[holder].name]}
	capitals[holder] = id
	return {"ok": true, "msg": ""}


func clear_capital(holder: Variant) -> void:
	capitals.erase(holder)


func _link(u: Dictionary) -> void:
	if int(u.parent) < 0:
		if not _roots.has(u.owner):
			_roots[u.owner] = []
		_roots[u.owner].append(u.id)
	else:
		if not _kids.has(u.parent):
			_kids[u.parent] = []
		_kids[u.parent].append(u.id)


# --- Tipos -----------------------------------------------------------------------

func add_type(type_name: String, owner: String) -> int:
	var id := next_type_id
	next_type_id += 1
	var final_name := type_name
	var existing := types_of(owner).size()
	var n := existing + 1
	while final_name == "" or has_type_name(final_name, owner, -1):
		final_name = tr("Tipo %d") % n
		n += 1
	types[id] = {"id": id, "name": final_name, "owner": owner, "color": PALETTE[existing % PALETTE.size()]}
	return id


func types_of(owner: String) -> Array:
	var out := []
	for t: Dictionary in types.values():
		if t.owner == owner:
			out.append(t)
	return out


func has_type_name(type_name: String, owner: String, except_id: int) -> bool:
	for t: Dictionary in types_of(owner):
		if t.id != except_id and String(t.name).to_lower() == type_name.to_lower():
			return true
	return false


func get_type(id: int) -> Dictionary:
	return types.get(id, {})


func rename_type(id: int, type_name: String) -> Dictionary:
	var clean := type_name.strip_edges()
	if clean == "":
		return {"ok": false, "msg": tr("O tipo precisa de um nome.")}
	if has_type_name(clean, types[id].owner, id):
		return {"ok": false, "msg": tr("Já existe um tipo chamado %s.") % clean}
	types[id].name = clean
	return {"ok": true, "msg": ""}


## Quantas unidades usam cada tipo. Uma passada só, para a lista de tipos não varrer tudo por linha.
func type_counts() -> Dictionary:
	var out := {}
	for u: Dictionary in units.values():
		out[u.type] = int(out.get(u.type, 0)) + 1
	return out


func units_of_type(id: int) -> int:
	var n := 0
	for u: Dictionary in units.values():
		if u.type == id:
			n += 1
	return n


func remove_type(id: int) -> Dictionary:
	if types_of(types[id].owner).size() <= 1:
		return {"ok": false, "msg": tr("É preciso manter pelo menos um tipo.")}
	var used := units_of_type(id)
	if used > 0:
		return {"ok": false, "msg": tr("%s ainda tem %d unidade(s). Mude o tipo delas ou apague-as antes.") % [types[id].name, used]}
	types.erase(id)
	return {"ok": true, "msg": ""}


# --- Hierarquia ------------------------------------------------------------------

## O cenário não traz população por unidade: ela é estimada. Gente se concentra menos do que a área cresce, e cada
## lugar tem o próprio fator, sempre o mesmo para o mesmo nome.
static func _population_weight(area: float, unit_name: String) -> float:
	return sqrt(maxf(area, 0.0001)) * (0.35 + float(absi(hash(unit_name)) % 1000) / 1000.0 * 1.6)


func population_weight(u: Dictionary) -> float:
	var w := float(u.get("pop_w", _population_weight(float(u.get("area", 1.0)), String(u.name))))
	# A capital concentra gente, salvo se o número já vem do censo.
	return w * (2.5 if not u.get("pop_known", false) and is_capital(u.id) else 1.0)


## Partes de todas as unidades de primeiro nível de um país, de uma vez só: é o que a eleição usa.
func root_shares(owner: String) -> Dictionary:
	var capital_ids := {}
	for held: Variant in capitals.values():
		capital_ids[held] = true
	var out := {}
	var total := 0.0
	for id: int in roots_of(owner):
		var u: Dictionary = units[id]
		var w := float(u.get("pop_w", _population_weight(float(u.get("area", 1.0)), String(u.name)))) * (2.5 if capital_ids.has(id) and not u.get("pop_known", false) else 1.0)
		out[id] = w
		total += w
	for id: int in out:
		out[id] = float(out[id]) / maxf(total, 0.0001)
	return out


## Parte da população do país que vive nesta unidade, de 0 a 1.
func pop_share(id: int) -> float:
	var u: Dictionary = units[id]
	var parent: int = u.parent
	var siblings: Array = children_of(parent) if parent >= 0 else roots_of(u.owner)
	var total := 0.0
	for s: int in siblings:
		total += population_weight(units[s])
	var mine := population_weight(u) / maxf(total, 0.0001)
	return mine * pop_share(parent) if parent >= 0 and units.has(parent) else mine


func roots_of(owner: String) -> Array:
	return _roots.get(owner, [])


func children_of(parent_id: int) -> Array:
	return _kids.get(parent_id, [])


## Percorre a árvore com as mães antes das filhas: [{unit, depth}, ...].
func walk_ids(ids: Array, depth := 0) -> Array:
	var out := []
	for id: int in ids:
		out.append({"unit": units[id], "depth": depth})
		out.append_array(walk_ids(children_of(id), depth + 1))
	return out


func walk_country(owner: String) -> Array:
	return walk_ids(roots_of(owner))


func depth_of(id: int) -> int:
	var depth := 0
	var u: Dictionary = units.get(id, {})
	while not u.is_empty() and int(u.parent) >= 0:
		depth += 1
		u = units.get(u.parent, {})
	return depth


func path_of(id: int) -> String:
	var parts := []
	var u: Dictionary = units.get(id, {})
	while not u.is_empty():
		parts.push_front(u.name)
		u = units.get(u.parent, {})
	return " › ".join(parts)


## Do nível mais alto até a própria unidade.
func chain_of(id: int) -> Array:
	var out := []
	var u: Dictionary = units.get(id, {})
	while not u.is_empty():
		out.push_front(u.id)
		u = units.get(u.parent, {})
	return out


func count_descendants(id: int) -> int:
	return walk_ids(children_of(id)).size()


func delete_unit(id: int) -> void:
	for e: Dictionary in walk_ids([id]):
		var target: int = e.unit.id
		units.erase(target)
		custom_ids.erase(target)
		_kids.erase(target)
	_reindex()


func rename_unit(id: int, unit_name: String) -> Dictionary:
	var clean := unit_name.strip_edges()
	if clean == "":
		return {"ok": false, "msg": tr("A unidade precisa de um nome.")}
	units[id].name = clean
	return {"ok": true, "msg": ""}


## Funde unidades vizinhas com a mesma mãe. A resultante herda nome e tipo da primeira,
## e as filhas de todas passam para ela.
func merge_units(ids: Array) -> Dictionary:
	if ids.size() < 2:
		return {"ok": false, "msg": tr("Escolha pelo menos duas unidades.")}
	var first: Dictionary = units[ids[0]]
	for id: int in ids:
		if units[id].parent != first.parent or units[id].owner != first.owner:
			return {"ok": false, "msg": tr("Só é possível fundir unidades do mesmo nível, dentro da mesma mãe.")}
	if not _all_connected(ids):
		return {"ok": false, "msg": tr("As unidades precisam fazer divisa entre si.")}
	var pieces := []
	var plain := true
	var share := 0.0
	var kids := []
	for id: int in ids:
		pieces.append_array(units[id].pieces)
		plain = plain and bool(units[id].get("plain", units[id].base))
		share += float(units[id].share)
		kids.append_array(children_of(id))
	var new_id := next_unit_id
	next_unit_id += 1
	var u := {
		"id": new_id, "name": first.name, "type": first.type, "parent": first.parent, "owner": first.owner, "base": false,
		"plain": plain, "share": share,
	}
	_set_geometry(u, _union(pieces))
	var merged_w := 0.0
	for id: int in ids:
		merged_w += float(units[id].get("pop_w", _population_weight(float(units[id].get("area", 1.0)), String(units[id].name))))
	u["pop_w"] = merged_w
	for id: int in ids:
		units.erase(id)
		custom_ids.erase(id)
	units[new_id] = u
	custom_ids.append(new_id)
	for kid: int in kids:
		units[kid].parent = new_id
	# A fundida herda o papel de capital das originais e a capital da primeira que tiver uma.
	for holder: Variant in capitals.keys():
		if capitals[holder] in ids:
			capitals[holder] = new_id
	for id: int in ids:
		if capitals.has(id):
			if not capitals.has(new_id):
				capitals[new_id] = capitals[id]
			capitals.erase(id)
	_sort_custom()
	_reindex()
	return {"ok": true, "msg": "", "id": new_id}


## Une as peças que se tocam, sem deixar a antiga divisa por dentro. Os dados nem sempre têm a mesma
## linha dos dois lados, então a união é feita com as peças levemente infladas, para fechar as frestas.
## Um furo de verdade, como um enclave, mantém as peças separadas.
static func _union(pieces: Array) -> Array:
	var out: Array = pieces.duplicate()
	var changed := true
	while changed:
		changed = false
		for i in out.size():
			for j in range(i + 1, out.size()):
				if not _bounds(out[i]).grow(0.01).intersects(_bounds(out[j])):
					continue
				var joined := _join_closing_gaps(out[i], out[j])
				if not joined.is_empty():
					out[i] = joined
					out.remove_at(j)
					changed = true
					break
			if changed:
				break
	return out


static func _join_closing_gaps(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var grown_a := _grown(a)
	var grown_b := _grown(b)
	if grown_a.is_empty() or grown_b.is_empty():
		return PackedVector2Array()
	var merged := Geometry2D.merge_polygons(grown_a, grown_b)
	if merged.is_empty():
		return PackedVector2Array()
	var outer: PackedVector2Array = merged[0]
	for p: PackedVector2Array in merged:
		if polygon_area(p) > polygon_area(outer):
			outer = p
	for p: PackedVector2Array in merged:
		# Peça separada ou furo grande: não é fresta, a união não se aplica.
		if p != outer and (polygon_area(p) > MAX_GAP_AREA or Geometry2D.is_polygon_clockwise(p) == Geometry2D.is_polygon_clockwise(outer)):
			return PackedVector2Array()
	var shrunk := Geometry2D.offset_polygon(outer, -GAP_CLOSE)
	if shrunk.size() != 1 or Geometry2D.triangulate_polygon(shrunk[0]).is_empty():
		return PackedVector2Array()
	return shrunk[0]


## Inflar um contorno sinuoso cria furinhos internos: fica só a borda externa, se o resto for desprezível.
static func _grown(p: PackedVector2Array) -> PackedVector2Array:
	var parts := Geometry2D.offset_polygon(p, GAP_CLOSE)
	if parts.is_empty():
		return PackedVector2Array()
	var outer: PackedVector2Array = parts[0]
	var total := 0.0
	for part: PackedVector2Array in parts:
		total += polygon_area(part)
		if polygon_area(part) > polygon_area(outer):
			outer = part
	return outer if total - polygon_area(outer) <= MAX_GAP_AREA else PackedVector2Array()


func _all_connected(ids: Array) -> bool:
	var reached := [ids[0]]
	var pending: Array = ids.slice(1)
	var grew := true
	while grew and not pending.is_empty():
		grew = false
		for id: int in pending.duplicate():
			for other: int in reached:
				if _touching(units[id], units[other]):
					reached.append(id)
					pending.erase(id)
					grew = true
					break
	return pending.is_empty()


static func _touching(a: Dictionary, b: Dictionary) -> bool:
	if not (a.rect as Rect2).grow(0.1).intersects(b.rect):
		return false
	for p: PackedVector2Array in a.pieces:
		var box := _bounds(p).grow(0.1)
		for q: PackedVector2Array in b.pieces:
			if not box.intersects(_bounds(q)):
				continue
			for grown: PackedVector2Array in Geometry2D.offset_polygon(p, 0.05):
				if not Geometry2D.intersect_polygons(grown, q).is_empty():
					return true
	return false


## Desmembra: a parte da unidade dentro do polígono vira uma unidade nova, irmã da original.
## As filhas ficam com a parte onde está o centro delas.
func split_unit(id: int, points: PackedVector2Array, region: String, dry_run := false) -> Dictionary:
	var u: Dictionary = units[id]
	var inside := _clean(intersect_all_pieces(u.pieces, points))
	var outside: Array = u.pieces
	outside = _clean(subtract(outside, points))
	if total_area(inside) < MIN_UNIT_AREA:
		return {"ok": false, "msg": tr("O polígono não cobre uma parte de %s.") % u.name}
	if total_area(outside) < MIN_UNIT_AREA:
		return {"ok": false, "msg": tr("O polígono cobre %s inteira: não sobra nada para desmembrar.") % u.name}
	if dry_run:
		return {"ok": true, "msg": ""}
	var new_id := _split_off(u, inside, outside, _generate_name(region), u.owner, u.type)
	return {"ok": true, "msg": "", "id": new_id}


func _split_off(u: Dictionary, inside: Array, outside: Array, new_name: String, owner: String, type_id: int, move_kids := true) -> int:
	var whole := total_area(inside) + total_area(outside)
	var part := total_area(inside) / maxf(whole, 0.001)
	var new_id := next_unit_id
	next_unit_id += 1
	var parent_w := float(u.get("pop_w", _population_weight(float(u.get("area", 1.0)), String(u.name))))
	u["pop_w"] = parent_w * (1.0 - part)
	var fresh := {
		"pop_w": parent_w * part,
		"id": new_id, "name": new_name, "type": type_id, "parent": u.parent, "owner": owner, "base": false,
		"plain": bool(u.get("plain", u.base)), "share": float(u.share) * part,
	}
	_set_geometry(fresh, inside)
	u.share = float(u.share) * (1.0 - part)
	_set_geometry(u, outside)
	u["reshaped"] = true
	units[new_id] = fresh
	custom_ids.append(new_id)
	if move_kids:
		for kid: int in children_of(u.id).duplicate():
			if _contains(fresh, units[kid].center):
				units[kid].parent = new_id
		# Se a capital foi junto com a parte nova, é dela que passa a ser capital.
		if capitals.has(u.id) and new_id in chain_of(capitals[u.id]):
			capitals[new_id] = capitals[u.id]
			capitals.erase(u.id)
	_sort_custom()
	_reindex()
	return new_id


func _set_geometry(u: Dictionary, pieces: Array) -> void:
	u["pieces"] = pieces
	u["rect"] = _bounds_all(pieces)
	u["center"] = _label_point(pieces)
	u["area"] = total_area(pieces)
	u.erase("outline")


## A mãe sempre antes da filha, ordem de que o desenho e a busca por ponto dependem.
func _sort_custom() -> void:
	custom_ids.sort_custom(func(a, b): return depth_of(a) < depth_of(b))


## Muda de país o que está nas peças: unidade inteira troca de dono, unidade cortada se divide.
func transfer_area(pieces: Array, from_isos: Array, to_iso: String) -> void:
	var box := _bounds_all(pieces)
	var roots := []
	for iso: String in from_isos:
		roots.append_array(roots_of(iso))
	for id: int in roots:
		var u: Dictionary = units[id]
		if not (u.rect as Rect2).intersects(box):
			continue
		_transfer_unit(id, pieces, box, -1, to_iso)
	_reindex()


## Passa ao novo país a parte da unidade dentro das peças e faz o mesmo com as filhas dela.
## new_parent é a mãe do lado do novo país (-1 para o nível mais alto).
func _transfer_unit(id: int, pieces: Array, box: Rect2, new_parent: int, to_iso: String) -> void:
	var u: Dictionary = units[id]
	var inside := _clean(_intersect_pieces(u.pieces, pieces))
	var inside_area := total_area(inside)
	if inside_area < minf(MIN_UNIT_AREA, float(u.area) * 0.5):
		return
	var type_id := _matching_type(get_type(u.type).get("name", "Região"), to_iso)
	var outside: Array = []
	if inside_area < float(u.area) * 0.98:
		outside = u.pieces
		for cut: PackedVector2Array in pieces:
			outside = subtract(outside, cut)
		outside = _clean(outside)
	if outside.is_empty():
		_change_owner(id, to_iso, type_id)
		if new_parent >= 0 and capitals.get(u.parent, -1) == id:
			capitals[new_parent] = id
		u.parent = new_parent
		_reindex()
		return
	var fresh := _split_off(u, inside, outside, u.name, to_iso, type_id, false)
	units[fresh].parent = new_parent
	_reindex()
	for kid: int in children_of(id).duplicate():
		if (units[kid].rect as Rect2).intersects(box):
			_transfer_unit(kid, pieces, box, fresh, to_iso)


func _change_owner(id: int, owner: String, type_id: int) -> void:
	# Um país não mantém como capital uma unidade que passou para outro.
	var moved := [id]
	for e: Dictionary in walk_ids(children_of(id)):
		moved.append(e.unit.id)
	for holder: Variant in capitals.keys():
		if holder is String and holder != owner and capitals[holder] in moved:
			capitals.erase(holder)
	for e: Dictionary in walk_ids(children_of(id)):
		e.unit.owner = owner
		e.unit.type = _matching_type(get_type(e.unit.type).get("name", "Região"), owner)
	units[id].owner = owner
	units[id].type = type_id


func _matching_type(type_name: String, owner: String) -> int:
	for t: Dictionary in types_of(owner):
		if t.name == type_name:
			return t.id
	return add_type(type_name, owner)


func unit_color(u: Dictionary) -> Color:
	var base: Color = get_type(u.type).get("color", Color.WHITE)
	var h := hash(int(u.id) * 7919 + 13)
	return Color.from_hsv(fposmod(base.h + (h % 100) / 100.0 * 0.07 - 0.035, 1.0), base.s, clampf(base.v - ((h >> 8) % 100) / 100.0 * 0.22, 0.2, 1.0))


## Unidades da maior para a menor, para os rótulos pararem assim que ficam pequenas demais.
func by_area() -> Array:
	if _by_area.is_empty() and not units.is_empty():
		_by_area = units.values()
		_by_area.sort_custom(func(a, b): return float(a.area) > float(b.area))
	return _by_area


## Contorno em pares de pontos, calculado só quando a unidade é destacada.
func outline_of(u: Dictionary) -> PackedVector2Array:
	if not u.has("outline"):
		u["outline"] = _outline(u.pieces)
	return u.outline


# --- Criação ---------------------------------------------------------------------

## O segmento from→to cruza o traçado já desenhado? Ao fechar, ignora a aresta que sai do primeiro ponto.
static func crosses(points: PackedVector2Array, from: Vector2, to: Vector2, closing := false) -> bool:
	for i in range(0, points.size() - 2):
		if closing and i == 0:
			continue
		if Geometry2D.segment_intersects_segment(points[i], points[i + 1], from, to) != null:
			return true
	return false


## territory: {"rings": [...], "holes": [...]}, os contornos do país do jogador.
func create_unit(points: PackedVector2Array, type_id: int, parent_id: int, territory: Dictionary, region: String, owner: String, dry_run := false) -> Dictionary:
	if points.size() < 3:
		return {"ok": false, "msg": tr("São necessários pelo menos 3 vértices.")}
	if get_type(type_id).is_empty():
		return {"ok": false, "msg": tr("Escolha um tipo de unidade.")}
	if parent_id >= 0 and not units.has(parent_id):
		return {"ok": false, "msg": tr("A unidade-mãe não existe mais.")}
	var pieces := intersect_all(points, territory.rings)
	if parent_id >= 0:
		pieces = _intersect_pieces(pieces, units[parent_id].pieces)
	for hole: PackedVector2Array in territory.holes:
		pieces = subtract(pieces, hole)
	var siblings := children_of(parent_id) if parent_id >= 0 else roots_of(owner)
	for sibling_id: int in siblings:
		for cut: PackedVector2Array in units[sibling_id].pieces:
			pieces = subtract(pieces, cut)
	pieces = _clean(pieces)
	var total := total_area(pieces)
	if total < MIN_UNIT_AREA:
		var where: String = units[parent_id].name if parent_id >= 0 else tr("seu território")
		var msg := tr("O polígono não cobre área livre dentro de %s.") % where
		if not siblings.is_empty():
			msg += tr(" Selecione uma unidade para desenhar dentro dela ou apague as que ocupam a área.")
		return {"ok": false, "msg": msg}
	if dry_run:
		return {"ok": true, "msg": ""}
	var territory_area := total_area(territory.rings)
	for hole: PackedVector2Array in territory.holes:
		territory_area -= polygon_area(hole)
	var id := next_unit_id
	next_unit_id += 1
	var final_owner: String = units[parent_id].owner if parent_id >= 0 else owner
	var u := {
		"id": id, "name": _generate_name(region), "type": type_id, "parent": parent_id, "owner": final_owner, "base": false,
		"pieces": pieces, "rect": _bounds_all(pieces), "center": _label_point(pieces), "area": total,
		"share": total / maxf(territory_area, 0.001), "pop_w": _population_weight(total, str(id)),
	}
	units[id] = u
	custom_ids.append(id)
	_link(u)
	_by_area.clear()
	return {"ok": true, "msg": "", "id": id, "clipped": total < polygon_area(points) * 0.99}


## A unidade mais específica no ponto: criadas pelo jogador primeiro (filhas antes das mães),
## depois as do cenário pela grade, onde cada célula lista da menor para a maior.
func unit_at(pos: Vector2) -> int:
	var custom := -1
	for i in range(custom_ids.size() - 1, -1, -1):
		if _contains(units[custom_ids[i]], pos):
			custom = custom_ids[i]
			break
	var base := -1
	for id: int in _grid.get(GameData.admin1_cell(pos), []):
		if units.has(id) and _contains(units[id], pos):
			base = id
			break
	if custom < 0 or base < 0:
		return maxi(custom, base)
	# Vale a mais profunda: um estado fundido não pode esconder os municípios dele.
	var dc := depth_of(custom)
	var db := depth_of(base)
	if dc != db:
		return custom if dc > db else base
	return custom if float(units[custom].area) <= float(units[base].area) else base


func _contains(u: Dictionary, pos: Vector2) -> bool:
	if not (u.rect as Rect2).has_point(pos):
		return false
	for piece: PackedVector2Array in u.pieces:
		if Geometry2D.is_point_in_polygon(pos, piece):
			return true
	return false


func _generate_name(region: String) -> String:
	var parts: Array = NAME_PARTS.get(region, NAME_PARTS["EUR"])
	var used := {}
	for u: Dictionary in units.values():
		used[u.name] = true
	var rng := RandomNumberGenerator.new()
	var candidate := ""
	for attempt in 40:
		name_counter += 1
		rng.seed = hash(region + str(name_counter))
		var prefixes: Array = parts[2]
		candidate = parts[0][rng.randi() % parts[0].size()] + parts[1][rng.randi() % parts[1].size()]
		if not prefixes.is_empty() and rng.randf() < 0.18:
			candidate = prefixes[rng.randi() % prefixes.size()] + candidate
		if not used.has(candidate):
			return candidate
	return "%s %d" % [candidate, name_counter]


# --- Geometria -------------------------------------------------------------------

static func polygon_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return absf(a) * 0.5


static func total_area(pieces: Array) -> float:
	var t := 0.0
	for p: PackedVector2Array in pieces:
		t += polygon_area(p)
	return t


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


static func _bounds_all(pieces: Array) -> Rect2:
	var r := _bounds(pieces[0])
	for p: PackedVector2Array in pieces:
		r = r.merge(_bounds(p))
	return r


static func intersect_all(poly: PackedVector2Array, containers: Array) -> Array:
	var out := []
	var box := _bounds(poly)
	for ring: PackedVector2Array in containers:
		if box.intersects(_bounds(ring)):
			out.append_array(Geometry2D.intersect_polygons(poly, ring))
	return out


func intersect_all_pieces(pieces: Array, poly: PackedVector2Array) -> Array:
	return intersect_all(poly, pieces)


static func _intersect_pieces(pieces: Array, containers: Array) -> Array:
	var out := []
	for p: PackedVector2Array in pieces:
		out.append_array(intersect_all(p, containers))
	return out


## Subtrai sem deixar furos: se o recorte fica no interior de uma peça, ela é dividida em duas
## por uma linha vertical que passa por ele, porque a triangulação não aceita buracos.
static func subtract(pieces: Array, cut: PackedVector2Array, guard := 0) -> Array:
	var out := []
	var box := _bounds(cut)
	for p: PackedVector2Array in pieces:
		var pb := _bounds(p)
		if not box.intersects(pb):
			out.append(p)
			continue
		var res := Geometry2D.clip_polygons(p, cut)
		if not _has_hole(res):
			out.append_array(res)
			continue
		if guard >= 6:
			continue
		var x := box.get_center().x
		var area := pb.grow(1.0)
		var left := _rect_poly(area.position.x, x, area.position.y, area.end.y)
		var right := _rect_poly(x, area.end.x, area.position.y, area.end.y)
		out.append_array(subtract(Geometry2D.intersect_polygons(p, left), cut, guard + 1))
		out.append_array(subtract(Geometry2D.intersect_polygons(p, right), cut, guard + 1))
	return out


## O Clipper devolve furos com orientação oposta à das bordas externas; a maior peça é sempre externa.
static func _has_hole(res: Array) -> bool:
	if res.size() < 2:
		return false
	var biggest: PackedVector2Array = res[0]
	for p: PackedVector2Array in res:
		if polygon_area(p) > polygon_area(biggest):
			biggest = p
	var cw := Geometry2D.is_polygon_clockwise(biggest)
	for p: PackedVector2Array in res:
		if Geometry2D.is_polygon_clockwise(p) != cw:
			return true
	return false


static func _rect_poly(x0: float, x1: float, y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _clean(pieces: Array) -> Array:
	var out := []
	for p: PackedVector2Array in pieces:
		if p.size() >= 3 and polygon_area(p) >= MIN_PIECE_AREA and not Geometry2D.triangulate_polygon(p).is_empty():
			out.append(p)
	return out


## Contorno em pares de pontos. Arestas compartilhadas por duas peças (divisão de furos) somem.
static func _outline(pieces: Array) -> PackedVector2Array:
	var edges := {}
	for p: PackedVector2Array in pieces:
		for i in p.size():
			var a := p[i]
			var b := p[(i + 1) % p.size()]
			var ka := Vector2i((a * 50.0).round())
			var kb := Vector2i((b * 50.0).round())
			if ka == kb:
				continue
			var back := Vector4i(kb.x, kb.y, ka.x, ka.y)
			if edges.has(back):
				edges.erase(back)
			else:
				edges[Vector4i(ka.x, ka.y, kb.x, kb.y)] = [a, b]
	var out := PackedVector2Array()
	for e: Array in edges.values():
		out.append(e[0])
		out.append(e[1])
	return out


static func _label_point(pieces: Array) -> Vector2:
	var biggest: PackedVector2Array = pieces[0]
	for p: PackedVector2Array in pieces:
		if polygon_area(p) > polygon_area(biggest):
			biggest = p
	var sum := Vector2.ZERO
	var twice := 0.0
	for i in biggest.size():
		var a := biggest[i]
		var b := biggest[(i + 1) % biggest.size()]
		var k := a.cross(b)
		twice += k
		sum += (a + b) * k
	if absf(twice) > 0.0001:
		var centroid := sum / (3.0 * twice)
		if Geometry2D.is_point_in_polygon(centroid, biggest):
			return centroid
	# Polígono côncavo: usa o maior triângulo da malha, que sempre fica dentro.
	var ids := Geometry2D.triangulate_polygon(biggest)
	var best := biggest[0]
	var best_area := -1.0
	for i in range(0, ids.size(), 3):
		var a := biggest[ids[i]]
		var b := biggest[ids[i + 1]]
		var c := biggest[ids[i + 2]]
		var area := absf((b - a).cross(c - a))
		if area > best_area:
			best_area = area
			best = (a + b + c) / 3.0
	return best


# --- Salvar e carregar -----------------------------------------------------------

## O cenário vem dos arquivos de dados: o save guarda só as unidades dele que mudaram ou foram
## apagadas, mais as criadas pelo jogador.
func to_dict() -> Dictionary:
	var base := []
	var custom := []
	var data: Array = GameData.load_admin1().units if base_count > 0 else []
	var deleted := []
	for id in base_count:
		if not units.has(id):
			deleted.append(id)
	for u: Dictionary in units.values():
		if u.base:
			var src: Dictionary = data[u.id]
			if u.name == src.name and u.owner == src.owner and u.type == u.type0 and u.parent == src.get("parent", -1) and not u.get("reshaped", false):
				continue
			var meta := {"id": u.id, "name": u.name, "type": u.type, "owner": u.owner, "parent": u.parent, "share": u.share}
			if u.get("reshaped", false):
				meta["pieces"] = u.pieces
			base.append(meta)
		else:
			var copy := u.duplicate()
			copy.erase("outline")
			custom.append(copy)
	return {
		"version": SAVE_VERSION, "types": types.values(), "base": base, "deleted": deleted, "custom": custom, "capitals": capitals,
		"next_type_id": next_type_id, "next_unit_id": next_unit_id, "name_counter": name_counter,
	}


func from_dict(d: Dictionary, player_iso: String) -> void:
	if d.is_empty():
		return
	if not d.has("version"):
		_load_v1(d, player_iso)
		return
	var version := int(d.version)
	if version < SAVE_VERSION:
		_shift_old_ids(d, version)
	# Os tipos das capitais podem não existir em saves antigos.
	var seeded := types.values().filter(func(t): return int(t.id) >= CITY_TYPE_FIRST_ID)
	types.clear()
	for t: Dictionary in seeded:
		types[int(t.id)] = t
	for t: Dictionary in d.types:
		types[int(t.id)] = t
	var kept := {}
	if version >= 3:
		kept = units
		for id: int in d.deleted:
			kept.erase(id)
	for meta: Dictionary in d.base:
		var u: Dictionary = units[int(meta.id)]
		u.name = meta.name
		u.type = meta.type
		u.owner = meta.get("owner", u.owner)
		u.parent = meta.get("parent", u.parent)
		u.share = meta.get("share", u.share)
		if meta.has("pieces"):
			_set_geometry(u, meta.pieces)
			u["reshaped"] = true
		kept[int(meta.id)] = u
	if version < 3:
		# Saves anteriores não conheciam os municípios: entram os dos estados que continuam existindo.
		for u: Dictionary in units.values():
			if u.base and int(u.parent) >= 0 and kept.has(u.parent):
				kept[u.id] = u
	units = kept
	custom_ids.clear()
	for u: Dictionary in d.custom:
		units[int(u.id)] = u
		custom_ids.append(int(u.id))
	next_type_id = d.next_type_id
	next_unit_id = d.next_unit_id
	name_counter = d.name_counter
	# Saves sem esta informação ficam com as capitais do cenário.
	if d.has("capitals"):
		var national := capitals.duplicate()
		capitals = d.capitals
		if version < SAVE_VERSION:
			for holder: Variant in national:
				if holder is String and holder != "BRA":
					capitals[holder] = national[holder]
	_reindex()


## Cada versão acrescentou unidades ao cenário: as criadas pelo jogador andam para depois delas.
func _shift_old_ids(d: Dictionary, version: int) -> void:
	var first: int = OLD_BASE_COUNT.get(version, base_count)
	var by := base_count - first
	var moved := func(id: int) -> int: return id + by if id >= first else id
	for u: Dictionary in d.custom:
		u.id = moved.call(int(u.id))
		u.parent = moved.call(int(u.parent))
	for meta: Dictionary in d.base:
		if meta.has("parent"):
			meta.parent = moved.call(int(meta.parent))
	if d.has("capitals"):
		var fixed := {}
		for holder: Variant in d.capitals:
			fixed[moved.call(holder) if holder is int else holder] = moved.call(int(d.capitals[holder]))
		d.capitals = fixed
	d.next_unit_id = int(d.next_unit_id) + by


## Saves da primeira versão: só tinham unidades desenhadas, todas do jogador.
func _load_v1(d: Dictionary, owner: String) -> void:
	var type_map := {}
	for t: Dictionary in d.types:
		var existing := -1
		for mine: Dictionary in types_of(owner):
			if String(mine.name).to_lower() == String(t.name).to_lower():
				existing = mine.id
		type_map[int(t.id)] = existing if existing >= 0 else add_type(t.name, owner)
	var id_map := {}
	for old: Dictionary in d.units:
		var id := next_unit_id
		next_unit_id += 1
		id_map[int(old.id)] = id
		var u: Dictionary = old.duplicate()
		u.erase("outline")
		u.id = id
		u.type = type_map.get(int(old.type), -1)
		u.parent = id_map.get(int(old.parent), -1)
		u.owner = owner
		u.base = false
		units[id] = u
		custom_ids.append(id)
	name_counter = maxi(name_counter, int(d.get("name_counter", 0)))
	_reindex()
