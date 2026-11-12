class_name CodeEleitoral
extends LawCode
## Electoral Code: Voting, electoral age, campaign financing, reelection and quotas.
##
## The Constitution rules: the system (Art. 18), the minimum electoral threshold (Art. 20) and the term (Art. 4)
## are its own. The code only chooses the system if the Constitution is silent, may raise the threshold above the
## constitutional floor and records parliament's term, which follows the Constitution's. `Elections.run` reads
## the rules from here through `rules_for`, and `Politics.player_election` respects the reelection limit.

const ITEMS := {
	"el_vote": "voto", "el_age": "idade", "el_system": "sistema", "el_threshold": "barreira", "el_funding": "financiamento",
	"el_reelection": "reeleicao", "el_term": "mandato", "el_quota": "cota", "el_ballot": "urna", "el_free_ads": "propaganda",
}
## Weight of the party fund in the vote, by financing model.
const MONEY_WEIGHT := {"publico": 0.0, "misto": 0.06, "privado_teto": 0.08, "privado": 0.15}
const COMPULSORY := ["ARG", "AUS", "BEL", "BOL", "BRA", "ECU", "EGY", "LUX", "PER", "PRY", "SGP", "TUR", "URY", "THA"]
const YOUTH_VOTE := ["ARG", "AUT", "BRA", "CUB", "ECU", "NIC", "MLT"]
const E_VOTING := ["BRA", "IND", "VEN", "PHL", "BGD", "EST"]


func _init() -> void:
	id = "eleitoral"
	title = "Código Eleitoral"
	ementa = "Voto, idade eleitoral, financiamento de campanha, reeleição e cotas."
	category = {"id": "eleitoral", "label": "Eleições", "color": Color("6a4fa5")}


func blocks() -> Array:
	var cat: String = category.id
	var rank := LawCatalog.RANK_COMPLEMENTARY
	return [
		{"id": "el_vote", "cat": cat, "kind": "statement", "text": "Voto {mode}", "fields": {"mode": {"t": "choice", "of": "el_vote_mode", "d": "facultativo"}}, "rank": rank, "social": 0.1},
		{"id": "el_age", "cat": cat, "kind": "statement", "text": "Idade mínima para votar de {age} anos", "fields": {"age": {"t": "num", "d": 18}}, "rank": rank, "social": 0.1},
		{"id": "el_system", "cat": cat, "kind": "statement", "text": "O parlamento é eleito pelo sistema {system}", "fields": {"system": {"t": "choice", "of": "el_system", "d": "pr"}}, "rank": rank},
		{"id": "el_threshold", "cat": cat, "kind": "statement", "text": "Cláusula de barreira de {pct}% dos votos nacionais", "fields": {"pct": {"t": "pct", "d": 3}}, "rank": rank, "social": -0.1},
		{"id": "el_funding", "cat": cat, "kind": "statement", "text": "Financiamento de campanha {mode}", "fields": {"mode": {"t": "choice", "of": "el_funding", "d": "misto"}}, "rank": rank, "econ": 0.1},
		{"id": "el_reelection", "cat": cat, "kind": "statement", "text": "Reeleição do chefe de governo: {mode}", "fields": {"mode": {"t": "choice", "of": "el_reelection", "d": "uma"}}, "rank": rank, "social": 0.1},
		{"id": "el_term", "cat": cat, "kind": "statement", "text": "Mandato do parlamento de {years} anos", "fields": {"years": {"t": "num", "d": 4}}, "rank": rank},
		{"id": "el_quota", "cat": cat, "kind": "statement", "text": "Cota mínima de {pct}% de mulheres nas listas dos partidos", "fields": {"pct": {"t": "pct", "d": 30}}, "rank": rank, "social": 0.2},
		{"id": "el_ballot", "cat": cat, "kind": "statement", "text": "Votação em {mode}", "fields": {"mode": {"t": "choice", "of": "el_ballot", "d": "papel"}}, "rank": rank},
		{"id": "el_free_ads", "cat": cat, "kind": "statement", "text": "Propaganda eleitoral gratuita no rádio e na TV: {on}", "fields": {"on": {"t": "bool", "d": true}}, "rank": rank, "social": 0.05},
	]


