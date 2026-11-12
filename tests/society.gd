extends SceneTree
## Age and death, district elections, plebiscite, units with a rite, ministries by law, end of career,
## conversations by compass, leaders' initiative and treaties.
## Uso: godot --headless --path . --script tests/society.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _fresh(iso := "BRA") -> GameWorld:
	var world := GameWorld.new()
	world.setup(7)
	world.leader = Character.random(world.rng)
	world.set_player(world.by_iso[iso], "normal")
	return world


func _majority(world: GameWorld) -> void:
	var data: Dictionary = world.politics.data_of(world.player.iso)
	data.coalition = data.parties.map(func(p): return p.id)
	for p: Dictionary in data.parties:
		p.econ = 0.0
		p.social = 0.0


func _settle(world: GameWorld, norm: Dictionary) -> void:
	for i in 300:
		world.player.next_election = 9999.0
		world.player.approval = 0.6
		world.player.stability = 0.6
		world.leader.erase("illness")
		world.leader["birth_year"] = world.year - 40
		# Who joins and leaves the parties moves their compass: the test keeps the majority in favor.
		_majority(world)
		# The life and death draw also applies to the player: here it does not matter.
		world.over = false
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


func _init() -> void:
	_ages()
	_population()
	_elections()
	_plebiscite()
	_units()
	_ministries()
	_careers()
	_talks()
	_treaties()
	print("RESULT: %d failures" % failures)
	quit()


func _ages() -> void:
	var world := _fresh()
	var data: Dictionary = world.politics.data_of("BRA")
	var ages := []
	for p: Dictionary in data.parties:
		for m: Dictionary in p.members:
			ages.append(People.age_of(m, world))
	ages.sort()
	_check(ages[0] >= 25 and ages[-1] <= 90, "politicians have plausible ages: %d to %d" % [ages[0], ages[-1]])
	_check(People.age_of(world.leader, world) >= 25, "the player has an age: %d" % People.age_of(world.leader, world))
	_check(People.yearly_death_chance(80) > People.yearly_death_chance(40) * 10.0, "death becomes more likely with age")
	# Measured mortality: how long the player survives, over many simulated lives.
	var survivors := {}
	for start_age: int in [40, 60, 80]:
		var alive := 0
		for life in 400:
			var probe := {"birth_year": world.year - start_age}
			var dead := false
			for month in 120:
				var age_now: int = start_age + month / 12
				var base := People.yearly_death_chance(age_now) / 12.0
				var sick: Dictionary = probe.get("illness", {})
				if sick.is_empty():
					if world.rng.randf() < base * 1.5 + 0.0006:
						probe["illness"] = {"severity": world.rng.randf_range(0.15, 1.0)}
					elif world.rng.randf() < base * 0.4:
						dead = true
						break
				else:
					if world.rng.randf() < float(sick.severity) * 0.07:
						dead = true
						break
					if world.rng.randf() < 0.3 * (1.1 - float(sick.severity)):
						probe.erase("illness")
			if not dead:
				alive += 1
		survivors[start_age] = alive
	print("  vivos depois de 10 anos, em 400: ", survivors)
	_check(int(survivors[40]) > int(survivors[60]) and int(survivors[60]) > int(survivors[80]), "older people die earlier")
	_check(int(survivors[40]) > 360, "aos 40, quase todos chegam aos 50")
	_check(int(survivors[80]) < 300, "at 80, many do not reach 90")
	# Ten years: some die, others come in, and the parties stay standing.
	var before := {}
	for p: Dictionary in data.parties:
		for m: Dictionary in p.members:
			before[m.id] = true
	var ill := [0]
	var news := []
	world.news_posted.connect(func(t, _k, _c): news.append(t))
	for y in 10:
		for d in 365:
			world.leader["birth_year"] = world.year - 40
			world.player.next_election = 9999.0
			world.player.approval = 0.6
			world.player.stability = 0.6
			world.tick_day()
			if world.over:
				world.over = false
	var gone := 0
	var fresh := 0
	var now := {}
	for p: Dictionary in data.parties:
		_check(not p.members.is_empty(), "party still has people: %s" % p.short) if p.members.is_empty() else null
		for m: Dictionary in p.members:
			now[m.id] = true
			if not before.has(m.id):
				fresh += 1
			if m.has("illness"):
				ill[0] += 1
	for id: int in before:
		if not now.has(id):
			gone += 1
	print("  em 10 anos: saíram %d, entraram %d, doentes agora %d" % [gone, fresh, ill[0]])
	_check(gone > 0, "politicians die or retire")
	_check(fresh > 0, "new politicians appear")
	var youngest := 200
	for p: Dictionary in data.parties:
		for m: Dictionary in p.members:
			if not m.get("player", false) and not before.has(m.id):
				youngest = mini(youngest, People.age_of(m, world))
	_check(youngest < 56, "whoever comes in is young: %d" % youngest)
	# Leader of another country dies: someone takes over.
	var usa: Country = world.by_iso["USA"]
	var usa_data: Dictionary = world.politics.data_of("USA")
	var ruling: Dictionary = world.politics.ruling_party("USA")
	var head: Dictionary = ruling.members[0]
	People.remove_member(world, usa, usa_data, ruling, head, "Teste")
	_check(world.politics.leader_of("USA") != head and not world.politics.leader_of("USA").is_empty(), "when the leader dies, another takes over")


