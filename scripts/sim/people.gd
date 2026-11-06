class_name People
extends RefCounted
## O ciclo de vida dos políticos: envelhecer, adoecer, morrer, se aposentar e dar lugar a gente nova.
## Todos os políticos do mundo passam por aqui uma vez por mês, e o jogador também.

const ILLNESSES := ["pneumonia", "uma cardiopatia", "um câncer", "um derrame", "uma infecção grave", "uma doença autoimune"]  # i18n-all
const RETIRE_AGE := 72
const RETIRE_CHANCE := 0.012
const NEW_FACE_MIN_AGE := 25
const NEW_FACE_MAX_AGE := 45
const PARTY_MIN_MEMBERS := 5
const PARTY_MAX_MEMBERS := 12
const NEW_FACE_CHANCE := 0.35
## Chance mensal de um atentado contra um chefe de governo, sem agravantes.
const ASSASSINATION_BASE := 0.00004
## O mundo inteiro tem milhares de políticos: cada país passa por aqui a cada tantos meses, com o risco acumulado.
## O país do jogador é visto todo mês.
const WORLD_STEP_MONTHS := 3


static func age_of(person: Dictionary, world: GameWorld) -> int:
	return world.year - int(person.get("birth_year", world.start_year - 50))


## Chance de morrer em um ano: dobra a cada 8 anos de idade, como nas tábuas de mortalidade.
static func yearly_death_chance(age: int) -> float:
	return minf(0.00008 * exp(0.085 * float(age)), 0.6)


static func step_month(world: GameWorld) -> void:
	var new_year: bool = world.month == 0
	for c: Country in world.countries:
		if not c.alive:
			continue
		var data: Dictionary = world.politics.data_of(c.iso)
		if data.is_empty():
			continue
		var months := 1 if c == world.player else WORLD_STEP_MONTHS
		if months == 1 or (c.idx + world.months_elapsed) % months == 0:
			for party: Dictionary in data.parties:
				for member: Dictionary in party.members.duplicate():
					if not member.get("player", false):
						_step_person(world, c, data, party, member, months)
			_step_leader_risk(world, c, data, months)
		if new_year:
			for party: Dictionary in data.parties:
				_renew(world, c, data, party)
	_step_player(world)


static func _step_person(world: GameWorld, c: Country, data: Dictionary, party: Dictionary, member: Dictionary, months: int) -> void:
	var rng := world.rng
	var age := age_of(member, world)
	var base := yearly_death_chance(age) / 12.0 * months
	var sick: Dictionary = member.get("illness", {})
	if sick.is_empty():
		if rng.randf() < base * 1.5 + 0.0006 * months:
			member["illness"] = {"name": ILLNESSES[rng.randi() % ILLNESSES.size()], "severity": rng.randf_range(0.15, 1.0)}
			if _is_head(c, data, party, member) and _matters(c, world):
				world.emit_news(TranslationServer.translate("%s, líder de %s, foi diagnosticado com %s.") % [member.name, c.name, TranslationServer.translate(member.illness.name)], "politica", c)
		elif rng.randf() < base * 0.4:
			remove_member(world, c, data, party, member, TranslationServer.translate("Morre %s, aos %d anos") % [member.name, age])
			return
	else:
		if rng.randf() < float(sick.severity) * 0.07 * months:
			remove_member(world, c, data, party, member, TranslationServer.translate("Morre %s, aos %d anos, depois de enfrentar %s") % [member.name, age, TranslationServer.translate(sick.name)])
			return
		if rng.randf() < 0.3 * months * (1.1 - float(sick.severity)):
			member.erase("illness")
	if age >= RETIRE_AGE and party.members.size() > 2 and rng.randf() < RETIRE_CHANCE * months:
		remove_member(world, c, data, party, member, TranslationServer.translate("%s se aposenta da política aos %d anos") % [member.name, age])


static func _is_head(c: Country, data: Dictionary, party: Dictionary, member: Dictionary) -> bool:
	return int(party.id) == int(data.ruling) and not party.members.is_empty() and party.members[0] == member


static func _matters(c: Country, world: GameWorld) -> bool:
	return c == world.player or c.y_usd() > world.world_gdp() * NationAI.NEWS_SHARE


## Tira a pessoa do partido. Pasta fica vaga, a liderança passa adiante, e a bússola refaz a média.
static func remove_member(world: GameWorld, c: Country, data: Dictionary, party: Dictionary, member: Dictionary, why: String) -> void:
	var was_head := _is_head(c, data, party, member)
	var was_leader: bool = party.members[0] == member
	party.members.erase(member)
	var cabinet: Dictionary = data.get("cabinet", {})
	for post: String in cabinet.keys():
		if int(cabinet[post].party) == int(party.id) and int(cabinet[post].member) == int(member.id):
			cabinet.erase(post)
			if c == world.player:
				world.emit_news(TranslationServer.translate("%s. A pasta ficou vaga.") % why, "politica", c)
	if party.members.is_empty():
		world.politics.add_new_members(data, party, 3, world.year)
	if was_leader:
		var best: Dictionary = party.members[0]
		for m: Dictionary in party.members:
			if m.get("player", false):
				best = m
				break
			if float(m.competence) > float(best.competence):
				best = m
		party.members.erase(best)
		party.members.push_front(best)
	Politics.refresh_compass(party)
	world.politics.revision += 1
	if was_head and _matters(c, world):
		world.emit_news(TranslationServer.translate("%s. %s assume o governo de %s.") % [why, party.members[0].name, c.name], "crise", c)
	if was_head:
		c.stability = clampf(c.stability - 0.02, 0.03, 0.97)
		world.diplomacy.on_government_change(c, world)


