class_name Politics
extends RefCounted
## Partidos e parlamentos de todos os países. Os partidos são fictícios, gerados por família política,
## e cada país tem um parlamento com assentos proporcionais aos votos. O jogador sempre pertence a um
## partido do próprio país, que passa a ser o partido do governo.

const THRESHOLD := 0.03
const MIN_SEATS := 30
const MAX_SEATS := 700
const COALITION_MAX_DISTANCE := 1.3
const OPPOSITION_SUPPORT_DISTANCE := 0.6
const COALITION_REBEL_DISTANCE := 1.5
const BILL_COOLDOWN_MONTHS := 6
## Abaixo deste índice de democracia não há parlamento livre: o líder manda, e ninguém propõe nada.
const FREE_PARLIAMENT_DEM := 4.0
const PARLIAMENT_PROPOSAL_CHANCE := 0.12
const PARLIAMENT_RECENT := 6
const PARLIAMENT_REPEAT_MONTHS := 18
## Pautas dos parlamentos dos outros países, além dos projetos da aba Política.
# i18n-begin
const WORLD_BILLS := [
	{"id": "w_tax_up", "name": "Aumento do imposto de renda", "econ": -0.6, "social": 0.1, "tax_income": 0.012, "approval": -0.01},
	{"id": "w_tax_down", "name": "Corte do imposto de renda", "econ": 0.7, "social": 0.1, "tax_income": -0.012, "approval": 0.012},
	{"id": "w_corp_down", "name": "Redução do imposto de empresas", "econ": 0.8, "social": 0.0, "tax_corporate": -0.006},
	{"id": "w_protect", "name": "Proteção à indústria nacional", "econ": -0.2, "social": -0.5, "tariff": 0.03},
	{"id": "w_open", "name": "Abertura comercial", "econ": 0.6, "social": 0.4, "tariff": -0.03},
	{"id": "w_welfare", "name": "Ampliação da previdência", "econ": -0.6, "social": 0.1, "sp_social": 0.008, "approval": 0.012},
	{"id": "w_austerity", "name": "Teto de gastos", "econ": 0.7, "social": -0.1, "sp_social": -0.007, "approval": -0.012},
	{"id": "w_education", "name": "Plano nacional de educação", "econ": -0.2, "social": 0.5, "sp_education": 0.005},
	{"id": "w_infra", "name": "Pacote de infraestrutura", "econ": 0.1, "social": -0.1, "sp_infra": 0.005},
	{"id": "w_defense", "name": "Reforço da defesa", "econ": 0.3, "social": -0.7, "sp_defense": 0.004},
	{"id": "w_rights", "name": "Lei de liberdades civis", "econ": 0.0, "social": 0.8, "stability": -0.004, "approval": 0.01},
	{"id": "w_order", "name": "Lei de ordem pública", "econ": 0.2, "social": -0.8, "stability": 0.01, "approval": -0.005},
]
# i18n-end
const SWITCH_COOLDOWN_MONTHS := 12
## Preço de cada gasto do fundo do partido, em múltiplos da "unidade" do país (ver fund_unit).
## A pesquisa de popularidade ouve o eleitorado todo e por isso é a mais cara.
const FUND_PRICES := {"poll_popularity": 1.0, "poll_support": 0.35, "campaign": 0.8, "censure": 0.5, "criticize": 0.3, "invite": 0.2}
# i18n-begin
const FUND_LABELS := {"poll_popularity": "Pesquisa de popularidade", "poll_support": "Pesquisa de apoio no parlamento", "campaign": "Campanha", "censure": "Moção de censura", "criticize": "Crítica ao governo", "invite": "Convite a um partido"}
# i18n-end
const FUND_START_MONTHS := 3.0
## Acima disso, um partido da IA gasta em campanha por conta própria.
const FUND_AI_SPEND_UNITS := 8.0
const UPPER_HOUSE_SHARE := 0.25
const UPPER_HOUSE_MIN := 20
const MEMBER_SPREAD := 0.3
const PARTNER_WITHOUT_POST_LEAVE_CHANCE := 0.04
## Ministérios. Quanto mais acima de 50% for a competência, maior o ganho; abaixo disso, a perda.
# i18n-begin
const PORTFOLIOS := [
	{"id": "finance", "label": "Fazenda", "desc": "Sobe a credibilidade do banco central."},
	{"id": "foreign", "label": "Relações Exteriores", "desc": "Melhores conversas com líderes."},
	{"id": "defense", "label": "Defesa", "desc": "Fortalece o estoque militar."},
	{"id": "health", "label": "Saúde", "desc": "Sustenta a aprovação do governo."},
	{"id": "education", "label": "Educação", "desc": "Eleva o capital humano."},
	{"id": "infrastructure", "label": "Infraestrutura", "desc": "Faz o capital do país render mais."},
	{"id": "justice", "label": "Justiça", "desc": "Mantém a estabilidade."},
]
# i18n-end
## Ministério a mais custa dinheiro, e ministério a menos economiza, mas a área dele fica sem titular.
const MINISTRY_COST_SHARE := 0.0005
const MERGED_MINISTRY_FACTOR := 0.9
const START_FOUNDED_SUPPORT := 0.05
const MID_TERM_FOUNDED_SUPPORT := 0.02

## econ: -1 esquerda a +1 direita. social: -1 autoritário a +1 libertário.
# i18n-begin
const FAMILIES := {
	"socialista": {"label": "Socialista", "econ": -0.8, "social": 0.3, "color": Color("c0392b"), "names": ["Partido Socialista", "Frente de Esquerda", "Movimento Popular"]},
	"trabalhista": {"label": "Trabalhista", "econ": -0.5, "social": 0.1, "color": Color("e74c3c"), "names": ["Partido Trabalhista", "União dos Trabalhadores", "Partido do Povo Trabalhador"]},
	"verde": {"label": "Verde", "econ": -0.3, "social": 0.7, "color": Color("27ae60"), "names": ["Partido Verde", "Aliança Ecológica", "Movimento Terra"]},
	"socialdemocrata": {"label": "Social-democrata", "econ": -0.2, "social": 0.4, "color": Color("e67e22"), "names": ["Partido Social-Democrata", "Aliança Progressista", "Partido Democrático"]},
	"centro": {"label": "Centro", "econ": 0.05, "social": 0.1, "color": Color("f1c40f"), "names": ["Partido do Centro", "União Democrática", "Movimento Republicano"]},
	"liberal": {"label": "Liberal", "econ": 0.5, "social": 0.6, "color": Color("2980b9"), "names": ["Partido Liberal", "Novo Caminho", "Aliança Liberal"]},
	"democristao": {"label": "Democrata-cristão", "econ": 0.3, "social": -0.2, "color": Color("16a085"), "names": ["Democracia Cristã", "União Cívica", "Partido Popular"]},
	"conservador": {"label": "Conservador", "econ": 0.6, "social": -0.4, "color": Color("34495e"), "names": ["Partido Conservador", "União Conservadora", "Partido da Ordem"]},
	"nacionalista": {"label": "Nacionalista", "econ": 0.2, "social": -0.8, "color": Color("8e44ad"), "names": ["Frente Nacional", "Partido da Pátria", "Movimento Soberano"]},
}
# i18n-end
const RULING_REGIME_NAME := "Partido da União Nacional" # i18n