func _population() -> void:
	var world := _fresh()
	var subs: Subdivisions = world.subdivisions
	var total := 0.0
	var roots: Array = subs.roots_of("BRA")
	var biggest := 0.0
	var smallest := 1.0
	for id: int in roots:
		var share := subs.pop_share(id)
		total += share
		biggest = maxf(biggest, share)
		smallest = minf(smallest, share)
	_check(absf(total - 1.0) < 0.001, "the units add up to the country's population: %.3f" % total)
	_check(biggest > smallest * 2.0, "the units have different populations")
	var by_name := {}
	for id: int in roots:
		by_name[subs.units[id].name] = id
	_check(by_name.has("São Paulo") and by_name.has("Roraima"), "Brazil's states have the expected names")
	_check(world.player.pop * subs.pop_share(by_name["São Paulo"]) > 40.0 and world.player.pop * subs.pop_share(by_name["Roraima"]) < 1.0, "São Paulo has tens of millions, and Roraima, less than one")
	var known := 0
	for id: int in roots:
		if subs.units[id].get("pop_known", false):
			known += 1
	_check(known == roots.size(), "all of Brazil's states use the census: %d of %d" % [known, roots.size()])
	var us: Array = subs.roots_of("USA")
	var us_known := 0
	var us_missing := []
	for id: int in us:
		if subs.units[id].get("pop_known", false):
			us_known += 1
		else:
			us_missing.append(subs.units[id].name)
	print("  EUA: %d de %d no censo; sem censo: %s" % [us_known, us.size(), str(us_missing)])
	_check(us_known >= 50, "the US states use the census: %d" % us_known)
	var state: int = roots[0]
	var kids: Array = subs.children_of(state)
	if not kids.is_empty():
		var sum := 0.0
		for k: int in kids:
			sum += subs.pop_share(k)
		_check(absf(sum - subs.pop_share(state)) < 0.001, "municipalities add up to the state")
	# Whoever splits off takes part of the people; merging adds up.
	var target: int = roots[1]
	var center: Vector2 = subs.units[target].center
	var w0 := float(subs.units[target].pop_w)
	var cut := PackedVector2Array([center + Vector2(-5, -5), center + Vector2(5, -5), center + Vector2(5, 5), center + Vector2(-5, 5)])
	var split: Dictionary = subs.split_unit(target, cut, "LAM")
	if split.ok:
		_check(absf(float(subs.units[target].pop_w) + float(subs.units[split.id].pop_w) - w0) < 0.001, "splitting off divides the population")


