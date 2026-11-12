class_name CodeDireitos
extends LawCode
## Rights and duties: Fundamental rights and duties of citizens.
##
## Everything here counts by the difference from the code's original text, which describes the country as it
## already is: the start of the match changes nothing, and only what the player alters weighs on approval, stability
## and investment. The rights that the Constitution guarantees (Art. 3) apply even without a block; suspending them
## takes the norm to the court. A right that a standalone law already grants or removes (`standing.rights`, from the advanced
## blocks) stays with it: `Legislation._update_macro` counts that one, and this code does not count it again.

const RANK_LAW := 60
const RANK_COMPLEMENTARY := 70

# i18n-begin
const RIGHTS := {
	"expressao": "a liberdade de expressão", "imprensa": "a liberdade de imprensa", "associacao": "a liberdade de reunião e associação",
	"culto": "a liberdade de culto", "privacidade": "a privacidade e o sigilo das comunicações", "greve": "o direito de greve",
	"propriedade": "a propriedade privada", "ir_vir": "a liberdade de ir e vir", "educacao": "a educação pública gratuita",
	"saude": "a saúde pública gratuita", "moradia": "a moradia digna", "internet": "o acesso à internet", "voto": "o voto",
	"arma": "o porte de arma", "aborto": "o aborto legal",
}
# i18n-end
## Civil and political rights: they go into the freedom index.
const CIVIL := ["expressao", "imprensa", "associacao", "culto", "privacidade", "ir_vir", "internet", "voto"]
# i18n-begin
const SCOPES := {"todos": "todas as pessoas", "adultos": "os maiores de 18 anos", "cidadaos": "os cidadãos"}
# i18n-end
## How much of a right's effect applies to each scope: restricting to citizens leaves foreigners out.
const SCOPE_WEIGHT := {"todos": 1.0, "adultos": 0.85, "cidadaos": 0.7}
## Each right's own effect, per month, besides the general weight on approval and stability.
const RIGHT_EFFECTS := {
	"propriedade": {"invest": 0.02},
	"greve": {"invest": -0.004, "inequality": -0.002},
	"ir_vir": {"invest": 0.006, "labor": 0.004},
	"privacidade": {"invest": 0.002},
	"educacao": {"tfp": 0.0005, "inequality": -0.004},
	"saude": {"inequality": -0.003, "labor": 0.002},
	"moradia": {"inequality": -0.002, "invest": -0.002},
	"internet": {"tfp": 0.0003},
	"arma": {"stability": -0.003},
	"aborto": {"stability": -0.001},
}
# i18n-begin
const DUTIES := {
	"tributos": "pagar os tributos", "vacinacao": "vacinar-se e vacinar os filhos", "alistamento": "alistar-se nas Forças Armadas aos 18 anos",
	"voto": "votar nas eleições",
}
# i18n-end
const DUTY_EFFECTS := {
	"tributos": {"evasion": -0.01},
	"vacinacao": {"approval": -0.002, "tfp": 0.0002},
	"alistamento": {"approval": -0.001},
	"voto": {"approval": -0.002, "stability": 0.001},
}
# i18n-begin
const DRAFTEES := {"homens": "os homens", "todos": "homens e mulheres"}
# i18n-end
# i18n-begin
const OUTLETS := {"imprensa": "a imprensa", "internet": "a internet", "artes": "as artes e os espetáculos"}
# i18n-end
const LEVELS := {"1": "leve", "2": "moderado", "3": "rigoroso"}
# i18n-begin
const SERVICES := {"redes": "as redes sociais estrangeiras", "noticias": "os sites de notícias estrangeiros", "vpn": "as VPNs e ferramentas de anonimato"}
# i18n-end

## Share of each 18-year-old generation actually drafted, and the size of a generation of men in the population.
const DRAFT_RATE := 0.15
const COHORT_MEN := 0.0065
## Without a schooling duty, actual primary education applies.
const SCHOOL_DEFAULT := 10

