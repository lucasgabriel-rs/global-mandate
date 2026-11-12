extends SceneTree
## Testes de fundir, desmembrar, cessões territoriais e fim de guerra, sem interface.
## Uso: godot --headless --path . -s tests/borders.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _box(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(-r, -r), center + Vector2(r, -r), center + Vector2(r, r), center + Vector2(-r, r)])


func _world(iso := "BRA") -> GameWorld:
	var w := GameWorld.new()
	w.setup(99)
	w.set_player(w.by_iso[iso], "normal")
	return w


func _unit_named(s: Subdivisions, iso: String, unit_name: String) -> int:
	for id: int in s.roots_of(iso):
		if s.units[id].name == unit_name:
			return id
	return -1


func _merge_split() -> void:
	var w := _world()
	var s := w.subdivisions
	var pa := _unit_named(s, "BRA", "Pará")
	var am := _unit_named(s, "BRA", "Amazonas")
	var sp := _unit_named(s, "BRA", "São Paulo")
	var area_sum: float = s.units[pa].area + s.units[am].area
	var s_pieces: int = s.units[pa].pieces.size() + s.units[am].pieces.size()
	_check(not s.merge_units([pa]).ok, "fusão exige duas unidades")
	_check(not s.merge_units([pa, sp]).ok, "fusão recusa unidades sem divisa")
	var foreign := s.roots_of("ARG")[0] as int
	_check(not s.merge_units([pa, foreign]).ok, "fusão recusa outro país")
	var land := w.territories.territory_of(w.player, w)
	var am_mun: int = s.children_of(am)[0]
	var kid := s.create_unit(_box(s.units[am_mun].center, 3.0), s.add_type("Comarca", "BRA"), am_mun, land, "LAM", "BRA")
	_check(kid.ok, "unidade criada dentro de um município antes da fusão")
	var am_kids: int = s.children_of(am).size()
	var pa_kids: int = s.children_of(pa).size()
	var before: int = s.roots_of("BRA").size()
	var m := s.merge_units([pa, am])
	_check(m.ok, "funde estados vizinhos")
	var merged: Dictionary = s.units[m.id]
	_check(merged.name == "Pará" and not s.units.has(pa) and not s.units.has(am), "resultante herda o nome da primeira")
	_check(absf(float(merged.area) - area_sum) < area_sum * 0.005, "área é a soma das duas (%.2f de %.2f)" % [float(merged.area), area_sum])
	_check(merged.pieces.size() < s_pieces, "a divisa interna some: %d peças de %d" % [merged.pieces.size(), s_pieces])
	var biggest := 0.0
	for piece: PackedVector2Array in merged.pieces:
		biggest = maxf(biggest, Subdivisions.polygon_area(piece))
	_check(biggest > area_sum * 0.95, "os dois estados viram uma peça só (%.0f de %.0f)" % [biggest, area_sum])
	_check(s.roots_of("BRA").size() == before - 1, "lista de unidades do país diminui")
	_check(s.units[am_mun].parent == m.id and s.children_of(m.id).size() == am_kids + pa_kids, "municípios passam para a resultante")
	_check(s.units[kid.id].parent == am_mun, "unidade do jogador continua no município")
	var hit: int = s.unit_at(merged.center)
	_check(hit >= 0 and s.chain_of(hit)[0] == m.id, "busca por ponto acha a resultante ou um município dela")
	_check(s.custom_ids.find(m.id) < s.custom_ids.find(kid.id), "mãe continua antes da filha")
	# Sem a divisa interna: o contorno da fusão é menor que a soma dos contornos.
	var outline_a := Subdivisions._outline(merged.pieces).size()
	var raw := 0
	for piece: PackedVector2Array in merged.pieces:
		raw += piece.size() * 2
	_check(outline_a < raw, "divisa interna some do contorno (%d de %d)" % [outline_a, raw])

	var ba := _unit_named(s, "BRA", "Bahia")
	var ba_area: float = s.units[ba].area
	var c: Vector2 = s.units[ba].center
	var sp1 := s.split_unit(ba, _box(c, 6.0), "LAM")
	_check(sp1.ok, "desmembra uma parte")
	_check(absf(float(s.units[sp1.id].area) - 144.0) < 1.0, "parte nova tem a área do polígono")
	_check(absf(float(s.units[ba].area) + float(s.units[sp1.id].area) - ba_area) < 0.5, "as duas partes somam a área original")
	_check(s.units[sp1.id].parent == s.units[ba].parent and s.units[sp1.id].type == s.units[ba].type, "parte nova é irmã e do mesmo tipo")
	_check(s._contains(s.units[sp1.id], c), "parte nova cobre o ponto")
	_check(not s.split_unit(ba, _box(c + Vector2(800, 0), 6.0), "LAM").ok, "polígono fora da unidade é recusado")
	_check(not s.split_unit(ba, _box(c, 500.0), "LAM").ok, "polígono que cobre tudo é recusado")
	var mg := _unit_named(s, "BRA", "Minas Gerais")
	var inner: int = s.children_of(mg)[0]
	var sp2 := s.split_unit(mg, _box(s.units[inner].center, 12.0), "LAM")
	_check(sp2.ok and s.units[inner].parent == sp2.id, "município acompanha a parte onde está")

	var bytes := var_to_bytes(w.to_dict())
	var w2 := GameWorld.new()
	w2.setup(99)
	w2.load_dict(bytes_to_var(bytes))
	var s2 := w2.subdivisions
	_check(s2.units.has(m.id) and not s2.units.has(am), "carregar mantém a fusão")
	_check(absf(float(s2.units[ba].area) - float(s.units[ba].area)) < 0.01, "carregar mantém a forma desmembrada")
	_check(s2._contains(s2.units[sp1.id], c), "carregar mantém a parte desmembrada")
	_check(s2.units[am_mun].parent == m.id, "carregar mantém os municípios na resultante")


