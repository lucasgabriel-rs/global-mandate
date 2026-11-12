class_name GameWorld
extends RefCounted
## Global state and simulation clock. One game day is the unit of time;
## each country runs its monthly macro step on a different day, which spreads the CPU
## cost and keeps the numbers always moving.

signal news_posted(text: String, kind: String, country: Country)
signal prompt_requested(prompt: Dictionary)
signal game_ended(result: Dictionary)
signal month_passed
signal player_changed
signal demarcation_requested(session: Dictionary)
## A leader reached out to the player, and the player agreed to talk.
signal talk_requested(target: Country)

const START_YEAR := 2025
const MAX_BORDER_PROPOSALS := 3
## Leaders do not approach the player in the first months, nor more than once in this interval.
const TALK_FIRST_MONTH := 6
const TALK_COOLDOWN_MONTHS := 4
# i18n-begin
const MONTHS := ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]
# i18n-end
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const DIFFICULTY := {
	"facil": {"fund": 1.4, "approval": 0.04},
	"normal": {"fund": 1.0, "approval": 0.0},
	"dificil": {"fund": 0.7, "approval": -0.04},
}

var rng := RandomNumberGenerator.new()
var countries: Array = []
var by_iso := {}
var usa: Country
var player: Country
## false when the player lost the election: the country stays with the AI, and the player leads the opposition.
var in_office := true
## Last month in which each foreign leader received the player: {iso: month}.
var talks := {}
var chats := {}           # contact -> messages (ChatLog)
var talk_turns := {}      # iso -> lines still left in the current conversation
var offers := {}          # iso -> open proposal the leader brought (Proposals)
var markets := Markets.new()
var diplomacy := Diplomacy.new()
var subdivisions := Subdivisions.new()
var territories := Territories.new()
var politics := Politics.new()
var legislation := Legislation.new()
var treaties := Treaties.new()
var infra := Infrastructure.new()
var corporate := Corporate.new()
var corruption := Corruption.new()
var next_talk_month := TALK_FIRST_MONTH
var campaign_noticed := false
var leader := {}
var start_year := START_YEAR

var day_index := 0
var year := START_YEAR
var month := 0
var day := 1
var next_ai := PackedFloat64Array()

var global_risk := 0.2
var global_tension := 0.3
var ecb_rate := 0.03
var eur_rate := 1.0
var _world_gdp := 110000.0
## While the simulation runs on another thread, no interface: signals stay queued until it ends.
var defer_events := false
## True while another thread uses this world: the interface cannot read or change anything in it.
var busy := false
var _events: Array = []
## Day of the last foreign action, by action and country: each has a minimum interval.
var action_used := {}
var difficulty := "normal"
var mandates := 0
var refresh_map := false
var over := false
var months_elapsed := 0
var peak_rank := 999
var nuke_used := false
var global_hist := {}