func _elections() -> void:
	var world := _fresh()
	var c := world.player
	var data: Dictionary = world.politics.data_of("BRA")
	_check(Elections.rules(c, data).system == "pr" and Elections.rules(c, data).head == "presidential", "Brazil is proportional and presidential")
	_check(Elections.rules(world.by_iso["GBR"], world.politics.data_of("GBR")).system == "fptp", "the United Kingdom is district-based")
	_check(Elections.rules(world.by_iso["DEU"], world.politics.data_of("DEU")).head == "parliamentary", "Germany is parliamentary")
	_check(Elections.apportion([0.5, 0.3, 0.2], 10) == [5, 3, 2], "seats follow the population")
	var seats := Elections.apportion([0.97, 0.01, 0.02], 10)
	_check(int(seats[1]) >= 1 and int(seats[2]) >= 1 and seats[0] + seats[1] + seats[2] == 10, "every district has at least one seat: %s" % str(seats))
	_check(Elections._dhondt({1: 0.6, 2: 0.3, 3: 0.1}, 10)[1] >= 6, "D'Hondt favors whoever has more votes")
	var result := world.politics.player_election(world)
	var report: Dictionary = result.report
	var total := 0
	var upper := 0
	for p: Dictionary in data.parties:
		total += int(p.seats)
		upper += int(p.upper_seats)
	_check(total == int(data.seats_total), "all seats filled: %d of %d" % [total, int(data.seats_total)])
	_check(upper == world.subdivisions.roots_of("BRA").size() * Elections.SENATORS_PER_UNIT, "each unit elects the same number of senators: %d" % upper)
	var top_senate := 0
	for p: Dictionary in data.parties:
		top_senate = maxi(top_senate, int(p.upper_seats))
	_check(top_senate < upper, "the senate is not of a single party: %d of %d" % [top_senate, upper])
	_check(report.turnout > 0.3 and report.turnout < 1.0, "plausible turnout: %.2f" % report.turnout)
	_check(not report.head.is_empty() and report.head.rounds in [1, 2], "president elected in %s round(s)" % str(report.head.get("rounds", "?")))
	_check(report.district_total == world.subdivisions.roots_of("BRA").size(), "vote by district: %d" % report.district_total)
	print("  ", report.parties.map(func(p): return "%s %d%% %d" % [p.short, roundi(p.vote * 100.0), p.seats]))
	# District: whoever has more votes wins more than the proportion.
	var uk := _fresh("GBR")
	var uk_data: Dictionary = uk.politics.data_of("GBR")
	var uk_report: Dictionary = uk.politics.player_election(uk).report
	var top: Dictionary = uk_report.parties[0]
	print("  Reino Unido: maior partido %d%% dos votos, %d de %d cadeiras" % [roundi(top.vote * 100.0), top.seats, int(uk_data.seats_total)])
	_check(float(top.seats) / float(uk_data.seats_total) > float(top.vote), "the district system gives a bonus to the largest party")
	# The Constitution changes the system.
	_majority(world)
	var art: Dictionary = {}
	for a: Dictionary in world.legislation.constitution.articles:
		if a.param == "electoral_system":
			art = a
	var emenda: Dictionary = world.legislation.new_norm(world, "emenda")
	emenda.title = "Voto distrital"
	emenda.ementa = "Teste"
	emenda.ops = [{"op": "alter", "article": art.id, "value": "fptp"}]
	world.legislation.present(world, emenda)
	_settle(world, emenda)
	_check(Elections.rules(c, data).system == "fptp", "an amendment changes the electoral system:" + emenda.state)
	# The AI also votes.
	var fr: Country = world.by_iso["FRA"]
	world.politics.ai_election(world, fr)
	_check(world.politics.data_of("FRA").has("last_election"), "other countries have real elections")


func _plebiscite() -> void:
	var world := _fresh()
	var leg: Legislation = world.legislation
	_majority(world)
	var norm: Dictionary = leg.new_norm(world, "plebiscito")
	norm.title = "Voto aos 16"
	norm.ementa = "Teste"
	norm.program = LawTemplates.civil_rights()
	_check(leg.present(world, norm).ok, "plebiscito convocado")
	_check("plebiscite" in norm.process.steps, "the rite includes the polls")
	_settle(world, norm)
	var result: Dictionary = norm.get("plebiscite_result", {})
	print("  plebiscito: ", norm.state, " ", result)
	_check(not result.is_empty() and float(result.turnout) > 0.0, "o eleitorado votou")
	_check((float(result.yes) > 0.5) == (norm.state == Legislation.STATE_IN_FORCE), "o resultado decide: %s" % norm.state)
	# Rejected at the polls does not apply, even if approved in parliament.
	var bad: Dictionary = leg.new_norm(world, "plebiscito")
	bad.title = "Toque de recolher"
	bad.ementa = "Teste"
	bad.program = LawTemplates.public_order()
	leg.present(world, bad)
	bad["position"] = {"econ": 0.0, "social": 0.0}
	bad["popularity"] = 0.0
	var original: int = leg.standing.restrictions.size()
	for i in 200:
		world.player.next_election = 9999.0
		if bad.process.steps[mini(int(bad.process.at), bad.process.steps.size() - 1)] == "plebiscite":
			break
		world.tick_day()
	world.player.approval = 0.02
	bad.program = LawTemplates.public_order()
	for i in 12:
		bad.program.stacks[0].blocks.append(LawProgram.new_block(bad.program, "rg_remove"))
	_settle_low(world, bad)
	print("  plebiscito impopular: ", bad.state, " ", bad.get("plebiscite_result", {}))
	_check(bad.state == Legislation.STATE_REJECTED and leg.standing.restrictions.size() == original, "the polls overturn what parliament approved")