func _cessions() -> void:
	var w := _world()
	var t := w.territories
	var s := w.subdivisions
	var bra: Country = w.player
	var arg: Country = w.by_iso["ARG"]
	var bra_area := t.area_of(bra, w)
	var arg_area := t.area_of(arg, w)
	var misiones := _unit_named(s, "ARG", "Misiones")
	var target: Vector2 = s.units[misiones].center
	_check(misiones >= 0 and t.owner_at(target, w) == null, "antes da guerra nada foi cedido")

	# Polígono que corta só parte de uma província.
	var cordoba := _unit_named(s, "ARG", "Córdoba")
	var pc: Vector2 = s.units[cordoba].center
	var area0: float = s.units[cordoba].area
	var pieces := t.clip_to(_box(pc, 5.0), arg, w)
	_check(not pieces.is_empty(), "polígono é recortado pelo território do rival")
	var share := t.apply(pieces, arg, bra, w)
	_check(share > 0.0 and share < 0.05, "fração cedida (%s)" % str(share))
	_check(t.owner_at(pc, w) == bra, "mapa mostra o novo dono")
	_check(absf(t.area_of(bra, w) - bra_area - 100.0) < 2.0, "ganhador soma a área")
	_check(absf(arg_area - t.area_of(arg, w) - 100.0) < 2.0, "perdedor perde a área")
	_check(s.units[cordoba].owner == "ARG" and float(s.units[cordoba].area) < area0, "província cortada fica menor")
	var part: int = s.unit_at(pc)
	_check(part >= 0 and s.units[part].owner == "BRA" and s.units[part].name == "Córdoba", "parte cortada vira unidade do novo dono")
	_check(s.get_type(s.units[part].type).owner == "BRA", "tipo da unidade passa a ser do novo país")
	_check(not t.changed_outline(bra, w).is_empty() and t.changed_outline(w.by_iso["CHL"], w).is_empty(), "só quem mudou ganha contorno novo")

	# Unidade inteira muda de dono, e novos desenhos respeitam a fronteira nova.
	var mis_pieces: Array = s.units[misiones].pieces
	t.apply(mis_pieces, arg, bra, w)
	_check(s.units[misiones].owner == "BRA", "unidade inteira troca de dono")
	_check(t.owner_at(target, w) == bra, "unidade inteira aparece com o novo dono")
	_check(t.clip_to(_box(target, 1.0), arg, w).is_empty(), "rival não desenha mais na área perdida")
	_check(not t.clip_to(_box(target, 1.0), bra, w).is_empty(), "novo dono desenha na área ganha")

	# Devolução: a área volta a ser original e a cessão some.
	var restore := t.clip_to(_box(pc, 5.0), bra, w)
	var count := t.cessions.size()
	t.apply(restore, bra, arg, w)
	_check(t.cessions.size() == count - 1, "devolver remove a cessão (%d -> %d)" % [count, t.cessions.size()])
	_check(t.owner_at(pc, w) == null, "área devolvida volta ao mapa original")

	var bytes := var_to_bytes(w.to_dict())
	var w2 := GameWorld.new()
	w2.setup(99)
	w2.load_dict(bytes_to_var(bytes))
	_check(w2.territories.owner_at(target, w2) == w2.by_iso["BRA"], "carregar mantém as fronteiras")
	_check(w2.subdivisions.units[misiones].owner == "BRA", "carregar mantém o dono das unidades")
	# Cessão de país depois anexado segue o anexador.
	var chl: Country = w2.by_iso["CHL"]
	w2.diplomacy.annex(chl, w2.by_iso["BRA"], w2)
	_check(w2.territories.owner_at(target, w2) == chl, "anexação leva as áreas ganhas")