func choices() -> Dictionary:
	return {
		"el_vote_mode": {"obrigatorio": "obrigatório", "facultativo": "facultativo"},
		"el_system": Elections.SYSTEMS,
		"el_funding": {"publico": "só público", "misto": "misto, público e privado", "privado_teto": "privado, com teto por doador", "privado": "privado, sem teto"},
		"el_reelection": {"proibida": "proibida", "uma": "permitida uma vez", "ilimitada": "ilimitada"},
		"el_ballot": {"eletronica": "urna eletrônica", "papel": "cédula de papel"},
	}


func _defaults(world: GameWorld, c: Country) -> Dictionary:
	var leg: Legislation = world.legislation
	var rule := Elections.rules(c, world.politics.data_of(c.iso))
	var presidential := String(rule.head) == "presidential"
	var funding := "misto"
	if c.iso == "BRA":
		funding = "publico"
	elif c.iso == "USA":
		funding = "privado"
	elif c.dem < 4.0:
		funding = "publico"
	return {
		"voto": {"mode": "obrigatorio" if c.iso in COMPULSORY else "facultativo"},
		"idade": {"age": 16 if c.iso in YOUTH_VOTE else 18},
		"sistema": {"system": String(leg.param("electoral_system", rule.system)) if leg else String(rule.system)},
		"barreira": {"pct": roundi(float(leg.param("threshold", 3)) if leg else float(rule.threshold) * 100.0)},
		"financiamento": {"mode": funding},
		"reeleicao": {"mode": "uma" if presidential and c.dem >= 4.0 else "ilimitada"},
		"mandato": {"years": roundi(leg.mandate_years()) if leg else 4},
		"cota": {"pct": 30 if c.dem >= 6.0 or c.region == "LAM" else 0},
		"urna": {"mode": "eletronica" if c.iso in E_VOTING else "papel"},
		"propaganda": {"on": c.dem >= 6.0 and c.iso != "USA"},
	}


func seed_program(world: GameWorld, c: Country) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	var values := _defaults(world, c)
	for op: String in ITEMS:
		var block := LawProgram.new_block(program, op)
		var fields: Dictionary = values[ITEMS[op]]
		for key: String in fields:
			block.fields[key] = fields[key]
		stack.blocks.append(block)
	return program


func apply(_world: GameWorld, leg: Legislation, op: String, values: Dictionary, weight: float, norm_id: int, prio: float) -> String:
	var item := String(ITEMS.get(op, ""))
	if item == "" or weight <= 0.0:
		return ""
	leg.stand(id + ":" + item, values.duplicate(), norm_id, prio)
	match op:
		"el_system":
			var fixed := String(leg.param("electoral_system", ""))
			if fixed != "" and fixed != String(values.system):
				return tr("sistema sem efeito: a Constituição (Art. 18) fixa %s") % tr(Elections.SYSTEMS.get(fixed, fixed)).to_lower()
		"el_threshold":
			var floor_pct := float(leg.param("threshold", 0))
			if float(values.pct) < floor_pct:
				return tr("barreira abaixo do piso constitucional de %d%%: vale a Constituição") % roundi(floor_pct)
		"el_term":
			if roundi(float(values.years)) != roundi(leg.mandate_years()):
				return tr("mandato sem efeito: a Constituição (Art. 4º) fixa %d anos") % roundi(leg.mandate_years())
	return ""


# --- Rules for the elections --------------------------------------------------------------