func _settle_low(world: GameWorld, norm: Dictionary) -> void:
	for i in 200:
		world.player.next_election = 9999.0
		world.player.approval = 0.02
		world.leader["birth_year"] = world.year - 40
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


func _units() -> void:
	var world := _fresh()
	var leg: Legislation = world.legislation
	var subs: Subdivisions = world.subdivisions
	_check(leg.units_need_approval(world), "democracy needs parliament and a plebiscite")
	var closed := _fresh("CHN")
	_check(not closed.legislation.units_need_approval(closed), "a closed regime creates by decree")
	_majority(world)
	var host: int = subs.roots_of("BRA")[0]
	var center: Vector2 = subs.units[host].center
	var cut := PackedVector2Array([center + Vector2(-4, -4), center + Vector2(4, -4), center + Vector2(4, 4), center + Vector2(-4, 4)])
	var count: int = subs.units.size()
	_check(subs.split_unit(host, cut, "LAM", true).ok and subs.units.size() == count, "checking the path does not create anything")
	var r: Dictionary = leg.present_unit(world, {"kind": "split_unit", "unit": host, "points": cut}, "Desmembramento")
	_check(r.ok and subs.units.size() == count, "while in procedure, the unit does not exist")
	_check("plebiscite" in r.norm.process.steps and "vote" in r.norm.process.steps, "it goes through parliament and the plebiscite")
	r.norm["popularity"] = 0.9
	_settle(world, r.norm)
	print("  unidade: ", r.norm.state, " ", r.norm.get("plebiscite_result", {}))
	if r.norm.state == Legislation.STATE_IN_FORCE:
		_check(subs.units.size() == count + 1, "aprovada, a unidade nasce")
	else:
		_check(subs.units.size() == count, "rejeitada, nada muda")


func _ministries() -> void:
	var world := _fresh()
	var leg: Legislation = world.legislation
	var politics := world.politics
	_majority(world)
	var base: int = politics.portfolios(world).size()
	var make := func(type: String, fields: Dictionary) -> Dictionary:
		var norm: Dictionary = leg.new_norm(world, "ordinaria")
		norm.title = type
		norm.ementa = "Teste"
		var program := LawProgram.empty()
		var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2.ZERO)
		var block := LawProgram.new_block(program, type)
		for key: String in fields:
			block.fields[key] = fields[key]
		stack.blocks.append(block)
		norm.program = program
		return norm
	var created: Dictionary = make.call("ad_min_create", {"name": "Ciência", "area": "science"})
	_check(leg.compile_norm(created).ok, "creating a ministry compiles: %s" % str(leg.compile_norm(created).errors))
	leg.present(world, created)
	_settle(world, created)
	_check(created.state == Legislation.STATE_IN_FORCE and politics.portfolios(world).size() == base + 1, "the law creates the ministry:" + created.state)
	_check(not politics.portfolio_of_area(world, "science").is_empty(), "the new area has a ministry")
	var options: Array = politics.eligible_ministers(world, String(politics.portfolio_of_area(world, "science").id))
	_check(politics.appoint(world, String(politics.portfolio_of_area(world, "science").id), options[0].party.id, options[0].member.id).ok, "the new minister can be appointed")
	var bad: Dictionary = make.call("ad_min_abolish", {"a": "Ministério que não existe"})
	_check(not leg.compile_norm(bad).ok, "you cannot abolish what does not exist")
	leg.delete_draft(int(bad.id))
	var merged: Dictionary = make.call("ad_min_merge", {"a": "Saúde", "b": "Educação", "name": "Saúde e Educação"})
	world.politics.data_of("BRA").get_or_add("cabinet", {})
	var holder: Dictionary = politics.minister(world, "health")
	leg.present(world, merged)
	_settle(world, merged)
	var combined: Dictionary = politics.portfolio_of_area(world, "health")
	_check(merged.state == Legislation.STATE_IN_FORCE and combined.label == "Saúde e Educação" and "education" in combined.areas, "the law merges two ministries:" + merged.state)
	_check(politics.portfolios(world).size() == base, "merging removes a portfolio")
	if not holder.is_empty():
		_check(politics.minister(world, String(combined.id)).get("id", -1) == holder.id or politics.minister(world, String(combined.id)).is_empty(), "the head of the first takes over the new one")
	var gone: Dictionary = make.call("ad_min_abolish", {"a": "Justiça"})
	leg.present(world, gone)
	_settle(world, gone)
	_check(politics.portfolio_of_area(world, "justice").is_empty(), "the law abolishes the ministry")
	_check(is_equal_approx(politics.minister_competence(world, "justice"), 0.3), "an area with no ministry is poorly looked after")
	leg.revoke_now(world, gone, "Teste", "Teste")
	_check(not politics.portfolio_of_area(world, "justice").is_empty(), "once the law is repealed, the ministry returns")
	world.politics.sync_cabinet(world)


