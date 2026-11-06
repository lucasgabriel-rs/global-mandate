class_name Elections
extends RefCounted
## Sistema eleitoral: cada país vota por distritos, nas suas unidades subnacionais, com cadeiras repartidas pela
## população. O sistema decide como votos viram cadeiras; o regime decide se o chefe de governo é eleito direto.

# i18n-begin
const SYSTEMS := {"pr": "Proporcional por distritos", "fptp": "Distrital de maioria simples", "two_round": "Distrital em dois turnos", "mixed": "Misto: distrital e proporcional"}
# i18n-end
# i18n-begin
const HEADS := {"presidential": "Presidencialismo: voto direto em dois turnos", "parliamentary": "Parlamentarismo: governa quem forma maioria"}
# i18n-end
const FPTP_COUNTRIES := ["USA", "GBR", "CAN", "IND", "NGA", "BGD", "PAK", "MYS", "GHA", "KEN"]
const TWO_ROUND_COUNTRIES := ["FRA", "EGY", "VNM", "HTI"]
const MIXED_COUNTRIES := ["DEU", "JPN", "KOR", "MEX", "NZL", "HUN", "ITA", "TWN", "THA", "PHL", "RUS", "UKR"]
const PRESIDENTIAL_COUNTRIES := ["USA", "FRA", "KOR", "PHL", "IDN", "NGA", "TUR", "RUS", "UKR", "KEN", "GHA", "TWN", "EGY", "IRN"]
const DEFAULT_THRESHOLD := 0.03
const SENATORS_PER_UNIT := 3
const FPTP_LOCAL_SPREAD := 0.5
const MAX_REPORT_DISTRICTS := 40


## Regras do país, criadas na primeira vez que alguém as pede.
static func rules(c: Country, data: Dictionary) -> Dictionary:
	if data.has("electoral"):
		return data.electoral
	var system := "pr"
	if c.iso in FPTP_COUNTRIES:
		system = "fptp"
	elif c.iso in TWO_ROUND_COUNTRIES:
		system = "two_round"
	elif c.iso in MIXED_COUNTRIES:
		system = "mixed"
	var head := "presidential" if c.region == "LAM" or c.iso in PRESIDENTIAL_COUNTRIES else "parliamentary"
	data["electoral"] = {"system": system, "head": head, "threshold": DEFAULT_THRESHOLD}
	return data.electoral


## Comparecimento esperado sem lei eleitoral: estabilidade e democracia levam gente às urnas.
static func base_turnout(c: Country) -> float:
	return 0.5 + c.stability * 0.2 + c.dem * 0.012


## Parte do voto acompanha o fundo de cada partido: quanto mais pesa o dinheiro privado, mais pesa o caixa.
static func _weigh_money(data: Dictionary, weight: float) -> void:
	if weight <= 0.0:
		return
	var total := 0.0
	for p: Dictionary in data.parties:
		total += maxf(float(p.get("funds", 0.0)), 0.0)
	if total <= 0.0:
		return
	for p: Dictionary in data.parties:
		p.support = float(p.support) * (1.0 - weight) + maxf(float(p.get("funds", 0.0)), 0.0) / total * weight
	Politics._normalize(data)


## Votos de um partido em um distrito: a força nacional, ajustada pelo reduto de cada um. O reduto é sempre o
## mesmo para o par partido e lugar, então as bases eleitorais persistem de uma eleição para outra.
static func _district_votes(parties: Array, place: String, rng: RandomNumberGenerator) -> Dictionary:
	var votes := {}
	var total := 0.0
	for p: Dictionary in parties:
		var lean := 0.6 + float(absi(hash(String(p.name) + place)) % 1000) / 1000.0 * 0.9
		var v := float(p.support) * lean * rng.randf_range(0.9, 1.1)
		votes[p.id] = v
		total += v
	for id: int in votes:
		votes[id] = float(votes[id]) / maxf(total, 0.0001)
	return votes


## Método D'Hondt: a próxima cadeira vai para quem tem o maior quociente votos / (cadeiras + 1).
static func _dhondt(votes: Dictionary, seats: int) -> Dictionary:
	var won := {}
	for id: int in votes:
		won[id] = 0
	for s in seats:
		var best := -1
		var best_q := -1.0
		for id: int in votes:
			var q := float(votes[id]) / (int(won[id]) + 1.0)
			if q > best_q:
				best_q = q
				best = id
		if best >= 0:
			won[best] = int(won[best]) + 1
	return won


static func _plurality(votes: Dictionary) -> int:
	var best := -1
	var best_v := -1.0
	for id: int in votes:
		if float(votes[id]) > best_v:
			best_v = float(votes[id])
			best = id
	return best