func _war_endings() -> void:
	# Vitória: o jogador escolhe e fica só com o que desenhou.
	var w := _world()
	var bra: Country = w.player
	var arg: Country = w.by_iso["ARG"]
	var prompts := []
	w.prompt_requested.connect(func(p): prompts.append(p))
	var requests := []
	w.demarcation_requested.connect(func(r): requests.append(r))
	w.diplomacy.declare_war(bra, arg, w)
	var war: Dictionary = w.diplomacy.war_between(bra.idx, arg.idx)
	prompts.clear()
	war.front = 98.0
	w.diplomacy._capitulation(war, bra, arg, w)
	var labels := []
	for o: Dictionary in prompts[-1].options:
		labels.append(o.label)
	_check("Demarcar novas fronteiras" in labels and "Não ficar com território" in labels, "capitulação oferece demarcar ou não ficar: " + str(labels))
	for o: Dictionary in prompts[-1].options:
		if o.label == "Demarcar novas fronteiras":
			o.fn.call()
	_check(requests.size() == 1 and requests[0].kind == "victory", "escolha abre a demarcação")
	_check(w.diplomacy.wars.has(war), "guerra só termina depois da demarcação")
	var pop0 := arg.pop
	var pieces := w.territories.clip_to(_box(w.subdivisions.units[_unit_named(w.subdivisions, "ARG", "Córdoba")].center, 6.0), arg, w)
	w.settle_victory(war, arg, pieces)
	_check(not w.diplomacy.wars.has(war) and arg.alive, "demarcação encerra a guerra e o rival sobrevive")
	_check(arg.pop < pop0, "população acompanha o território cedido")
	_check(w.territories.cessions.size() == 1, "mapa recebe a cessão")

	# Vitória sem ficar com nada.
	var w2 := _world()
	w2.diplomacy.declare_war(w2.player, w2.by_iso["ARG"], w2)
	var war2: Dictionary = w2.diplomacy.war_between(w2.player.idx, w2.by_iso["ARG"].idx)
	var rel0: float = w2.diplomacy.relation(w2.player.idx, w2.by_iso["ARG"].idx)
	w2.settle_victory(war2, w2.by_iso["ARG"], [])
	_check(w2.territories.cessions.is_empty() and w2.diplomacy.relation(w2.player.idx, w2.by_iso["ARG"].idx) > rel0, "não ficar com território melhora a relação e não muda o mapa")

	# Paz sem vencedor: frente equilibrada leva à negociação.
	var w3 := _world()
	var p3 := []
	w3.prompt_requested.connect(func(p): p3.append(p))
	var arg3: Country = w3.by_iso["ARG"]
	w3.diplomacy.declare_war(w3.player, arg3, w3)
	var war3: Dictionary = w3.diplomacy.war_between(w3.player.idx, arg3.idx)
	war3.front = 2.0
	arg3.war_exhaustion = 1.0
	p3.clear()
	var r: Dictionary = w3._propose_peace(arg3)
	_check(r.ok and p3.size() == 1 and p3[0].title == "Negociação de fronteiras", "paz sem vencedor abre a negociação")
	var cordoba: Vector2 = w3.subdivisions.units[_unit_named(w3.subdivisions, "ARG", "Córdoba")].center
	var greedy := w3.territories.clip_to(_box(cordoba, 80.0), arg3, w3)
	var bad: Dictionary = w3.propose_borders(war3, arg3, greedy, [])
	_check(not bad.ok and w3.diplomacy.wars.has(war3), "pedido grande demais é recusado: " + str(bad.msg))
	_check(w3.territories.cessions.is_empty(), "proposta recusada não muda o mapa")
	var small := w3.territories.clip_to(_box(cordoba, 3.0), arg3, w3)
	var rs: Vector2 = w3.subdivisions.units[_unit_named(w3.subdivisions, "BRA", "Rio Grande do Sul")].center
	var offer := w3.territories.clip_to(_box(rs, 3.0), w3.player, w3)
	var good: Dictionary = w3.propose_borders(war3, arg3, small, offer)
	_check(good.ok and not w3.diplomacy.wars.has(war3), "troca equilibrada é aceita e encerra a guerra")
	_check(w3.territories.owner_at(cordoba, w3) == w3.player and w3.territories.owner_at(rs, w3) == arg3, "troca aparece nos dois sentidos")
	# A área cedida no Rio Grande do Sul corta municípios: cada parte precisa seguir a própria mãe.
	var moved_mun := 0
	var wrong := 0
	for u: Dictionary in w3.subdivisions.units.values():
		if int(u.parent) >= 0:
			if w3.subdivisions.units[u.parent].owner != u.owner:
				wrong += 1
			if u.owner == "ARG":
				moved_mun += 1
	_check(moved_mun > 0 and wrong == 0, "municípios cedidos seguem o novo estado (%d movidos, %d errados)" % [moved_mun, wrong])
	var rs_hit: int = w3.subdivisions.unit_at(rs)
	_check(rs_hit >= 0 and w3.subdivisions.units[rs_hit].owner == "ARG", "ponto cedido pertence a uma unidade do novo dono")

	var w4 := _world()
	var arg4: Country = w4.by_iso["ARG"]
	w4.diplomacy.declare_war(w4.player, arg4, w4)
	var war4: Dictionary = w4.diplomacy.war_between(w4.player.idx, arg4.idx)
	w4.settle_old_borders(war4, arg4)
	_check(not w4.diplomacy.wars.has(war4) and w4.territories.cessions.is_empty(), "fronteiras antigas encerram a guerra sem mudar o mapa")

	# Paz em que o jogador é o vencedor nunca cede sozinha: quem decide é ele.
	var w5 := _world()
	var p5 := []
	w5.prompt_requested.connect(func(p): p5.append(p))
	var arg5: Country = w5.by_iso["ARG"]
	w5.diplomacy.declare_war(w5.player, arg5, w5)
	var war5: Dictionary = w5.diplomacy.war_between(w5.player.idx, arg5.idx)
	war5.front = 40.0
	arg5.war_exhaustion = 1.0
	p5.clear()
	var r5: Dictionary = w5._propose_peace(arg5)
	if r5.ok:
		_check(p5.size() == 1 and p5[0].title.begins_with("Vitória") and w5.territories.cessions.is_empty(), "vencedor por tratado escolhe, nada muda sozinho")
	else:
		print("rival recusou nesta rodada; repetir com outra semente")

	# Inimigo vencedor impõe a cessão ao jogador, com unidades inteiras.
	var w6 := _world()
	var arg6: Country = w6.by_iso["ARG"]
	w6.diplomacy.declare_war(arg6, w6.player, w6)
	var war6: Dictionary = w6.diplomacy.war_between(w6.player.idx, arg6.idx)
	w6.diplomacy.end_war_by_player(war6, arg6, w6.player, w6, 0.1, "Paz: %s cede {pct}." % w6.player.name)
	_check(not w6.territories.cessions.is_empty(), "derrota por tratado muda o mapa do jogador")
	var moved := 0
	for u: Dictionary in w6.subdivisions.units.values():
		if u.base and u.owner == "ARG" and w6.subdivisions.get_type(u.type).name == "Estado":
			moved += 1
	_check(moved > 0, "estados cedidos mudam de dono (%d)" % moved)
	var bra_left := w6.territories.area_of(w6.player, w6)
	_check(not w6.subdivisions.roots_of("BRA").is_empty() and bra_left > 0.0, "perdedor continua com território")

	# Guerra entre IAs: tratado altera o mapa e o texto reflete a fração real.
	var w7 := _world()
	var news := []
	w7.news_posted.connect(func(text, _k, _c): news.append(text))
	var rus: Country = w7.by_iso["RUS"]
	var kaz: Country = w7.by_iso["KAZ"]
	w7.diplomacy.declare_war(rus, kaz, w7)
	var war7: Dictionary = w7.diplomacy.war_between(rus.idx, kaz.idx)
	w7.diplomacy._end_war(war7, w7, "Tratado: %s cede {pct} a %s." % [kaz.name, rus.name], rus, kaz, 0.1)
	_check(not w7.territories.cessions.is_empty(), "tratado entre IAs muda o mapa")
	_check(not news[-1].contains("{pct}"), "notícia mostra a fração: " + str(news[-1]))
	# País de uma unidade só não consegue ceder: guerra acaba sem mudar fronteiras.
	var w8 := _world()
	var single: Country = null
	for c: Country in w8.countries:
		if c != w8.player and w8.subdivisions.roots_of(c.iso).size() == 1:
			single = c
			break
	if single:
		w8.diplomacy.declare_war(w8.by_iso["RUS"], single, w8)
		var war8: Dictionary = w8.diplomacy.war_between(w8.by_iso["RUS"].idx, single.idx)
		w8.diplomacy._end_war(war8, w8, "Tratado {pct}.", w8.by_iso["RUS"], single, 0.2)
		_check(w8.territories.cessions.is_empty() and single.alive, "%s, com uma só unidade, não perde tudo" % single.name)