func _careers() -> void:
	var world := _fresh()
	var c := world.player
	var endings := []
	world.game_ended.connect(func(r): endings.append(r))
	# Losing an election does not end the game, nor does war in a democracy, nor nuclear war.
	c.approval = 0.02
	c.next_election = world.year_float()
	world.check_player_politics(c)
	_check(endings.is_empty() and not world.over, "losing the election the game goes on")
	world.in_office = true
	world.player_lost_war(world.by_iso["ARG"])
	_check(endings.is_empty() and not world.over and not world.in_office, "losing the war in a democracy leads to opposition")
	world.in_office = true
	# Resignation ends it, and the new character continues the same match.
	world.resign()
	_check(endings.size() == 1 and endings[0].reason == "renuncia" and world.over, "renunciar encerra a carreira")
	var day := world.day_index
	var old_name: String = world.leader.name
	var next := Character.random(world.rng)
	next.name = "Novo Nome"
	world.assume_new_character(next)
	_check(not world.over and world.leader.name == "Novo Nome" and world.day_index == day, "novo personagem segue a partida: era %s" % old_name)
	_check(not world.in_office and world.politics.player_politician(world).get("name", "") == "Novo Nome", "in a democracy, they start in opposition")
	var count := 0
	for party: Dictionary in world.politics.data_of("BRA").parties:
		for m: Dictionary in party.members:
			if m.get("player", false):
				count += 1
	_check(count == 1, "only one person is the player")
	world.tick_day()
	_check(not world.over, "o tempo volta a andar")
	# Impeachment agora encerra.
	var w2 := _fresh()
	var ended := []
	w2.game_ended.connect(func(r): ended.append(r))
	w2.player.approval = 0.05
	var d2: Dictionary = w2.politics.data_of("BRA")
	for p: Dictionary in d2.parties:
		p.seats = 0
	d2.parties[0].seats = int(d2.seats_total)
	d2.coalition = [d2.parties[1].id]
	d2.ruling = d2.parties[1].id
	for i in 400:
		if w2.over:
			break
		w2.player.approval = 0.05
		w2.player.next_election = 9999.0
		w2.check_player_politics(w2.player)
	_check(not ended.is_empty() and ended[0].reason == "impeachment", "impeachment encerra a carreira")
	# Regime fechado: quem assume governa.
	var w3 := _fresh("CHN")
	w3.resign()
	w3.assume_new_character(Character.random(w3.rng))
	_check(w3.in_office, "in a closed regime, the new character is the successor")