## Countries with compulsory military service and the duration, in months.
const CONSCRIPTION := {
	"BRA": 12, "RUS": 12, "KOR": 18, "PRK": 120, "ISR": 32, "TUR": 12, "EGY": 24, "IRN": 21, "CHE": 5, "AUT": 6, "FIN": 6, "NOR": 12,
	"GRC": 9, "VNM": 24, "THA": 24, "COL": 18, "UKR": 18, "CUB": 24, "SGP": 24, "TWN": 12, "DNK": 4, "EST": 11, "LTU": 9, "SWE": 11,
	"DZA": 12, "SYR": 24, "ERI": 18, "MMR": 24, "BOL": 12, "PRY": 12, "ARM": 24, "AZE": 18, "GEO": 12, "BLR": 18, "KAZ": 12, "UZB": 12,
}
const COMPULSORY_VOTE := ["BRA", "ARG", "AUS", "BEL", "PER", "URY", "ECU", "BOL", "LUX", "SGP", "PRY", "CRI", "EGY"]
const GUNS := ["USA", "CHE", "CZE", "YEM", "PAK", "FIN", "SRB", "URY"]
const ABORTION := [
	"USA", "CAN", "MEX", "ARG", "URY", "COL", "CUB", "FRA", "DEU", "GBR", "ESP", "PRT", "ITA", "NLD", "BEL", "CHE", "AUT", "SWE", "NOR", "DNK",
	"FIN", "ISL", "IRL", "CZE", "SVK", "HUN", "ROU", "BGR", "GRC", "EST", "LVA", "LTU", "SVN", "HRV", "SRB", "UKR", "RUS", "BLR", "KAZ", "CHN",
	"VNM", "MNG", "PRK", "IND", "JPN", "KOR", "AUS", "NZL", "ZAF", "TUN", "TUR", "MOZ", "THA", "NPL", "KHM",
]
const FIREWALL := ["CHN", "IRN", "PRK", "TKM", "ERI"]


func _init() -> void:
	# Rights and duties apply as a complementary law; those the Constitution guarantees stay in Art. 3.
	id = "direitos"
	title = "Direitos e deveres"
	ementa = "Direitos fundamentais e deveres dos cidadãos."
	category = {"id": "direitos", "label": "Direitos e deveres", "color": Color("a53f5e")}


func blocks() -> Array:
	return [
		{"id": "dr_right", "cat": "direitos", "kind": "statement", "text": "Garantir {right} a {scope}", "fields": {"right": {"t": "choice", "of": "dr_right", "d": "expressao"}, "scope": {"t": "choice", "of": "dr_scope", "d": "todos"}}, "rank": RANK_LAW, "econ": -0.05, "social": 0.4, "pop": 0.04},
		{"id": "dr_suspend", "cat": "direitos", "kind": "statement", "text": "Suspender {right}", "fields": {"right": {"t": "choice", "of": "dr_right", "d": "greve"}}, "rank": RANK_COMPLEMENTARY, "social": -0.6, "pop": -0.1},
		{"id": "dr_duty", "cat": "direitos", "kind": "statement", "text": "Todos têm o dever de {duty}", "fields": {"duty": {"t": "choice", "of": "dr_duty", "d": "tributos"}}, "rank": RANK_LAW, "social": -0.15, "pop": -0.03},
		{"id": "dr_military", "cat": "direitos", "kind": "statement", "text": "Serviço militar obrigatório de {months} meses para {who}", "fields": {"months": {"t": "num", "d": 12}, "who": {"t": "choice", "of": "dr_draftees", "d": "homens"}}, "rank": RANK_LAW, "social": -0.25, "pop": -0.06},
		{"id": "dr_school", "cat": "direitos", "kind": "statement", "text": "Escolaridade obrigatória até os {age} anos", "fields": {"age": {"t": "num", "d": 17}}, "rank": RANK_LAW, "econ": -0.05, "social": 0.05, "pop": 0.02},
		{"id": "dr_censor", "cat": "direitos", "kind": "statement", "text": "Submeter {outlet} à censura prévia", "fields": {"outlet": {"t": "choice", "of": "dr_outlet", "d": "imprensa"}}, "rank": RANK_COMPLEMENTARY, "social": -0.7, "pop": -0.1},
		{"id": "dr_regulate", "cat": "direitos", "kind": "statement", "text": "Regular {outlet} por um conselho de rigor {level}", "fields": {"outlet": {"t": "choice", "of": "dr_outlet", "d": "imprensa"}, "level": {"t": "choice", "of": "dr_level", "d": "1"}}, "rank": RANK_LAW, "social": -0.2, "pop": -0.02},
		{"id": "dr_block", "cat": "direitos", "kind": "statement", "text": "Bloquear {service} na internet", "fields": {"service": {"t": "choice", "of": "dr_service", "d": "redes"}}, "rank": RANK_LAW, "social": -0.5, "pop": -0.06},
		{"id": "dr_emergency", "cat": "direitos", "kind": "statement", "text": "Decretar estado de emergência por {days} dias", "fields": {"days": {"t": "days", "d": 30}}, "rank": RANK_COMPLEMENTARY, "social": -0.5, "pop": -0.05},
	]