## Segundo turno: os dois mais votados ficam, e os outros eleitores migram para quem está mais perto das ideias deles.
static func _runoff(votes: Dictionary, data: Dictionary) -> Dictionary:
	var ordered: Array = votes.keys()
	ordered.sort_custom(func(a, b): return float(votes[a]) > float(votes[b]))
	if ordered.size() < 2:
		return {"winner": ordered[0] if not ordered.is_empty() else -1, "a": ordered[0] if not ordered.is_empty() else -1, "b": -1, "share_a": 1.0}
	var a: int = ordered[0]
	var b: int = ordered[1]
	var party_a := Politics._find(data, a)
	var party_b := Politics._find(data, b)
	var va := float(votes[a])
	var vb := float(votes[b])
	for id: int in ordered.slice(2):
		var other := Politics._find(data, id)
		if Politics.distance(other, party_a) <= Politics.distance(other, party_b):
			va += float(votes[id])
		else:
			vb += float(votes[id])
	return {"winner": a if va >= vb else b, "a": a, "b": b, "share_a": va / maxf(va + vb, 0.0001)}


## Cadeiras por distrito, pela população, por maiores restos. Cada distrito tem ao menos uma.
static func apportion(shares: Array, total: int) -> Array:
	var seats := []
	var rest := []
	var given := 0
	for i in shares.size():
		var exact := float(shares[i]) * total
		var whole := maxi(int(exact), 1)
		seats.append(whole)
		given += whole
		rest.append([exact - int(exact), i])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	var k := 0
	while given < total and not rest.is_empty():
		seats[rest[k % rest.size()][1]] += 1
		given += 1
		k += 1
	k = 0
	while given > total and k < seats.size() * 4:
		var i: int = rest[rest.size() - 1 - (k % rest.size())][1]
		if int(seats[i]) > 1:
			seats[i] -= 1
			given -= 1
		k += 1
	return seats


## Roda a eleição. mood(partido) diz quanto o momento político multiplica a força de cada partido.
static func run(world: GameWorld, c: Country, data: Dictionary, mood: Callable) -> Dictionary:
	var rng := world.rng
	var rule := rules(c, data)
	# O Código Eleitoral do jogador ajusta barreira, comparecimento e o peso do dinheiro; a Constituição vale primeiro.
	var law := CodeEleitoral.rules_for(world, c)
	for p: Dictionary in data.parties:
		p.support = float(p.support) * float(mood.call(p)) * rng.randf_range(0.92, 1.08)
		# Voto obrigatório leva às urnas quem costuma faltar, e esse eleitor pende para a esquerda econômica.
		if law.get("compulsory", false):
			p.support = float(p.support) * (1.0 - 0.06 * float(p.get("econ", 0.0)))
	Politics._normalize(data)
	_weigh_money(data, float(law.get("money_weight", 0.0)))
	var turnout := clampf(base_turnout(c) + float(law.get("turnout", 0.0)) + rng.randf_range(-0.04, 0.04), 0.3, 0.97 if law.get("compulsory", false) else 0.92)
	var threshold := maxf(float(rule.threshold), float(law.get("threshold", 0.0)))
	var subs: Subdivisions = world.subdivisions
	var roots: Array = subs.roots_of(c.iso)
	var total: int = data.seats_total
	# Partidos abaixo da cláusula de barreira, medida no voto nacional, não entram pela lista.
	var eligible: Array = data.parties.filter(func(p): return float(p.support) >= threshold)
	if eligible.is_empty():
		eligible = data.parties
	var districts := []
	if roots.is_empty() or roots.size() > total / 2:
		districts.append({"name": c.name, "share": 1.0})
	else:
		var pop_shares := subs.root_shares(c.iso)
		for id: int in roots:
			districts.append({"name": subs.units[id].name, "share": pop_shares[id], "id": id})
	var shares := []
	for d: Dictionary in districts:
		shares.append(float(d.share))
	var district_seats := apportion(shares, total)
	var won := {}
	for p: Dictionary in data.parties:
		won[p.id] = 0
	var national := {}
	for p: Dictionary in eligible:
		national[p.id] = float(p.support)
	var system: String = rule.system if String(law.get("system", "")) == "" else String(law.system)
	var by_list := 0
	if system == "mixed":
		by_list = total / 2
	var report_districts := []
	for i in districts.size():
		var d: Dictionary = districts[i]
		var n: int = district_seats[i]
		if system == "mixed":
			n = maxi(n - roundi(float(n) * float(by_list) / total), 1) if total > by_list else n
		var votes := _district_votes(eligible if system == "pr" else data.parties, String(d.name), rng)
		var result := {}
		match system:
			"pr":
				result = _dhondt(votes, n)
			_:
				for s in n:
					# Cada cadeira é um distrito menor, com o humor local dele.
					var local := {}
					for id: int in votes:
						# Lugares votam bem diferente uns dos outros: é isso que abre espaço a quem é forte só em parte do país.
						local[id] = float(votes[id]) * exp(rng.randfn(0.0, FPTP_LOCAL_SPREAD))
					var winner: int = _plurality(local) if system != "two_round" else int(_runoff(local, data).winner)
					result[winner] = int(result.get(winner, 0)) + 1
		var top := -1
		var top_seats := -1
		for id: int in result:
			won[id] = int(won.get(id, 0)) + int(result[id])
			if int(result[id]) > top_seats:
				top_seats = int(result[id])
				top = id
		if report_districts.size() < MAX_REPORT_DISTRICTS:
			report_districts.append({"name": d.name, "seats": n, "winner": Politics._find(data, top).get("short", "—"), "population": c.pop * float(d.share)})
	if by_list > 0:
		var used := 0
		for id: int in won:
			used += int(won[id])
		var list_seats := _dhondt(national, maxi(total - used, 0))
		for id: int in list_seats:
			won[id] = int(won[id]) + int(list_seats[id])
	# Ajuste fino: o que sobrou ou faltou por arredondamento fica com o maior partido.
	var count := 0
	for id: int in won:
		count += int(won[id])
	if count != total:
		var largest := _plurality(national)
		if largest >= 0:
			won[largest] = maxi(int(won[largest]) + total - count, 0)
	for p: Dictionary in data.parties:
		p.seats = int(won.get(p.id, 0))
	_elect_upper_house(data, districts, rng, world, c)
	var head := {}
	if rule.head == "presidential":
		head = _presidential(data, rng)
	var report := {
		"country": c.name, "date": world.date_string().get_slice("  ", 0), "year": world.year, "system": system, "head_system": rule.head, "turnout": turnout,
		"districts": report_districts, "district_total": districts.size(), "head": head, "threshold": threshold, "parties": [],
	}
	for p: Dictionary in data.parties:
		report.parties.append({"name": p.name, "short": p.short, "vote": float(p.support), "seats": int(p.seats), "upper": int(p.get("upper_seats", 0)), "color": p.color})
	report.parties.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	data["last_election"] = report
	return report