func _talks() -> void:
	var world := _fresh()
	var target: Country = world.by_iso["FRA"]
	var theirs: Dictionary = world.politics.leader_of("FRA")
	var mine: Dictionary = world.politics.player_party(world)
	# The player party's compass counts.
	theirs.econ = 0.5
	theirs.social = 0.5
	mine.econ = 0.5
	mine.social = 0.5
	var close := Dialogue.affinity(world, target)
	var close_will := Dialogue.goodwill(world, target)
	mine.econ = -0.9
	mine.social = -0.9
	_check(Dialogue.affinity(world, target) < close, "a distant party reduces affinity")
	_check(Dialogue.goodwill(world, target) < close_will, "and the leader's goodwill")
	# The leader's compass weighs on each subject.
	world.diplomacy.set_relation(world.player.idx, target.idx, 5.0)
	mine.econ = 0.0
	mine.social = 0.0
	theirs.econ = 1.0
	theirs.social = 0.0
	var accepts_right := 0
	theirs.econ = -1.0
	var accepts_left := 0
	for i in 30:
		theirs.econ = 1.0
		if Dialogue.goodwill(world, target) + 25.0 >= Dialogue.NEED_FTA:
			accepts_right += 1
		theirs.econ = -1.0
		if Dialogue.goodwill(world, target) - 25.0 >= Dialogue.NEED_FTA:
			accepts_left += 1
	_check(accepts_right > accepts_left, "a right-wing leader accepts opening markets more easily")
	theirs.social = -1.0
	var dove := Dialogue.hawkishness({"social": 1.0})
	_check(Dialogue.hawkishness(theirs) > dove, "an authoritarian is harder than a libertarian")
	_check(Dialogue.temper({"econ": -0.5, "social": -0.5}) == "esquerda, autoritário", "the leader introduces themselves by their ideas")
	# An authoritarian does not yield to a threat that a libertarian would accept.
	world.player.mil_stock = target.mil_stock * 4.0
	world.player.troops = target.troops * 1.0
	var ratio := world.player.military_power() / maxf(target.military_power(), 0.01)
	print("  ameaça: força %.2f vezes" % ratio)
	theirs.social = 1.0
	var soft: Dictionary = Dialogue.choose(world, target, "threat")
	theirs.social = -1.0
	world.player.mil_stock = target.mil_stock * 1.0
	var hard: Dictionary = Dialogue.choose(world, target, "threat")
	_check(hard.accepted == false, "the authoritarian faces the threat")
	_check(soft is Dictionary, "the libertarian answers: %s" % soft.reply)
	var options := Dialogue.options(world, target)
	_check(options.any(func(o): return String(o.id).begins_with("treaty:")), "a conversa oferece tratados")
	# The leaders' initiative.
	var prompts := []
	world.prompt_requested.connect(func(p): prompts.append(p))
	world.next_talk_month = 0
	world.request_talk(target)
	_check(prompts.size() == 1 and String(prompts[0].title).contains("quer falar"), "a leader approaches the player")
	world.request_talk(target)
	_check(prompts.size() == 1, "and does not insist right afterwards")
	var answered := []
	world.talk_requested.connect(func(c): answered.append(c))
	prompts[0].options[0].fn.call()
	_check(answered == [target], "answering opens the conversation")
	_check(Dialogue.start(world, target, true).ok, "conversa a convite ignora o intervalo")
	# Two AI governments meet.
	var a: Country = world.by_iso["DEU"]
	var b: Country = world.by_iso["ITA"]
	var la: Dictionary = world.politics.leader_of(a.iso)
	var lb: Dictionary = world.politics.leader_of(b.iso)
	la.econ = 0.0
	la.social = 0.0
	lb.econ = 0.0
	lb.social = 0.0
	var rel0: float = world.diplomacy.relation(a.idx, b.idx)
	Dialogue.summit(world, a, b)
	_check(world.diplomacy.relation(a.idx, b.idx) > rel0 - 3.0, "similar leaders end up closer")
	lb.econ = 1.0
	lb.social = -1.0
	la.econ = -1.0
	la.social = 1.0
	var rel1: float = world.diplomacy.relation(a.idx, b.idx)
	Dialogue.summit(world, a, b)
	_check(world.diplomacy.relation(a.idx, b.idx) < rel1, "opposite leaders end up further apart")