func choices() -> Dictionary:
	var duties := DUTIES.duplicate()
	if electoral_vote_duty():
		duties.erase("voto")
	return {"dr_right": RIGHTS, "dr_scope": SCOPES, "dr_duty": duties, "dr_draftees": DRAFTEES, "dr_outlet": OUTLETS, "dr_level": LEVELS, "dr_service": SERVICES}


## Compulsory voting belongs to the Electoral Code once it has its own block for it.
static func electoral_vote_duty() -> bool:
	var electoral := LawCodes.get_code("eleitoral")
	if electoral == null:
		return false
	for b: Dictionary in electoral.blocks():
		var text := String(b.get("text", "")).to_lower()
		if text.contains("voto") and text.contains("obrigat"):
			return true
	return false


# --- Initial text ---------------------------------------------------------------------

func seed_program(world: GameWorld, c: Country) -> Dictionary:
	var program := LawProgram.empty()
	var rights := _seed_rights(world, c)
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	for r: String in rights:
		var block := LawProgram.new_block(program, "dr_right")
		block.fields.right = r
		block.fields.scope = "cidadaos" if r == "voto" or r == "arma" else ("adultos" if r == "aborto" else "todos")
		stack.blocks.append(block)
	# Rights in one column; duties and press in another, beside it, so nothing overlaps in the editor.
	var duties := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(520, 30))
	var duty := LawProgram.new_block(program, "dr_duty")
	duty.fields.duty = "tributos"
	duties.blocks.append(duty)
	var school := LawProgram.new_block(program, "dr_school")
	school.fields.age = 17 if c.gdp_pc() >= 12000.0 else 14
	duties.blocks.append(school)
	if c.sp_health >= 0.04:
		var vaccine := LawProgram.new_block(program, "dr_duty")
		vaccine.fields.duty = "vacinacao"
		duties.blocks.append(vaccine)
	if CONSCRIPTION.has(c.iso):
		var service := LawProgram.new_block(program, "dr_military")
		service.fields.months = CONSCRIPTION[c.iso]
		service.fields.who = "todos" if c.iso in ["ISR", "PRK", "NOR", "SWE", "ERI"] else "homens"
		duties.blocks.append(service)
	elif c.iso == "USA":
		var draft := LawProgram.new_block(program, "dr_duty")
		draft.fields.duty = "alistamento"
		duties.blocks.append(draft)
	if c.iso in COMPULSORY_VOTE and not electoral_vote_duty():
		var vote := LawProgram.new_block(program, "dr_duty")
		vote.fields.duty = "voto"
		duties.blocks.append(vote)
	var media := []
	if c.dem < 4.0:
		media.append(["dr_censor", {"outlet": "imprensa"}])
		media.append(["dr_censor", {"outlet": "internet"}])
	elif c.dem < 6.0:
		media.append(["dr_regulate", {"outlet": "imprensa", "level": "2"}])
	if c.iso in FIREWALL:
		media.append(["dr_block", {"service": "redes"}])
		media.append(["dr_block", {"service": "vpn"}])
	if not media.is_empty():
		var y: int = 90 + 40 * duties.blocks.size()
		var press := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(520, y))
		for entry: Array in media:
			var block := LawProgram.new_block(program, entry[0])
			block.fields.merge(entry[1], true)
			press.blocks.append(block)
	return program


