class_name Corruption
extends RefCounted
## Corruption of the player's government, paid for now with the party fund.
##
## Contract with the rest of the game:
## - `Country.corruption` is the real level, `Country.corruption0` the starting one and `Country.corr_seen` what public
##   opinion and investors see (slow to follow, and jumps in a scandal). All from 0 to 1.
## - The economy only feels the DEVIATION from the start (`drift`): without player action the deviation is zero, and nothing changes
##   in the calibration. The hooks are in Economy (`_risk_premium`, investment, collection).
## - Money comes from a single point: `balance`, `take` and `give`. To change the source (State cash, donations,
##   favors) just change these three functions.
## - `offer` and `quote` are the door to diplomacy: a conversation with a party leader can pay the counterpart
##   of a vote without knowing anything about this file.
## Runs on the simulation thread: no nodes or signals, only `world.emit_news` and `world.ask_player`.

## Prices in multiples of the fund unit (Politics.fund_unit).
const BRIBE_FACTOR := 0.6
const HUSH_PRICE := 1.5
const FAVOR_PRICE := 1.0
const FAVOR_RETURN := 1.6
const FAVOR_MONTHS := 6
const EMBEZZLE_GAIN := 2.0
const SKIM_GAIN := 1.5
const SKIM_SCORE := 2.0
const SKIM_SCORE_CAP := 60.0

## Each action: moral debt on the real level (`corruption`), exposure (`heat`) and cooldown, in months.
const ACTIONS := {
	"bribe": {"corruption": 0.010, "heat": 0.12, "cooldown": 0},
	"hush": {"corruption": 0.008, "heat": 0.0, "cooldown": 2},
	"favor": {"corruption": 0.015, "heat": 0.10, "cooldown": 3},
	"embezzle": {"corruption": 0.020, "heat": 0.18, "cooldown": 3},
	"skim": {"corruption": 0.020, "heat": 0.20, "cooldown": 3},
}
# i18n-begin
const LABELS := {
	"bribe": "Comprar votos", "hush": "Abafar o escândalo", "favor": "Favorecer empresas aliadas",
	"embezzle": "Caixa dois para o partido", "skim": "Desviar para si",
}
const DESCRIPTIONS := {
	"bribe": "Paga a um partido para votar como você quer numa lei em tramitação. Quase sempre aceita, sem deixar rastro na negociação oficial.",
	"hush": "Paga para esfriar investigações e matérias. Tira exposição e processo, mas fracassa mais onde a imprensa e a justiça são fortes.",
	"favor": "Contratos para empresas aliadas, que devolvem parte ao fundo ao longo de seis meses.",
	"embezzle": "Desvia verba do Estado para o fundo do partido. Rende na hora, e é a ação que mais chama atenção.",
	"skim": "Leva dinheiro público para o seu bolso. Conta pontos no fim da carreira, se ninguém descobrir antes.",
}
# i18n-end
## Chance of a month with no action bringing the scandal: exposure * (BASE + SCALE * integrity).
const SCANDAL_BASE := 0.10
const SCANDAL_SCALE := 0.50
const HEAT_DECAY := 0.06
## The real level slowly returns to the start, faster where institutions work.
const REVERT := 0.010
const SEEN_FOLLOW := 0.08
const INVESTIGATION_MONTHS := 6
const CASE_LIMIT := 0.6
const CASE_DECAY := 0.03
## Cap on the deviation the economy feels, and the strength of each channel.
const DRIFT_MIN := -0.10
const DRIFT_MAX := 0.60
const RISK_PER_DRIFT := 0.06
const INVEST_PER_DRIFT := 0.35
const EVASION_PER_DRIFT := 0.25
## Words that mark an institution created by law as an anti-corruption body.
const WATCHDOG_WORDS := ["corrup", "integridade", "controladoria", "auditoria", "ouvidoria"]

var heat := 0.0
var case_load := 0.0
var investigation := 0
var stash := 0.0
var scandals := 0
var last_scandal := -999
var cooldowns := {}
var kickbacks := []
## Latest facts, from newest to oldest: {month, text}.
var history := []
var revision := 0
var _rng := RandomNumberGenerator.new()


func setup(world: GameWorld) -> void:
	_rng.seed = world.rng.seed ^ 0x5C0A
	for c: Country in world.countries:
		var base := base_level(c)
		c.corruption = base
		c.corruption0 = base
		c.corr_seen = base


