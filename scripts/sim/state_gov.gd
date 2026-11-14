class_name StateGov
extends RefCounted
## The government of a first-level subnational unit that the player runs. Its economy is derived from the
## country that holds the unit (the "union") in one direction only: nothing here ever writes into a Country,
## so the state's budget cannot count the same GDP, revenue or spending twice.

const MIN_ROOT_UNITS := 2
## Income of the unit holding the national capital, relative to the other units. The scenario has no income per unit.
const CAPITAL_INCOME := 1.3
const MAX_SPEND_SHARE := 0.2
const MAX_TAX_RATE := 0.15
const DEFAULT_TAX_RATE := 0.05
## Spending areas the state may fund, as share of the state GDP. Union-held areas stay at zero.
const FUNDS_COOLDOWN_MONTHS := 6
## A granted request adds this share of the annual transfer, fading by FUNDS_BONUS_DECAY each month.
const FUNDS_REQUEST_SHARE := 0.2
const FUNDS_BONUS_DECAY := 0.9
## Approval that decides an election: the executive keeps the post above it, and loses it below.
const ELECTION_BASELINE := 0.46
const ELECTION_NOISE := 0.03
const CAMPAIGN_BONUS := 0.03
const DEFAULT_SPEND := {"health": 0.015, "education": 0.015, "public_security": 0.01, "infrastructure": 0.005}

var unit_id := -1
var union_iso := ""
var party_id := -1
var approval := 0.5
var next_election := -1.0
var in_office := true
## The party that holds the executive: the player's while in office, a rival's in the opposition.
var incumbent_party := -1
## Gathered by campaigns in the opposition, spent at the next election.
var campaign_bonus := 0.0
var tax_rate := 0.0
var spend := {}
var debt := 0.0
var transfers_in := 0.0
var transfer_bonus := 0.0
var last_request_month := -1000

var _share := 0.0
var _share_revision := -1


## Starts governing a unit: {ok, msg, gov}.
static func create(world: GameWorld, id: int) -> Dictionary:
	var sub := world.subdivisions
	if not sub.units.has(id) or int(sub.units[id].parent) >= 0:
		return {"ok": false, "msg": TranslationServer.translate("Só unidades de primeiro nível podem ser governadas."), "gov": null}
	var owner: String = sub.units[id].owner
	if sub.roots_of(owner).size() < MIN_ROOT_UNITS:
		return {"ok": false, "msg": TranslationServer.translate("Este país tem uma só unidade de primeiro nível."), "gov": null}
	var gov := StateGov.new()
	gov.unit_id = id
	gov.union_iso = owner
	var iso := gov.union_iso
	gov.tax_rate = DEFAULT_TAX_RATE if Competences.decides(iso, "taxes") else 0.0
	for area: String in DEFAULT_SPEND:
		gov.spend[area] = float(DEFAULT_SPEND[area]) if Competences.decides(iso, area) else 0.0
	return {"ok": true, "msg": "", "gov": gov}


func union(world: GameWorld) -> Country:
	return world.resolve_owner(union_iso)


func unit(world: GameWorld) -> Dictionary:
	return world.subdivisions.units.get(unit_id, {})


## Share of the union's GDP produced here: population share weighted by income, normalized over the sibling units.
func gdp_share(world: GameWorld) -> float:
	var sub := world.subdivisions
	if _share_revision == sub.revision:
		return _share
	var owner: String = unit(world).get("owner", union_iso)
	var weights := {}
	var total := 0.0
	for id: int in sub.roots_of(owner):
		var w := sub.pop_share(id) * (CAPITAL_INCOME if sub.is_capital(id) else 1.0)
		weights[id] = w
		total += w
	_share = float(weights.get(unit_id, 0.0)) / maxf(total, 0.0001)
	_share_revision = sub.revision
	return _share


func gdp(world: GameWorld) -> float:
	return union(world).y_usd() * gdp_share(world)


## Population in millions.
func pop(world: GameWorld) -> float:
	return union(world).pop * world.subdivisions.pop_share(unit_id)


## Annual revenue: own taxes plus federal transfers.
func revenue(world: GameWorld) -> float:
	return tax_rate * gdp(world) + transfers_in


func spending(world: GameWorld) -> float:
	var total := 0.0
	for area: String in spend:
		total += float(spend[area])
	return total * gdp(world)


func set_spend(area: String, share: float) -> Dictionary:
	if not DEFAULT_SPEND.has(area):
		return {"ok": false, "msg": tr("Essa área não existe.")}
	if not Competences.decides(union_iso, area):
		return {"ok": false, "msg": tr("Esta área é decidida pela União.")}
	spend[area] = clampf(share, 0.0, MAX_SPEND_SHARE)
	return {"ok": true, "msg": ""}


func set_tax(rate: float) -> Dictionary:
	if not Competences.decides(union_iso, "taxes"):
		return {"ok": false, "msg": tr("Os tributos são decididos pela União.")}
	tax_rate = clampf(rate, 0.0, MAX_TAX_RATE)
	return {"ok": true, "msg": ""}


## How close the governor's party is to the one that runs the union, from 0 to 1.
func affinity(world: GameWorld) -> float:
	var mine := world.politics.party_of(union_iso, party_id)
	var ruling := world.politics.ruling_party(union_iso)
	if mine.is_empty() or ruling.is_empty():
		return 0.5
	return clampf(1.0 - Politics.distance(mine, ruling) / 2.0, 0.0, 1.0)


