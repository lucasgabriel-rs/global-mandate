extends SceneTree
## Testes das capitais de unidades e de países, sem interface.
## Uso: godot --headless --path . -s tests/capitals.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FALHA: ", what)


func _world() -> GameWorld:
	var w := GameWorld.new()
	w.setup(5)
	w.set_player(w.by_iso["BRA"], "normal")
	return w


func _root(s: Subdivisions, iso: String, unit_name: String) -> int:
	for id: int in s.roots_of(iso):
		if s.units[id].name == unit_name:
			return id
	return -1


func _kid(s: Subdivisions, parent: int, unit_name: String) -> int:
	for id: int in s.children_of(parent):
		if s.units[id].name == unit_name:
			return id
	return -1


func _box(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])


func _init() -> void:
	# Cenário.
	var w := _world()
	var s := w.subdivisions
	var wrong := []
	for id: int in s.roots_of("BRA"):
		var capital := s.capital_of(id)
		if capital < 0 or s.units[capital].parent != id or s.units[capital].name != Subdivisions.BRAZIL_STATE_CAPITALS[s.units[id].name]:
			wrong.append(s.units[id].name)
	_check(wrong.is_empty(), "os 27 estados têm a capital certa %s" % str(wrong))
	_check(s.units[s.capital_of("BRA")].name == "Brasília", "Brasília é a capital do Brasil")
	var df := _root(s, "BRA", "Distrito Federal")
	_check(s.capital_of(df) == s.capital_of("BRA") and s.holders_of(s.capital_of("BRA")).size() == 2, "Brasília é capital do país e do Distrito Federal")
	var none := []
	var known := {"ARG": "Buenos Aires", "USA": "Washington", "CHN": "Pequim", "FRA": "Paris", "DEU": "Berlim", "JPN": "Tóquio", "ZAF": "Pretória", "TZA": "Dodoma", "BEN": "Porto Novo", "KAZ": "Astana", "PSE": "Ramala", "XKX": "Pristina", "RUS": "Moscou", "PRT": "Lisboa"}
	var misplaced := []
	for c: Country in w.countries:
		var id := s.capital_of(c.iso)
		if id < 0:
			none.append(c.iso)
			continue
		var unit: Dictionary = s.units[id]
		if unit.owner != c.iso:
			misplaced.append(c.iso)
		# A capital precisa estar no próprio país no mapa.
		var land := w.territories.territory_of(c, w)
		var center: Vector2 = unit.center
		if not Territories._inside_any(center, land.rings):
			misplaced.append("%s:%s" % [c.iso, unit.name])
	_check(none.is_empty(), "todos os países têm capital %s" % str(none))
	_check(misplaced.is_empty(), "capitais ficam dentro do próprio país %s" % str(misplaced))
	for iso: String in known:
		var id := s.capital_of(iso)
		var got: String = s.units[id].name if id >= 0 else ""
		_check(got == known[iso], "capital de %s: %s" % [iso, got])
	var arg_cap := s.capital_of("ARG")
	_check(s.units[arg_cap].parent >= 0 or float(s.units[arg_cap].area) <= 5.0, "capital é cidade ou unidade pequena")
	# Bruxelas é enclave de Brabante Flamengo, cujo contorno externo também contém o ponto.
	var brussels: Dictionary = s.units[s.capital_of("BEL")]
	_check(brussels.name == "Bruxelas" and int(brussels.parent) < 0 and float(brussels.area) < 5.0, "capital enclave fica na menor unidade: " + String(brussels.name))
	# Save anterior a esta versão: ids das unidades criadas andam, e entram os tipos e capitais novos.
	var saved := _world()
	var sv := saved.subdivisions
	var kind0 := sv.add_type("Zona", "BRA")
	var host := _kid(sv, _root(sv, "BRA", "Pará"), "Belém")
	var made := sv.create_unit(_box(sv.units[host].center, 0.3), kind0, host, saved.territories.territory_of(saved.player, saved), "LAM", "BRA")
	_check(made.ok, "unidade criada para o teste de save antigo")
	sv.set_capital("BRA", made.id)
	var old_d: Dictionary = bytes_to_var(var_to_bytes(sv.to_dict()))
	var shift: int = sv.base_count - Subdivisions.OLD_BASE_COUNT[3]
	old_d.version = 3
	old_d.next_unit_id = int(old_d.next_unit_id) - shift
	old_d.capitals = {"BRA": int(made.id) - shift, _root(sv, "BRA", "Pará"): host}
	for u: Dictionary in old_d.custom:
		u.id = int(u.id) - shift
	old_d.types = old_d.types.filter(func(t): return int(t.id) < Subdivisions.CITY_TYPE_FIRST_ID)
	var loaded := _world()
	loaded.subdivisions.from_dict(old_d, "BRA")
	var ls := loaded.subdivisions
	_check(ls.units.has(made.id) and ls.units[made.id].parent == host, "unidade do save antigo não sobrescreve as novas")
	_check(ls.units[host].name == "Belém", "município continua intacto")
	_check(ls.capital_of("BRA") == made.id, "capital do save antigo segue a unidade")
	_check(ls.capital_of("ARG") >= 0, "save antigo ganha as capitais estrangeiras")
	_check(not ls.get_type(ls.units[ls.capital_of("USA")].type).is_empty(), "tipo Cidade existe depois de carregar")
	_check(ls.next_unit_id > made.id, "ids novos continuam depois das existentes")
	# Conquista: a capital estrangeira segue a mesma regra da nacional.
	var conquest := _world()
	var cs := conquest.subdivisions
	var uy_cap := cs.capital_of("URY")
	var uy_units := []
	for id: int in cs.roots_of("URY"):
		uy_units.append_array(cs.units[id].pieces)
	conquest.diplomacy.annex(conquest.player, conquest.by_iso["URY"], conquest)
	_check(cs.capital_of("URY") == uy_cap, "anexação não apaga a capital do anexado")

	# Definir, trocar e recusar.
	var pa := _root(s, "BRA", "Pará")
	var belem := _kid(s, pa, "Belém")
	var santarem := _kid(s, pa, "Santarém")
	var am := _root(s, "BRA", "Amazonas")
	_check(s.capital_of(pa) == belem, "Belém é a capital do Pará")
	_check(s.set_capital(pa, santarem).ok and s.capital_of(pa) == santarem, "trocar substitui a capital")
	_check(not s.is_capital(belem), "a anterior deixa de ser capital")
	_check(not s.set_capital(am, santarem).ok and s.capital_of(am) != santarem, "capital precisa ficar dentro da unidade")
	_check(not s.set_capital(pa, pa).ok, "unidade não é capital de si mesma")
	_check(not s.set_capital(santarem, pa).ok, "mãe não é capital da filha")
	_check(s.set_capital("BRA", santarem).ok and s.holders_of(santarem).size() == 2, "a mesma unidade serve o estado e o país")
	var land := w.territories.territory_of(w.player, w)
	var kind := s.add_type("Distrito", "BRA")
	var inner := s.create_unit(_box(s.units[santarem].center, 1.0), kind, santarem, land, "LAM", "BRA")
	_check(inner.ok and s.set_capital(santarem, inner.id).ok, "unidade criada pode ser capital do município")
	_check(s.set_capital(pa, inner.id).ok and s.set_capital("BRA", inner.id).ok, "e também do estado e do país")
	_check(s.holders_of(inner.id).size() == 3, "três funções na mesma unidade")
	var name_of_inner: String = s.units[inner.id].name
	s.set_capital(pa, santarem)
	s.set_capital("BRA", santarem)

	# Salvar e carregar.
	s.clear_capital(am)
	var w2 := GameWorld.new()
	w2.setup(5)
	w2.load_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	var s2 := w2.subdivisions
	_check(s2.capital_of(pa) == santarem and s2.capital_of("BRA") == santarem, "carregar mantém as capitais")
	_check(s2.capital_of(am) == -1, "carregar mantém a capital removida")
	_check(s2.capital_of(santarem) == inner.id and s2.units[inner.id].name == name_of_inner, "carregar mantém a capital da unidade criada")
	var old := w.to_dict()
	old.subdivisions.erase("capitals")
	var w3 := GameWorld.new()
	w3.setup(5)
	w3.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(w3.subdivisions.units[w3.subdivisions.capital_of("BRA")].name == "Brasília", "save sem capitais usa as do cenário")

	# Apagar.
	s.delete_unit(inner.id)
	_check(s.capital_of(santarem) == -1, "apagar a capital limpa a função")
	var doomed := _world()
	var ds := doomed.subdivisions
	var dpa := _root(ds, "BRA", "Pará")
	ds.set_capital("BRA", _kid(ds, dpa, "Belém"))
	ds.delete_unit(dpa)
	_check(ds.capital_of("BRA") == -1 and ds.capital_of(dpa) == -1, "apagar o estado limpa a capital dele e a do país")

	# Fundir.
	var w4 := _world()
	var s4 := w4.subdivisions
	var a := _root(s4, "BRA", "Pará")
	var b := _root(s4, "BRA", "Amazonas")
	var cap_a := s4.capital_of(a)
	var m := s4.merge_units([a, b])
	_check(m.ok and s4.capital_of(m.id) == cap_a, "estado fundido fica com a capital da primeira")
	_check(not s4.capitals.has(a) and not s4.capitals.has(b), "estados antigos saem da lista")
	var pair := []
	for kid: int in s4.children_of(_root(s4, "BRA", "São Paulo")):
		if pair.is_empty() or Subdivisions._touching(s4.units[pair[0]], s4.units[kid]):
			if kid != s4.capital_of(_root(s4, "BRA", "São Paulo")) or pair.is_empty():
				pair.append(kid)
		if pair.size() == 2:
			break
	var sp := _root(s4, "BRA", "São Paulo")
	s4.set_capital(sp, pair[0])
	s4.set_capital("BRA", pair[1])
	var m2 := s4.merge_units(pair)
	_check(m2.ok and s4.capital_of(sp) == m2.id and s4.capital_of("BRA") == m2.id, "município fundido herda o papel de capital")

	# Desmembrar.
	var w5 := _world()
	var s5 := w5.subdivisions
	var mg := _root(s5, "BRA", "Minas Gerais")
	var bh := s5.capital_of(mg)
	var sp5 := s5.split_unit(mg, _box(s5.units[bh].center, 10.0), "LAM")
	_check(sp5.ok and s5.units[bh].parent == sp5.id, "capital fica com a parte onde está")
	_check(s5.capital_of(sp5.id) == bh and s5.capital_of(mg) == -1, "e passa a ser capital da parte nova")
	s5.set_capital("BRA", bh)
	_check(s5.capital_of("BRA") == bh, "desmembrar não atrapalha a capital do país")
	var ba := _root(s5, "BRA", "Bahia")
	var ssa := s5.capital_of(ba)
	var far: Vector2 = s5.units[s5.children_of(ba)[0]].center
	_check(far.distance_to(s5.units[ssa].center) > 12.0, "caso de teste: município longe de Salvador")
	_check(s5.split_unit(ba, _box(far, 5.0), "LAM").ok and s5.capital_of(ba) == ssa, "capital longe do corte continua na original")

	# Guerra: unidade inteira cedida e capital nacional perdida.
	var w6 := _world()
	var s6 := w6.subdivisions
	var news := []
	w6.news_posted.connect(func(text, _k, _c): news.append(text))
	var capital_area: int = s6.capital_of("BRA")
	var cut := w6.territories.clip_to(_box(s6.units[capital_area].center, 2.0), w6.player, w6)
	w6.territories.apply(cut, w6.player, w6.by_iso["ARG"], w6)
	_check(s6.capital_of("BRA") == capital_area and s6.units[capital_area].owner == "BRA", "corte parcial mantém a capital com o país")
	var w7 := _world()
	var s7 := w7.subdivisions
	var news7 := []
	w7.news_posted.connect(func(text, _k, _c): news7.append(text))
	var go := _root(s7, "BRA", "Goiás")
	s7.set_capital("BRA", s7.capital_of(go))
	var go_cap := s7.capital_of(go)
	var whole: Array = s7.units[go].pieces.duplicate()
	whole.append_array(s7.units[_root(s7, "BRA", "Distrito Federal")].pieces)
	w7.territories.apply(whole, w7.player, w7.by_iso["ARG"], w7)
	_check(s7.units[go_cap].owner == "ARG", "capital cedida muda de dono")
	_check(s7.capital_of("BRA") == -1, "país que perde a capital fica sem ela")
	_check(s7.capital_of(go) == go_cap, "o estado cedido mantém a própria capital")
	var told := false
	for text: String in news7:
		told = told or text.contains("perde a capital")
	_check(told, "notícia avisa a perda da capital")
	# Corte que passa pela capital de um estado não a deixa fora do estado.
	var w8 := _world()
	var s8 := w8.subdivisions
	var rs := _root(s8, "BRA", "Rio Grande do Sul")
	var poa := s8.capital_of(rs)
	var slice := w8.territories.clip_to(_box(s8.units[poa].center, 12.0), w8.player, w8)
	w8.territories.apply(slice, w8.player, w8.by_iso["ARG"], w8)
	var invalid := 0
	for holder: Variant in s8.capitals:
		if holder is int and (not s8.units.has(holder) or not holder in s8.chain_of(s8.capitals[holder]) or s8.units[holder].owner != s8.units[s8.capitals[holder]].owner):
			invalid += 1
	_check(invalid == 0, "depois da guerra, toda capital continua dentro da própria unidade (%d inválidas)" % invalid)

	print("RESULTADO: ", failures, " falhas")
	quit(1 if failures > 0 else 0)