## The country's actual rights: those of the Constitution and what the regime and budget already sustain.
func _seed_rights(world: GameWorld, c: Country) -> Array:
	var out := []
	var guaranteed: Array = world.legislation.param("rights", []) if world.legislation else []
	for r: String in RIGHTS:
		var on := false
		match r:
			"expressao", "imprensa", "privacidade", "internet":
				on = c.dem >= 6.0
			"associacao", "greve":
				on = c.dem >= 5.0
			"culto":
				on = c.dem >= 3.0
			"ir_vir", "propriedade":
				on = c.dem >= 2.0
			"voto":
				on = c.dem >= 4.0
			"educacao":
				on = c.sp_education >= 0.03
			"saude":
				on = c.sp_health >= 0.04
			"moradia":
				on = c.dem >= 6.0 and c.sp_social >= 0.12
			"arma":
				on = c.iso in GUNS
			"aborto":
				on = c.iso in ABORTION
		if on or r in guaranteed:
			out.append(r)
	return out


# --- Execution --------------------------------------------------------------------------

func apply(world: GameWorld, leg: Legislation, op: String, values: Dictionary, _weight: float, norm_id: int, prio: float) -> String:
	match op:
		"dr_right":
			var r := String(values.get("right", ""))
			leg.stand("direitos:right:" + r, {"on": true, "scope": String(values.get("scope", "todos"))}, norm_id, prio)
			return tr("garante %s") % tr(RIGHTS.get(r, r))
		"dr_suspend":
			var r := String(values.get("right", ""))
			leg.stand("direitos:right:" + r, {"on": false, "scope": "todos"}, norm_id, prio)
			return tr("suspende %s") % tr(RIGHTS.get(r, r))
		"dr_duty":
			var d := String(values.get("duty", ""))
			leg.stand("direitos:duty:" + d, {"on": true}, norm_id, prio)
			return tr("dever de %s") % tr(DUTIES.get(d, d))
		"dr_military":
			var months := clampi(roundi(float(values.get("months", 12))), 1, 60)
			leg.stand("direitos:military", {"months": months, "who": String(values.get("who", "homens"))}, norm_id, prio)
			return tr("serviço militar de %d meses") % months
		"dr_school":
			var age := clampi(roundi(float(values.get("age", 17))), 6, 21)
			leg.stand("direitos:school", {"age": age}, norm_id, prio)
			return tr("escola obrigatória até os %d anos") % age
		"dr_censor":
			leg.stand("direitos:censor:" + String(values.get("outlet", "")), {"on": true}, norm_id, prio)
			return tr("censura prévia")
		"dr_regulate":
			leg.stand("direitos:regulate:" + String(values.get("outlet", "")), {"level": int(String(values.get("level", "1")))}, norm_id, prio)
			return tr("conselho de regulação")
		"dr_block":
			leg.stand("direitos:block:" + String(values.get("service", "")), {"on": true}, norm_id, prio)
			return tr("bloqueio na internet")
		"dr_emergency":
			var days := clampi(roundi(float(values.get("days", 30))), 1, 365)
			leg.stand("direitos:emergency", {"until": world.day_index + days, "days": days}, norm_id, prio)
			world.emit_news(tr("Estado de emergência decretado por %d dias.") % days, "crise", world.player)
			return tr("estado de emergência por %d dias") % days
	return ""