## Starting level: more democratic and richer, less corrupt.
static func base_level(c: Country) -> float:
	return clampf(0.88 - 0.065 * c.dem - 0.2 * minf(c.gdp_pc() / 40000.0, 1.0), 0.05, 0.95)


## How much corruption has risen (or fallen) since the start. This is what the economy feels.
static func drift(c: Country) -> float:
	return clampf(c.corruption - c.corruption0, DRIFT_MIN, DRIFT_MAX)


static func risk_extra(c: Country) -> float:
	return RISK_PER_DRIFT * drift(c)


static func invest_factor(c: Country) -> float:
	return 1.0 - INVEST_PER_DRIFT * drift(c)


static func collection_factor(c: Country) -> float:
	return 1.0 - EVASION_PER_DRIFT * drift(c)


## Score in the style of perception indexes: 100 is clean.
static func perception_score(c: Country) -> int:
	return int(round(100.0 * (1.0 - c.corr_seen)))


# --- Money: the only point that knows the source ------------------------------------------

func unit(world: GameWorld) -> float:
	return world.politics.fund_unit(world)


func balance(world: GameWorld) -> float:
	return world.politics.party_fund(world)


## Takes money from the source. False if there is no balance.
func take(world: GameWorld, amount: float) -> bool:
	var mine := world.politics.player_party(world)
	if mine.is_empty() or float(mine.get("funds", 0.0)) < amount:
		return false
	mine.funds = float(mine.funds) - amount
	world.politics.revision += 1
	return true


func give(world: GameWorld, amount: float) -> void:
	var mine := world.politics.player_party(world)
	if mine.is_empty():
		return
	mine["funds"] = float(mine.get("funds", 0.0)) + amount
	world.politics.revision += 1


# --- Institutions -------------------------------------------------------------------------

## From 0 to 1: how much the country manages to discover and punish. A sum of bets on what the game already has: democracy,
## constitutional review, free opposition and press, justice minister and bodies created by law.
func integrity(world: GameWorld, c: Country) -> float:
	var leg := world.legislation
	var i := 0.30 * clampf(c.dem / 10.0, 0.0, 1.0)
	i += 0.20 if leg.param("judicial_review", true) else 0.0
	i += 0.15 if leg.param("opposition_present", true) else 0.0
	i += 0.15 if _free_press(leg) else 0.0
	i += 0.12 * clampf(world.politics.minister_competence(world, "justice"), 0.0, 1.0)
	var organs := 0
	var watchdogs := 0
	for key: String in leg.standing.institutions:
		organs += 1
		for word: String in WATCHDOG_WORDS:
			if key.to_lower().contains(word):
				watchdogs += 1
				break
	i += 0.08 * clampf(organs / 3.0, 0.0, 1.0) + 0.10 * clampf(watchdogs, 0.0, 1.0)
	return clampf(i, 0.0, 1.0)


static func _free_press(leg: Legislation) -> bool:
	if leg.standing.rights.has("expressao"):
		return bool(leg.standing.rights.expressao.on)
	return "expressao" in leg.param("rights", [])


## Chance of any month bringing the scandal, with the current exposure.
func scandal_chance(world: GameWorld, c: Country) -> float:
	return clampf(heat * (SCANDAL_BASE + SCANDAL_SCALE * integrity(world, c)), 0.0, 0.6)


## How much the public and the press react: where the press is gagged, the scandal weighs less.
func bite(world: GameWorld, c: Country) -> float:
	return lerpf(0.35, 1.0, integrity(world, c))


# --- Actions --------------------------------------------------------------------------------

func can_act(world: GameWorld) -> bool:
	return world.player != null and world.governed() != null and not world.over


func wait_left(world: GameWorld, kind: String) -> int:
	return maxi(int(cooldowns.get(kind, 0)) - world.months_elapsed, 0)


func price(world: GameWorld, kind: String, norm := {}, party_id := -1) -> float:
	match kind:
		"bribe":
			if norm.is_empty() or party_id < 0:
				return 0.0
			var party: Dictionary = Politics._find(world.politics.data_of(world.player.iso), party_id)
			return 0.0 if party.is_empty() else world.legislation.deal_price(world, party, false) * BRIBE_FACTOR
		"hush": return unit(world) * HUSH_PRICE
		"favor": return unit(world) * FAVOR_PRICE
	return 0.0


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}


