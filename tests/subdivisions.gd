extends SceneTree
## Testes do modelo de unidades subnacionais e dos dados do cenário, sem interface.
## Uso: godot --headless --path . -s tests/subdivisions.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FALHA: ", what)


func _square(cx: float, cy: float, r: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - r, cy - r), Vector2(cx + r, cy - r), Vector2(cx + r, cy + r), Vector2(cx - r, cy + r)])


func _model() -> void:
	var land := {"rings": [_square(0, 0, 100)], "holes": [_square(80, 80, 5)]}
	var s := Subdivisions.new()
	var state := s.add_type("Estado", "TST")

	# Tipos definidos pelo jogador, por país.
	var province := s.add_type("Província", "TST")
	_check(s.get_type(province).name == "Província", "novo tipo recebe o nome escolhido")
	_check(not s.rename_type(province, "estado").ok, "nome de tipo repetido é recusado")
	_check(not s.rename_type(province, "   ").ok, "nome de tipo vazio é recusado")
	_check(s.rename_type(province, "Cantão").ok and s.get_type(province).name == "Cantão", "tipo pode ser renomeado")
	var other := s.add_type("Estado", "XXX")
	_check(s.get_type(other).name == "Estado" and s.types_of("TST").size() == 2, "cada país tem os próprios tipos")

	# Criação e nome automático.
	var a := s.create_unit(_square(-50, 0, 20), state, -1, land, "LAM", "TST")
	_check(a.ok and s.units.size() == 1, "polígono fechado cria unidade")
	_check(String(s.units[a.id].name) != "", "unidade recebe nome automático: " + String(s.units[a.id].name))
	_check(absf(s.units[a.id].area - 1600.0) < 2.0 and not a.clipped, "unidade interna mantém a área")
	_check(absf(s.units[a.id].share - 1600.0 / (40000.0 - 100.0)) < 0.001, "participação no território")
	_check(s.unit_at(Vector2(-50, 0)) == a.id, "seleção por ponto")

	var names := {}
	for i in 30:
		var extra := Subdivisions.new()
		extra.name_counter = i * 100
		names[extra._generate_name("ASI")] = true
	_check(names.size() > 15, "nomes variados (%d de 30)" % names.size())

	# Recorte pelo território e pelas irmãs.
	var edge := s.create_unit(_square(100, 0, 20), state, -1, land, "LAM", "TST")
	_check(edge.ok and edge.clipped and absf(s.units[edge.id].area - 800.0) < 2.0, "recorte pela fronteira")
	var over := s.create_unit(_square(-30, 0, 20), state, -1, land, "LAM", "TST")
	_check(over.ok and absf(s.units[over.id].area - 800.0) < 2.0, "irmã não sobrepõe a existente")
	_check(not s.create_unit(_square(500, 500, 20), state, -1, land, "LAM", "TST").ok, "polígono fora do território é recusado")
	_check(not s.create_unit(_square(-50, 0, 10), state, -1, land, "LAM", "TST").ok, "polígono sobre área já ocupada é recusado")
	var enclave := s.create_unit(_square(80, 80, 12), state, -1, land, "LAM", "TST")
	_check(enclave.ok and absf(s.units[enclave.id].area - (576.0 - 100.0)) < 2.0, "enclave estrangeiro fica de fora")
	_check(s.units[enclave.id].pieces.size() >= 2, "furo vira peças trianguláveis")

	# Hierarquia.
	var city := s.create_unit(_square(-50, 0, 8), province, a.id, land, "LAM", "TST")
	_check(city.ok and s.units[city.id].parent == a.id, "unidade criada dentro de outra")
	_check(s.unit_at(Vector2(-50, 0)) == city.id, "seleção prefere a unidade mais profunda")
	var over_parent := s.create_unit(_square(-70, 0, 8), province, a.id, land, "LAM", "TST")
	_check(over_parent.ok and absf(s.units[over_parent.id].area - 128.0) < 2.0, "filha é recortada pela mãe")
	var deep := s.create_unit(_square(-50, 0, 4), state, city.id, land, "LAM", "TST")
	_check(deep.ok and s.depth_of(deep.id) == 2, "terceiro nível")
	_check(s.path_of(deep.id).count(" › ") == 2, "caminho: " + s.path_of(deep.id))
	var order := s.walk_country("TST")
	var at_parent := -1
	var at_child := -1
	for i in order.size():
		if order[i].unit.id == a.id:
			at_parent = i
		if order[i].unit.id == city.id:
			at_child = i
	_check(at_parent >= 0 and at_child > at_parent, "árvore lista a mãe antes da filha")

	# Tipos em uso e remoção em cascata.
	_check(not s.remove_type(province).ok, "tipo em uso não pode ser apagado")
	_check(s.count_descendants(a.id) == 3, "descendentes contados")
	var bytes := var_to_bytes(s.to_dict())
	s.delete_unit(a.id)
	_check(not s.units.has(a.id) and not s.units.has(city.id) and not s.units.has(deep.id), "apagar remove as filhas")
	_check(s.remove_type(province).ok, "tipo livre pode ser apagado")

	# Salvar e carregar passando pelo formato do arquivo.
	var loaded := Subdivisions.new()
	loaded.from_dict(bytes_to_var(bytes), "TST")
	_check(loaded.units.has(deep.id) and loaded.depth_of(deep.id) == 2, "carregamento mantém a hierarquia")
	_check(loaded.get_type(province).name == "Cantão", "carregamento mantém os tipos")
	_check(loaded.unit_at(Vector2(-50, 0)) == deep.id, "carregamento mantém a busca por ponto")
	var next := loaded.create_unit(_square(0, -60, 10), state, -1, land, "LAM", "TST")
	_check(next.ok and next.id > deep.id, "ids continuam depois de carregar")

	# Traçado.
	var zig := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	_check(Subdivisions.crosses(zig, zig[2], Vector2(5, -5)), "aresta que cruza é detectada")
	_check(not Subdivisions.crosses(zig, zig[2], Vector2(0, 10)), "aresta livre é aceita")
	_check(not Subdivisions.crosses(zig, zig[2], zig[0], true), "fechamento no primeiro ponto é aceito")