## Todo janeiro, os partidos renovam os quadros: gente mais nova entra, sobretudo onde faltam nomes.
static func _renew(world: GameWorld, c: Country, data: Dictionary, party: Dictionary) -> void:
	var size: int = party.members.size()
	var wanted := 0
	if size < PARTY_MIN_MEMBERS:
		wanted = PARTY_MIN_MEMBERS - size
	elif size < PARTY_MAX_MEMBERS and world.rng.randf() < NEW_FACE_CHANCE:
		wanted = 1
	if wanted == 0:
		return
	world.politics.add_new_members(data, party, wanted, world.year)
	if c == world.player and int(party.id) == int(data.player_party):
		world.emit_news(TranslationServer.translate("Novo nome em %s: %s, de %d anos, começa na política.") % [party.short, party.members[-1].name, age_of(party.members[-1], world)], "politica", c)


## Atentados são raros, mas regimes instáveis e guerras aumentam o risco.
static func assassination_chance(c: Country, world: GameWorld) -> float:
	var risk := ASSASSINATION_BASE
	if c.stability < 0.25:
		risk += 0.0012
	if c.dem < 4.0:
		risk += 0.0002
	if c.unrest > 0.3:
		risk += 0.0006
	if world.diplomacy.in_war(c.idx):
		risk += 0.0002
	return risk


static func _step_leader_risk(world: GameWorld, c: Country, data: Dictionary, months: int) -> void:
	if c == world.player and world.in_office:
		return
	if world.rng.randf() >= assassination_chance(c, world) * months:
		return
	var party: Dictionary = world.politics.ruling_party(c.iso)
	if party.is_empty() or party.members.is_empty() or party.members[0].get("player", false):
		return
	var head: Dictionary = party.members[0]
	remove_member(world, c, data, party, head, TranslationServer.translate("%s, líder de %s, é assassinado") % [head.name, c.name])


static func _step_player(world: GameWorld) -> void:
	var c := world.player
	if c == null or world.over or world.leader.is_empty():
		return
	var leader: Dictionary = world.leader
	var rng := world.rng
	var age := age_of(leader, world)
	var base := yearly_death_chance(age) / 12.0
	if world.in_office and rng.randf() < assassination_chance(c, world):
		world._finish("assassinato", TranslationServer.translate("%s foi assassinado aos %d anos, em um atentado que chocou %s.") % [leader.get("name", TranslationServer.translate("O líder")), age, c.name])
		return
	var sick: Dictionary = leader.get("illness", {})
	if sick.is_empty():
		if rng.randf() < base * 1.5 + 0.0006:
			_player_falls_ill(world, leader)
		elif rng.randf() < base * 0.4:
			world._finish("morte", TranslationServer.translate("%s morreu de repente, aos %d anos.") % [leader.get("name", TranslationServer.translate("O líder")), age])
		return
	var severity := float(sick.severity) * (0.5 if sick.get("treated", false) else 1.0)
	if rng.randf() < severity * 0.07:
		world._finish("morte", TranslationServer.translate("%s não resistiu a %s e morreu aos %d anos.") % [leader.get("name", TranslationServer.translate("O líder")), TranslationServer.translate(sick.name), age])
	elif rng.randf() < 0.3 * (1.1 - severity):
		leader.erase("illness")
		world.emit_news(TranslationServer.translate("%s se recupera de %s.") % [leader.get("name", TranslationServer.translate("O líder")), TranslationServer.translate(sick.name)], "politica", c)


## Adoecer é uma decisão de governo: parar para se tratar custa aprovação, e seguir trabalhando custa saúde.
static func _player_falls_ill(world: GameWorld, leader: Dictionary) -> void:
	var c := world.player
	var sick := {"name": ILLNESSES[world.rng.randi() % ILLNESSES.size()], "severity": world.rng.randf_range(0.15, 1.0)}
	leader["illness"] = sick
	world.emit_news(TranslationServer.translate("%s foi diagnosticado com %s.") % [leader.get("name", TranslationServer.translate("O líder")), TranslationServer.translate(sick.name)], "politica", c)
	world.ask_player({
		"title": TranslationServer.translate("Diagnóstico: %s") % TranslationServer.translate(sick.name), "always": true,
		"text": TranslationServer.translate("Os médicos pedem que %s se afaste para o tratamento. Seu estado é %s.") % [leader.get("name", TranslationServer.translate("você")), TranslationServer.translate("grave") if float(sick.severity) > 0.65 else (TranslationServer.translate("sério") if float(sick.severity) > 0.35 else TranslationServer.translate("leve"))],
		"options": [
			{"label": TranslationServer.translate("Fazer o tratamento completo"), "hint": TranslationServer.translate("O risco de morrer cai pela metade. A aprovação cai 3 pontos."), "fn": func():
				sick["treated"] = true
				c.approval = clampf(c.approval - 0.03, 0.02, 0.95)},
			{"label": TranslationServer.translate("Seguir trabalhando"), "hint": TranslationServer.translate("Sem afastamento, mas com o risco inteiro."), "fn": func(): pass},
		],
	})