## Senado: cada unidade elege o mesmo número de senadores, por maioria, seja grande ou pequena.
static func _elect_upper_house(data: Dictionary, districts: Array, rng: RandomNumberGenerator, _world: GameWorld, _c: Country) -> void:
	for p: Dictionary in data.parties:
		p["upper_seats"] = 0
	if districts.size() < 6:
		for p: Dictionary in Politics.upper_house({"parties": data.parties, "seats_total": data.seats_total}):
			Politics._find(data, p.id)["upper_seats"] = int(p.seats)
		return
	for d: Dictionary in districts:
		var votes := _district_votes(data.parties, "senado" + String(d.name), rng)
		for s in SENATORS_PER_UNIT:
			var local := {}
			for id: int in votes:
				local[id] = float(votes[id]) * exp(rng.randfn(0.0, FPTP_LOCAL_SPREAD))
			var winner := Politics._find(data, _plurality(local))
			winner["upper_seats"] = int(winner.get("upper_seats", 0)) + 1


## Chefe de governo eleito direto, em dois turnos: pesa o partido e também o candidato.
static func _presidential(data: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var votes := {}
	var total := 0.0
	for p: Dictionary in data.parties:
		if p.members.is_empty() or float(p.support) < 0.01:
			continue
		var candidate: Dictionary = p.members[0]
		var v := float(p.support) * (0.65 + float(candidate.competence) * 0.7) * rng.randf_range(0.85, 1.15)
		votes[p.id] = v
		total += v
	if votes.is_empty():
		return {}
	for id: int in votes:
		votes[id] = float(votes[id]) / maxf(total, 0.0001)
	var first := _plurality(votes)
	if float(votes[first]) > 0.5:
		return {"winner": first, "name": Politics._find(data, first).members[0].name, "rounds": 1, "share": float(votes[first])}
	var round2 := _runoff(votes, data)
	var share: float = float(round2.share_a) if round2.winner == round2.a else 1.0 - float(round2.share_a)
	return {"winner": round2.winner, "name": Politics._find(data, round2.winner).members[0].name, "rounds": 2, "share": share}