## State that a program describes, in the same keys that `apply` stores. Repealed articles do not count.
static func state_of(program: Dictionary) -> Dictionary:
	var blocks := []
	for stack: Dictionary in program.get("stacks", []):
		if not stack.get("repealed", false):
			LawProgram.walk(stack.blocks, func(b): blocks.append(b))
	var out := {}
	for b: Dictionary in blocks:
		var f: Dictionary = b.fields
		match String(b.type):
			"dr_right":
				out["right:" + String(f.get("right", ""))] = {"on": true, "scope": String(f.get("scope", "todos"))}
			"dr_suspend":
				out["right:" + String(f.get("right", ""))] = {"on": false, "scope": "todos"}
			"dr_duty":
				out["duty:" + String(f.get("duty", ""))] = {"on": true}
			"dr_military":
				out["military"] = {"months": clampi(roundi(float(f.get("months", 12))), 1, 60), "who": String(f.get("who", "homens"))}
			"dr_school":
				out["school"] = {"age": clampi(roundi(float(f.get("age", 17))), 6, 21)}
			"dr_censor":
				out["censor:" + String(f.get("outlet", ""))] = {"on": true}
			"dr_regulate":
				out["regulate:" + String(f.get("outlet", ""))] = {"level": int(String(f.get("level", "1")))}
			"dr_block":
				out["block:" + String(f.get("service", ""))] = {"on": true}
	return out


## The text the code started the match with, even if it was repealed later.
static func _base_norm(leg: Legislation) -> Dictionary:
	for norm: Dictionary in leg.norms.values():
		if String(norm.get("code", "")) == "direitos" and norm.get("base_code", false) and not norm.versions.is_empty():
			return norm
	return {}


## What applies now: the original text while nobody has changed the code, plus what the norms in force keep.
static func current_state(leg: Legislation) -> Dictionary:
	var base := _base_norm(leg)
	var code := leg.code_norm("direitos")
	var out := {}
	if not code.is_empty() and int(code.current_v) == 0 and int(code.id) == int(base.get("id", -1)):
		out = state_of(code.versions[0].program)
	out.merge(leg.code_standing("direitos"), true)
	return out


static func base_state(leg: Legislation) -> Dictionary:
	var base := _base_norm(leg)
	return state_of(base.versions[0].program) if not base.is_empty() else {}


## 1 with the right in force for everyone, less for a smaller scope, 0 if it does not apply. Without a block, the Constitution applies.
static func right_level(leg: Legislation, state: Dictionary, r: String) -> float:
	if leg.standing.rights.has(r):
		return 1.0 if leg.standing.rights[r].on else 0.0
	var entry: Dictionary = state.get("right:" + r, {})
	if entry.is_empty():
		return 1.0 if r in leg.param("rights", []) else 0.0
	return float(SCOPE_WEIGHT.get(String(entry.scope), 1.0)) if entry.on else 0.0


## Draftees per year, in thousands of soldiers.
static func conscripts(c: Country, state: Dictionary) -> float:
	var service: Dictionary = state.get("military", {})
	if service.is_empty():
		return 0.0
	var share := 2.0 if String(service.who) == "todos" else 1.0
	return c.pop * 1000.0 * COHORT_MEN * share * float(service.months) / 12.0 * DRAFT_RATE