func setup(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	# Builds the block catalog and the legal codes here, before the simulation gets a thread.
	LawCatalog.categories()
	var map_info := GameData.map_info()
	var rows := GameData.load_countries()
	for row: Dictionary in rows:
		var c := Country.new()
		c.idx = countries.size()
		c.iso = row.iso
		c.name = TranslationServer.translate(row.name)
		c.region = row.region
		c.blocs = row.blocs
		var info: Dictionary = map_info.get(c.iso, {})
		c.center = info.get("center", Vector2.ZERO)
		c.area = info.get("area", 10.0)
		countries.append(c)
		by_iso[c.iso] = c
		Economy.init_country(c, row, self)
	usa = by_iso["USA"]
	_world_gdp = _sum_gdp()
	markets.setup(self)
	for c: Country in countries:
		Economy.finish_init(c, self)
		Sectors.init_country(c, self)
		c.push_hist("y", c.y)
		Economy.record_start(c)
	# The initial migration comes from the birth rate: the data's growth already includes immigrants.
	Demography.init_world(self)
	# Charts already have the starting point on the first day.
	for i in 5:
		markets.push_hist(i)
	diplomacy.setup(self)
	diplomacy.refresh_sanction_cache(self)
	subdivisions.load_base(GameData.load_admin1())
	politics.setup(self)
	treaties.setup(self)
	infra.setup(self)
	corporate.setup(self)
	corruption.setup(self)
	next_ai.resize(countries.size())
	for i in countries.size():
		next_ai[i] = fmod(i * 11.1, 30.4)
	# Starting dynamics: a few months of warm-up with nobody watching.
	_update_global()


func _sum_gdp() -> float:
	var t := 0.0
	for c: Country in countries:
		if c.alive:
			t += c.y_usd()
	return t


func world_gdp() -> float:
	return _world_gdp


## Country that currently controls the territory of iso, following annexations.
func resolve_owner(iso: String) -> Country:
	var c: Country = by_iso.get(iso)
	while c and not c.alive and c.annexed_by >= 0:
		c = countries[c.annexed_by]
	return c


func owned_isos(c: Country) -> Array:
	var out := []
	for o: Country in countries:
		if resolve_owner(o.iso) == c:
			out.append(o.iso)
	return out


func owns_unit(c: Country, id: int) -> bool:
	return subdivisions.units.has(id) and resolve_owner(subdivisions.units[id].owner) == c


func year_float() -> float:
	return start_year + day_index / 365.0


func global_price_index() -> float:
	return usa.p


func date_string() -> String:
	return "%02d %s %d" % [day, tr(MONTHS[month]), year]


func set_player(c: Country, diff: String) -> void:
	player = c
	difficulty = diff
	c.approval = clampf(c.approval + float(DIFFICULTY[diff].approval) + 0.05, 0.2, 0.85)
	if c.dem >= 4.0:
		c.next_election = year_float() + 3.9 + 0.0
	# Every ruler belongs to a party: with no choice, the one already governing.
	if int(politics.data_of(c.iso).player_party) < 0:
		politics.join_party(self, int(politics.data_of(c.iso).ruling), true)
	politics.auto_cabinet(self)
	politics.init_funds(self)
	legislation.setup(self)
	if c.dem >= 4.0:
		c.next_election = year_float() + legislation.mandate_years() - 0.1
	_send(player_changed)


func tick_day() -> void:
	if over:
		return
	day_index += 1
	day += 1
	if day > MONTH_DAYS[month]:
		day = 1
		month += 1
		if month >= 12:
			month = 0
			year += 1
		_economy_month()
		_on_month()
	diplomacy.step_wars(self)
	legislation.step_day(self)
	for i in countries.size():
		if day_index >= next_ai[i]:
			next_ai[i] += 30.4167
			if countries[i] == player and in_office:
				_player_upkeep(countries[i])
			else:
				NationAI.step_month(countries[i], self)


## The month's economic calculation, on day 1, for all countries at the same time: global risk, each
## country's economy and commodity prices. AI decisions remain spread through the month.
func _economy_month() -> void:
	# Same dynamics as the daily version (0.4% a day return to 0.2 and noise of 0.004), summed over the month.
	global_risk += (0.2 - global_risk) * 0.115 + rng.randfn(0.0, 0.021)
	global_risk = clampf(global_risk, 0.05, 1.0)
	# Countries close the month with the prices in force; the market reacts afterwards and applies to the next month.
	for c: Country in countries:
		Economy.step_month(c, self)
	# Migration after births and deaths: all countries have already closed the month.
	Demography.step_world(self)
	markets.step_month(self, rng)


func _player_upkeep(c: Country) -> void:
	# Same military stock calculation as the AI, but with no automatic decisions.
	var ppp := clampf(pow(60000.0 / maxf(c.gdp_pc(), 500.0), 0.35), 1.0, 3.0)
	c.mil_stock += (c.sp_defense * c.y_usd() * ppp * 0.35 - 0.06 * c.mil_stock) / 12.0
	c.troops += (c.troops0 * (1.0 + c.mobilization) - c.troops) * 0.03
	if not diplomacy.in_war(c.idx):
		c.war_exhaustion = maxf(c.war_exhaustion - 0.012, 0.0)


## Who governs the player's country: the player, or nobody that depends on human decisions.
func governed() -> Country:
	return player if in_office else null


func _on_month() -> void:
	months_elapsed += 1
	_update_global()
	WorldEvents.step_month(self)
	politics.step_month(self)
	politics.step_world_parliaments(self)
	People.step_month(self)
	treaties.step_month(self)
	legislation.step_month(self)
	infra.step_month(self)
	corporate.step_month(self)
	corruption.step_month(self)
	for i in 5:
		markets.push_hist(i)
	if month == 0:
		diplomacy._compute_shares(self)
	if player and not in_office:
		if not player.alive:
			_finish("golpe", tr("%s deixou de existir, e sua carreira política acabou junto com o país.") % player.name)
	_send(month_passed)


func _update_global() -> void:
	_world_gdp = _sum_gdp()
	# European Central Bank: Taylor rule on the euro area aggregate.
	var w := 0.0
	var pi_val := 0.0
	var gap_val := 0.0
	var pe := 0.0
	var ln_p := 0.0
	for c: Country in countries:
		if c.alive and c.peg == 2:
			var g := c.y_usd()
			w += g
			pi_val += c.pi_yoy * g
			gap_val += c.gap * g
			pe += c.pi_e * g
			ln_p += log(c.p) * g
	if w > 0.0:
		pi_val /= w
		gap_val /= w
		pe /= w
		ln_p /= w
		var target := clampf(0.012 + pe + 0.6 * (pi_val - 0.02) + 0.5 * gap_val, 0.0, 0.25)
		ecb_rate += (target - ecb_rate) * 0.14
		var rd := (ecb_rate - pe - 0.012) - (usa.rate - usa.pi_e - usa.r_n)
		var le_target := ln_p - log(usa.p) - 1.1 * clampf(rd, -0.1, 0.1)
		eur_rate = exp(log(eur_rate) + (le_target - log(eur_rate)) * 0.08 + rng.randfn(0.0, 0.006))
	diplomacy.refresh_sanction_cache(self)
	# Global tension: wars (weighted by size), sanctions and nuclear powers involved.
	var t := 0.15
	for war: Dictionary in diplomacy.wars:
		var a: Country = countries[war.main_a]
		var d: Country = countries[war.main_d]
		var s := sqrt((a.y_usd() + d.y_usd()) / _world_gdp)
		t += 0.05 + 0.35 * s
		if a.nukes > 0 or d.nukes > 0:
			t += 0.06
		if a.nukes > 200 and d.nukes > 0:
			t += 0.25
		for i: int in war.a + war.d:
			if countries[i].nukes > 200 and i != war.main_a and i != war.main_d:
				t += 0.15
	global_tension += (clampf(t + 0.25 * (global_risk - 0.2), 0.05, 1.0) - global_tension) * 0.2
	for c: Country in countries:
		if c.alive:
			c.influence = influence_of(c)
	var keys := {"tension": global_tension, "risk": global_risk, "world_gdp": _world_gdp}
	for k: String in keys:
		var a: PackedFloat32Array = global_hist.get(k, PackedFloat32Array())
		a.append(keys[k])
		if a.size() > 480:
			a = a.slice(a.size() - 480)
		global_hist[k] = a


func influence_of(c: Country) -> float:
	var allies := 0.0
	for o: Country in countries:
		if o != c and o.alive and diplomacy.allied(c.idx, o.idx):
			allies += o.y_usd()
	var mil := c.military_power() / maxf(usa.military_power(), 0.01)
	var v := 55.0 * pow(c.y_usd() / _world_gdp, 0.55)
	v += 18.0 * clampf(pow(mil, 0.6), 0.0, 1.5)
	# Allies count more for whoever has weight of their own within the alliance.
	v += 10.0 * pow(allies / _world_gdp, 0.6) * sqrt(clampf(c.y_usd() / _world_gdp * 20.0, 0.0, 1.0))
	v += 5.0 * c.stability
	if c.nukes > 0:
		v += 3.0
	return v


func rank_of(c: Country, key: Callable) -> int:
	var v: float = key.call(c)
	var r := 1
	for o: Country in countries:
		if o != c and o.alive and float(key.call(o)) > v:
			r += 1
	return r


## Country names in the current language. Called on opening and when switching language, on the main thread.
func localize_country_names() -> void:
	for c: Country in countries:
		c.name = TranslationServer.translate(GameData.country_name_pt(c.iso))


func emit_news(text: String, kind: String, country: Country) -> void:
	_send(news_posted, [_decimal_comma(text), kind, country])


## Numbers in the texts follow the pt-BR format (1,5 and not 1.5), except in English.
static var _decimal_re: RegEx


func _send(event: Signal, args := []) -> void:
	if defer_events:
		_events.append([event, args])
	else:
		event.emit.callv(args)


## Delivers on the main thread what happened during the background simulation.
func flush_events() -> void:
	var pending := _events
	_events = []
	for item: Array in pending:
		(item[0] as Signal).emit.callv(item[1])


## Is something in the queue demanding the player? Then a multi-day advance must stop here.
func has_urgent_event() -> bool:
	for item: Array in _events:
		if item[0] != news_posted and item[0] != month_passed:
			return true
	return false


func _decimal_comma(text: String) -> String:
	# In English, the decimal point stays.
	if Lang.english_numbers:
		return text
	if _decimal_re == null:
		_decimal_re = RegEx.create_from_string("(\\d)\\.(\\d)")
	return _decimal_re.sub(text, "$1,$2", true)


func ask_player(prompt: Dictionary) -> void:
	# In opposition, only the windows about the player themselves arrive: government decisions stay with the AI.
	if player and not over and (in_office or prompt.get("always", false)):
		prompt["text"] = _decimal_comma(prompt.get("text", ""))
		for opt: Dictionary in prompt.options:
			opt["hint"] = _decimal_comma(opt.get("hint", ""))
		_send(prompt_requested, [prompt])


# --- Player politics ---------------------------------------------------

func check_player_politics(c: Country) -> void:
	if c != player or over:
		return
	var yf := year_float()
	if c.dem >= 4.0 and yf >= c.next_election - 0.25 and yf < c.next_election and not campaign_noticed:
		campaign_noticed = true
		emit_news(tr("Começa a campanha eleitoral em %s. Faltam cerca de três meses para a votação.") % c.name, "politica", c)
	if not in_office:
		if c.dem >= 4.0 and yf >= c.next_election:
			_opposition_election(c)
		return
	if c.dem >= 4.0 and yf >= c.next_election:
		_player_election(c)
	elif c.dem >= 4.0 and c.approval < 0.2 and politics.government_share(c.iso) < 1.0 / 3.0 and rng.randf() < 0.04:
		var next_party: Dictionary = politics.hand_over(c)
		_finish("impeachment", tr("Sem apoio no parlamento e com a aprovação em %d%%, %s sofreu impeachment. %s assume o governo.") % [int(c.approval * 100.0), leader.get("name", tr("o governo")), next_party.get("name", tr("Outro partido"))])
	elif c.dem < 4.0:
		if c.stability < 0.1 and rng.randf() < 0.08:
			_finish("golpe", tr("Generais e a elite política perderam a paciência. Um golpe encerrou seu governo."))
		elif c.approval < 0.1 and c.unrest > 0.3 and rng.randf() < 0.05:
			_finish("golpe", tr("Multidões tomaram o palácio, e os militares não defenderam o regime. Você foi deposto."))


func _player_election(c: Country) -> void:
	campaign_noticed = false
	legislation.fire(self, "ev_election")
	c.next_election = year_float() + legislation.mandate_years()
	var result := politics.player_election(self)
	if result.won:
		mandates += 1
		c.approval = clampf(c.approval + 0.04, 0.0, 0.95)
		ask_player({
			"title": tr("Reeleito!"),
			"text": tr("Seu partido fez %.1f%% dos votos e %d de %d assentos. Você conquista seu %dº mandato consecutivo em %s.") % [float(result.vote) * 100.0, int(result.seats), int(result.total), mandates + 1, c.name],
			"options": [{"label": tr("Seguir governando"), "hint": "", "fn": func(): pass}],
		})
	else:
		enter_opposition(tr("%s venceu a eleição com %d de %d assentos. Sua aprovação de %d%% não bastou. Você passa a liderar a oposição até a próxima eleição.") % [result.winner.name, int(result.winner.seats), int(result.total), int(c.approval * 100.0)], tr("Derrotado nas urnas"))


## Starts the match out of government: whoever already governs stays, and the player runs in the next election.
## Closed regimes have no election, so there is no playable opposition in them.
func start_in_opposition() -> Dictionary:
	if player == null or player.dem < 4.0:
		return {"ok": false, "msg": tr("Este regime não tem eleições: não há como disputar o poder pela oposição.")}
	in_office = false
	player.rate_manual = false
	politics.clear_cabinet(player.iso)
	legislation.drop_government_bills(self)
	return {"ok": true, "msg": ""}


## The player stays in the game, at the head of their party: the AI governs until the next election.
func enter_opposition(text: String, title: String) -> void:
	in_office = false
	player.rate_manual = false
	# Whoever takes over starts with their own popularity, not that of the government that fell.
	player.approval = clampf(0.55 + rng.randf_range(-0.05, 0.08), 0.3, 0.75)
	# Whoever takes over starts with their own popularity, not that of the government that fell.
	player.approval = clampf(0.55 + rng.randf_range(-0.05, 0.08), 0.3, 0.75)
	politics.clear_cabinet(player.iso)
	legislation.drop_government_bills(self)
	emit_news(tr("%s deixa o governo de %s.") % [leader.get("name", tr("O líder")), player.name], "politica", player)
	ask_player({
		"title": title, "text": text, "always": true,
		"options": [{"label": tr("Liderar a oposição"), "hint": tr("Critique o governo, faça campanha e dispute a próxima eleição"), "fn": func(): pass}],
	})


func _opposition_election(c: Country) -> void:
	campaign_noticed = false
	legislation.fire(self, "ev_election")
	c.next_election = year_float() + legislation.mandate_years()
	var result := politics.opposition_election(self)
	if result.won:
		in_office = true
		mandates += 1
		c.approval = clampf(0.55 + rng.randf_range(-0.03, 0.05), 0.3, 0.8)
		politics.auto_cabinet(self)
		diplomacy.on_government_change(c, self)
		emit_news(tr("%s vence a eleição em %s e volta ao poder.") % [leader.get("name", tr("O líder")), c.name], "politica", c)
		ask_player({
			"title": tr("De volta ao poder!"), "text": tr("Seu partido fez %.1f%% dos votos e %d de %d assentos. O governo é seu novamente.") % [float(result.vote) * 100.0, int(result.seats), int(result.total)],
			"always": true, "options": [{"label": tr("Assumir o governo"), "hint": tr("Revise o orçamento e escolha os ministros"), "fn": func(): pass}],
		})
	else:
		ask_player({
			"title": tr("Oposição mais quatro anos"), "text": tr("%s venceu com %d de %d assentos. Seu partido fez %.1f%% dos votos e ficou com %d.") % [result.winner.name, int(result.winner.seats), int(result.total), float(result.vote) * 100.0, int(result.seats)],
			"always": true, "options": [{"label": tr("Seguir na oposição"), "hint": "", "fn": func(): pass}],
		})


## Resigning is an exit like the others: the next party takes over.
func resign() -> void:
	if not in_office or over:
		return
	var next_party: Dictionary = politics.hand_over(player) if player.dem >= Politics.FREE_PARLIAMENT_DEM else {}
	_finish("renuncia", tr("%s renunciou ao cargo.%s") % [leader.get("name", tr("O líder")), tr(" %s assume o governo.") % next_party.name if not next_party.is_empty() else ""])


## After the end of the career, the player takes over another person in the same country. If the country ended, goes to whoever took it.
## In a democracy, they start in opposition; in a closed regime, it is whoever succeeds to power.
func assume_new_character(character: Dictionary) -> void:
	over = false
	if not player.alive:
		var heir: Country = countries[player.annexed_by] if player.annexed_by >= 0 else usa
		player = heir
		legislation = Legislation.new()
		legislation.setup(self)
		politics.init_funds(self)
	var c := player
	var data: Dictionary = politics.data_of(c.iso)
	for party: Dictionary in data.parties:
		for m: Dictionary in party.members.duplicate():
			if m.get("player", false):
				party.members.erase(m)
				if party.members.is_empty():
					politics.add_new_members(data, party, 3, year)
				Politics.refresh_compass(party)
	leader = character
	mandates = 0
	data.erase("last_switch")
	var closed := c.dem < Politics.FREE_PARLIAMENT_DEM
	in_office = closed
	if closed:
		politics.join_party(self, int(data.ruling), true)
		politics.auto_cabinet(self)
	else:
		politics.clear_cabinet(c.iso)
		var pick: Dictionary = {}
		for party: Dictionary in data.parties:
			if party.id != int(data.ruling) and (pick.is_empty() or int(party.seats) > int(pick.seats)):
				pick = party
		politics.join_party(self, int(pick.get("id", data.ruling)), true)
	if c.next_election <= year_float():
		c.next_election = year_float() + legislation.mandate_years()
	emit_news(tr("%s entra na política de %s.") % [leader.get("name", tr("Um novo nome")), c.name], "politica", c)


## A leader wants to talk to the player. The player decides whether to answer.
func request_talk(c: Country) -> void:
	if months_elapsed < next_talk_month or not in_office or player == null:
		return
	next_talk_month = months_elapsed + TALK_COOLDOWN_MONTHS
	var theirs: Dictionary = politics.leader_of(c.iso)
	var rel: float = diplomacy.relation(player.idx, c.idx)
	var offer := Proposals.make(self, c)
	offers[c.iso] = offer
	var subject := tr("aproximar os dois países")
	match String(offer.kind):
		"peace":
			subject = tr("discutir a guerra")
		"threat":
			subject = tr("cobrar explicações sobre o seu governo")
		"treaty":
			subject = tr("propor um novo acordo")
		"request":
			subject = tr("pedir a sua ajuda")
		"offer":
			subject = tr("fazer uma oferta")
	var pl := player
	ask_player({
		"title": tr("%s quer falar com você") % theirs.get("name", tr("Um líder")),
		"text": tr("O líder de %s (%s) pede uma conversa para %s.") % [c.name, Dialogue.temper(theirs), subject],
		"options": [
			{"label": tr("Atender"), "hint": tr("Abre a conversa agora."), "fn": func(): _send(talk_requested, [c])},
			{"label": tr("Não atender"), "hint": tr("Relação -3."), "fn": func():
				offers.erase(c.iso)
				diplomacy.add_relation(pl.idx, c.idx, -3.0)},
		],
	})


func _finish(reason: String, text: String) -> void:
	if over:
		return
	over = true
	var score := _final_score()
	_send(game_ended, [{"reason": reason, "text": _decimal_comma(text), "score": score, "years": year_float() - start_year, "mandates": mandates}])


func _final_score() -> int:
	if player == null:
		return 0
	var pc_growth := (player.y / maxf(player.pop, 0.001)) / maxf(player.pc0, 0.0001)
	var s := 100.0 * (pc_growth - 1.0) + 8.0 * influence_of(player) + 60.0 * mandates + 3.0 * (year_float() - start_year)
	s += 80.0 * player.stability
	s += corruption.score_bonus(self)
	return int(maxf(s, 0.0))


# --- Interactions with the player -----------------------------------------------

func offer_imf(c: Country) -> void:
	if c.imf_program > 0.0:
		return
	c.imf_program = 12.0
	ask_player({
		"title": tr("Colapso do financiamento"),
		"text": tr("Os credores não rolam mais a dívida de %s. O juro chegou a %.1f%% e as reservas estão em US$ %.1f bi.") % [c.name, c.yield_gov * 100.0, c.reserves],
		"options": [
			{"label": tr("Aceitar pacote do FMI"), "hint": tr("US$ %.0f bi, com corte de gastos e aumento de impostos") % (c.y_usd() * 0.08), "fn": func():
				Economy.apply_imf(c, self)},
			{"label": tr("Declarar moratória"), "hint": tr("Corta 45% da dívida; 3 anos sem mercado, recessão severa"), "fn": func():
				c.imf_program = 0.0
				Economy.apply_default(c, self)},
		],
	})


func offer_fta(c: Country) -> void:
	var pl := player
	ask_player({
		"title": tr("Proposta comercial de %s") % c.name,
		"text": tr("O governo de %s propõe um acordo de livre comércio. Hoje ele responde por %.1f%% das suas exportações.") % [c.name, diplomacy.shares[pl.idx * diplomacy.n + c.idx] * 100.0],
		"options": [
			{"label": tr("Assinar"), "hint": tr("Vale depois de ratificado pelos dois parlamentos"), "fn": func():
				treaties.sign_with_player(self, c, "fta")},
			{"label": tr("Recusar"), "hint": tr("Relação -5"), "fn": func():
				diplomacy.add_relation(pl.idx, c.idx, -5.0)},
		],
	})


func offer_alliance(c: Country) -> void:
	var pl := player
	ask_player({
		"title": tr("Pacto de defesa"),
		"text": tr("%s propõe um pacto de defesa mútua. Se um dos dois for atacado, o outro entra na guerra.") % c.name,
		"options": [
			{"label": tr("Assinar"), "hint": tr("Vale depois de ratificado. Proteção mútua; arrisca arrastar você para guerras alheias"), "fn": func():
				treaties.sign_with_player(self, c, "defense")},
			{"label": tr("Recusar educadamente"), "hint": tr("Relação -3"), "fn": func():
				diplomacy.add_relation(pl.idx, c.idx, -3.0)},
		],
	})


func receive_threat(c: Country) -> void:
	var pl := player
	ask_player({
		"title": tr("Ultimato de %s") % c.name,
		"text": tr("%s concentra forças e exige que você reduza a presença militar e retire apoio aos rivais dele.") % c.name,
		"options": [
			{"label": tr("Ceder para ganhar tempo"), "hint": tr("Relação +15; aprovação -6 pontos"), "fn": func():
				diplomacy.add_relation(pl.idx, c.idx, 15.0)
				pl.approval = maxf(pl.approval - 0.06, 0.02)},
			{"label": tr("Rejeitar publicamente"), "hint": tr("Aprovação +3 pontos; relação -12 e tensão maior"), "fn": func():
				diplomacy.add_relation(pl.idx, c.idx, -12.0)
				pl.approval = minf(pl.approval + 0.03, 0.95)
				global_risk = clampf(global_risk + 0.04, 0.0, 1.0)},
		],
	})


func war_declared(w: Dictionary, att: Country, def: Country) -> void:
	if player == null:
		return
	if def == player:
		ask_player({
			"title": tr("Fomos invadidos!"),
			"text": tr("Tropas de %s cruzaram a fronteira. A guerra começou e a economia sente o choque.") % att.name,
			"options": [{"label": tr("Mobilizar o país"), "hint": tr("Mobilização a 60%"), "fn": func():
				player.mobilization = maxf(player.mobilization, 0.6)}],
		})


func ally_attacked(w: Dictionary, ally: Country, enemy: Country) -> void:
	var pl := player
	ask_player({
		"title": tr("Aliado sob ataque"),
		"text": tr("%s invocou o pacto de defesa: %s atacou. Se honrar o tratado, seu país entra em guerra.") % [ally.name, enemy.name],
		"options": [
			{"label": tr("Honrar o pacto e entrar na guerra"), "hint": tr("Mobilização 25%; alta de gastos"), "fn": func():
				if diplomacy.wars.has(w):
					diplomacy.join_war(pl, w, true, self)},
			{"label": tr("Quebrar o pacto"), "hint": tr("Pacto cancelado; relações com aliados despencam"), "fn": func():
				diplomacy.break_alliance(pl, ally, self)
				for c: Country in countries:
					if c.alive and c != pl and diplomacy.allied(c.idx, pl.idx):
						diplomacy.add_relation(c.idx, pl.idx, -15.0)},
		],
	})


## Losing the war topples the government, but does not end the career: in a democracy, the player goes to opposition.
## With no elections to contest, the regime falls and the leader is deposed.
func player_lost_war(enemy: Country) -> void:
	if not player.alive or player.dem < Politics.FREE_PARLIAMENT_DEM:
		_finish("golpe", tr("As tropas de %s tomaram a capital, e o regime caiu com a rendição.") % enemy.name)
		return
	var next_party: Dictionary = politics.hand_over(player)
	enter_opposition(tr("As tropas de %s tomaram a capital, e seu governo assinou a rendição. %s assume, e você passa a liderar a oposição.") % [enemy.name, next_party.get("name", tr("Outro partido"))], tr("Rendição"))


func player_won_war(w: Dictionary, def: Country) -> void:
	var pl := player
	var d := diplomacy
	# Avoids re-entering until the decision: freezes the front below capitulation.
	w.front = 96.0
	ask_player({
		"title": tr("%s capitulou") % def.name,
		"text": tr("As forças de %s se renderam. Qual será o futuro do país?") % def.name,
		"options": [
			{"label": tr("Anexar"), "hint": tr("Ganha população e recursos; reputação global despenca"), "fn": func():
				d.annex(pl, def, self)
				d.end_war_by_player(w, pl, def, self, 0.0, tr("%s anexa %s depois de vencer a guerra.") % [pl.name, def.name])},
			{"label": tr("Instalar governo aliado"), "hint": tr("Vira Estado-cliente e aliado militar"), "fn": func():
				d.make_client(pl, def, self)
				d.end_war_by_player(w, pl, def, self, 0.0, tr("%s vence e instala governo aliado em %s.") % [pl.name, def.name])},
			{"label": tr("Demarcar novas fronteiras"), "hint": tr("Você desenha no mapa as áreas que ficam com o seu país"), "fn": func():
				_send(demarcation_requested, [{"kind": "victory", "war": w, "rival": def, "budget": 0.9}])},
			{"label": tr("Não ficar com território"), "hint": tr("Retira as tropas e melhora a reputação internacional"), "fn": func():
				settle_victory(w, def, [])},
		],
	})


## Whoever invaded the player was expelled: the player won and decides whether to keep what was taken.
func player_repelled(w: Dictionary, att: Country) -> void:
	w.front = -49.0
	_offer_victory(w, att, 0.3)


func _offer_victory(w: Dictionary, rival: Country, budget: float) -> void:
	ask_player({
		"title": tr("Vitória sobre %s") % rival.name,
		"text": tr("Suas tropas controlam cerca de %s do território de %s. Fica com alguma parte?") % [UiKit.pct(budget), rival.name],
		"options": [
			{"label": tr("Demarcar novas fronteiras"), "hint": tr("Você desenha no mapa as áreas que ficam com o seu país"), "fn": func():
				_send(demarcation_requested, [{"kind": "victory", "war": w, "rival": rival, "budget": budget}])},
			{"label": tr("Não ficar com território"), "hint": tr("Retira as tropas e melhora a reputação internacional"), "fn": func():
				settle_victory(w, rival, [])},
		],
	})


func _offer_negotiation(w: Dictionary, rival: Country) -> void:
	ask_player({
		"title": tr("Negociação de fronteiras"),
		"text": tr("O cessar-fogo com %s saiu sem vencedor. Como ficam as fronteiras?") % rival.name,
		"options": [
			{"label": tr("Restabelecer fronteiras antigas"), "hint": tr("Cada lado volta para onde estava antes da guerra"), "fn": func():
				settle_old_borders(w, rival)},
			{"label": tr("Propor novas fronteiras"), "hint": tr("Desenhe o que pede e o que oferece. %s pode recusar") % rival.name, "fn": func():
				_send(demarcation_requested, [{"kind": "negotiation", "war": w, "rival": rival, "budget": 1.0}])},
		],
	})


## The winner keeps the marked areas. Empty list: withdraws the troops and nothing changes on the map.
func settle_victory(w: Dictionary, rival: Country, pieces: Array) -> void:
	var pl := player
	var d := diplomacy
	if pieces.is_empty():
		d.add_relation(rival.idx, pl.idx, 15.0)
		for c: Country in countries:
			if c.alive and c != pl and c != rival:
				d.add_relation(c.idx, pl.idx, 3.0)
		d.end_war_by_player(w, pl, rival, self, 0.0, tr("%s vence a guerra, retira as tropas e não fica com território de %s.") % [pl.name, rival.name])
		return
	var share := territories.apply(pieces, rival, pl, self)
	d.transfer(rival, pl, share, self)
	for c: Country in countries:
		if c.alive and c != pl:
			d.add_relation(c.idx, pl.idx, -clampf(share * 30.0, 1.0, 10.0))
	d.end_war_by_player(w, pl, rival, self, 0.0, tr("Novas fronteiras: %s fica com %s do território de %s.") % [pl.name, UiKit.pct(share), rival.name])


func settle_old_borders(w: Dictionary, rival: Country, msg := "") -> void:
	diplomacy.add_relation(rival.idx, player.idx, 6.0)
	var text := msg if msg != "" else tr("%s e %s restabelecem as fronteiras de antes da guerra.") % [player.name, rival.name]
	diplomacy.end_war_by_player(w, player, rival, self, 0.0, text)


## Proposal of new borders in a peace with no winner. The rival compares, in GDP, what it loses and what
## it gains, and tolerates more when the front is against it or when it is tired of the war.
func propose_borders(w: Dictionary, rival: Country, claims: Array, offers: Array) -> Dictionary:
	var pl := player
	var t := territories
	var claim_share := Subdivisions.total_area(claims) / t.area_of(rival, self)
	var offer_share := Subdivisions.total_area(offers) / t.area_of(pl, self)
	var net := claim_share - offer_share * pl.y_usd() / maxf(rival.y_usd(), 0.001)
	var pl_att: bool = pl.idx in w.a
	var f: float = float(w.front) if pl_att else -float(w.front)
	var tolerance := 0.02 + maxf(f, 0.0) / 100.0 * 0.6 + rival.war_exhaustion * 0.12 - maxf(-f, 0.0) / 100.0 * 0.3
	if net > tolerance:
		diplomacy.add_relation(rival.idx, pl.idx, -2.0)
		return {"ok": false, "msg": tr("%s recusou: a troca tira território demais. O saldo aceitável é cerca de %s do país.") % [rival.name, UiKit.pct(maxf(tolerance, 0.0))]}
	var gained := t.apply(claims, rival, pl, self)
	diplomacy.transfer(rival, pl, gained, self)
	var given := t.apply(offers, pl, rival, self)
	diplomacy.transfer(pl, rival, given, self)
	diplomacy.add_relation(rival.idx, pl.idx, 4.0)
	diplomacy.end_war_by_player(w, pl, rival, self, 0.0, tr("Acordo de paz: %s e %s estabelecem novas fronteiras.") % [pl.name, rival.name])
	return {"ok": true, "msg": ""}


func nuclear_check(w: Dictionary, att: Country, def: Country, force := false) -> bool:
	var f: float = w.front
	var losing: Country = null
	if f > 70.0 and def.nukes > 0:
		losing = def
	elif f < -35.0 and att.nukes > 0:
		losing = att
	if losing == null or (not force and rng.randf() > 0.006):
		return false
	nuke_used = true
	global_tension = 1.0
	global_risk = 1.0
	emit_news(tr("ATAQUE NUCLEAR: %s usa armas atômicas diante da derrota.") % losing.name, "guerra", losing)
	var other := att if losing == def else def
	other.damage = 0.5
	other.capital *= 0.7
	if player:
		player.stability = maxf(player.stability - 0.2, 0.03)
		player.approval = maxf(player.approval - 0.1, 0.02)
		emit_news(tr("%s lançou armas nucleares. O mundo inteiro entra em choque.") % losing.name, "crise", losing)
	return true


# --- Player actions ---------------------------------------------------------------

const ACTION_COOLDOWN_DAYS := 30


## Days until the same action can be repeated with the same country.
func action_wait(action: String, target: Country) -> int:
	var last: int = action_used.get("%s:%s" % [action, target.iso], -9999)
	return maxi(last + ACTION_COOLDOWN_DAYS - day_index, 0)


func do_action(action: String, target: Country) -> Dictionary:
	var pl := player
	var d := diplomacy
	if pl == null or target == pl or not target.alive:
		return {"ok": false, "msg": tr("Ação inválida.")}
	if not in_office:
		return {"ok": false, "msg": tr("Na oposição, você não fala em nome do país.")}
	if action_wait(action, target) > 0:
		return {"ok": false, "msg": tr("Essa ação com %s só pode ser repetida em %d dia(s).") % [target.name, action_wait(action, target)]}
	var rel := d.relation(pl.idx, target.idx)
	var msg := ""
	match action:
		"mission":
			d.add_relation(pl.idx, target.idx, rng.randf_range(4.0, 9.0))
			msg = tr("Missão diplomática melhora relações com %s.") % target.name
		"aid":
			var amount := pl.y_usd() * 0.001
			pl.debt_loc += amount * pl.e
			target.reserves += amount
			target.demand_shock += amount / maxf(target.y_usd(), 0.01) * 0.6
			d.add_relation(pl.idx, target.idx, clampf(10.0 * sqrt(amount / maxf(target.y_usd() * 0.002, 0.01)), 2.0, 16.0))
			msg = tr("Pacote de ajuda de US$ %.1f bi enviado a %s.") % [amount, target.name]
		"fta":
			if d.has_fta(pl.idx, target.idx, self):
				return {"ok": false, "msg": tr("Já existe acordo comercial.")}
			if rel < 15.0:
				return {"ok": false, "msg": tr("%s não negocia: relação abaixo de +15.") % target.name}
			var deal: Dictionary = treaties.propose(self, target, "fta")
			msg = String(deal.msg)
			if not deal.get("accepted", false):
				return {"ok": deal.ok, "msg": msg}
		"alliance":
			if d.allied(pl.idx, target.idx):
				var existing: Dictionary = treaties.between(pl, target, "defense", [Treaties.STATE_FORCE])
				if not existing.is_empty() and existing.parties.size() == 2:
					msg = String(treaties.denounce(self, int(existing.id)).msg)
				else:
					d.break_alliance(pl, target, self)
					msg = tr("Pacto de defesa com %s cancelado.") % target.name
			else:
				if rel < 55.0:
					return {"ok": false, "msg": tr("%s recusa: relação abaixo de +55.") % target.name}
				var pact: Dictionary = treaties.propose(self, target, "defense")
				msg = String(pact.msg)
				if not pact.get("accepted", false):
					return {"ok": pact.ok, "msg": msg}
		"denounce":
			d.add_relation(pl.idx, target.idx, -10.0)
			pl.approval = minf(pl.approval + 0.005, 0.95)
			msg = tr("Seu governo condena %s publicamente.") % target.name
		"sanction":
			var lvl := d.sanction_level(pl.idx, target.idx)
			if lvl >= 1:
				d.set_sanction(pl, target, 0, self)
				msg = tr("Sanções contra %s suspensas.") % target.name
			else:
				d.set_sanction(pl, target, 1, self)
				msg = tr("Sanções financeiras contra %s em vigor.") % target.name
		"embargo":
			var lvl2 := d.sanction_level(pl.idx, target.idx)
			if lvl2 >= 2:
				d.set_sanction(pl, target, 1, self)
				msg = tr("Embargo contra %s reduzido a sanções.") % target.name
			else:
				d.set_sanction(pl, target, 2, self)
				msg = tr("Embargo total contra %s decretado.") % target.name
		"tariff":
			var cur := float(d.tariffs.get(d.key(pl.idx, target.idx), 0.0))
			if cur > 0.0:
				d.set_tariff_on(pl, target, 0.0, self)
				msg = tr("Tarifa contra %s removida.") % target.name
			else:
				d.set_tariff_on(pl, target, 0.2, self)
				msg = tr("Tarifa de 20%% sobre produtos de %s.") % target.name
		"covert":
			var defense := target.stability * 0.35 + clampf(target.gdp_pc() / 90000.0, 0.0, 0.3)
			if rng.randf() < defense:
				d.add_relation(pl.idx, target.idx, -22.0)
				pl.approval = maxf(pl.approval - 0.02, 0.02)
				msg = tr("Operação secreta descoberta em %s: escândalo internacional.") % target.name
			else:
				target.stability = maxf(target.stability - 0.08, 0.02)
				target.unrest = minf(target.unrest + 0.3, 1.0)
				target.conf = maxf(target.conf - 0.06, 0.05)
				msg = tr("Operação secreta desestabiliza %s.") % target.name
		"arms":
			if rel < 10.0:
				return {"ok": false, "msg": tr("%s não compra de você: relação abaixo de +10.") % target.name}
			var value := minf(target.y_usd() * 0.003, pl.y_usd() * 0.001)
			target.mil_stock += value * 0.6
			pl.demand_shock += value / maxf(pl.y_usd(), 0.01) * 0.5
			d.add_relation(pl.idx, target.idx, 5.0)
			msg = tr("Venda de armas de US$ %.1f bi para %s.") % [value, target.name]
		"war":
			if d.allied(pl.idx, target.idx):
				return {"ok": false, "msg": tr("Cancele o pacto com %s antes.") % target.name}
			if d.at_war(pl.idx, target.idx):
				return {"ok": false, "msg": tr("Já em guerra.")}
			d.declare_war(pl, target, self)
			return {"ok": true, "msg": ""}
		"peace":
			return _propose_peace(target)
		_:
			return {"ok": false, "msg": tr("Ação desconhecida.")}
	action_used["%s:%s" % [action, target.iso]] = day_index
	if msg != "":
		emit_news(msg, "diplomacia", target)
	return {"ok": true, "msg": msg}


func _propose_peace(target: Country) -> Dictionary:
	var pl := player
	var d := diplomacy
	var w := d.war_between(pl.idx, target.idx)
	if w.is_empty():
		return {"ok": false, "msg": tr("Vocês não estão em guerra.")}
	var pl_att: bool = pl.idx in w.a
	var f: float = w.front if pl_att else -float(w.front)  # >0 favors the player
	var enemy: Country = countries[w.main_d] if pl_att else countries[w.main_a]
	var accepts := enemy.war_exhaustion * 0.9 + (f / 100.0) * 0.8 + 0.18
	if f < -15.0:
		accepts -= 0.25 + (-f) * 0.008  # an enemy that is winning does not accept easily
	action_used["peace:%s" % target.iso] = day_index
	if rng.randf() > clampf(accepts, 0.02, 0.97):
		return {"ok": false, "msg": tr("%s rejeitou a proposta de paz.") % enemy.name}
	if f > 15.0:
		_offer_victory(w, enemy, clampf(f / 100.0, 0.02, 0.9))
	elif f >= -15.0:
		_offer_negotiation(w, enemy)
	else:
		# The enemy won: it is the one who chooses what it keeps.
		d.end_war_by_player(w, enemy, pl, self, clampf(-f * 0.004, 0.0, 0.3), tr("Paz assinada: %s cede {pct} do território a %s.") % [pl.name, enemy.name])
	return {"ok": true, "msg": ""}


# --- Saving and loading ---------------------------------------------------------

func to_dict() -> Dictionary:
	var cs := []
	for c: Country in countries:
		cs.append(c.to_dict())
	return {
		"countries": cs, "markets": markets.to_dict(), "diplomacy": diplomacy.to_dict(),
		"day_index": day_index, "year": year, "month": month, "day": day,
		"next_ai": next_ai, "global_risk": global_risk, "global_tension": global_tension,
		"ecb_rate": ecb_rate, "eur_rate": eur_rate, "action_used": action_used, "difficulty": difficulty,
		"mandates": mandates, "months_elapsed": months_elapsed, "global_hist": global_hist,
		"player": player.idx if player else -1, "world_gdp": _world_gdp,
		"rng_state": rng.state, "rng_seed": rng.seed, "subdivisions": subdivisions.to_dict(),
		"territories": territories.to_dict(), "leader": leader, "politics": politics.to_dict(),
		"in_office": in_office, "talks": talks, "chats": chats, "talk_turns": talk_turns, "offers": offers, "legislation": legislation.to_dict(), "treaties": treaties.to_dict(), "next_talk_month": next_talk_month,
		"infra": infra.to_dict(), "corporate": corporate.to_dict(), "corruption": corruption.to_dict(),
	}


func load_dict(d: Dictionary) -> void:
	countries.clear()
	by_iso.clear()
	for cd: Dictionary in d.countries:
		var c := Country.from_dict(cd)
		countries.append(c)
		by_iso[c.iso] = c
	# The save keeps the name in the language it was saved in.
	localize_country_names()
	usa = by_iso["USA"]
	markets.from_dict(d.markets)
	diplomacy.from_dict(d.diplomacy)
	for k: String in ["day_index", "year", "month", "day", "next_ai", "global_risk", "global_tension", "ecb_rate", "eur_rate", "difficulty", "mandates", "months_elapsed", "global_hist"]:
		set(k, d[k])
	_world_gdp = d.world_gdp
	rng.seed = d.rng_seed
	rng.state = d.rng_state
	player = countries[d.player] if int(d.player) >= 0 else null
	subdivisions.from_dict(d.get("subdivisions", {}), player.iso if player else "")
	territories.from_dict(d.get("territories", {}))
	leader = Character.migrated(d.get("leader", {}), rng) if d.has("leader") and not d.leader.is_empty() else {}
	politics.from_dict(d.get("politics", {}))
	in_office = d.get("in_office", true)
	talks = d.get("talks", {})
	chats = d.get("chats", {})
	talk_turns = d.get("talk_turns", {})
	offers = d.get("offers", {})
	action_used = d.get("action_used", {})
	next_talk_month = d.get("next_talk_month", months_elapsed + TALK_COOLDOWN_MONTHS)
	treaties = Treaties.new()
	if d.has("treaties"):
		treaties.from_dict(d.treaties)
	else:
		treaties.setup(self)
	legislation = Legislation.new()
	if d.has("legislation"):
		legislation.from_dict(d.legislation, self)
	elif player:
		legislation.setup(self)
	infra = Infrastructure.new()
	if d.has("infra"):
		infra.from_dict(d.infra, self)
	else:
		infra.setup(self)
	corporate = Corporate.new()
	if d.has("corporate"):
		corporate.from_dict(d.corporate, self)
	else:
		corporate.setup(self)
	corruption = Corruption.new()
	corruption.from_dict(d.get("corruption", {}))
	# Old saves do not have the index: starts from the current level, with no deviation.
	if not d.has("corruption"):
		corruption.setup(self)
	if player and int(politics.data_of(player.iso).player_party) < 0:
		politics.join_party(self, int(politics.data_of(player.iso).ruling), true)
	over = false
	diplomacy.refresh_sanction_cache(self)
