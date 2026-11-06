class_name CodePenal
extends LawCode
## Código Penal: Crimes, penas, maioridade penal, drogas, armas e sistema prisional.
##
## O que vale fica em `standing.codes` como "penal:<item>". Todo mês o código recalcula a
## criminalidade (`c.code_stats["criminalidade"]`, 0-1), que anda devagar em direção ao que a
## desigualdade, o desemprego, a polícia, as penas e as armas pedem.

## Orçamento de partida da polícia e das prisões, em fração do PIB. Já está na despesa calibrada do
## país: só o que passar disso (ou faltar) vira gasto (ou economia) da lei.
const BASE_BUDGET := {"policia": 0.009, "prisoes": 0.002}
## Quanto cada conduta pesa na criminalidade e na lotação das prisões quando é crime.
const CONDUCT_WEIGHT := {
	"porte_drogas": 0.6, "trafico": 1.0, "aborto": 0.2, "jogos_azar": 0.2, "sonegacao": 0.3, "corrupcao": 0.4,
	"ambiental": 0.2, "odio": 0.1, "cibernetico": 0.3, "prostituicao": 0.2, "eutanasia": 0.05, "lavagem": 0.3,
}
## Condutas cuja criminalização pesa na liberdade individual: aprovação e estabilidade sentem.
const LIBERTY_CONDUCTS := ["porte_drogas", "aborto", "jogos_azar", "odio", "prostituicao", "eutanasia"]
## A criminalidade anda esta fração do caminho até o alvo a cada mês.
const CRIME_PACE := 0.06


func _init() -> void:
	id = "penal"
	title = "Código Penal"
	ementa = "Crimes, penas, maioridade penal, drogas, armas e sistema prisional."
	category = {"id": "penal", "label": "Penal", "color": Color("9e3b3b")}