## Freedom index, from 0 to 100.
static func freedom_index(world: GameWorld, leg: Legislation, state: Dictionary) -> float:
	var score := 0.0
	for r: String in CIVIL:
		score += right_level(leg, state, r)
	score = score / float(CIVIL.size()) * 100.0
	for key: String in state:
		if key.begins_with("censor:"):
			score -= 15.0
		elif key.begins_with("block:"):
			score -= 5.0
		elif key.begins_with("regulate:"):
			score -= 3.0 * float(state[key].level)
	if int(state.get("emergency", {}).get("until", -1)) > world.day_index:
		score -= 20.0
	return clampf(score, 0.0, 100.0)


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	var now := current_state(leg)
	var base := base_state(leg)
	var out := {"approval": 0.0, "stability": 0.0, "invest": 0.0, "labor": 0.0, "tfp": 0.0, "inequality": 0.0, "evasion": 0.0}
	var free := c.dem >= 4.0
	for r: String in RIGHTS:
		if leg.standing.rights.has(r):
			continue
		var d := right_level(leg, now, r) - right_level(leg, base, r)
		if is_zero_approx(d):
			continue
		if d > 0.0:
			out.approval += Legislation.RIGHT_APPROVAL * d
			out.stability += Legislation.RIGHT_STABILITY * d
		else:
			out.approval += Legislation.RIGHT_APPROVAL * 2.0 * d
			out.stability += Legislation.RIGHT_STABILITY * d * (1.0 if free else -0.5)
		var extra: Dictionary = RIGHT_EFFECTS.get(r, {})
		for k: String in extra:
			out[k] += float(extra[k]) * d
	for duty: String in DUTIES:
		var d := (1.0 if now.has("duty:" + duty) else 0.0) - (1.0 if base.has("duty:" + duty) else 0.0)
		if is_zero_approx(d):
			continue
		var extra: Dictionary = DUTY_EFFECTS.get(duty, {})
		for k: String in extra:
			out[k] += float(extra[k]) * d
	_military(c, now, base, out)
	var school := float(now.get("school", {}).get("age", SCHOOL_DEFAULT)) - float(base.get("school", {}).get("age", SCHOOL_DEFAULT))
	out.tfp += 0.0003 * school
	out.labor -= 0.002 * school
	out.inequality -= 0.001 * school
	out.approval += 0.0005 * school
	for outlet: String in OUTLETS:
		var d := (1.0 if now.has("censor:" + outlet) else 0.0) - (1.0 if base.has("censor:" + outlet) else 0.0)
		out.approval -= (0.006 if free else 0.002) * d
		out.stability += (-0.004 if free else 0.004) * d
		out.invest -= 0.005 * d
		if outlet == "internet":
			out.tfp -= 0.0003 * d
		var level := float(now.get("regulate:" + outlet, {}).get("level", 0)) - float(base.get("regulate:" + outlet, {}).get("level", 0))
		out.approval -= 0.0015 * level
		out.invest -= 0.001 * level
	for service: String in SERVICES:
		var d := (1.0 if now.has("block:" + service) else 0.0) - (1.0 if base.has("block:" + service) else 0.0)
		out.approval -= 0.003 * d
		out.invest -= 0.003 * d
		out.tfp -= 0.0002 * d
	if int(now.get("emergency", {}).get("until", -1)) > world.day_index:
		var war := world.diplomacy.in_war(c.idx)
		out.approval -= 0.003 if war else 0.01
		out.stability += 0.008
		out.invest -= 0.01
	c.code_stats["liberdades"] = freedom_index(world, leg, now)
	return out


## Military service: the base force follows the draftees above or below the original text,
## within a limit, and whoever is in the barracks leaves the labor force.
func _military(c: Country, now: Dictionary, base: Dictionary, out: Dictionary) -> void:
	var reference := float(c.code_stats.get_or_add("direitos_efetivo_base", c.troops0))
	var delta := clampf(conscripts(c, now) - conscripts(c, base), -0.6 * reference, reference)
	var applied := float(c.code_stats.get("direitos_conscritos", 0.0))
	if not is_equal_approx(delta, applied):
		c.troops0 = maxf(c.troops0 + delta - applied, 0.5)
		c.code_stats["direitos_conscritos"] = delta
	c.code_stats["conscritos"] = conscripts(c, now)
	out.labor -= delta / maxf(c.pop * 500.0, 1.0)
	var burden := func(state: Dictionary) -> float:
		var service: Dictionary = state.get("military", {})
		return 0.0 if service.is_empty() else float(service.months) / 12.0 * (2.0 if String(service.who) == "todos" else 1.0)
	var d: float = burden.call(now) - burden.call(base)
	out.approval -= 0.006 * d