## What is in force, with the original text filling in what is missing. Empty without a code.
func _current(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	var norm := leg.code_norm(id)
	var held := leg.code_standing(id)
	if held.is_empty() and not norm.is_empty():
		# The code seeded at the start of the match never fired "on taking effect": it fires now, once.
		leg.fire(world, "ev_enact", {"only": int(norm.id)})
		held = leg.code_standing(id)
	if norm.is_empty() and held.is_empty():
		return {}
	var out := _defaults(world, c)
	if not norm.is_empty() and not norm.versions.is_empty():
		out.merge(_read_program(norm.versions[0].program), true)
	out.merge(held, true)
	return out


func _read_program(program: Dictionary) -> Dictionary:
	var out := {}
	for block: Dictionary in LawProgram.all_blocks(program):
		var item := String(ITEMS.get(String(block.type), ""))
		if item != "":
			out[item] = block.fields
	return out


## Rules of the Electoral Code for the election of `c`, only in the player's country. Empty: the game default applies.
## {threshold (fraction), system ("" if the Constitution decides), turnout (adds to turnout),
## compulsory, money_weight, reelection}.
static func rules_for(world: GameWorld, c: Country) -> Dictionary:
	if world == null or c == null or world.player != c or world.legislation == null or world.legislation.iso != c.iso:
		return {}
	var code := LawCodes.get_code("eleitoral") as CodeEleitoral
	var leg: Legislation = world.legislation
	var v := code._current(world, c, leg)
	if v.is_empty():
		return {}
	var compulsory := String(v.voto.mode) == "obrigatorio"
	var turnout := 0.12 if compulsory else 0.0
	turnout += 0.02 if bool(v.propaganda.on) else 0.0
	turnout += 0.01 if String(v.urna.mode) == "eletronica" else 0.0
	# Young people vote less: lowering the age increases the electorate more than the votes.
	turnout -= clampf(18.0 - float(v.idade.age), 0.0, 4.0) * 0.005
	var money := float(MONEY_WEIGHT.get(String(v.financiamento.mode), 0.06))
	if bool(v.propaganda.on):
		money *= 0.6
	# The Constitution fixes the system; the code only decides if the article was suppressed.
	var system := "" if String(leg.param("electoral_system", "")) != "" else String(v.sistema.system)
	return {
		"threshold": maxf(float(v.barreira.pct) / 100.0, float(leg.param("threshold", 0)) / 100.0),
		"system": system, "turnout": turnout, "compulsory": compulsory,
		"money_weight": money, "reelection": String(v.reeleicao.mode),
	}


## Can the player run for another term? Counts the terms they have already won in the country.
static func may_run_again(world: GameWorld) -> bool:
	var rules := rules_for(world, world.player)
	match String(rules.get("reelection", "ilimitada")):
		"proibida":
			return false
		"uma":
			return world.mandates < 1
	return true


# --- Monthly effect -----------------------------------------------------------------------

func _effects(c: Country, v: Dictionary) -> Dictionary:
	var free := c.dem >= 4.0
	var e := {"approval": 0.0, "stability": 0.0, "invest": 0.0, "cost": 0.0}
	if String(v.voto.mode) == "obrigatorio":
		e.approval -= 0.004
		e.stability += 0.002
	e.approval += clampf(18.0 - float(v.idade.age), -4.0, 4.0) * 0.001
	match String(v.financiamento.mode):
		"publico":
			e.cost += 0.0002
			e.approval += 0.003
		"privado":
			e.invest += 0.004
			e.approval -= 0.006
			e.stability -= 0.003
		"privado_teto":
			e.invest += 0.002
	var reelection := String(v.reeleicao.mode)
	if reelection == "ilimitada" and free:
		e.stability -= 0.004
	elif reelection == "proibida":
		e.stability += 0.002
	e.approval += float(v.cota.pct) / 100.0 * (0.01 if free else 0.002)
	if String(v.urna.mode) == "eletronica":
		e.cost += 0.0001
		e.stability += 0.004 if c.dem >= 5.0 else -0.002
	if bool(v.propaganda.on):
		e.cost += 0.0001
		e.approval += 0.002
	# A high threshold leaves the small parties out of parliament: fewer parties, more complaints from those left out.
	e.stability -= maxf(float(v.barreira.pct) - 5.0, 0.0) * 0.002
	return e


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	var now := _current(world, c, leg)
	if now.is_empty():
		return {}
	var norm := leg.code_norm(id)
	var base := _defaults(world, c)
	if not norm.is_empty() and not norm.versions.is_empty():
		base.merge(_read_program(norm.versions[0].program), true)
	var e_now := _effects(c, now)
	var e_base := _effects(c, base)
	var extra := (float(e_now.cost) - float(e_base.cost)) * c.y_usd() / 12.0
	if extra > 0.0:
		Legislation._pay(c, extra)
	elif extra < 0.0:
		Legislation._collect(c, -extra)
	var rules := rules_for(world, c)
	c.code_stats["comparecimento"] = clampf(Elections.base_turnout(c) + float(rules.get("turnout", 0.0)), 0.3, 0.97)
	return {
		"approval": float(e_now.approval) - float(e_base.approval),
		"stability": float(e_now.stability) - float(e_base.stability),
		"invest": float(e_now.invest) - float(e_base.invest),
	}