## Projetos que o governo pode levar a voto. Os campos valem o que muda ao ser aprovado.
# i18n-begin
const BILLS := [
	{"id": "welfare", "name": "Ampliação da previdência", "desc": "Gastos sociais +1 p.p. do PIB. Aprovação sobe, déficit também.", "econ": -0.6, "social": 0.1, "sp_social": 0.01, "approval": 0.015},
	{"id": "austerity", "name": "Teto de gastos", "desc": "Gastos sociais -0,8 p.p. e administração -0,4 p.p. Reduz o déficit e custa aprovação.", "econ": 0.7, "social": -0.1, "sp_social": -0.008, "sp_admin": -0.004, "approval": -0.015},
	{"id": "education", "name": "Plano nacional de educação", "desc": "Educação +0,6 p.p. do PIB. Efeito longo sobre a produtividade.", "econ": -0.2, "social": 0.4, "sp_education": 0.006},
	{"id": "infra", "name": "Pacote de infraestrutura", "desc": "Infraestrutura +0,6 p.p. do PIB. Amplia o PIB potencial.", "econ": 0.1, "social": -0.1, "sp_infra": 0.006},
	{"id": "defense", "name": "Reforço da defesa", "desc": "Defesa +0,5 p.p. do PIB.", "econ": 0.3, "social": -0.6, "sp_defense": 0.005},
	{"id": "early", "name": "Eleições antecipadas", "desc": "Precisa de 3/5 dos assentos. Convoca eleições agora.", "econ": 0.0, "social": 0.0, "share": 0.6, "election": true},
]
# i18n-end
const BILL_LIMITS := {
	"tax_income": [0.0, 0.32], "sp_social": [0.0, 0.30], "sp_admin": [0.0, 0.12], "sp_education": [0.0, 0.12],
	"sp_infra": [0.0, 0.10], "sp_defense": [0.0, 0.20], "tariff": [0.0, 0.5],
}

## O governo define os gastos sem passar pelo parlamento, salvo se uma lei em vigor fixar o valor. Os tributos
## só mudam por lei no editor de blocos.
# i18n-begin
const BUDGET_LABELS := {
	"sp_social": "Previdência e assistência", "sp_health": "Saúde", "sp_education": "Educação e ciência",
	"sp_infra": "Infraestrutura", "sp_defense": "Defesa", "sp_admin": "Administração",
}
# i18n-end

## Por país: {parties, seats_total, ruling, coalition, player_party, bills_used, next_id}.
var countries := {}
## Sobe a cada mudança, para a interface saber quando redesenhar.
var revision := 0


func setup(world: GameWorld) -> void:
	for c: Country in world.countries:
		countries[c.iso] = _generate(c)


func data_of(iso: String) -> Dictionary:
	return countries.get(iso, {})


func party_of(iso: String, id: int) -> Dictionary:
	for p: Dictionary in data_of(iso).get("parties", []):
		if p.id == id:
			return p
	return {}


func player_party(world: GameWorld) -> Dictionary:
	if world.player == null:
		return {}
	return party_of(world.player.iso, int(data_of(world.player.iso).get("player_party", -1)))


# --- Geração -----------------------------------------------------------------------