## What the union hands over this month, from the areas it keeps and the governor's standing with it.
func monthly_transfer(world: GameWorld) -> float:
	var u := union(world)
	var weight := 1.0 - Competences.state_weight(union_iso)
	return u.revenue * world.subdivisions.pop_share(unit_id) * weight * (0.6 + 0.8 * affinity(world)) / 12.0


func request_wait(world: GameWorld) -> int:
	return maxi(last_request_month + FUNDS_COOLDOWN_MONTHS - world.months_elapsed, 0)


## Asks the union for extra money: {ok, msg, amount}.
func request_funds(world: GameWorld) -> Dictionary:
	var wait := request_wait(world)
	if wait > 0:
		return {"ok": false, "msg": TranslationServer.translate("O governo federal só recebe outro pedido em %d mês(es).") % wait, "amount": 0.0}
	last_request_month = world.months_elapsed
	var chance := clampf(0.2 + 0.5 * affinity(world) + 0.3 * (approval - 0.5), 0.05, 0.9)
	if world.rng.randf() >= chance:
		return {"ok": false, "msg": TranslationServer.translate("O governo federal recusou o pedido."), "amount": 0.0}
	var amount := monthly_transfer(world) * 12.0 * FUNDS_REQUEST_SHARE
	transfer_bonus += amount
	transfers_in = monthly_transfer(world) * 12.0 + transfer_bonus
	return {"ok": true, "msg": TranslationServer.translate("O governo federal liberou verba extra."), "amount": amount}


## The strongest party of the union other than the player's: the one that takes the post when the player loses it.
func rival_party(world: GameWorld) -> int:
	var best := -1
	var best_support := -1.0
	for p: Dictionary in world.politics.data_of(union_iso).parties:
		if int(p.id) != party_id and float(p.support) > best_support:
			best = int(p.id)
			best_support = float(p.support)
	return best


## The vote for the head of the unit: {won, winner_party, vetoed}. In office the player needs approval above the
## baseline (and the national party's blessing); in the opposition, the incumbent's approval has to fall below it.
func hold_election(world: GameWorld) -> Dictionary:
	var vetoed := in_office and world.politics.national_veto(world)
	var score := approval + world.rng.randfn(0.0, ELECTION_NOISE)
	var won := score >= ELECTION_BASELINE and not vetoed if in_office else score - campaign_bonus < ELECTION_BASELINE
	campaign_bonus = 0.0
	return {"won": won, "winner_party": party_id if won else rival_party(world), "vetoed": vetoed}


func _reset_approval(world: GameWorld) -> void:
	approval = clampf(0.55 + world.rng.randf_range(-0.05, 0.08), 0.3, 0.75)


## The player loses the post and keeps leading the party's directory in the unit.
func enter_unit_opposition(world: GameWorld, why: String) -> void:
	in_office = false
	incumbent_party = rival_party(world)
	_reset_approval(world)
	world.emit_news(TranslationServer.translate("%s deixa o governo de %s.") % [world.leader.get("name", TranslationServer.translate("O líder")), unit(world).get("name", "?")], "politica", union(world))
	world.ask_player({
		"title": TranslationServer.translate("Derrotado nas urnas"), "text": why, "always": true,
		"options": [{"label": TranslationServer.translate("Liderar o diretório"), "hint": TranslationServer.translate("Critique o governo, faça campanha e dispute a próxima eleição"), "fn": func(): pass}],
	})


func take_office(world: GameWorld) -> void:
	in_office = true
	incumbent_party = party_id
	_reset_approval(world)
	world.emit_news(TranslationServer.translate("%s volta ao governo de %s.") % [world.leader.get("name", TranslationServer.translate("O líder")), unit(world).get("name", "?")], "politica", union(world))
	world.ask_player({
		"title": TranslationServer.translate("De volta ao poder!"), "text": TranslationServer.translate("Seu partido venceu a eleição da unidade."), "always": true,
		"options": [{"label": TranslationServer.translate("Assumir o governo"), "hint": TranslationServer.translate("Revise o orçamento"), "fn": func(): pass}],
	})


## A month of the state's accounts. Reads the union, writes only the state.
func step_month(world: GameWorld) -> void:
	transfer_bonus *= FUNDS_BONUS_DECAY
	# Transfers are not taken from the union's accounts in v1: the state only receives them.
	transfers_in = monthly_transfer(world) * 12.0 + transfer_bonus
	debt = maxf(debt + (spending(world) - revenue(world)) / 12.0, 0.0)


func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id, "union_iso": union_iso, "party_id": party_id, "approval": approval, "next_election": next_election,
		"in_office": in_office, "incumbent_party": incumbent_party, "campaign_bonus": campaign_bonus, "tax_rate": tax_rate, "spend": spend, "debt": debt, "transfers_in": transfers_in,
		"transfer_bonus": transfer_bonus, "last_request_month": last_request_month,
	}


static func from_dict(d: Dictionary) -> StateGov:
	var gov := StateGov.new()
	gov.unit_id = int(d.unit_id)
	gov.union_iso = String(d.union_iso)
	gov.party_id = int(d.party_id)
	for key: String in ["approval", "next_election", "tax_rate", "debt", "transfers_in", "transfer_bonus"]:
		gov.set(key, float(d.get(key, 0.0)))
	gov.in_office = bool(d.get("in_office", true))
	gov.incumbent_party = int(d.get("incumbent_party", gov.party_id))
	gov.campaign_bonus = float(d.get("campaign_bonus", 0.0))
	gov.spend = d.get("spend", {}).duplicate()
	gov.last_request_month = int(d.get("last_request_month", -1000))
	return gov