func blocks() -> Array:
	return [
		{"id": "pn_crime", "cat": "penal", "kind": "statement", "text": "Tipificar {conduct} como crime, com pena de {min} a {max} anos de prisão", "fields": {"conduct": {"t": "choice", "of": "penal_conduct", "d": "corrupcao"}, "min": {"t": "num", "d": 2}, "max": {"t": "num", "d": 8}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.05, "social": -0.35},
		{"id": "pn_fine", "cat": "penal", "kind": "statement", "text": "Punir {conduct} só com multa de até {amount}", "fields": {"conduct": {"t": "choice", "of": "penal_conduct", "d": "porte_drogas"}, "amount": {"t": "money", "d": 2000}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": 0.1},
		{"id": "pn_decrim", "cat": "penal", "kind": "statement", "text": "Descriminalizar {conduct}", "fields": {"conduct": {"t": "choice", "of": "penal_conduct", "d": "porte_drogas"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.05, "social": 0.5},
		{"id": "pn_age", "cat": "penal", "kind": "statement", "text": "Fixar a maioridade penal em {age} anos", "fields": {"age": {"t": "num", "d": 18}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": -0.1},
		{"id": "pn_guns", "cat": "penal", "kind": "statement", "text": "Tornar o porte e a posse de armas {regime}", "fields": {"regime": {"t": "choice", "of": "gun_regime", "d": "restrito"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.1},
		{"id": "pn_death", "cat": "penal", "kind": "statement", "text": "Pena de morte: {status}", "fields": {"status": {"t": "choice", "of": "death_status", "d": "abolida"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": -0.3},
		{"id": "pn_life", "cat": "penal", "kind": "statement", "text": "Prisão perpétua: {status}, com cumprimento máximo de {years} anos nas demais penas", "fields": {"status": {"t": "choice", "of": "life_status", "d": "proibida"}, "years": {"t": "num", "d": 40}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": -0.15},
		{"id": "pn_regime", "cat": "penal", "kind": "statement", "text": "Cumprir as penas em regime {regime}, com progressão após {share}% da pena", "fields": {"regime": {"t": "choice", "of": "prison_regime", "d": "progressivo"}, "share": {"t": "pct", "d": 25}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": 0.05},
		{"id": "pn_budget", "cat": "penal", "kind": "statement", "text": "Destinar {value}% do PIB a {area}", "fields": {"value": {"t": "pct", "d": 0.9}, "area": {"t": "choice", "of": "security_area", "d": "policia"}}, "rank": LawCatalog.RANK_LAW, "econ": -0.15, "social": -0.2},
		{"id": "pn_alternative", "cat": "penal", "kind": "statement", "text": "Substituir penas de até {years} anos por penas alternativas (serviço comunitário, tornozeleira)", "fields": {"years": {"t": "num", "d": 4}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": -0.05, "social": 0.3},
	]


func choices() -> Dictionary:
	return {
		"penal_conduct": {
			"porte_drogas": "o porte de drogas para uso próprio", "trafico": "o tráfico de drogas", "aborto": "o aborto",
			"jogos_azar": "os jogos de azar", "sonegacao": "a sonegação fiscal", "corrupcao": "a corrupção",
			"ambiental": "o dano ambiental", "odio": "o discurso de ódio", "cibernetico": "a invasão de sistemas informáticos",
			"prostituicao": "a prostituição", "eutanasia": "a eutanásia", "lavagem": "a lavagem de dinheiro",
		},
		"gun_regime": {"proibido": "proibidos aos civis", "restrito": "restritos, com licença e registro", "livre": "livres para maiores de idade"},
		"death_status": {"abolida": "abolida", "guerra": "só em tempo de guerra", "crimes_graves": "admitida para crimes hediondos"},
		"life_status": {"proibida": "proibida", "crimes_graves": "admitida para crimes hediondos"},
		"prison_regime": {"progressivo": "progressivo, por bom comportamento", "integral": "integralmente fechado para crimes graves", "condicional": "progressivo, com livramento condicional"},
		"security_area": {"policia": "policiamento", "prisoes": "sistema prisional"},
	}


## O texto com que o país começa: democracias ricas e progressistas punem menos condutas e mais
## devagar; regimes fechados punem muito, admitem pena de morte e proíbem armas.
func seed_program(world: GameWorld, c: Country) -> Dictionary:
	var lean := _lean(world, c)
	var social := float(lean.social)
	var right := float(lean.econ)
	var rich := c.gdp_pc() >= 25000.0
	var free := c.dem >= 6.0
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	var list: Array = stack.blocks
	_add(program, list, "pn_crime", {"conduct": "trafico", "min": 5, "max": 15 if free else 20})
	_add(program, list, "pn_crime", {"conduct": "corrupcao", "min": 2, "max": 12})
	_add(program, list, "pn_crime", {"conduct": "lavagem", "min": 3, "max": 10})
	_add(program, list, "pn_crime", {"conduct": "sonegacao", "min": 2, "max": 5})
	_add(program, list, "pn_crime", {"conduct": "ambiental", "min": 1, "max": 4})
	_add(program, list, "pn_crime", {"conduct": "cibernetico", "min": 1, "max": 4})
	if free and rich and social > 0.25:
		_add(program, list, "pn_decrim", {"conduct": "porte_drogas"})
	elif free:
		_add(program, list, "pn_fine", {"conduct": "porte_drogas", "amount": 1000})
	else:
		_add(program, list, "pn_crime", {"conduct": "porte_drogas", "min": 1, "max": 5})
	if free and social > 0.15:
		_add(program, list, "pn_decrim", {"conduct": "aborto"})
	else:
		_add(program, list, "pn_crime", {"conduct": "aborto", "min": 1, "max": 3})
	if rich or right > 0.3:
		_add(program, list, "pn_decrim", {"conduct": "jogos_azar"})
	else:
		_add(program, list, "pn_fine", {"conduct": "jogos_azar", "amount": 5000})
	# Em regime fechado, "discurso de ódio" também serve para calar a oposição.
	_add(program, list, "pn_crime", {"conduct": "odio", "min": 1, "max": 3 if free else 8})
	_add(program, list, "pn_age", {"age": 18 if free or c.gdp_pc() > 8000.0 else 16})
	var guns := "restrito"
	if c.dem < 4.0:
		guns = "proibido"
	elif social < -0.2 and right > 0.3:
		guns = "livre"
	_add(program, list, "pn_guns", {"regime": guns})
	var death := "abolida"
	if c.dem < 4.0:
		death = "crimes_graves"
	elif c.dem < 6.5 or social < -0.3:
		death = "guerra"
	_add(program, list, "pn_death", {"status": death})
	_add(program, list, "pn_life", {"status": "proibida" if free else "crimes_graves", "years": 30 if free and social > 0.2 else 40})
	_add(program, list, "pn_regime", {"regime": "condicional" if free else "integral", "share": 25 if free else 50})
	_add(program, list, "pn_budget", {"value": BASE_BUDGET.policia * 100.0, "area": "policia"})
	_add(program, list, "pn_budget", {"value": BASE_BUDGET.prisoes * 100.0, "area": "prisoes"})
	if c.dem >= 4.0:
		_add(program, list, "pn_alternative", {"years": 4 if free else 2})
	return program


func apply(_world: GameWorld, leg: Legislation, op: String, values: Dictionary, _weight: float, norm_id: int, prio: float) -> String:
	match op:
		"pn_crime":
			var low := clampf(float(values.get("min", 0.0)), 0.0, 100.0)
			var high := clampf(float(values.get("max", 0.0)), low, 100.0)
			leg.stand("penal:crime:%s" % values.conduct, {"mode": "prisao", "min": low, "max": high}, norm_id, prio)
			return tr("%s é crime (%d a %d anos)") % [_upper_first(_conduct(values.conduct)), roundi(low), roundi(high)]
		"pn_fine":
			leg.stand("penal:crime:%s" % values.conduct, {"mode": "multa", "amount": maxf(float(values.get("amount", 0.0)), 0.0)}, norm_id, prio)
			return tr("%s só dá multa") % _upper_first(_conduct(values.conduct))
		"pn_decrim":
			leg.stand("penal:crime:%s" % values.conduct, {"mode": "livre"}, norm_id, prio)
			return tr("%s deixa de ser crime") % _upper_first(_conduct(values.conduct))
		"pn_age":
			leg.stand("penal:maioridade", {"age": clampf(float(values.get("age", 18.0)), 7.0, 25.0)}, norm_id, prio)
		"pn_guns":
			leg.stand("penal:armas", {"regime": String(values.get("regime", "restrito"))}, norm_id, prio)
		"pn_death":
			leg.stand("penal:pena_morte", {"status": String(values.get("status", "abolida"))}, norm_id, prio)
		"pn_life":
			leg.stand("penal:perpetua", {"status": String(values.get("status", "proibida")), "years": clampf(float(values.get("years", 40.0)), 5.0, 100.0)}, norm_id, prio)
		"pn_regime":
			leg.stand("penal:regime", {"regime": String(values.get("regime", "progressivo")), "share": clampf(float(values.get("share", 25.0)), 0.0, 100.0) / 100.0}, norm_id, prio)
		"pn_budget":
			var area := String(values.get("area", "policia"))
			leg.stand("penal:orcamento_%s" % area, {"share": clampf(float(values.get("value", 0.0)), 0.0, 10.0) / 100.0}, norm_id, prio)
			return tr("%s%% do PIB para %s") % [UiKit.num(float(values.get("value", 0.0)), 2), tr(choices().security_area.get(area, area))]
		"pn_alternative":
			leg.stand("penal:alternativas", {"years": clampf(float(values.get("years", 0.0)), 0.0, 20.0)}, norm_id, prio)
	return ""


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	_enact_seed(world, leg)
	var law := leg.code_standing(id)
	var yusd := maxf(c.y_usd(), 0.001)
	# Dinheiro: o que a lei manda gastar além (ou aquém) do orçamento de partida.
	var police := float(law.get("orcamento_policia", {}).get("share", BASE_BUDGET.policia))
	var prisons := float(law.get("orcamento_prisoes", {}).get("share", BASE_BUDGET.prisoes))
	var extra := (police - BASE_BUDGET.policia + prisons - BASE_BUDGET.prisoes) * yusd / 12.0
	if extra >= 0.0:
		Legislation._pay(c, extra)
	else:
		Legislation._collect(c, -extra)
	# Penas: quantas condutas são crime, com que dureza, e quanta gente vai presa por isso.
	var severity := 0.0
	var load := 0.0
	var liberty_hits := 0
	var evasion := 0.0
	for conduct: String in CONDUCT_WEIGHT:
		var rule: Dictionary = law.get("crime:" + conduct, {})
		var weight: float = CONDUCT_WEIGHT[conduct]
		match String(rule.get("mode", "")):
			"prisao":
				var years := (float(rule.min) + float(rule.max)) * 0.5
				severity += weight * minf(years / 10.0, 1.5)
				load += weight * minf(years / 8.0, 2.0)
				if conduct in LIBERTY_CONDUCTS:
					liberty_hits += 1
				if conduct == "sonegacao":
					evasion -= 0.01
			"multa":
				severity += weight * 0.1
				if conduct == "sonegacao":
					evasion += 0.01
			_:
				if conduct == "sonegacao":
					evasion += 0.03
				elif conduct == "trafico" or conduct == "corrupcao":
					# Sem crime para o tráfico ou a corrupção, o crime organizado cresce.
					severity -= weight * 0.5
	severity /= 3.0
	var regime: Dictionary = law.get("regime", {})
	var alternative := float(law.get("alternativas", {}).get("years", 0.0))
	load *= 1.0 + float(regime.get("share", 0.25)) - minf(alternative / 8.0, 0.5)
	if String(regime.get("regime", "")) == "integral":
		load *= 1.3
	# Prisão lotada vira escola do crime: a pressão é a carga dividida pela capacidade paga.
	var capacity := prisons / BASE_BUDGET.prisoes
	var crowding := clampf(load / 3.0 / maxf(capacity, 0.2), 0.0, 3.0)
	var guns := String(law.get("armas", {}).get("regime", "restrito"))
	var age := float(law.get("maioridade", {}).get("age", 18.0))
	var death := String(law.get("pena_morte", {}).get("status", "abolida"))
	var life := String(law.get("perpetua", {}).get("status", "proibida"))
	var target := 0.28
	target += (c.inequality - 0.35) * 1.3
	target += (c.unemp - 0.06) * 1.6
	target -= log(maxf(c.gdp_pc(), 500.0) / 12000.0) * 0.04
	target -= clampf((police / BASE_BUDGET.policia - 1.0) * 0.08, -0.12, 0.15)
	target -= clampf(severity, -0.3, 1.0) * 0.06
	target += maxf(crowding - 1.0, 0.0) * 0.05
	target += float({"proibido": -0.02, "restrito": 0.0, "livre": 0.05}.get(guns, 0.0))
	target -= clampf((18.0 - age) * 0.004, -0.03, 0.02)
	target -= 0.005 if death == "crimes_graves" else 0.0
	target -= minf(alternative, 8.0) * 0.002
	target = clampf(target, 0.02, 0.98)
	var crime := float(c.code_stats.get("criminalidade", target))
	crime = clampf(crime + (target - crime) * CRIME_PACE, 0.0, 1.0)
	c.code_stats["criminalidade"] = crime
	c.code_stats["lotacao_prisional"] = crowding
	# Medo do crime derruba a aprovação; a dureza do código agrada ou assusta conforme o regime.
	var free := c.dem >= 6.0
	var harsh := float(liberty_hits) + (1.0 if death == "crimes_graves" else 0.0) + (0.5 if life == "crimes_graves" else 0.0) + (1.0 if guns == "proibido" else 0.0)
	var approval := -(crime - 0.3) * 0.06 - maxf(crowding - 1.2, 0.0) * 0.005
	var stability := -(crime - 0.3) * 0.08 - maxf(crowding - 1.5, 0.0) * 0.01
	if free:
		approval -= harsh * 0.002
		stability -= harsh * 0.001
	else:
		stability += harsh * 0.002
	if guns == "livre":
		stability -= 0.004
	return {
		"approval": approval, "stability": stability, "evasion": evasion,
		"invest": -(crime - 0.3) * 0.05,
	}


## Os códigos semeados nascem em vigor sem rodar: na primeira vez, o texto inicial executa.
func _enact_seed(world: GameWorld, leg: Legislation) -> void:
	var norm := leg.code_norm(id)
	if norm.is_empty() or norm.get("seed_run", false) or not leg.code_standing(id).is_empty():
		return
	norm["seed_run"] = true
	leg.fire(world, "ev_enact", {"only": int(norm.id)})


func _conduct(key: Variant) -> String:
	return tr(choices().penal_conduct.get(String(key), String(key)))


static func _upper_first(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func _add(program: Dictionary, list: Array, type: String, fields: Dictionary) -> void:
	var block := LawProgram.new_block(program, type)
	for key: String in fields:
		block.fields[key] = fields[key]
	list.append(block)


## A bússola média do país, pesada pelo apoio de cada partido. Sem dados: o centro.
static func _lean(world: GameWorld, c: Country) -> Dictionary:
	var out := {"econ": 0.0, "social": 0.0}
	if world.politics == null:
		return out
	var total := 0.0
	for party: Dictionary in world.politics.data_of(c.iso).get("parties", []):
		var support := float(party.get("support", 0.0))
		out.econ = float(out.econ) + float(party.get("econ", 0.0)) * support
		out.social = float(out.social) + float(party.get("social", 0.0)) * support
		total += support
	if total > 0.0:
		out.econ = float(out.econ) / total
		out.social = float(out.social) / total
	return out
