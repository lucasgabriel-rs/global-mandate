extends SceneTree
## Tests of merging, splitting off, territorial cessions and the end of a war, without the interface.
## Usage: godot --headless --path . -s tests/borders.gd

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
	_check(not s.merge_units([pa]).ok, "merge requires two units")
	_check(not s.merge_units([pa, sp]).ok, "merge refuses units with no shared border")
	var foreign := s.roots_of("ARG")[0] as int
	_check(not s.merge_units([pa, foreign]).ok, "merge refuses another country")
	var land := w.territories.territory_of(w.player, w)
	var am_mun: int = s.children_of(am)[0]
	var kid := s.create_unit(_box(s.units[am_mun].center, 3.0), s.add_type("Comarca", "BRA"), am_mun, land, "LAM", "BRA")
	_check(kid.ok, "unit created inside a municipality before the merge")
	var am_kids: int = s.children_of(am).size()
	var pa_kids: int = s.children_of(pa).size()
	var before: int = s.roots_of("BRA").size()
	var m := s.merge_units([pa, am])
	_check(m.ok, "funde estados vizinhos")
	var merged: Dictionary = s.units[m.id]
	_check(merged.name == "Pará" and not s.units.has(pa) and not s.units.has(am), "result inherits the name of the first")
	_check(absf(float(merged.area) - area_sum) < area_sum * 0.005, "area is the sum of both (%.2f of %.2f)" % [float(merged.area), area_sum])
	_check(merged.pieces.size() < s_pieces, "the internal border disappears: %d pieces of %d" % [merged.pieces.size(), s_pieces])
	var biggest := 0.0
	for piece: PackedVector2Array in merged.pieces:
		biggest = maxf(biggest, Subdivisions.polygon_area(piece))
	_check(biggest > area_sum * 0.95, "the two states become a single piece (%.0f of %.0f)" % [biggest, area_sum])
	_check(s.roots_of("BRA").size() == before - 1, "the country's unit list shrinks")
	_check(s.units[am_mun].parent == m.id and s.children_of(m.id).size() == am_kids + pa_kids, "municipalities pass to the result")
	_check(s.units[kid.id].parent == am_mun, "the player's unit stays in the municipality")
	var hit: int = s.unit_at(merged.center)
	_check(hit >= 0 and s.chain_of(hit)[0] == m.id, "point lookup finds the result or one of its municipalities")
	_check(s.custom_ids.find(m.id) < s.custom_ids.find(kid.id), "parent stays before the child")
	# Without the internal border: the outline of the merge is smaller than the sum of the outlines.
	var outline_a := Subdivisions._outline(merged.pieces).size()
	var raw := 0
	for piece: PackedVector2Array in merged.pieces:
		raw += piece.size() * 2
	_check(outline_a < raw, "internal border disappears from the outline (%d of %d)" % [outline_a, raw])

	var ba := _unit_named(s, "BRA", "Bahia")
	var ba_area: float = s.units[ba].area
	var c: Vector2 = s.units[ba].center
	var sp1 := s.split_unit(ba, _box(c, 6.0), "LAM")
	_check(sp1.ok, "splits off a part")
	_check(absf(float(s.units[sp1.id].area) - 144.0) < 1.0, "new part has the polygon's area")
	_check(absf(float(s.units[ba].area) + float(s.units[sp1.id].area) - ba_area) < 0.5, "the two parts add up to the original area")
	_check(s.units[sp1.id].parent == s.units[ba].parent and s.units[sp1.id].type == s.units[ba].type, "new part is a sibling and of the same type")
	_check(s._contains(s.units[sp1.id], c), "parte nova cobre o ponto")
	_check(not s.split_unit(ba, _box(c + Vector2(800, 0), 6.0), "LAM").ok, "polygon outside the unit is refused")
	_check(not s.split_unit(ba, _box(c, 500.0), "LAM").ok, "polygon that covers everything is refused")
	var mg := _unit_named(s, "BRA", "Minas Gerais")
	var inner: int = s.children_of(mg)[0]
	var sp2 := s.split_unit(mg, _box(s.units[inner].center, 12.0), "LAM")
	_check(sp2.ok and s.units[inner].parent == sp2.id, "municipality follows the part where it is")

	var bytes := var_to_bytes(w.to_dict())
	var w2 := GameWorld.new()
	w2.setup(99)
	w2.load_dict(bytes_to_var(bytes))
	var s2 := w2.subdivisions
	_check(s2.units.has(m.id) and not s2.units.has(am), "loading keeps the merge")
	_check(absf(float(s2.units[ba].area) - float(s.units[ba].area)) < 0.01, "loading keeps the split shape")
	_check(s2._contains(s2.units[sp1.id], c), "loading keeps the split part")
	_check(s2.units[am_mun].parent == m.id, "loading keeps the municipalities in the result")


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
	_check(misiones >= 0 and t.owner_at(target, w) == null, "before the war nothing was ceded")

	# Polygon that cuts only part of a province.
	var cordoba := _unit_named(s, "ARG", "Córdoba")
	var pc: Vector2 = s.units[cordoba].center
	var area0: float = s.units[cordoba].area
	var pieces := t.clip_to(_box(pc, 5.0), arg, w)
	_check(not pieces.is_empty(), "polygon is clipped by the rival's territory")
	var share := t.apply(pieces, arg, bra, w)
	_check(share > 0.0 and share < 0.05, "fraction ceded (%s)" % str(share))
	_check(t.owner_at(pc, w) == bra, "map shows the new owner")
	_check(absf(t.area_of(bra, w) - bra_area - 100.0) < 2.0, "winner adds the area")
	_check(absf(arg_area - t.area_of(arg, w) - 100.0) < 2.0, "loser loses the area")
	_check(s.units[cordoba].owner == "ARG" and float(s.units[cordoba].area) < area0, "cut province gets smaller")
	var part: int = s.unit_at(pc)
	_check(part >= 0 and s.units[part].owner == "BRA" and s.units[part].name == "Córdoba", "cut part becomes a unit of the new owner")
	_check(s.get_type(s.units[part].type).owner == "BRA", "the unit's type becomes the new country's")
	_check(not t.changed_outline(bra, w).is_empty() and t.changed_outline(w.by_iso["CHL"], w).is_empty(), "only whoever changed gets a new outline")

	# A whole unit changes owner, and new drawings respect the new border.
	var mis_pieces: Array = s.units[misiones].pieces
	t.apply(mis_pieces, arg, bra, w)
	_check(s.units[misiones].owner == "BRA", "whole unit changes owner")
	_check(t.owner_at(target, w) == bra, "whole unit appears with the new owner")
	_check(t.clip_to(_box(target, 1.0), arg, w).is_empty(), "rival no longer draws in the lost area")
	_check(not t.clip_to(_box(target, 1.0), bra, w).is_empty(), "new owner draws in the gained area")

	# Return: the area goes back to being the original and the cession disappears.
	var restore := t.clip_to(_box(pc, 5.0), bra, w)
	var count := t.cessions.size()
	t.apply(restore, bra, arg, w)
	_check(t.cessions.size() == count - 1, "returning removes the cession (%d -> %d)" % [count, t.cessions.size()])
	_check(t.owner_at(pc, w) == null, "returned area goes back to the original map")

	var bytes := var_to_bytes(w.to_dict())
	var w2 := GameWorld.new()
	w2.setup(99)
	w2.load_dict(bytes_to_var(bytes))
	_check(w2.territories.owner_at(target, w2) == w2.by_iso["BRA"], "loading keeps the borders")
	_check(w2.subdivisions.units[misiones].owner == "BRA", "loading keeps the owner of the units")
	# Cession by a country later annexed follows the annexer.
	var chl: Country = w2.by_iso["CHL"]
	w2.diplomacy.annex(chl, w2.by_iso["BRA"], w2)
	_check(w2.territories.owner_at(target, w2) == chl, "annexation takes the gained areas")