func _gate(world: GameWorld, kind: String) -> Dictionary:
	if not can_act(world):
		return _fail(tr("Só quem governa pode mexer em dinheiro público."))
	var left := wait_left(world, kind)
	if left > 0:
		return _fail(tr("Ainda é cedo para repetir isto: faltam %d meses.") % left)
	return {}


func _commit(world: GameWorld, kind: String) -> void:
	var def: Dictionary = ACTIONS[kind]
	var c := world.player
	c.corruption = clampf(c.corruption + float(def.corruption), 0.0, 1.0)
	heat = clampf(heat + float(def.heat), 0.0, 1.0)
	cooldowns[kind] = world.months_elapsed + int(def.cooldown)
	revision += 1


func _note(world: GameWorld, text: String) -> void:
	history.push_front({"month": world.months_elapsed, "text": text})
	if history.size() > 12:
		history.pop_back()


## Buys a caucus's vote on a norm that is still going to the floor. The player's own caucus does not need it.
func bribe_votes(world: GameWorld, norm: Dictionary, party_id: int, want_yes: bool) -> Dictionary:
	var blocked := _gate(world, "bribe")
	if not blocked.is_empty():
		return blocked
	var leg := world.legislation
	var data: Dictionary = world.politics.data_of(world.player.iso)
	var party: Dictionary = Politics._find(data, party_id)
	if party.is_empty() or party_id == int(data.player_party):
		return _fail(tr("Escolha outro partido."))
	if not leg.can_negotiate(norm):
		return _fail(tr("Não há mais votação a comprar nesta proposta."))
	var deals: Dictionary = norm.get_or_add("deals", {})
	if deals.has(str(party_id)):
		return _fail(tr("%s já tem acordo sobre esta proposta.") % party.short)
	var cost := price(world, "bribe", norm, party_id)
	if not take(world, cost):
		return _fail(tr("A compra custa %s, e o fundo tem %s.") % [UiKit.millions(cost), UiKit.millions(balance(world))])
	_commit(world, "bribe")
	if _rng.randf() < 0.1:
		# The party takes the money, does not deliver and also leaks the conversation.
		heat = clampf(heat + 0.25, 0.0, 1.0)
		_note(world, tr("%s embolsou o dinheiro e ameaça denunciar.") % party.short)
		return {"ok": true, "accepted": false, "msg": tr("%s embolsou %s e não se comprometeu. A conversa pode vazar.") % [party.short, UiKit.millions(cost)]}
	deals[str(party_id)] = want_yes
	leg.revision += 1
	_note(world, tr("Voto de %s comprado em %s.") % [party.short, leg.norm_label(norm)])
	return {"ok": true, "accepted": true, "msg": tr("%s vai votar %s. Pago por fora: %s.") % [party.short, tr("a favor") if want_yes else tr("contra"), UiKit.millions(cost)]}


func hush(world: GameWorld) -> Dictionary:
	var blocked := _gate(world, "hush")
	if not blocked.is_empty():
		return blocked
	if heat <= 0.0 and investigation <= 0 and case_load <= 0.0:
		return _fail(tr("Não há escândalo para abafar."))
	var cost := price(world, "hush")
	if not take(world, cost):
		return _fail(tr("Abafar custa %s, e o fundo tem %s.") % [UiKit.millions(cost), UiKit.millions(balance(world))])
	var c := world.player
	var chance := clampf(0.85 - 0.7 * integrity(world, c), 0.1, 0.9)
	_commit(world, "hush")
	if _rng.randf() < chance:
		heat *= 0.5
		case_load = maxf(case_load - 0.25, 0.0)
		_note(world, tr("Investigações esfriadas."))
		return {"ok": true, "accepted": true, "msg": tr("Matérias e inquéritos esfriaram. Custou %s.") % UiKit.millions(cost)}
	heat = clampf(heat + 0.2, 0.0, 1.0)
	c.corr_seen = clampf(c.corr_seen + 0.05, 0.0, 1.0)
	_note(world, tr("A tentativa de abafar veio à tona."))
	return {"ok": true, "accepted": false, "msg": tr("A tentativa de abafar vazou. Perdeu %s e ficou mais exposto.") % UiKit.millions(cost)}