func _character() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var c := Character.random(rng, "RUS")
		var group := Names.group_for("RUS")
		_check(String(c.gender) in Character.GENDERS, "gênero válido")
		_check(String(c.first_name) in Names.GROUPS[group][c.gender], "prenome do gênero sorteado: %s (%s)" % [c.first_name, c.gender])
		_check(c.name == "%s %s" % [c.first_name, c.last_name], "nome inteiro igual a prenome e sobrenome")
		if c.gender == "f":
			_check(not String(c.last_name).ends_with("ov") and not String(c.last_name).ends_with("ev"), "sobrenome russo no feminino: %s" % c.last_name)
	_check(String(Character.random(rng).name).contains(" "), "personagem aleatório tem nome e sobrenome")
	# Trocar o gênero troca o que foi sorteado e mantém o que foi digitado.
	var who := Character.random(rng, "RUS")
	Character.set_gender(who, "m", "ru", rng)
	Character.set_names(who, who.first_name, "Ivanov")
	Character.set_gender(who, "f", "ru", rng)
	_check(String(who.first_name) in Names.GROUPS.ru.f and who.last_name == "Ivanova", "trocar para feminino troca prenome e forma do sobrenome sorteados")
	who["first_rolled"] = false
	Character.set_names(who, "Boris", who.last_name)
	Character.set_gender(who, "m", "ru", rng)
	_check(who.first_name == "Boris" and who.last_name == "Ivanov", "prenome digitado fica, sobrenome sorteado volta ao masculino")
	who["last_rolled"] = false
	Character.set_gender(who, "f", "ru", rng)
	_check(who.last_name == "Ivanov" and who.name == "Boris Ivanov", "sobrenome digitado fica como está")
	_check(Names.group_for("XXX", "AFR") == "af_en" and Names.group_for("BRA") == "pt", "idioma por país, e pela região quando falta")
	var w := _world()
	who = Character.random(rng, "BRA")
	Character.set_names(who, "Teste", "da Silva")
	who.gender = "f"
	w.leader = who
	var w2 := GameWorld.new()
	w2.setup(99)
	w2.load_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	_check(w2.leader.first_name == "Teste" and w2.leader.last_name == "da Silva" and w2.leader.gender == "f", "personagem entra no save")
	# Saves antigos: só o nome inteiro, às vezes com o boneco antigo junto.
	var old := w.to_dict()
	old.leader = {"name": "Helena Moreira Prado", "skin": 3, "hat": 2, "glasses": 1, "outfit": 3}
	var w3 := GameWorld.new()
	w3.setup(99)
	w3.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(w3.leader.first_name == "Helena" and w3.leader.last_name == "Moreira Prado" and w3.leader.name == "Helena Moreira Prado", "save antigo divide o nome no primeiro espaço")
	_check(w3.leader.gender == "f" and w3.leader.has("birth_year"), "save antigo ganha gênero pelo prenome")
	old.leader = {"name": "Otávio", "face": 1, "clothes_color": Color.RED}
	w3.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(w3.leader.first_name == "Otávio" and w3.leader.last_name == "" and w3.leader.gender == "m", "nome sem sobrenome também abre")
	# Políticos: gênero e nome coerentes; os de saves antigos ganham gênero pelo prenome.
	var data: Dictionary = w.politics.data_of("RUS")
	var members := 0
	for party: Dictionary in data.parties:
		for m: Dictionary in party.members:
			if m.get("player", false):
				continue
			members += 1
			var first := String(m.name).get_slice(" ", 0)
			_check(first in Names.GROUPS.ru[m.gender], "político com prenome do gênero: %s (%s)" % [m.name, m.gender])
	_check(members > 5, "há políticos para conferir")
	var women := 0
	var everyone := 0
	for iso: String in w.politics.countries:
		for party: Dictionary in w.politics.countries[iso].parties:
			for m: Dictionary in party.members:
				everyone += 1
				women += 1 if m.get("gender", "") == "f" else 0
	_check(women > everyone * 0.4 and women < everyone * 0.6, "metade dos políticos são mulheres (%d de %d)" % [women, everyone])
	_check(Character.for_politician({"name": "Ana Souza"}).gender == "f" and Character.for_politician({"name": "Pedro Souza"}).gender == "m", "político antigo ganha gênero pelo prenome")
	# Bandeiras: todo país tem uma, e todas as cores são válidas.
	var flags: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Countryball.FLAGS))
	var lacking := []
	for c: Country in w.countries:
		if not flags.has(c.iso):
			lacking.append(c.iso)
	_check(lacking.is_empty(), "todo país tem bandeira %s" % str(lacking))
	_check(Countryball.flag("ZZZ").has("h") or Countryball.flag("ZZZ").has("v"), "país sem bandeira vira listras")


func _init() -> void:
	_merge_split()
	_cessions()
	_war_endings()
	_character()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