func _war_endings() -> void:
	# Victory: the player chooses and keeps only what they drew.
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
	_check("Demarcar novas fronteiras" in labels and "Não ficar com território" in labels, "capitulation offers to demarcate or not to keep:" + str(labels))
	for o: Dictionary in prompts[-1].options:
		if o.label == "Demarcar novas fronteiras":
			o.fn.call()
	_check(requests.size() == 1 and requests[0].kind == "victory", "choice opens the demarcation")
	_check(w.diplomacy.wars.has(war), "war only ends after the demarcation")
	var pop0 := arg.pop
	var pieces := w.territories.clip_to(_box(w.subdivisions.units[_unit_named(w.subdivisions, "ARG", "Córdoba")].center, 6.0), arg, w)
	w.settle_victory(war, arg, pieces)
	_check(not w.diplomacy.wars.has(war) and arg.alive, "demarcation ends the war and the rival survives")
	_check(arg.pop < pop0, "population follows the ceded territory")
	_check(w.territories.cessions.size() == 1, "map receives the cession")

	# Victory without keeping anything.
	var w2 := _world()
	w2.diplomacy.declare_war(w2.player, w2.by_iso["ARG"], w2)
	var war2: Dictionary = w2.diplomacy.war_between(w2.player.idx, w2.by_iso["ARG"].idx)
	var rel0: float = w2.diplomacy.relation(w2.player.idx, w2.by_iso["ARG"].idx)
	w2.settle_victory(war2, w2.by_iso["ARG"], [])
	_check(w2.territories.cessions.is_empty() and w2.diplomacy.relation(w2.player.idx, w2.by_iso["ARG"].idx) > rel0, "not keeping territory improves the relation and does not change the map")

	# Peace with no winner: a balanced front leads to negotiation.
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
	_check(r.ok and p3.size() == 1 and p3[0].title == "Negociação de fronteiras", "peace with no winner opens the negotiation")
	var cordoba: Vector2 = w3.subdivisions.units[_unit_named(w3.subdivisions, "ARG", "Córdoba")].center
	var greedy := w3.territories.clip_to(_box(cordoba, 80.0), arg3, w3)
	var bad: Dictionary = w3.propose_borders(war3, arg3, greedy, [])
	_check(not bad.ok and w3.diplomacy.wars.has(war3), "too large a request is refused:" + str(bad.msg))
	_check(w3.territories.cessions.is_empty(), "refused proposal does not change the map")
	var small := w3.territories.clip_to(_box(cordoba, 3.0), arg3, w3)
	var rs: Vector2 = w3.subdivisions.units[_unit_named(w3.subdivisions, "BRA", "Rio Grande do Sul")].center
	var offer := w3.territories.clip_to(_box(rs, 3.0), w3.player, w3)
	var good: Dictionary = w3.propose_borders(war3, arg3, small, offer)
	_check(good.ok and not w3.diplomacy.wars.has(war3), "balanced swap is accepted and ends the war")
	_check(w3.territories.owner_at(cordoba, w3) == w3.player and w3.territories.owner_at(rs, w3) == arg3, "swap appears in both directions")
	# The area ceded in Rio Grande do Sul cuts municipalities: each part must follow its own parent.
	var moved_mun := 0
	var wrong := 0
	for u: Dictionary in w3.subdivisions.units.values():
		if int(u.parent) >= 0:
			if w3.subdivisions.units[u.parent].owner != u.owner:
				wrong += 1
			if u.owner == "ARG":
				moved_mun += 1
	_check(moved_mun > 0 and wrong == 0, "ceded municipalities follow the new state (%d moved, %d wrong)" % [moved_mun, wrong])
	var rs_hit: int = w3.subdivisions.unit_at(rs)
	_check(rs_hit >= 0 and w3.subdivisions.units[rs_hit].owner == "ARG", "ceded point belongs to a unit of the new owner")

	var w4 := _world()
	var arg4: Country = w4.by_iso["ARG"]
	w4.diplomacy.declare_war(w4.player, arg4, w4)
	var war4: Dictionary = w4.diplomacy.war_between(w4.player.idx, arg4.idx)
	w4.settle_old_borders(war4, arg4)
	_check(not w4.diplomacy.wars.has(war4) and w4.territories.cessions.is_empty(), "old borders end the war without changing the map")

	# Peace in which the player is the winner never cedes on its own: the player decides.
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
		_check(p5.size() == 1 and p5[0].title.begins_with("Vitória") and w5.territories.cessions.is_empty(), "winner by treaty chooses, nothing changes on its own")
	else:
		print("rival refused this round; repeat with another seed")

	# The winning enemy imposes the cession on the player, with whole units.
	var w6 := _world()
	var arg6: Country = w6.by_iso["ARG"]
	w6.diplomacy.declare_war(arg6, w6.player, w6)
	var war6: Dictionary = w6.diplomacy.war_between(w6.player.idx, arg6.idx)
	w6.diplomacy.end_war_by_player(war6, arg6, w6.player, w6, 0.1, "Paz: %s cede {pct}." % w6.player.name)
	_check(not w6.territories.cessions.is_empty(), "defeat by treaty changes the player's map")
	var moved := 0
	for u: Dictionary in w6.subdivisions.units.values():
		if u.base and u.owner == "ARG" and w6.subdivisions.get_type(u.type).name == "Estado":
			moved += 1
	_check(moved > 0, "ceded states change owner (%d)" % moved)
	var bra_left := w6.territories.area_of(w6.player, w6)
	_check(not w6.subdivisions.roots_of("BRA").is_empty() and bra_left > 0.0, "loser keeps territory")

	# War between AIs: the treaty changes the map and the text reflects the real fraction.
	var w7 := _world()
	var news := []
	w7.news_posted.connect(func(text, _k, _c): news.append(text))
	var rus: Country = w7.by_iso["RUS"]
	var kaz: Country = w7.by_iso["KAZ"]
	w7.diplomacy.declare_war(rus, kaz, w7)
	var war7: Dictionary = w7.diplomacy.war_between(rus.idx, kaz.idx)
	w7.diplomacy._end_war(war7, w7, "Tratado: %s cede {pct} a %s." % [kaz.name, rus.name], rus, kaz, 0.1)
	_check(not w7.territories.cessions.is_empty(), "treaty between AIs changes the map")
	_check(not news[-1].contains("{pct}"), "news shows the fraction:" + str(news[-1]))
	# A country with a single unit cannot cede: the war ends without changing borders.
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
		_check(w8.territories.cessions.is_empty() and single.alive, "%s, with a single unit, does not lose everything" % single.name)