func favor_allies(world: GameWorld) -> Dictionary:
	var blocked := _gate(world, "favor")
	if not blocked.is_empty():
		return blocked
	var cost := price(world, "favor")
	if not take(world, cost):
		return _fail(tr("Os contratos custam %s, e o fundo tem %s.") % [UiKit.millions(cost), UiKit.millions(balance(world))])
	_commit(world, "favor")
	kickbacks.append({"left": FAVOR_MONTHS, "amount": cost * FAVOR_RETURN / FAVOR_MONTHS})
	_note(world, tr("Contratos para aliados fechados."))
	return {"ok": true, "msg": tr("Contratos fechados. Devolvem %s ao fundo em %d meses.") % [UiKit.millions(cost * FAVOR_RETURN), FAVOR_MONTHS]}


func embezzle(world: GameWorld) -> Dictionary:
	var blocked := _gate(world, "embezzle")
	if not blocked.is_empty():
		return blocked
	var amount := unit(world) * EMBEZZLE_GAIN
	_commit(world, "embezzle")
	give(world, amount)
	# The money leaves the Treasury: the spending shows up in the accounts, without delivering anything.
	world.player.extra_spend_bucket += amount / 1000.0
	_note(world, tr("Verba pública desviada para o fundo do partido."))
	return {"ok": true, "msg": tr("%s saíram do Tesouro para o fundo do partido.") % UiKit.millions(amount)}


func skim(world: GameWorld) -> Dictionary:
	var blocked := _gate(world, "skim")
	if not blocked.is_empty():
		return blocked
	var amount := unit(world) * SKIM_GAIN
	_commit(world, "skim")
	stash += amount
	world.player.extra_spend_bucket += amount / 1000.0
	_note(world, tr("Dinheiro público foi para o seu bolso."))
	return {"ok": true, "msg": tr("%s foram para o seu patrimônio.") % UiKit.millions(amount)}


## Extension point for diplomacy: the price of buying a party's vote on a norm, in US$ millions.
func quote(world: GameWorld, norm: Dictionary, party_id: int) -> float:
	return price(world, "bribe", norm, party_id)


## Extension point for diplomacy: offers a counterpart to a party leader for the vote on a norm.
## `kind` is the type of counterpart; only "money" (the current source's money) exists for now. Returns
## {ok, accepted, msg}.
func offer(world: GameWorld, party_id: int, norm: Dictionary, want_yes: bool, kind := "money") -> Dictionary:
	if kind != "money":
		return _fail(tr("Esta contrapartida ainda não existe."))
	return bribe_votes(world, norm, party_id, want_yes)


## Points that the diverted wealth adds at the end of the career.
func score_bonus(world: GameWorld) -> float:
	return minf(stash / maxf(unit(world), 0.001) * SKIM_SCORE, SKIM_SCORE_CAP)


# --- Month ----------------------------------------------------------------------------------

func step_month(world: GameWorld) -> void:
	var c := world.player
	if c == null:
		return
	var i := integrity(world, c)
	var kept := []
	for k: Dictionary in kickbacks:
		give(world, float(k.amount))
		k.left = int(k.left) - 1
		if int(k.left) > 0:
			kept.append(k)
	kickbacks = kept
	# The real level slowly returns to the start; perception follows the real level.
	c.corruption += (c.corruption0 - c.corruption) * REVERT * (0.5 + i)
	c.corr_seen += (c.corruption - c.corr_seen) * SEEN_FOLLOW
	if investigation > 0:
		_step_investigation(world, c, i)
	else:
		case_load = maxf(case_load - CASE_DECAY, 0.0)
	heat *= 1.0 - HEAT_DECAY * (0.5 if investigation > 0 else 1.0)
	if heat < 0.005:
		heat = 0.0
	elif world.governed() != null and investigation <= 0 and _rng.randf() < scandal_chance(world, c):
		_scandal(world, c, i)
	revision += 1