func _scenario() -> void:
	var t0 := Time.get_ticks_msec()
	GameData.load_admin1()
	print("leitura de admin1.json: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var w := GameWorld.new()
	w.setup(77)
	print("montagem do mundo: %d ms" % (Time.get_ticks_msec() - t0))
	var s := w.subdivisions

	_check(s.units.size() == s.base_count and s.base_count >= 4220 + 5564, "cenário traz %d unidades" % s.base_count)
	var muns := 0
	var empty_states := []
	for id: int in s.roots_of("BRA"):
		muns += s.children_of(id).size()
		if s.children_of(id).is_empty():
			empty_states.append(s.units[id].name)
	_check(muns == 5564 and empty_states.is_empty(), "os 5.564 municípios estão nos 27 estados %s" % str(empty_states))
	_check(s.units[s.children_of(s.roots_of("BRA")[0])[0]].base and s.get_type(s.units[s.children_of(s.roots_of("BRA")[0])[0]].type).name == "Município", "município tem o tipo certo")
	var hits := {}
	for id: int in s.children_of(s.roots_of("BRA")[0]):
		hits[s.unit_at(s.units[id].center)] = true
	_check(hits.size() > s.children_of(s.roots_of("BRA")[0]).size() * 0.9, "clique acha o município, não o estado")
	var sp_units := 0
	for u: Dictionary in s.units.values():
		if u.name == "São Paulo" and u.parent >= 0:
			sp_units += 1
			_check(s.path_of(u.id) == "São Paulo › São Paulo", "caminho do município de São Paulo")
	_check(sp_units == 1, "município de São Paulo existe uma vez")
	var without := []
	for c: Country in w.countries:
		if s.roots_of(c.iso).is_empty():
			without.append(c.iso)
		elif s.types_of(c.iso).is_empty():
			without.append(c.iso + "(sem tipo)")
	_check(without.is_empty(), "todos os %d países têm unidades %s" % [w.countries.size(), str(without)])

	var brazil := {}
	for id: int in s.roots_of("BRA"):
		brazil[s.units[id].name] = s.get_type(s.units[id].type).name
	_check(brazil.size() == 27, "Brasil tem 27 unidades (%d)" % brazil.size())
	_check(brazil.get("Pará") == "Estado" and brazil.get("Distrito Federal") == "Distrito federal", "tipos do Brasil traduzidos")
	_check(s.roots_of("USA").size() == 51 + 5 + 3 + 3 + 8 or s.roots_of("USA").size() > 51, "EUA têm %d unidades, com territórios" % s.roots_of("USA").size())

	var total := 0.0
	for id: int in s.roots_of("BRA"):
		total += s.units[id].share
	_check(absf(total - 1.0) < 0.001, "participações do Brasil somam 100%")

	# Busca por ponto: o centro de cada unidade deve achar a própria unidade (ou um enclave dentro dela).
	var misses := 0
	t0 = Time.get_ticks_usec()
	for u: Dictionary in s.units.values():
		var hit: int = s.unit_at(u.center)
		if hit < 0 or s.units[hit].owner != u.owner:
			misses += 1
	var usec := Time.get_ticks_usec() - t0
	print("busca por ponto: %.1f µs por consulta" % (float(usec) / s.base_count))
	_check(misses < s.base_count * 0.01, "centros encontram a unidade certa (%d erros)" % misses)

	# Save pequeno e fiel: sem geometria do cenário, com edições e remoções do jogador.
	var pa: int = -1
	for id: int in s.roots_of("BRA"):
		if s.units[id].name == "Pará":
			pa = id
	s.rename_unit(pa, "Grão-Pará")
	s.rename_type(s.units[pa].type, "Unidade federativa")
	var am: int = s.roots_of("BRA")[0] if s.roots_of("BRA")[0] != pa else s.roots_of("BRA")[1]
	s.delete_unit(am)
	var territory := {"rings": s.units[pa].pieces, "holes": []}
	var mun := s.add_type("Comarca", "BRA")
	_check(not s.create_unit(_square(s.units[pa].center.x, s.units[pa].center.y, 3.0), mun, pa, territory, "LAM", "BRA").ok, "estado coberto por municípios não aceita desenho direto")
	var pa_mun: int = s.children_of(pa)[0]
	var child := s.create_unit(_square(s.units[pa_mun].center.x, s.units[pa_mun].center.y, 1.0), mun, pa_mun, territory, "LAM", "BRA")
	_check(child.ok, "unidade criada dentro de um município: " + str(child.get("msg", "")))
	var bytes := var_to_bytes(s.to_dict())
	print("unidades no save: %d KB" % (bytes.size() / 1024))
	_check(bytes.size() < 800 * 1024, "save não carrega a geometria do cenário")
	var w2 := GameWorld.new()
	w2.setup(77)
	var s2 := w2.subdivisions
	s2.from_dict(bytes_to_var(bytes), "BRA")
	_check(s2.units[pa].name == "Grão-Pará", "carregar mantém o nome editado")
	_check(s2.get_type(s2.units[pa].type).name == "Unidade federativa", "carregar mantém o tipo editado")
	_check(not s2.units.has(am), "carregar mantém a remoção")
	_check(s2.units[child.id].parent == pa_mun and s2.custom_ids == [child.id], "carregar mantém a unidade criada")
	_check(not s2.units[pa].pieces.is_empty(), "carregar devolve a geometria do cenário")
	_check(s2.children_of(pa).size() == s.children_of(pa).size() and s2.children_of(pa).size() == 143, "carregar mantém os municípios do Pará")
	_check(not s2.units.has(s.base_count - 1) == not s.units.has(s.base_count - 1), "remoções continuam iguais")
	# Save da versão 2: lista todas as unidades do cenário, e nela não existem municípios.
	var w_v2 := GameWorld.new()
	w_v2.setup(77)
	var v2_base := []
	var v2_gone: int = w_v2.subdivisions.roots_of("BRA")[0]
	for id in 4220:
		if id != v2_gone:
			var uu: Dictionary = w_v2.subdivisions.units[id]
			v2_base.append({"id": id, "name": uu.name, "type": uu.type})
	var v2_types: Array = w_v2.subdivisions.types.values()
	w_v2.subdivisions.from_dict({"version": 2, "types": v2_types, "base": v2_base, "custom": [], "next_type_id": w_v2.subdivisions.next_type_id, "next_unit_id": w_v2.subdivisions.next_unit_id, "name_counter": 0}, "BRA")
	_check(w_v2.subdivisions.units.size() > 9000 and not w_v2.subdivisions.units.has(v2_gone), "save da versão 2 ganha os municípios e mantém a remoção")
	var orphans := 0
	for uu: Dictionary in w_v2.subdivisions.units.values():
		if int(uu.parent) >= 0 and not w_v2.subdivisions.units.has(uu.parent):
			orphans += 1
	_check(orphans == 0, "estado apagado não deixa municípios soltos")
	var fresh := GameWorld.new()
	fresh.setup(77)
	_check(fresh.subdivisions.units[pa].name == "Pará", "nova partida não herda edições")

	# Save da versão anterior, só com unidades desenhadas.
	var w3 := GameWorld.new()
	w3.setup(77)
	var v1 := {"types": [{"id": 0, "name": "Estado", "color": Color.RED}, {"id": 9, "name": "Zona", "color": Color.BLUE}], "units": [
		{"id": 0, "name": "Velha", "type": 9, "parent": -1, "pieces": [_square(0, 0, 3)], "outline": PackedVector2Array(), "rect": Rect2(-3, -3, 6, 6), "center": Vector2.ZERO, "area": 36.0, "share": 0.01},
		{"id": 1, "name": "Filha", "type": 0, "parent": 0, "pieces": [_square(0, 0, 1)], "outline": PackedVector2Array(), "rect": Rect2(-1, -1, 2, 2), "center": Vector2.ZERO, "area": 4.0, "share": 0.01},
	], "next_type_id": 10, "next_unit_id": 2, "name_counter": 5}
	w3.subdivisions.from_dict(v1, "BRA")
	var s3 := w3.subdivisions
	_check(s3.custom_ids.size() == 2 and s3.units.size() == s3.base_count + 2, "save antigo mantém o cenário e soma as unidades")
	var filha: Dictionary = s3.units[s3.custom_ids[1]]
	_check(filha.parent == s3.custom_ids[0] and filha.owner == "BRA", "save antigo mantém a hierarquia")
	_check(s3.get_type(s3.units[s3.custom_ids[0]].type).name == "Zona", "save antigo mantém os tipos")


## Nenhuma unidade ou divisa pode passar do que a contém: país para estados, estado para municípios.
func _containment() -> void:
	var w := GameWorld.new()
	w.setup(77)
	var s := w.subdivisions
	var all := GameData.native_rings()
	var worst := 0.0
	var worst_name := ""
	var over := 0
	var islets := 0
	for u: Dictionary in s.units.values():
		var container: Array = s.units[u.parent].pieces if int(u.parent) >= 0 else all.get(u.owner, [])
		var inside := Subdivisions.total_area(Subdivisions._intersect_pieces(u.pieces, container))
		var outside := maxf(float(u.area) - inside, 0.0)
		# Margem para o arredondamento das coordenadas ao gravar, cerca de 18 km² no mapa.
		if outside > maxf(float(u.area) * 0.005, 0.05):
			over += 1
			print("transborda: %s (%s) %.4f de %.4f" % [u.name, u.owner, outside, float(u.area)])
			if outside > worst:
				worst = outside
				worst_name = "%s (%s)" % [u.name, u.owner]
		if float(u.area) < 0.05:
			islets += 1
	print("unidades menores que 0,05: %d; pior transbordo: %.3f em %s" % [islets, worst, worst_name])
	_check(over == 0, "nenhuma unidade passa do que a contém (%d passam)" % over)
	var arc_groups := [[s.arcs, false], [s.mun_arcs, true]]
	for group: Array in arc_groups:
		var total := 0
		var bad := 0
		for arc: Array in group[0]:
			var owner: Dictionary = s.units[arc[0]]
			var container: Array = s.units[owner.parent].pieces if group[1] else all.get(owner.owner, [])
			var pts: PackedVector2Array = arc[2]
			for i in pts.size() - 1:
				total += 1
				if not Territories._inside_any((pts[i] + pts[i + 1]) * 0.5, container):
					bad += 1
		print("divisas %s: %d trechos fora de %d" % ["de município" if group[1] else "de estado", bad, total])
		_check(bad == 0, "divisas ficam dentro do limite (%d de %d)" % [bad, total])
	var rio := -1
	for id: int in s.roots_of("BRA"):
		if s.units[id].name == "Rio de Janeiro":
			for kid: int in s.children_of(id):
				if s.units[kid].name == "Rio de Janeiro":
					rio = kid
	_check(rio >= 0 and float(s.units[rio].area) > 1.5, "município do Rio mantém a área real (%.2f)" % float(s.units[rio].area))
	_check(s.base_count >= 4220 + 5564, "recorte não perde unidades")


func _init() -> void:
	_model()
	_scenario()
	_containment()
	print("RESULTADO: ", failures, " falhas")
	quit(1 if failures > 0 else 0)