func _character() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var c := Character.random(rng, "RUS")
		var group := Names.group_for("RUS")
		_check(String(c.gender) in Character.GENDERS, "valid gender")
		_check(String(c.first_name) in Names.GROUPS[group][c.gender], "first name of the drawn gender: %s (%s)" % [c.first_name, c.gender])
		_check(c.name == "%s %s" % [c.first_name, c.last_name], "nome inteiro igual a prenome e sobrenome")
		if c.gender == "f":
			_check(not String(c.last_name).ends_with("ov") and not String(c.last_name).ends_with("ev"), "Russian surname in the feminine: %s" % c.last_name)
	_check(String(Character.random(rng).name).contains(" "), "random character has first name and surname")
	# Switching gender swaps what was drawn and keeps what was typed.
	var who := Character.random(rng, "RUS")
	Character.set_gender(who, "m", "ru", rng)
	Character.set_names(who, who.first_name, "Ivanov")
	Character.set_gender(who, "f", "ru", rng)
	_check(String(who.first_name) in Names.GROUPS.ru.f and who.last_name == "Ivanova", "switching to female swaps the drawn first name and surname form")
	who["first_rolled"] = false
	Character.set_names(who, "Boris", who.last_name)
	Character.set_gender(who, "m", "ru", rng)
	_check(who.first_name == "Boris" and who.last_name == "Ivanov", "typed first name stays, drawn surname goes back to masculine")
	who["last_rolled"] = false
	Character.set_gender(who, "f", "ru", rng)
	_check(who.last_name == "Ivanov" and who.name == "Boris Ivanov", "typed surname stays as is")
	_check(Names.group_for("XXX", "AFR") == "af_en" and Names.group_for("BRA") == "pt", "language by country, and by region when missing")
	var w := _world()
	who = Character.random(rng, "BRA")
	Character.set_names(who, "Teste", "da Silva")
	who.gender = "f"
	w.leader = who
	var w2 := GameWorld.new()
	w2.setup(99)
	w2.load_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	_check(w2.leader.first_name == "Teste" and w2.leader.last_name == "da Silva" and w2.leader.gender == "f", "character goes into the save")
	# Old saves: only the full name, sometimes with the old doll attached.
	var old := w.to_dict()
	old.leader = {"name": "Helena Moreira Prado", "skin": 3, "hat": 2, "glasses": 1, "outfit": 3}
	var w3 := GameWorld.new()
	w3.setup(99)
	w3.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(w3.leader.first_name == "Helena" and w3.leader.last_name == "Moreira Prado" and w3.leader.name == "Helena Moreira Prado", "old save splits the name at the first space")
	_check(w3.leader.gender == "f" and w3.leader.has("birth_year"), "old save gets gender from the first name")
	old.leader = {"name": "Otávio", "face": 1, "clothes_color": Color.RED}
	w3.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(w3.leader.first_name == "Otávio" and w3.leader.last_name == "" and w3.leader.gender == "m", "a name without a surname also opens")
	# Politicians: coherent gender and name; those from old saves get gender from the first name.
	var data: Dictionary = w.politics.data_of("RUS")
	var members := 0
	for party: Dictionary in data.parties:
		for m: Dictionary in party.members:
			if m.get("player", false):
				continue
			members += 1
			var first := String(m.name).get_slice(" ", 0)
			_check(first in Names.GROUPS.ru[m.gender], "politician with a first name of the gender: %s (%s)" % [m.name, m.gender])
	_check(members > 5, "there are politicians to check")
	var women := 0
	var everyone := 0
	for iso: String in w.politics.countries:
		for party: Dictionary in w.politics.countries[iso].parties:
			for m: Dictionary in party.members:
				everyone += 1
				women += 1 if m.get("gender", "") == "f" else 0
	_check(women > everyone * 0.4 and women < everyone * 0.6, "half of the politicians are women (%d of %d)" % [women, everyone])
	_check(Character.for_politician({"name": "Ana Souza"}).gender == "f" and Character.for_politician({"name": "Pedro Souza"}).gender == "m", "old politician gets gender from the first name")
	# Flags: every country has one, and all the colors are valid.
	var flags: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Countryball.FLAGS))
	var lacking := []
	for c: Country in w.countries:
		if not flags.has(c.iso):
			lacking.append(c.iso)
	_check(lacking.is_empty(), "every country has a flag %s" % str(lacking))
	_check(Countryball.flag("ZZZ").has("h") or Countryball.flag("ZZZ").has("v"), "country without a flag becomes stripes")


func _init() -> void:
	_merge_split()
	_cessions()
	_war_endings()
	_character()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