## Só usa um sorteador próprio, ligado ao país: o cenário não muda o resto da simulação.
func _generate(c: Country) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("politica" + c.iso)
	var keys: Array = FAMILIES.keys()
	for i in range(keys.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: String = keys[i]
		keys[i] = keys[j]
		keys[j] = swap
	var count := rng.randi_range(4, 7) if c.dem >= 6.0 else (rng.randi_range(3, 5) if c.dem >= 4.0 else rng.randi_range(2, 3))
	var data := {
		"parties": [], "seats_total": clampi(roundi(pow(maxf(c.pop, 0.01) * 1e6, 1.0 / 3.0)), MIN_SEATS, MAX_SEATS),
		"ruling": -1, "coalition": [], "player_party": -1, "bills_used": {}, "next_id": 0,
	}
	data["region"] = c.region
	data["iso"] = c.iso
	data["next_member"] = 0
	for i in count:
		var family: String = keys[i]
		_add_party(data, _variant_name(family, rng), family, FAMILIES[family].color, rng.randf_range(0.05, 0.3), rng)
	if c.dem < 4.0:
		# Regime fechado: um partido dominante, e o resto faz figuração.
		var regime: Dictionary = data.parties[0]
		regime.name = RULING_REGIME_NAME
		regime.short = _initials(RULING_REGIME_NAME)
		regime.support = 3.0
	elif c.dem < 6.0:
		data.parties[0].support = float(data.parties[0].support) * 2.5
	_normalize(data)
	_allocate_seats(data)
	var largest: Dictionary = data.parties[0]
	for p: Dictionary in data.parties:
		if float(p.support) > float(largest.support):
			largest = p
	data.ruling = largest.id
	form_coalition(data)
	return data


func _variant_name(family: String, rng: RandomNumberGenerator) -> String:
	var names: Array = FAMILIES[family].names
	return names[rng.randi() % names.size()]


func _add_party(data: Dictionary, party_name: String, family: String, color: Color, support: float, rng: RandomNumberGenerator) -> Dictionary:
	var p := {
		"id": data.next_id, "name": party_name, "short": _initials(party_name), "family": family,
		"econ": FAMILIES[family].econ, "social": FAMILIES[family].social, "color": color, "support": support, "seats": 0,
		"members": [],
	}
	data.next_id = int(data.next_id) + 1
	data.parties.append(p)
	_fill_members(data, p, rng.randi_range(5, 8), rng)
	return p


# --- Políticos ---------------------------------------------------------------------

## Cada político tem a própria bússola, espalhada em torno da família do partido. O primeiro lidera.
func _fill_members(data: Dictionary, party: Dictionary, count: int, rng: RandomNumberGenerator, birth_low := GameWorld.START_YEAR - 74, birth_high := GameWorld.START_YEAR - 32) -> void:
	var family: Dictionary = FAMILIES[party.family]
	var group := Names.group_for(String(data.get("iso", "")), String(data.get("region", "EUR")))
	for i in count:
		# O gênero sai de um sorteador à parte, para não mudar o resto da geração dos partidos.
		var gender_rng := RandomNumberGenerator.new()
		gender_rng.seed = hash("%s%d" % [data.get("iso", ""), int(data.next_member)])
		var gender: String = Character.GENDERS[gender_rng.randi() % Character.GENDERS.size()]
		party.members.append({
			"id": data.next_member, "name": "%s %s" % [Names.first(group, gender, rng), Names.last(group, gender, rng)], "gender": gender,
			"econ": clampf(float(family.econ) + rng.randf_range(-MEMBER_SPREAD, MEMBER_SPREAD), -1.0, 1.0),
			"social": clampf(float(family.social) + rng.randf_range(-MEMBER_SPREAD, MEMBER_SPREAD), -1.0, 1.0),
			"competence": rng.randf_range(0.25, 0.95), "seed": rng.randi(), "birth_year": rng.randi_range(birth_low, birth_high),
		})
		data.next_member = int(data.next_member) + 1
	refresh_compass(party)


## Gente nova entra na política, com idades de quem está começando.
func add_new_members(data: Dictionary, party: Dictionary, count: int, year: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s%d%d" % [party.name, year, int(data.next_member)])
	_fill_members(data, party, count, rng, year - People.NEW_FACE_MAX_AGE, year - People.NEW_FACE_MIN_AGE)


## A bússola do partido é a média das bússolas dos políticos dele.
static func refresh_compass(party: Dictionary) -> void:
	var members: Array = party.get("members", [])
	if members.is_empty():
		return
	var econ := 0.0
	var social := 0.0
	for m: Dictionary in members:
		econ += float(m.econ)
		social += float(m.social)
	party.econ = econ / members.size()
	party.social = social / members.size()


func leader_of(iso: String) -> Dictionary:
	var ruling := ruling_party(iso)
	var members: Array = ruling.get("members", [])
	return members[0] if not members.is_empty() else {}


func player_politician(world: GameWorld) -> Dictionary:
	for m: Dictionary in player_party(world).get("members", []):
		if m.get("player", false):
			return m
	return {}


## Tira o jogador do partido antigo e o coloca à frente do novo, recalculando as duas médias.
func _seat_player(world: GameWorld, data: Dictionary, party: Dictionary) -> void:
	var me := {}
	for p: Dictionary in data.parties:
		for m: Dictionary in p.members.duplicate():
			if m.get("player", false):
				me = m
				p.members.erase(m)
				refresh_compass(p)
	if me.is_empty():
		me = {"id": data.next_member, "player": true, "competence": 0.7, "seed": 1}
		data.next_member = int(data.next_member) + 1
	me["name"] = world.leader.get("name", tr("Você"))
	me["gender"] = world.leader.get("gender", "m")
	me["birth_year"] = int(world.leader.get("birth_year", world.start_year - 50))
	me["econ"] = float(world.leader.get("econ", party.econ))
	me["social"] = float(world.leader.get("social", party.social))
	party.members.push_front(me)
	refresh_compass(party)


## Atualiza a bússola do jogador no partido, depois de mudar suas ideias ou seu nome.
func sync_player(world: GameWorld) -> void:
	var party := player_party(world)
	if party.is_empty():
		return
	_seat_player(world, data_of(world.player.iso), party)
	revision += 1


# --- Ministros ---------------------------------------------------------------------

func clear_cabinet(iso: String) -> void:
	data_of(iso)["cabinet"] = {}
	revision += 1


## Os ministérios do país agora: os de sempre, mudados pelas leis em vigor. Cada um cuida de uma ou mais áreas.
func portfolios(world: GameWorld) -> Array:
	var out := []
	for p: Dictionary in PORTFOLIOS:
		var copy: Dictionary = p.duplicate()
		copy["areas"] = [p.id]
		out.append(copy)
	for op: Dictionary in world.legislation.ministry_ops():
		match op.op:
			"create":
				if not _named(out, String(op.name)).is_empty():
					continue
				out.append({"id": "m_%d" % absi(hash(String(op.name))), "label": op.name, "desc": tr("Cuida de %s.") % tr(LawCatalog.CHOICES.ministry_area.get(op.area, op.area)).to_lower(), "areas": [op.area]})
			"merge":
				var a := _named(out, String(op.a))
				var b := _named(out, String(op.b))
				if a.is_empty() or b.is_empty() or a == b:
					continue
				out.erase(a)
				out.erase(b)
				var areas: Array = a.areas + b.areas
				out.append({"id": "m_%d" % absi(hash(String(op.name))), "label": op.name, "desc": tr("Fusão de %s e %s.") % [tr(a.label), tr(b.label)], "areas": areas, "merged": [a.id, b.id]})
			"abolish":
				out.erase(_named(out, String(op.a)))
	return out


static func _named(list: Array, label: String) -> Dictionary:
	for p: Dictionary in list:
		if String(p.label) == label:
			return p
	return {}


func portfolio_of_area(world: GameWorld, area: String) -> Dictionary:
	for p: Dictionary in portfolios(world):
		if area in p.areas:
			return p
	return {}


## Pastas que sumiram levam o titular junto; em uma fusão, o titular da primeira assume a nova.
func sync_cabinet(world: GameWorld) -> void:
	var data := data_of(world.player.iso)
	var cabinet: Dictionary = data.get("cabinet", {})
	var current := portfolios(world)
	var ids := {}
	for p: Dictionary in current:
		ids[p.id] = true
		for old: String in p.get("merged", []):
			if cabinet.has(old) and not cabinet.has(p.id):
				cabinet[p.id] = cabinet[old]
	for post: String in cabinet.keys():
		if not ids.has(post):
			cabinet.erase(post)
	revision += 1


func minister(world: GameWorld, post: String) -> Dictionary:
	var entry: Dictionary = data_of(world.player.iso).get("cabinet", {}).get(post, {})
	if entry.is_empty():
		return {}
	var data := data_of(world.player.iso)
	for m: Dictionary in _find(data, entry.party).get("members", []):
		if m.id == entry.member:
			return m
	return {}


## Ministério vago conta como uma competência baixa: a pasta funciona, mas mal.
func minister_competence(world: GameWorld, area: String) -> float:
	if world.player == null:
		return 0.5
	var portfolio := portfolio_of_area(world, area)
	if portfolio.is_empty():
		return 0.3
	var who := minister(world, String(portfolio.id))
	if who.is_empty():
		return 0.3
	# Quem acumula áreas rende um pouco menos em cada uma, e doença atrapalha.
	var skill := float(who.get("competence", 0.3)) * (MERGED_MINISTRY_FACTOR if portfolio.areas.size() > 1 else 1.0)
	return skill * (1.0 - float(who.get("illness", {}).get("severity", 0.0)) * 0.5)


## Quem pode ser ministro: políticos dos partidos da coalizão, menos o próprio jogador e quem já tem pasta.
func eligible_ministers(world: GameWorld, post: String) -> Array:
	var data := data_of(world.player.iso)
	var busy := {}
	var cabinet: Dictionary = data.get("cabinet", {})
	for key: String in cabinet:
		if key != post:
			busy[cabinet[key].member] = true
	var out := []
	for id: int in data.coalition:
		var party := _find(data, id)
		for m: Dictionary in party.members:
			if not m.get("player", false) and not busy.has(m.id):
				out.append({"party": party, "member": m})
	out.sort_custom(func(a, b): return float(a.member.competence) > float(b.member.competence))
	return out


func appoint(world: GameWorld, post: String, party_id: int, member_id: int) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": tr("Na oposição, você não nomeia ministros.")}
	var data := data_of(world.player.iso)
	var found := false
	for e: Dictionary in eligible_ministers(world, post):
		if e.party.id == party_id and e.member.id == member_id:
			found = true
	if not found:
		return {"ok": false, "msg": tr("Esse político não pode assumir a pasta.")}
	data.get_or_add("cabinet", {})[post] = {"party": party_id, "member": member_id}
	revision += 1
	return {"ok": true, "msg": ""}


func dismiss_minister(world: GameWorld, post: String) -> void:
	data_of(world.player.iso).get("cabinet", {}).erase(post)
	revision += 1


## Primeiro gabinete: reparte as pastas entre os partidos da coalizão, os melhores de cada um primeiro.
func auto_cabinet(world: GameWorld) -> void:
	if not world.in_office:
		return
	var data := data_of(world.player.iso)
	data["cabinet"] = {}
	var turn := 0
	for portfolio: Dictionary in portfolios(world):
		var options := eligible_ministers(world, portfolio.id)
		if options.is_empty():
			continue
		var partner: int = data.coalition[turn % data.coalition.size()]
		turn += 1
		var pick: Dictionary = options[0]
		for e: Dictionary in options:
			if e.party.id == partner:
				pick = e
				break
		data.cabinet[portfolio.id] = {"party": pick.party.id, "member": pick.member.id}
	revision += 1


## Partido que deixa o governo leva os ministros junto.
func _prune_cabinet(data: Dictionary) -> void:
	var cabinet: Dictionary = data.get("cabinet", {})
	for post: String in cabinet.keys():
		if not int(cabinet[post].party) in data.coalition:
			cabinet.erase(post)
	revision += 1


func _step_cabinet(world: GameWorld, data: Dictionary) -> void:
	var c := world.player
	var skill := func(post: String) -> float: return minister_competence(world, post) - 0.5
	c.cred = clampf(c.cred + skill.call("finance") * 0.004, 0.05, 0.97)
	c.mil_stock *= 1.0 + skill.call("defense") * 0.004
	c.approval = clampf(c.approval + skill.call("health") * 0.004, 0.02, 0.95)
	c.human *= 1.0 + skill.call("education") * 0.0004
	c.capital *= 1.0 + skill.call("infrastructure") * 0.0004
	c.stability = clampf(c.stability + skill.call("justice") * 0.006, 0.03, 0.97)
	# Áreas novas só contam quando há ministério para elas.
	if not portfolio_of_area(world, "science").is_empty():
		c.tfp *= 1.0 + skill.call("science") * 0.0002
	if not portfolio_of_area(world, "culture").is_empty():
		c.approval = clampf(c.approval + skill.call("culture") * 0.002, 0.02, 0.95)
	if not portfolio_of_area(world, "environment").is_empty():
		c.stability = clampf(c.stability + skill.call("environment") * 0.002, 0.03, 0.97)
	if not portfolio_of_area(world, "agriculture").is_empty():
		c.demand_shock += skill.call("agriculture") * 0.0002
	sync_cabinet(world)
	# Aliado sem nenhuma pasta pode abandonar o governo.
	var with_post := {}
	for entry: Dictionary in data.get("cabinet", {}).values():
		with_post[entry.party] = true
	for id: int in data.coalition.duplicate():
		if id != int(data.ruling) and not with_post.has(id) and world.rng.randf() < PARTNER_WITHOUT_POST_LEAVE_CHANCE:
			data.coalition.erase(id)
			world.emit_news(tr("%s deixa o governo: sem nenhum ministério, não vê motivo para ficar.") % _find(data, id).name, "politica", c)


# --- Fundo dos partidos --------------------------------------------------------------

## Unidade de preço, em US$ milhões: política custa mais em uma economia maior.
func fund_unit(world: GameWorld) -> float:
	return maxf(world.player.y_usd() * 0.002, 0.05)


func fund_price(world: GameWorld, kind: String) -> float:
	return fund_unit(world) * float(FUND_PRICES[kind])


## O fundo do partido, em US$ milhões.
func party_fund(world: GameWorld) -> float:
	return float(player_party(world).get("funds", 0.0))


## Repasse público pela votação, mais doações. O partido do jogador recebe conforme a dificuldade.
func fund_income(world: GameWorld, party: Dictionary) -> float:
	return fund_unit(world) * (0.2 + 4.0 * float(party.support))


func init_funds(world: GameWorld) -> void:
	for p: Dictionary in data_of(world.player.iso).parties:
		p["funds"] = fund_income(world, p) * FUND_START_MONTHS


## Cada gasto tem o próprio preço e sai do fundo do partido do jogador.
func spend_fund(world: GameWorld, kind: String) -> Dictionary:
	var mine := player_party(world)
	var price := fund_price(world, kind)
	if float(mine.get("funds", 0.0)) < price:
		return {"ok": false, "msg": tr("%s custa %s, e o fundo de %s tem %s.") % [tr(FUND_LABELS[kind]), UiKit.millions(price), mine.get("short", tr("seu partido")), UiKit.millions(float(mine.get("funds", 0.0)))]}
	mine.funds = float(mine.funds) - price
	revision += 1
	return {"ok": true, "msg": ""}


func _step_funds(world: GameWorld, data: Dictionary) -> void:
	var unit := fund_unit(world)
	for p: Dictionary in data.parties:
		var income := fund_income(world, p)
		var is_mine: bool = int(p.id) == int(data.player_party)
		if is_mine:
			income *= float(GameWorld.DIFFICULTY[world.difficulty].fund)
		p["funds"] = float(p.get("funds", 0.0)) + income
		if not is_mine and float(p.funds) > unit * FUND_AI_SPEND_UNITS:
			p.funds = float(p.funds) - unit * float(FUND_PRICES.campaign)
			p.support = float(p.support) * 1.01


# --- Casas do parlamento -------------------------------------------------------------

## As casas do país: uma só, ou a câmara e o senado, cada uma com a própria bancada.
func houses(world: GameWorld) -> Array:
	var data := data_of(world.player.iso)
	if not world.legislation.param("bicameral", false):
		return [{"id": "lower", "name": tr("Parlamento"), "total": int(data.seats_total), "parties": data.parties}]
	var upper := upper_house(data)
	return [
		{"id": "lower", "name": tr("Câmara"), "total": int(data.seats_total), "parties": data.parties},
		{"id": "upper", "name": tr("Senado"), "total": _count_seats(upper), "parties": upper},
	]


## Cópia rasa dos partidos com os assentos do senado, repartidos pelos maiores restos.
static func upper_house(data: Dictionary) -> Array:
	# Depois da primeira eleição, vale a bancada que o eleitor escolheu para o senado.
	var elected := 0
	for p: Dictionary in data.parties:
		elected += int(p.get("upper_seats", 0))
	if elected > 0:
		var chosen := []
		for p: Dictionary in data.parties:
			var copy: Dictionary = p.duplicate()
			copy.seats = int(p.get("upper_seats", 0))
			chosen.append(copy)
		return chosen
	var total := maxi(roundi(float(data.seats_total) * UPPER_HOUSE_SHARE), UPPER_HOUSE_MIN)
	var out := []
	var given := 0
	var rest := []
	for p: Dictionary in data.parties:
		var copy: Dictionary = p.duplicate()
		var exact := float(p.seats) / maxf(float(data.seats_total), 1.0) * total
		copy.seats = int(exact)
		given += int(exact)
		out.append(copy)
		rest.append([exact - int(exact), copy])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	var i := 0
	while given < total and not rest.is_empty():
		rest[i % rest.size()][1].seats += 1
		given += 1
		i += 1
	return out


static func _count_seats(parties: Array) -> int:
	var total := 0
	for p: Dictionary in parties:
		total += int(p.seats)
	return total


# --- Oposição ------------------------------------------------------------------------

func _opposition_guard(world: GameWorld, kind: String) -> Dictionary:
	if world.in_office:
		return {"ok": false, "msg": tr("Você está no governo.")}
	return spend_fund(world, kind)


func _boost_player_party(world: GameWorld, factor: float) -> void:
	var data := data_of(world.player.iso)
	var mine := player_party(world)
	mine.support = float(mine.support) * factor
	_normalize(data)
	revision += 1


## Critica o governo em público: a aprovação dele cai e seu partido ganha um pouco.
func criticize(world: GameWorld) -> Dictionary:
	var guard := _opposition_guard(world, "criticize")
	if not guard.ok:
		return guard
	world.player.approval = clampf(world.player.approval - 0.012, 0.02, 0.95)
	_boost_player_party(world, 1.03)
	return {"ok": true, "msg": tr("Sua crítica repercute, e a aprovação do governo cai.")}


func campaign(world: GameWorld) -> Dictionary:
	var guard := _opposition_guard(world, "campaign")
	if not guard.ok:
		return guard
	_boost_player_party(world, 1.08)
	return {"ok": true, "msg": tr("A campanha percorre o país, e o partido cresce nas pesquisas.")}


## Moção de censura: se a oposição somar a maioria dos assentos, o governo cai e há eleição agora.
func censure(world: GameWorld) -> Dictionary:
	var guard := _opposition_guard(world, "censure")
	if not guard.ok:
		return guard
	var c := world.player
	var data := data_of(c.iso)
	var total: int = data.seats_total
	var opposition := total - government_seats(c.iso)
	if opposition * 2 <= total:
		return {"ok": true, "passed": false, "msg": tr("Moção de censura rejeitada: a oposição tem %d de %d assentos.") % [opposition, total]}
	world.emit_news(tr("Moção de censura derruba o governo em %s: novas eleições.") % c.name, "politica", c)
	c.next_election = world.year_float()
	world.check_player_politics(c)
	return {"ok": true, "passed": true, "msg": tr("Moção aprovada: o governo caiu, e o país vai às urnas.")}


## Força de cada partido no dia da eleição: quem governa colhe a aprovação; os outros, o contrário.
func _mood_for(world: GameWorld, data: Dictionary, boost_mine := false) -> Callable:
	var ratio := maxf(world.player.approval, 0.01) / 0.46
	var mine: int = data.player_party
	return func(p: Dictionary) -> float:
		if p.id == int(data.ruling):
			return pow(ratio, 1.5)
		if p.id in data.coalition:
			return pow(ratio, 0.6)
		if boost_mine and p.id == mine:
			return pow(1.0 / ratio, 0.6)
		return pow(1.0 / ratio, 0.3)


## Quem governa depois da eleição. No presidencialismo, é o eleito; no parlamentarismo, quem tem maior bancada.
static func _winner_of(data: Dictionary, report: Dictionary) -> Dictionary:
	if not report.head.is_empty():
		return _find(data, int(report.head.winner))
	var largest: Dictionary = data.parties[0]
	for p: Dictionary in data.parties:
		if int(p.seats) > int(largest.seats):
			largest = p
	return largest


## Eleição na oposição: quanto pior a aprovação do governo, melhor para quem está fora dele.
func opposition_election(world: GameWorld) -> Dictionary:
	var c := world.player
	var data := data_of(c.iso)
	var mine := player_party(world)
	var report := Elections.run(world, c, data, _mood_for(world, data, true))
	var winner := _winner_of(data, report)
	var won: bool = winner.id == mine.id
	data.ruling = mine.id if won else winner.id
	form_coalition(data)
	_prune_cabinet(data)
	return {"won": won, "vote": float(mine.support), "seats": int(mine.seats), "total": int(data.seats_total), "winner": winner, "report": report}


## Passa o governo adiante sem eleição: quem assume é o maior partido fora do governo do jogador.
func hand_over(c: Country) -> Dictionary:
	var data := data_of(c.iso)
	var mine := int(data.player_party)
	var next: Dictionary = {}
	for p: Dictionary in data.parties:
		if p.id != mine and (next.is_empty() or int(p.seats) > int(next.seats)):
			next = p
	data.ruling = next.id
	form_coalition(data)
	return next


static func _initials(party_name: String) -> String:
	var out := ""
	for word: String in party_name.split(" ", false):
		if word.length() > 2 and word.to_lower() != "dos":
			out += word.left(1).to_upper()
	return out if out.length() >= 2 else party_name.left(3).to_upper()


static func _normalize(data: Dictionary) -> void:
	var total := 0.0
	for p: Dictionary in data.parties:
		total += float(p.support)
	for p: Dictionary in data.parties:
		p.support = float(p.support) / maxf(total, 0.0001)


## Maiores restos sobre os votos válidos: quem fica abaixo da cláusula de barreira não entra.
static func _allocate_seats(data: Dictionary) -> void:
	var total: int = data.seats_total
	var valid := 0.0
	for p: Dictionary in data.parties:
		if float(p.support) >= THRESHOLD:
			valid += float(p.support)
	var given := 0
	var rest := []
	for p: Dictionary in data.parties:
		p.seats = 0
		if float(p.support) < THRESHOLD or valid <= 0.0:
			continue
		var exact := float(p.support) / valid * total
		p.seats = int(exact)
		given += int(p.seats)
		rest.append([exact - int(exact), p])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	var i := 0
	while given < total and not rest.is_empty():
		rest[i % rest.size()][1].seats += 1
		given += 1
		i += 1


static func distance(a: Dictionary, b: Dictionary) -> float:
	return Vector2(float(a.econ) - float(b.econ), float(a.social) - float(b.social)).length()


# --- Governo -----------------------------------------------------------------------

## Monta a coalizão do partido do governo com os mais próximos, até ter maioria ou acabar quem aceite.
func form_coalition(data: Dictionary) -> void:
	var ruling := _find(data, data.ruling)
	data.coalition = [ruling.id]
	var seats: int = ruling.seats
	var others: Array = data.parties.filter(func(p): return p.id != ruling.id and int(p.seats) > 0)
	others.sort_custom(func(a, b): return distance(ruling, a) < distance(ruling, b))
	for p: Dictionary in others:
		if seats * 2 > int(data.seats_total) or distance(ruling, p) > COALITION_MAX_DISTANCE:
			break
		data.coalition.append(p.id)
		seats += int(p.seats)
	revision += 1


static func _find(data: Dictionary, id: int) -> Dictionary:
	for p: Dictionary in data.parties:
		if p.id == id:
			return p
	return {}


func government_seats(iso: String) -> int:
	var data := data_of(iso)
	var seats := 0
	for id: int in data.get("coalition", []):
		seats += int(_find(data, id).get("seats", 0))
	return seats


func government_share(iso: String) -> float:
	return float(government_seats(iso)) / maxf(float(data_of(iso).get("seats_total", 1)), 1.0)


func ruling_party(iso: String) -> Dictionary:
	var data := data_of(iso)
	return _find(data, int(data.get("ruling", -1))) if not data.is_empty() else {}


# --- Partido do jogador --------------------------------------------------------------

## Entra em um partido, que passa a ser o do governo. Depois do início da partida, custa aprovação a quem
## governa e só pode ser feito de tempos em tempos. Em regime fechado, o partido do líder herda a posição dominante.
func join_party(world: GameWorld, id: int, at_start := false, keep_ideas := false) -> Dictionary:
	var c := world.player
	var data := data_of(c.iso)
	var party := _find(data, id)
	if party.is_empty():
		return {"ok": false, "msg": tr("Esse partido não existe.")}
	if int(data.player_party) == id:
		return {"ok": false, "msg": tr("Você já é de %s.") % party.name}
	if not at_start:
		if switch_wait(world) > 0:
			return {"ok": false, "msg": tr("Você mudou de partido há pouco. Tente em %d mês(es).") % switch_wait(world)}
		data["last_switch"] = world.months_elapsed
		if world.in_office:
			c.approval = clampf(c.approval - 0.04, 0.02, 0.95)
	if c.dem < 4.0 and world.in_office:
		_give_dominance(data, party)
	# O jogador só escolhe bússola ao fundar um partido; ao entrar em outro, adota as ideias dele.
	if not keep_ideas:
		world.leader["econ"] = float(party.econ)
		world.leader["social"] = float(party.social)
	_seat_player(world, data, party)
	data.player_party = id
	if world.in_office:
		data.ruling = id
		form_coalition(data)
		_prune_cabinet(data)
	if not at_start:
		var verb := tr("agora governa por") if world.in_office else tr("agora lidera")
		world.emit_news(tr("%s troca de partido e %s %s.") % [world.leader.get("name", tr("O líder")), verb, party.name], "politica", c)
	return {"ok": true, "msg": ""}


func switch_wait(world: GameWorld) -> int:
	var last: int = data_of(world.player.iso).get("last_switch", -9999)
	return maxi(last + SWITCH_COOLDOWN_MONTHS - world.months_elapsed, 0)


func _give_dominance(data: Dictionary, party: Dictionary) -> void:
	var top := _find(data, data.ruling)
	var dominant := float(top.support)
	top.support = party.support
	party.support = dominant
	_allocate_seats(data)


## Funda um partido novo e entra nele. Sem eleição, ele chega ao parlamento só no início da partida.
func found_party(world: GameWorld, party_name: String, family: String, color: Color, at_start := false) -> Dictionary:
	var clean := party_name.strip_edges()
	if clean == "":
		return {"ok": false, "msg": tr("O partido precisa de um nome.")}
	if not FAMILIES.has(family):
		return {"ok": false, "msg": tr("Escolha uma família política.")}
	var c := world.player
	var data := data_of(c.iso)
	for p: Dictionary in data.parties:
		if String(p.name).to_lower() == clean.to_lower():
			return {"ok": false, "msg": tr("Já existe um partido com esse nome.")}
	if not at_start:
		if switch_wait(world) > 0:
			return {"ok": false, "msg": tr("Você mudou de partido há pouco. Tente em %d mês(es).") % switch_wait(world)}
		data["last_switch"] = world.months_elapsed
		if world.in_office:
			c.approval = clampf(c.approval - 0.04, 0.02, 0.95)
	var share := START_FOUNDED_SUPPORT if at_start else MID_TERM_FOUNDED_SUPPORT
	for p: Dictionary in data.parties:
		p.support = float(p.support) * (1.0 - share)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(clean + c.iso)
	var party := _add_party(data, clean, family, color, share, rng)
	party["funds"] = fund_income(world, party) * FUND_START_MONTHS
	if at_start:
		_allocate_seats(data)
	var joined := join_party(world, party.id, true, true)
	if not at_start:
		world.emit_news(tr("%s funda %s.") % [world.leader.get("name", tr("O líder")), party.name], "politica", c)
	return joined


## Convida ou expulsa um partido da coalizão.
func invite(world: GameWorld, id: int) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": tr("Na oposição, você não monta o governo.")}
	var c := world.player
	var data := data_of(c.iso)
	var party := _find(data, id)
	if party.is_empty() or id in data.coalition:
		return {"ok": false, "msg": tr("Esse partido já está no governo.")}
	var paid := spend_fund(world, "invite")
	if not paid.ok:
		return paid
	if distance(_find(data, data.ruling), party) > COALITION_MAX_DISTANCE:
		return {"ok": false, "msg": tr("%s recusou: as ideias são distantes demais.") % party.name}
	if c.approval < 0.25:
		return {"ok": false, "msg": tr("%s recusou: seu governo está impopular demais.") % party.name}
	data.coalition.append(id)
	revision += 1
	return {"ok": true, "msg": tr("%s entra no governo. Lembre de dar um ministério ao novo aliado.") % party.name}


func dismiss(world: GameWorld, id: int) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": tr("Na oposição, você não monta o governo.")}
	var data := data_of(world.player.iso)
	if id == int(data.ruling) or not id in data.coalition:
		return {"ok": false, "msg": tr("Esse partido não pode sair do governo.")}
	data.coalition.erase(id)
	_prune_cabinet(data)
	return {"ok": true, "msg": tr("%s deixa o governo e leva os ministros.") % _find(data, id).name}


# --- Parlamento ----------------------------------------------------------------------

static func bill(id: String) -> Dictionary:
	for b: Dictionary in BILLS:
		if b.id == id:
			return b
	return {}


func bill_wait(world: GameWorld, id: String) -> int:
	var used: int = data_of(world.player.iso).bills_used.get(id, -9999)
	return maxi(used + BILL_COOLDOWN_MONTHS - world.months_elapsed, 0)


## Manda um projeto pronto ao parlamento. Ele não vale na hora: passa pela discussão e pela votação em
## cada casa, como qualquer norma, e só então produz efeito.
func vote(world: GameWorld, id: String) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": tr("Na oposição, você não propõe projetos do governo.")}
	var c := world.player
	var data := data_of(c.iso)
	var b := bill(id)
	if b.is_empty():
		return {"ok": false, "msg": tr("Projeto desconhecido.")}
	if bill_wait(world, id) > 0:
		return {"ok": false, "msg": tr("Esse tema só volta à pauta em %d mês(es).") % bill_wait(world, id)}
	if b.get("election", false) and c.dem < 4.0:
		return {"ok": false, "msg": tr("Este regime não realiza eleições.")}
	data.bills_used[id] = world.months_elapsed
	revision += 1
	return world.legislation.present_payload(world, {"kind": "bill", "id": id, "share": float(b.get("share", 0.0))}, b.name, b.desc, {"econ": b.econ, "social": b.social})


## Um partido apoia? A coalizão sim, salvo se discordar muito; a oposição, só se estiver perto.
static func _party_supports(p: Dictionary, data: Dictionary, position: Dictionary) -> bool:
	if p.id == int(data.ruling):
		return true
	if p.id in data.coalition:
		return distance(p, position) <= COALITION_REBEL_DISTANCE
	return distance(p, position) <= OPPOSITION_SUPPORT_DISTANCE


## share 0 significa maioria simples: mais da metade dos assentos.
static func _votes_needed(data: Dictionary, share: float) -> int:
	return ceili(float(data.seats_total) * share) if share > 0.0 else int(data.seats_total) / 2 + 1


# --- Orçamento -----------------------------------------------------------------------

## O governo define o gasto na hora, a não ser que uma lei em vigor obrigue aquele valor.
func set_budget(world: GameWorld, field: String, value: float) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": tr("Na oposição, o orçamento é do governo.")}
	if not BUDGET_LABELS.has(field):
		return {"ok": false, "msg": tr("Esse campo não faz parte do orçamento.")}
	var lock: Dictionary = world.legislation.budget_lock(field)
	if not lock.is_empty():
		return {"ok": false, "msg": tr("%s é fixado em %s por lei.") % [tr(BUDGET_LABELS[field]), UiKit.pct(lock.value)]}
	_apply_budget_change(world.player, field, value)
	revision += 1
	return {"ok": true, "msg": ""}


## Consumo e tarifa passam em parte aos preços no momento em que mudam.
static func _apply_budget_change(c: Country, field: String, value: float) -> void:
	if field == "tax_consumption":
		c.hist["_oneoff"] = float(c.hist.get("_oneoff", 0.0)) + (value - c.tax_consumption) * 0.45
	elif field == "tariff":
		c.hist["_oneoff"] = float(c.hist.get("_oneoff", 0.0)) + (value - c.tariff) * clampf(c.m_share, 0.05, 0.5) * 0.7
	c.set(field, value)


func apply_bill(world: GameWorld, b: Dictionary) -> void:
	var c := world.player
	for field: String in BILL_LIMITS:
		if b.has(field) and world.legislation.budget_lock(field).is_empty():
			var limits: Array = BILL_LIMITS[field]
			c.set(field, clampf(float(c.get(field)) + float(b[field]), limits[0], limits[1]))
	if b.has("approval"):
		c.approval = clampf(c.approval + float(b.approval), 0.02, 0.95)
	if b.get("election", false):
		c.next_election = world.year_float()
		world.check_player_politics(c)


## Todo mês o apoio ao governo acompanha a aprovação, e o governo sem maioria perde estabilidade.
func step_month(world: GameWorld) -> void:
	var c := world.player
	if c == null:
		return
	var data := data_of(c.iso)
	_step_funds(world, data)
	if world.in_office:
		_step_cabinet(world, data)
	var swing := (c.approval - 0.46) * 0.02
	for p: Dictionary in data.parties:
		var signed := swing if p.id in data.coalition else -swing * 0.5
		p.support = maxf(float(p.support) * (1.0 + signed), 0.002)
	_normalize(data)
	if government_share(c.iso) <= 0.5 and c.dem >= 4.0:
		c.stability = clampf(c.stability - 0.002, 0.03, 0.97)
	revision += 1


# --- Parlamentos dos outros países --------------------------------------------------

## Todo mês, cada parlamento livre delibera o que está na pauta ou recebe uma proposta nova de um partido.
func step_world_parliaments(world: GameWorld) -> void:
	for c: Country in world.countries:
		if not c.alive or c == world.player or c.dem < FREE_PARLIAMENT_DEM:
			continue
		var data := data_of(c.iso)
		if data.is_empty():
			continue
		var pending: Dictionary = data.get("pending_bill", {})
		if not pending.is_empty():
			if world.months_elapsed >= int(pending.due):
				_decide_world_bill(world, c, data, pending)
		elif world.rng.randf() < PARLIAMENT_PROPOSAL_CHANCE:
			_propose_world_bill(world, c, data)


static func _world_bill(id: String) -> Dictionary:
	for b: Dictionary in WORLD_BILLS:
		if b.id == id:
			return b
	return {}


func _propose_world_bill(world: GameWorld, c: Country, data: Dictionary) -> void:
	var total := 0
	for p: Dictionary in data.parties:
		total += int(p.seats)
	if total <= 0:
		return
	# Quem tem mais assentos apresenta mais projetos.
	var roll := world.rng.randi_range(1, total)
	var author: Dictionary = data.parties[0]
	for p: Dictionary in data.parties:
		roll -= int(p.seats)
		if roll <= 0:
			author = p
			break
	var recent: Dictionary = data.get_or_add("bill_memory", {})
	var options := []
	for b: Dictionary in WORLD_BILLS:
		if world.months_elapsed - int(recent.get(b.id, -9999)) >= PARLIAMENT_REPEAT_MONTHS:
			options.append([distance(author, b), b])
	if options.is_empty():
		return
	options.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var pick: Dictionary = options[world.rng.randi_range(0, mini(2, options.size() - 1))][1]
	recent[pick.id] = world.months_elapsed
	data["pending_bill"] = {"id": pick.id, "author": author.id, "due": world.months_elapsed + world.rng.randi_range(1, 2)}


func _decide_world_bill(world: GameWorld, c: Country, data: Dictionary, pending: Dictionary) -> void:
	data.erase("pending_bill")
	var b := _world_bill(String(pending.id))
	var author := _find(data, int(pending.author))
	if b.is_empty() or author.is_empty():
		return
	var government_bill: bool = author.id in data.coalition
	var yes := 0
	for p: Dictionary in data.parties:
		var limit := OPPOSITION_SUPPORT_DISTANCE
		if p.id == author.id:
			limit = 99.0
		elif p.id in data.coalition:
			limit = COALITION_REBEL_DISTANCE if government_bill else OPPOSITION_SUPPORT_DISTANCE * 0.7
		if distance(p, b) <= limit:
			yes += int(p.seats)
	var total: int = data.seats_total
	var passed := yes * 2 > total
	if passed:
		for field: String in BILL_LIMITS:
			if b.has(field):
				var limits: Array = BILL_LIMITS[field]
				c.set(field, clampf(float(c.get(field)) + float(b[field]), limits[0], limits[1]))
		c.approval = clampf(c.approval + float(b.get("approval", 0.0)), 0.02, 0.95)
		c.stability = clampf(c.stability + float(b.get("stability", 0.0)), 0.03, 0.97)
	var laws: Array = data.get_or_add("recent_laws", [])
	laws.push_front({"title": b.name, "party": author.short, "yes": yes, "total": total, "passed": passed, "date": world.date_string().get_slice("  ", 0)})
	if laws.size() > PARLIAMENT_RECENT:
		laws.resize(PARLIAMENT_RECENT)
	revision += 1
	if c.y_usd() > world.world_gdp() * NationAI.NEWS_SHARE:
		var verdict := tr("Parlamento de %s aprova: %s (%s), por %d a %d.") if passed else tr("Parlamento de %s rejeita: %s (%s), por %d a %d.")
		world.emit_news(verdict % [c.name, tr(b.name), author.short, yes, total - yes], "politica", c)


# --- Eleições ------------------------------------------------------------------------

## Eleição do país do jogador. No presidencialismo, ele precisa vencer o voto direto, e o parlamento pode sair
## contra ele; no parlamentarismo, continua se o partido dele for o maior ou se a coalizão mantiver a maioria.
func player_election(world: GameWorld) -> Dictionary:
	var c := world.player
	var data := data_of(c.iso)
	var me := _find(data, data.ruling)
	# Sem direito a outro mandato pelo Código Eleitoral, o jogador não concorre: o partido vai às urnas sem ele.
	var barred := not CodeEleitoral.may_run_again(world)
	var report := Elections.run(world, c, data, _mood_for(world, data))
	var winner := _winner_of(data, report)
	var won: bool = winner.id == me.id
	if report.head.is_empty() and not won:
		won = government_seats(c.iso) * 2 > int(data.seats_total)
	if barred:
		world.emit_news(tr("O Código Eleitoral de %s não permite outro mandato: o chefe de governo deixa o cargo, e %s assume.") % [c.name, winner.name], "politica", c)
		won = false
	if not won:
		data.ruling = winner.id
	form_coalition(data)
	_prune_cabinet(data)
	revision += 1
	return {"won": won, "barred": barred, "vote": float(me.support), "seats": int(me.seats), "total": int(data.seats_total), "winner": winner, "report": report}


## Países da IA: a mesma eleição. Devolve se o governo continuou.
func ai_election(world: GameWorld, c: Country) -> bool:
	var data := data_of(c.iso)
	if data.is_empty():
		return true
	var ratio := maxf(c.approval, 0.01) / 0.46
	var ruling: int = data.ruling
	var coalition: Array = data.coalition
	var report := Elections.run(world, c, data, func(p: Dictionary) -> float:
		if p.id == ruling:
			return pow(ratio, 1.5)
		return pow(ratio, 0.6) if p.id in coalition else pow(1.0 / ratio, 0.3))
	var winner := _winner_of(data, report)
	var stays: bool = winner.id == ruling or (report.head.is_empty() and government_seats(c.iso) * 2 > int(data.seats_total))
	if not stays:
		data.ruling = winner.id
	form_coalition(data)
	return stays


func to_dict() -> Dictionary:
	return {"countries": countries}


func from_dict(d: Dictionary) -> void:
	if d.has("countries"):
		countries = d.countries
	# Saves anteriores aos políticos: cada partido ganha os seus, em volta da posição que já tinha.
	for iso: String in countries:
		var data: Dictionary = countries[iso]
		data["iso"] = iso
		if not data.has("next_member"):
			data["next_member"] = 0
			data["region"] = "EUR"
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("politicos" + iso)
			for p: Dictionary in data.parties:
				p["members"] = []
				_fill_members(data, p, rng.randi_range(5, 8), rng)
	revision += 1