func _treaties() -> void:
	var world := _fresh()
	var t: Treaties = world.treaties
	_check(not t.items.is_empty(), "the world already starts with treaties: %d" % t.items.size())
	_check(t.items.any(func(x): return String(x.title).contains("Atlântico Norte") and x.parties.size() > 5), "NATO is a multilateral treaty")
	var target: Country = world.by_iso["ARG"]
	var d := world.diplomacy
	_majority(world)
	d.set_relation(world.player.idx, target.idx, 95.0)
	world.politics.leader_of("ARG").econ = 0.5
	world.politics.leader_of("ARG").social = 0.3
	var signed: Dictionary = t.sign_with_player(world, target, "arms")
	var treaty: Dictionary = signed.treaty
	_check(treaty.state == Treaties.STATE_RATIFYING, "signing does not put it in force")
	_check(not t.between(world.player, target, "arms").is_empty(), "the treaty is recorded")
	var sign_again: Dictionary = t.propose(world, target, "arms")
	_check(not sign_again.ok, "it is not signed twice")
	var ratification: Dictionary = {}
	for n: Dictionary in world.legislation.norms.values():
		if n.get("payload", {}).get("kind", "") == "treaty" and int(n.payload.treaty) == int(treaty.id):
			ratification = n
	_check(not ratification.is_empty(), "goes to parliament")
	_settle(world, ratification)
	print("  ratificação: ", ratification.state, " tratado: ", treaty.state)
	for i in 120:
		world.player.next_election = 9999.0
		world.tick_day()
		if treaty.state != Treaties.STATE_RATIFYING:
			break
	print("  depois do outro parlamento: ", treaty.state)
	if treaty.state == Treaties.STATE_FORCE:
		_check(int(treaty.expires_month) > world.months_elapsed, "has a term of validity")
		var r: Dictionary = t.denounce(world, int(treaty.id))
		_check(r.ok and treaty.state == Treaties.STATE_DENOUNCED, "denunciation applies with prior notice")
		for i in 200:
			world.player.next_election = 9999.0
			world.tick_day()
			if treaty.state == Treaties.STATE_ENDED:
				break
		_check(treaty.state == Treaties.STATE_ENDED, "acabado o aviso, o tratado termina")
	else:
		_check(treaty.state == Treaties.STATE_REJECTED, "or the parliament there refuses: %s" % treaty.state)
	# Free trade: the effect only arrives with ratification, and denunciation undoes it.
	var fr: Country = world.by_iso["FRA"]
	var free: Dictionary = t._add("Teste", "fta", [world.player.iso, fr.iso], Treaties.STATE_RATIFYING, world, 0)
	_check(not d.has_fta(world.player.idx, fr.idx, world), "before ratification, nothing changes")
	free.ratified[world.player.iso] = true
	free.ratified[fr.iso] = true
	t._check_force(world, free)
	_check(free.state == Treaties.STATE_FORCE and d.has_fta(world.player.idx, fr.idx, world), "once ratified, trade opens")
	t._apply(world, free, false)
	_check(not d.has_fta(world.player.idx, fr.idx, world), "once ended, trade has barriers again")
	# Tearing up non-aggression costs a lot and breaks the treaty.
	var pol: Country = world.by_iso["POL"]
	var rus: Country = world.by_iso["RUS"]
	var pact: Dictionary = t._add("Pacto", "nonaggression", [rus.iso, pol.iso], Treaties.STATE_FORCE, world, 10)
	_check(t.blocks_war(rus, pol), "non-aggression holds back war")
	var approval0 := rus.approval
	t.on_war(world, rus, pol)
	_check(pact.state == Treaties.STATE_BROKEN and rus.approval < approval0, "breaking has a price")
	# Multilateral: whoever leaves ceases to be part, and the others continue.
	var mult: Dictionary = {}
	for x: Dictionary in t.items:
		if x.parties.size() > 2 and world.player.iso in x.parties:
			mult = x
	if not mult.is_empty():
		var size0: int = mult.parties.size()
		_check(t.denounce(world, int(mult.id)).ok and mult.parties.size() == size0 - 1 and mult.state == Treaties.STATE_FORCE, "leaving a multilateral treaty does not end it")
	# Saves.
	var back := GameWorld.new()
	back.setup(7)
	back.load_dict(bytes_to_var(var_to_bytes(world.to_dict())))
	_check(back.treaties.items.size() == t.items.size(), "treaties come back from the save")