func _scandal(world: GameWorld, c: Country, i: float) -> void:
	var sev := clampf(0.3 + 1.2 * heat + 0.3 * _rng.randf(), 0.2, 1.0)
	var b := bite(world, c)
	scandals += 1
	last_scandal = world.months_elapsed
	c.approval = clampf(c.approval - 0.06 * sev * b, 0.02, 0.95)
	c.stability = clampf(c.stability - 0.03 * sev * b, 0.02, 0.98)
	c.corr_seen = clampf(maxf(c.corr_seen, c.corruption) + 0.12 * sev, 0.0, 1.0)
	var mine := world.politics.player_party(world)
	if not mine.is_empty():
		mine.support = maxf(float(mine.support) * (1.0 - 0.08 * sev * b), 0.002)
		world.politics.revision += 1
	for o: Country in world.countries:
		if o != c and o.alive and o.dem >= 7.0:
			var rel := world.diplomacy.relation(c.idx, o.idx)
			world.diplomacy.set_relation(c.idx, o.idx, rel - 3.0 * sev * b)
			world.diplomacy.set_relation(o.idx, c.idx, world.diplomacy.relation(o.idx, c.idx) - 3.0 * sev * b)
	case_load += 0.25 * sev * (0.5 + i)
	investigation = INVESTIGATION_MONTHS
	heat *= 0.5
	_note(world, tr("Escândalo de corrupção."))
	world.emit_news(TranslationServer.translate("Escândalo de corrupção abala o governo de %s.") % c.name, "politica", c)
	var cost := unit(world) * HUSH_PRICE
	world.ask_player({
		"title": tr("Escândalo de corrupção"),
		"text": tr("A imprensa revela pagamentos suspeitos ligados ao seu governo. Há pedidos de investigação, e a oposição exige explicações."),
		"always": true,
		"options": [
			{"label": tr("Assumir e colaborar com a investigação"), "hint": tr("Aprovação cai mais agora; o processo perde força e a corrupção recua"), "fn": func():
				c.approval = clampf(c.approval - 0.02, 0.02, 0.95)
				case_load = maxf(case_load - 0.3, 0.0)
				c.corruption = maxf(c.corruption - 0.04, 0.0)
				heat = 0.0},
			{"label": tr("Abafar (%s do fundo)") % UiKit.millions(cost), "hint": tr("Pode esfriar tudo, ou piorar se vazar"), "fn": func():
				var r := hush(world)
				world.emit_news(r.msg, "politica", c)},
			{"label": tr("Negar tudo"), "hint": tr("Sem custo, mas o inquérito segue"), "fn": func(): pass},
		],
	})


func _step_investigation(world: GameWorld, c: Country, i: float) -> void:
	investigation -= 1
	var b := bite(world, c)
	c.approval = clampf(c.approval - 0.004 * b, 0.02, 0.95)
	case_load += 0.02 * i
	if investigation > 0:
		return
	var condemned := case_load >= CASE_LIMIT and i >= 0.35 and world.governed() != null
	if condemned:
		case_load = 0.0
		if c.dem >= Politics.FREE_PARLIAMENT_DEM:
			var next: Dictionary = world.politics.hand_over(c)
			world._finish("impeachment", tr("A investigação concluiu o esquema de corrupção. %s foi afastado, e %s assume o governo.") % [world.leader.get("name", tr("O governo")), next.get("name", tr("Outro partido"))])
		else:
			world._finish("golpe", tr("O escândalo de corrupção rachou o regime, e as elites retiraram o apoio. Você foi deposto."))
		return
	case_load *= 0.5
	c.approval = clampf(c.approval + 0.01, 0.02, 0.95)
	world.emit_news(TranslationServer.translate("A investigação sobre o governo de %s foi arquivada.") % c.name, "politica", c)


# --- Saving and loading --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"heat": heat, "case_load": case_load, "investigation": investigation, "stash": stash, "scandals": scandals,
		"last_scandal": last_scandal, "cooldowns": cooldowns, "kickbacks": kickbacks, "history": history,
		"rng_state": _rng.state, "rng_seed": _rng.seed,
	}


func from_dict(d: Dictionary) -> void:
	heat = float(d.get("heat", 0.0))
	case_load = float(d.get("case_load", 0.0))
	investigation = int(d.get("investigation", 0))
	stash = float(d.get("stash", 0.0))
	scandals = int(d.get("scandals", 0))
	last_scandal = int(d.get("last_scandal", -999))
	cooldowns = d.get("cooldowns", {})
	kickbacks = d.get("kickbacks", [])
	history = d.get("history", [])
	if d.has("rng_seed"):
		_rng.seed = int(d.rng_seed)
		_rng.state = int(d.rng_state)
