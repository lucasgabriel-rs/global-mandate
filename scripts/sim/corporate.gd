class_name Corporate
extends RefCounted
## Empresas de cada país e a bolsa de valores (capital aberto e capital fechado).
## Contrato com o resto do jogo: lê `Country.sector_out`/`sector_share` (ver Sectors), pode somar em
## `Country.sector_boost`, e é dono de `Country.stock`, o índice da bolsa. Nunca toca em nós nem emite sinais:
## roda na thread da simulação (notícias só por `world.emit_news`).
##
## Cada empresa fatura uma fração do produto do seu setor; a margem sente o ciclo, o juro e o câmbio, e o
## valor é o lucro vezes um P/L que cai quando o juro e o risco sobem. As grandes são nomeadas (dados reais
## ou geradas); o resto das listadas entra agregado como "demais empresas", que acompanha o PIB nominal.

const DATA_PATH := "res://data/companies.json"
## P/L típico de cada setor (mesma ordem de Sectors.NAMES).
const PE := [12.0, 9.0, 15.0, 10.0, 18.0, 13.0, 10.0, 24.0, 16.0, 13.0]
## Margem líquida para onde as empresas voltam com o tempo.
const NORM_MARGIN := [0.05, 0.10, 0.07, 0.04, 0.03, 0.05, 0.15, 0.15, 0.07, 0.07]
## Fração do lucro paga em dividendos.
const PAYOUT := [0.35, 0.55, 0.35, 0.35, 0.35, 0.4, 0.45, 0.15, 0.3, 0.6]
## Margem perdida por ponto de juro acima do inicial: construção e serviços públicos vivem de dívida.
const RATE_SENS := [0.3, 0.3, 0.3, 0.6, 0.25, 0.4, -0.15, 0.1, 0.3, 0.5]
## Margem ganha com a moeda mais fraca em termos reais: exportadores ganham, importadores perdem.
const FX_SENS := [0.12, 0.15, 0.08, 0.0, -0.06, -0.03, 0.0, 0.03, 0.1, 0.0]
## Quanto cada setor amplifica o humor do mercado.
const BETA := [0.7, 1.0, 1.1, 1.4, 1.0, 1.1, 1.3, 1.3, 1.2, 0.6]
## Volatilidade própria de cada ação, por mês.
const VOL := [0.04, 0.05, 0.045, 0.06, 0.045, 0.05, 0.045, 0.07, 0.05, 0.03]
## Setores em que uma campeã nacional forte puxa a produtividade do setor inteiro.
const CHAMPION_SECTORS := [Sectors.INDUSTRY, Sectors.TECH]
const MAX_EVENTS := 40
const STATE_DISCOUNT := 0.25
const PRIVATIZE_DISCOUNT := 0.08
const TAKEOVER_PREMIUM := 0.2

## Nomes das estatais geradas, por setor: são únicas no país.
const STATE_NAMES := [
	"Companhia Nacional de Agricultura", "Companhia Nacional de Petróleo", "Indústrias Nacionais Reunidas",
	"Construtora Nacional", "Rede Nacional de Abastecimento", "Linhas Aéreas Nacionais", "Banco Nacional",
	"Telecom Nacional", "Empresa Nacional de Turismo", "Companhia Elétrica Nacional",
]
## Nomes das privadas geradas: o %s recebe uma palavra de TOKENS.
const PRIVATE_NAMES := [
	["Agro %s", "Grãos %s", "Frigorífico %s"], ["%s Energia", "Mineração %s", "Petróleo %s"],
	["Indústrias %s", "%s Metalúrgica", "%s Química"], ["Construtora %s", "%s Engenharia", "%s Cimentos"],
	["Rede %s", "Supermercados %s", "Magazine %s"], ["%s Logística", "Transportadora %s", "%s Linhas Aéreas"],
	["Banco %s", "%s Seguros", "%s Investimentos"], ["%s Digital", "%s Telecom", "%s Software"],
	["Hotéis %s", "%s Turismo", "Resorts %s"], ["%s Saneamento", "%s Saúde", "Elétrica %s"],
]
const TOKENS := [
	"Atlas", "Vértice", "Horizonte", "Aurora", "Delta", "Sigma", "Pioneira", "Meridiano", "Zênite", "Órbita",
	"Pilar", "Ápice", "Fênix", "Alvorada", "Boreal", "Cosmos", "Ômega", "Prisma", "Vanguarda", "Nobre",
	"Sol Nascente", "Estrela", "Continental", "Progresso", "União", "Federal", "Litoral", "Planalto",
]

## Bolsas e empresas por país: {iso: mercado}. O mercado guarda a lista de empresas e o estado da bolsa.
var markets := {}
## Humor do mercado mundial (log): todas as bolsas sentem.
var global_mood := 0.0
var _last_risk := 0.2
var next_id := 1
## Gerador próprio: o do mundo só dá um sorteio por país e mês, como a fórmula antiga do índice, para que
## o resto da simulação (guerras, crises, eleições) não mude de rumo por causa das empresas.
var _rng := RandomNumberGenerator.new()


# --- Montagem ----------------------------------------------------------------------------

func setup(world: GameWorld) -> void:
	_rng.seed = hash("empresas%d" % world.rng.seed)
	markets.clear()
	global_mood = 0.0
	_last_risk = world.global_risk
	var data := _load_data()
	for c: Country in world.countries:
		if c.sector_share.size() != Sectors.COUNT:
			Sectors.init_country(c, world)
		var m := _new_market(c, world)
		var src: Dictionary = data.get(c.iso, {})
		if src.is_empty():
			_generate(c, m, world)
		else:
			m.exchange = String(src.get("exchange", ""))
			for row: Array in src.get("companies", []):
				_add(c, m, world, String(row[0]), int(row[1]), float(row[2]), float(row[3]), float(row[4]), int(row[5]) == 1, float(row[6]))
		_calibrate(c, m, float(src.get("market_cap", m.get("cap_hint", 0.0))))
		m.erase("cap_hint")
		markets[c.iso] = m


static func _load_data() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed.get("countries", {})
	return {}


func _new_market(c: Country, _world: GameWorld) -> Dictionary:
	return {
		"exchange": "", "list": [], "mood": 0.0, "rest_ratio": 0.0, "rest": 0.0, "cap": 0.0,
		"e0": c.e, "p0": c.p, "real0": c.rate - c.pi_e, "disc0": _discount(c), "crisis": c.crisis_cooldown,
		"boost": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "champ0": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"div0": 0.0, "events": [], "n0": 0, "change": 0.0, "pe": 0.0, "dy": 0.0,
	}


## Cria uma empresa. rev, profit e value em US$ bi; state é a participação do Estado.
func _add(c: Country, m: Dictionary, world: GameWorld, name_: String, sector: int, rev: float, profit: float, value: float, listed: bool, state: float) -> Dictionary:
	var sec_usd := maxf(Sectors.output_usd(c, sector), 0.001)
	var price := snappedf(_rng.randf_range(8.0, 90.0), 0.01)
	var co := {
		"id": next_id, "name": name_, "sector": sector, "listed": listed, "state": clampf(state, 0.0, 1.0),
		"k": maxf(rev, 0.001) / sec_usd, "mb": clampf(profit / maxf(rev, 0.001), -0.01, 0.6), "mi": 0.0,
		"rev": rev, "profit": profit, "value": maxf(value, 0.05), "prem": 0.0, "vi": 0.0,
		"shares": maxf(value, 0.05) / price, "local": maxf(value, 0.05) * c.e, "ch": 0.0, "ch12": 0.0, "price12": price,
		"div": 0.0, "distress": 0.0, "g": _rng.randfn(0.0, 0.025), "since": world.year,
	}
	next_id += 1
	m.list.append(co)
	return co


## Fecha a conta inicial: o prêmio de cada empresa faz o valor de partida bater com o dado real.
func _calibrate(c: Country, m: Dictionary, market_cap: float) -> void:
	var yusd := maxf(c.y_usd(), 0.001)
	var mult := _multiple(c, m, c.g0)
	var named := 0.0
	var state_div := 0.0
	for co: Dictionary in m.list:
		var s: int = co.sector
		var margin: float = co.mb
		co.profit = float(co.rev) * margin
		var fund := _fundamental(co, mult)
		co.prem = log(float(co.value) / fund)
		co.div = maxf(float(co.profit), 0.0) * float(PAYOUT[s])
		state_div += float(co.div) * float(co.state)
		if co.listed:
			named += float(co.value)
		if s in CHAMPION_SECTORS and margin > 0.0:
			m.champ0[s] = float(m.champ0[s]) + float(co.k)
	m.n0 = m.list.size()
	m.div0 = state_div / yusd
	if m.exchange != "":
		var total := maxf(market_cap, named * 1.15)
		m.rest_ratio = maxf(total - named, total * 0.12) / yusd
	m.rest = float(m.rest_ratio) * yusd
	m.cap = named + float(m.rest)
	_summary(m)


## Países sem dado ganham suas maiores empresas a partir dos setores que mais pesam.
func _generate(c: Country, m: Dictionary, world: GameWorld) -> void:
	var rng := _rng
	var yusd := maxf(c.y_usd(), 0.01)
	var pc := maxf(c.gdp_pc(), 300.0)
	var n := clampi(int(roundf(2.0 + log(maxf(yusd, 1.0)) / log(10.0) * 1.6)), 2, 8)
	var has_exchange := yusd > 25.0
	if has_exchange:
		m.exchange = tr("Bolsa de Valores de %s") % c.name
	var order := range(Sectors.COUNT)
	order.sort_custom(func(a, b): return c.sector_share[a] > c.sector_share[b])
	for pos in mini(n, order.size()):
		var s: int = order[pos]
		var state_odds := 0.2 + (0.4 if c.dem < 4.0 else 0.0) + (0.25 if s in [Sectors.MINING, Sectors.PUBLIC, Sectors.TRANSPORT] else 0.0)
		var is_state := rng.randf() < state_odds
		var state := 1.0 if is_state else 0.0
		var name_ := String(STATE_NAMES[s]) if is_state else _private_name(m, s, rng)
		var rev := Sectors.output_usd(c, s) * rng.randf_range(0.04, 0.12)
		var margin: float = float(NORM_MARGIN[s]) * rng.randf_range(0.5, 1.3)
		var listed := false
		if has_exchange:
			if is_state and rng.randf() < 0.25:
				listed = true
				state = rng.randf_range(0.5, 0.75)
			elif not is_state:
				listed = rng.randf() < 0.6
		var value := rev * margin * float(PE[s]) * rng.randf_range(0.7, 1.3)
		_add(c, m, world, name_, s, rev, rev * margin, value, listed, state)
	if has_exchange:
		var rich := clampf(log(pc / 3000.0) / 3.0, 0.0, 1.0)
		var named := 0.0
		for co: Dictionary in m.list:
			if co.listed:
				named += float(co.value)
		# Valor de toda a bolsa, que _calibrate lê em setup.
		m["cap_hint"] = maxf(yusd * (0.05 + 0.6 * rich), named * 1.2)


func _private_name(m: Dictionary, s: int, rng: RandomNumberGenerator) -> String:
	var options: Array = PRIVATE_NAMES[s]
	for attempt in 8:
		var name_ := String(options[rng.randi() % options.size()]) % String(TOKENS[rng.randi() % TOKENS.size()])
		if find(m, name_).is_empty():
			return name_
	return "%s %d" % [String(options[0]) % String(TOKENS[0]), next_id]


# --- Valuation ----------------------------------------------------------------------------

## Taxa com que o mercado desconta lucros: juro real, prêmio de ações e risco do país.
static func _discount(c: Country) -> float:
	return 0.08 + 0.5 * clampf(c.rate - c.pi_e, -0.03, 0.2) + 0.5 * c.risk


## Quantas vezes o lucro o mercado paga hoje, relativo ao início (1 = como no começo).
static func _multiple(c: Country, m: Dictionary, growth: float) -> float:
	var ratio := float(m.disc0) / maxf(_discount(c), 0.02)
	return clampf(ratio, 0.4, 2.2) * exp(clampf(2.0 * (growth - c.g0), -0.3, 0.2))


static func _fundamental(co: Dictionary, mult: float) -> float:
	var s: int = co.sector
	var earn := maxf(float(co.profit), float(co.rev) * 0.005)
	var control := 1.0 - STATE_DISCOUNT * clampf((float(co.state) - 0.3) / 0.7, 0.0, 1.0)
	return maxf(earn * float(PE[s]) * mult * control, 0.001)


# --- Etapa mensal de cada país -----------------------------------------------------------

## Índice da bolsa, chamado na etapa mensal de cada país.
static func update_index(c: Country, world: GameWorld, growth: float) -> void:
	var shock := world.rng.randfn(0.0, 0.14)
	var m: Dictionary = world.corporate.markets.get(c.iso, {})
	if m.is_empty() or c.sector_share.size() != Sectors.COUNT:
		_macro_index(c, world, growth, shock)
		return
	world.corporate._step_country(c, m, world, growth, shock)


## Fórmula macro para países sem nenhuma empresa listada.
static func _macro_index(c: Country, world: GameWorld, growth: float, shock: float) -> void:
	c.stock *= exp(clampf(0.05 + 2.0 * (growth - c.g0) - 1.0 * c.rgap - 0.3 * (world.global_risk - 0.2) + c.pi_yoy * 0.8 + shock, -0.8, 0.8) * Economy.DT)


## shock: o sorteio do mês vindo do gerador do mundo, em desvios de 0,14.
func _step_country(c: Country, m: Dictionary, world: GameWorld, growth: float, shock: float) -> void:
	var rng := _rng
	var yusd := maxf(c.y_usd(), 0.001)
	var big := yusd > world.world_gdp() * 0.01
	var mine := c == world.player
	# Crise bancária: a Economia zera o crédito e arma um intervalo de oito anos; aqui só se percebe o salto.
	var crisis := c.crisis_cooldown > float(m.crisis) + 1.0
	m.crisis = c.crisis_cooldown
	var mood: float = m.mood
	mood += -0.07 * mood + shock * 0.03 / 0.14
	if crisis:
		mood -= 0.22
	var market := mood + 0.8 * global_mood
	var mult := _multiple(c, m, growth)
	var real_dep := clampf(log(c.e / maxf(float(m.e0), 0.0001)) - log(c.p / maxf(float(m.p0), 0.0001)), -0.5, 0.5)
	# Juro real, e não nominal: com inflação alta o juro nominal sobe sem apertar ninguém.
	var rate_up := clampf(c.rate - c.pi_e - float(m.real0), -0.04, 0.06)
	var before := 0.0
	var after := 0.0
	var gone: Array = []
	var named := 0.0
	var state_div := 0.0
	var earn := 0.0
	var divs := 0.0
	var healthy := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	# O que o país impõe a cada setor neste mês: ciclo, juro, câmbio e crédito.
	var macro := PackedFloat32Array()
	macro.resize(Sectors.COUNT)
	for s in Sectors.COUNT:
		macro[s] = 0.25 * float(Sectors.CYCLE_BETA[s]) * c.gap - float(RATE_SENS[s]) * rate_up + float(FX_SENS[s]) * real_dep
	macro[Sectors.FINANCE] += 0.3 * clampf(c.credit_gap, -0.15, 0.1)
	var january := world.month == 0
	# Os campos são lidos e escritos uma vez cada: com centenas de empresas, cada acesso ao dicionário pesa.
	for co: Dictionary in m.list:
		var s: int = co.sector
		var g: float = co.g
		var k: float = float(co.k) * exp(g / 12.0 + rng.randfn(0.0, 0.012))
		var rev := k * yusd * c.sector_share[s]
		var norm: float = NORM_MARGIN[s]
		var mb: float = co.mb
		# Margens ruins voltam rápido ao normal; margens excepcionais duram anos.
		mb += (norm - mb) * (0.03 if mb < norm * 0.3 else 0.002)
		var mi: float = float(co.mi) * 0.9 + rng.randfn(0.0, 0.004)
		var bank_hit := crisis and s == Sectors.FINANCE
		if bank_hit:
			mi -= 0.06
		var margin := mb + mi + macro[s]
		var profit := rev * margin
		var div := maxf(profit, 0.0) * float(PAYOUT[s])
		var state: float = co.state
		state_div += div * state
		var prem: float = float(co.prem) * 0.998
		var vi: float = float(co.vi) * 0.95 + rng.randfn(0.0, float(VOL[s]))
		var control := 1.0 - STATE_DISCOUNT * clampf((state - 0.3) / 0.7, 0.0, 1.0)
		var fund := maxf(maxf(profit, rev * 0.005) * float(PE[s]) * mult * control, 0.001)
		var value := fund * exp(prem + vi + float(BETA[s]) * market)
		var old_local: float = co.local
		var local := value * c.e
		var distress: float = float(co.distress) * 0.93 + maxf(-margin, 0.0) * 1.5 + (0.1 if bank_hit else 0.0)
		co.k = k
		co.g = g * 0.995
		co.rev = rev
		co.mb = mb
		co.mi = mi
		co.profit = profit
		co.div = div
		co.prem = prem
		co.vi = vi
		co.value = value
		co.local = local
		co.ch = local / maxf(old_local, 0.0001) - 1.0
		co.distress = distress
		if january:
			var price := value / float(co.shares)
			co.ch12 = price / maxf(float(co.price12), 0.0001) - 1.0
			co.price12 = price
		var listed: bool = co.listed
		if listed:
			before += old_local
			after += local
		# Prejuízo acumulado vira dificuldade; dificuldade demais, quebra.
		if distress > 0.12 and rng.randf() < 0.2:
			if _rescue_or_fail(c, m, co, world, mine, big):
				gone.append(co)
				if listed:
					after -= local
				continue
		if listed:
			named += value
			earn += profit
			divs += div
		if margin > 0.0 and (s == Sectors.INDUSTRY or s == Sectors.TECH):
			healthy[s] = float(healthy[s]) + k
	# Na crise, o banco mais frágil pode não resistir.
	if crisis:
		var failed := _bank_run(c, m, world, gone, mine, big)
		if not failed.is_empty() and failed.listed:
			after -= float(failed.local)
			named -= float(failed.value)
	for co: Dictionary in gone:
		m.list.erase(co)
	m.mood = mood
	# O resto do mercado, agregado, acompanha o PIB nominal, o múltiplo e o humor.
	var old_rest: float = float(m.rest) * float(m.get("e_last", c.e))
	m.rest = float(m.rest_ratio) * yusd * mult * exp(market)
	before += old_rest
	after += float(m.rest) * c.e
	m.e_last = c.e
	if before > 0.0:
		var ret := clampf(after / before, 0.5, 1.6)
		c.stock *= ret
		m.change = ret - 1.0
		if crisis and (mine or big):
			world.emit_news(tr("Bolsa de %s despenca %d%% com a crise bancária.") % [c.name, int(roundf((1.0 - ret) * 100.0))], "crise", c)
	else:
		_macro_index(c, world, growth, shock)
	m.cap = named + float(m.rest)
	c.push_hist("mcap", float(m.cap))
	_treasury(c, m, state_div, yusd)
	_champions(c, m, healthy)
	_lifecycle(c, m, world, market, mine, big)
	m.pe = named / earn if earn > 0.0 else 0.0
	m.dy = divs / named if named > 0.0 else 0.0


## Dividendos das estatais: o que já vinha no orçamento do início está na receita-base; o Tesouro sente a diferença.
func _treasury(c: Country, m: Dictionary, state_div: float, yusd: float) -> void:
	c.extra_rev_bucket += (state_div - float(m.div0) * yusd) / 12.0


## Uma campeã nacional mais forte que no início puxa a produtividade do setor; se ela some, o setor perde.
func _champions(c: Country, m: Dictionary, healthy: Array) -> void:
	if c.sector_boost.size() != Sectors.COUNT:
		return
	for s: int in CHAMPION_SECTORS:
		var base: float = m.champ0[s]
		var target := 0.0
		if base > 0.0:
			target = clampf(0.05 * (float(healthy[s]) / base - 1.0), -0.02, 0.03)
		c.sector_boost[s] += target - float(m.boost[s])
		m.boost[s] = target


## Quem quebra: estatais e gigantes são socorridos pelo Tesouro; as demais saem do mercado.
## Devolve verdadeiro se a empresa deixou de existir.
func _rescue_or_fail(c: Country, m: Dictionary, co: Dictionary, world: GameWorld, mine: bool, big: bool) -> bool:
	var yusd := maxf(c.y_usd(), 0.001)
	var too_big := float(co.rev) > yusd * 0.02
	if float(co.state) >= 0.5 or too_big:
		var cost := float(co.rev) * 0.06
		c.extra_spend_bucket += cost
		co.distress = 0.0
		co.mi = 0.0
		co.mb = maxf(float(co.mb), float(NORM_MARGIN[co.sector]))
		if float(co.state) < 0.5:
			co.state = minf(float(co.state) + 0.4, 1.0)
			co.prem = float(co.prem) - 0.7
		_log(m, world, "socorro", co, cost)
		if mine or big:
			world.emit_news(tr("Governo de %s socorre %s com %s.") % [c.name, co.name, UiKit.money(cost)], "economia", c)
		return false
	var weight := float(co.value) / maxf(float(m.cap), 0.001)
	m.mood = float(m.mood) - clampf(weight * 3.0, 0.0, 0.12)
	_log(m, world, "falencia", co, float(co.value))
	if mine or (big and float(co.rev) > yusd * 0.004):
		world.emit_news(tr("%s quebra em %s: %s em receita somem do mercado.") % [co.name, c.name, UiKit.money(float(co.rev))], "crise", c)
	return true


## Devolve o banco que quebrou, ou vazio.
func _bank_run(c: Country, m: Dictionary, world: GameWorld, gone: Array, mine: bool, big: bool) -> Dictionary:
	var weakest: Dictionary = {}
	for co: Dictionary in m.list:
		if co.sector == Sectors.FINANCE and float(co.state) < 0.5 and not co in gone:
			if weakest.is_empty() or float(co.distress) > float(weakest.distress):
				weakest = co
	if weakest.is_empty() or _rng.randf() > 0.35:
		return {}
	if _rescue_or_fail(c, m, weakest, world, mine, big):
		gone.append(weakest)
		return weakest
	return {}


## Nascimentos, aberturas e fechamentos de capital.
func _lifecycle(c: Country, m: Dictionary, world: GameWorld, market: float, mine: bool, big: bool) -> void:
	var rng := _rng
	var count: int = m.list.size()
	var n0: int = m.n0
	if (count < n0 and rng.randf() < 0.04) or (count < n0 + 6 and rng.randf() < 0.004):
		var co := _birth(c, m, world)
		if mine and not co.is_empty():
			world.emit_news(tr("Nasce uma nova empresa em %s: %s, em %s.") % [c.name, co.name, tr(Sectors.NAMES[co.sector]).to_lower()], "economia", c)
	if m.exchange == "":
		return
	if m.list.is_empty():
		return
	var hot := clampf(1.0 + 3.0 * market, 0.2, 3.0)
	# Um sorteio por mês, numa empresa qualquer, com a chance multiplicada pelo tamanho da lista:
	# dá a mesma frequência que sortear todas, sem percorrer a lista.
	var n: int = m.list.size()
	var co: Dictionary = m.list[rng.randi() % n]
	if not co.listed:
		if float(co.state) < 0.5 and float(co.value) > 0.5 and rng.randf() < 0.004 * hot * n:
			_list(c, m, co, world, mine or (big and float(co.value) > 30.0))
	elif float(co.state) < 0.3 and rng.randf() < (0.0004 / hot + (0.001 if float(co.prem) + float(co.vi) < -0.6 else 0.0)) * n:
		co.listed = false
		_log(m, world, "fechamento", co, float(co.value))
		if mine:
			world.emit_news(tr("%s fecha o capital: investidores compram as ações e a empresa sai da bolsa.") % co.name, "economia", c)


func _list(c: Country, m: Dictionary, co: Dictionary, world: GameWorld, announce: bool) -> void:
	co.listed = true
	co.shares = float(co.value) / snappedf(_rng.randf_range(10.0, 40.0), 0.01)
	co.price12 = float(co.value) / float(co.shares)
	co.local = float(co.value) * c.e
	_log(m, world, "ipo", co, float(co.value))
	if announce:
		world.emit_news(tr("IPO: %s estreia na %s valendo %s.") % [co.name, m.exchange, UiKit.money(float(co.value))], "economia", c)


func _birth(c: Country, m: Dictionary, world: GameWorld) -> Dictionary:
	var rng := _rng
	var pick := rng.randf()
	var s := Sectors.COUNT - 1
	for i in Sectors.COUNT:
		pick -= c.sector_share[i]
		if pick <= 0.0:
			s = i
			break
	var name_ := _private_name(m, s, rng)
	var rev := Sectors.output_usd(c, s) * rng.randf_range(0.003, 0.02)
	var margin: float = float(NORM_MARGIN[s]) * rng.randf_range(0.6, 1.4)
	var co := _add(c, m, world, name_, s, rev, rev * margin, 1.0, false, 0.0)
	co.profit = rev * margin
	co.g = rng.randfn(0.04, 0.03)
	var fund := _fundamental(co, _multiple(c, m, c.growth_yoy()))
	co.value = fund
	co.prem = rng.randfn(0.0, 0.2)
	co.shares = fund / 20.0
	co.local = fund * c.e
	_log(m, world, "nova", co, fund)
	return co


func _summary(m: Dictionary) -> void:
	var cap := 0.0
	var earn := 0.0
	var div := 0.0
	for co: Dictionary in m.list:
		if co.listed:
			cap += float(co.value)
			earn += float(co.profit)
			div += float(co.div)
	m.pe = cap / earn if earn > 0.0 else 0.0
	m.dy = div / cap if cap > 0.0 else 0.0


func _log(m: Dictionary, world: GameWorld, kind: String, co: Dictionary, value: float) -> void:
	var events: Array = m.events
	events.push_front({"kind": kind, "name": co.name, "value": value, "date": "%s/%d" % [tr(GameWorld.MONTHS[world.month]), world.year]})
	if events.size() > MAX_EVENTS:
		events.resize(MAX_EVENTS)


# --- Etapa mensal global ---------------------------------------------------------------

## Chamado uma vez por mês, depois da legislação.
func step_month(world: GameWorld) -> void:
	var rng := _rng
	# O humor mundial sente o risco global: subida brusca do risco derruba todas as bolsas juntas.
	# O risco global já oscila uns 5 pontos por mês; com peso 0,6 a bolsa americana varia ~5% ao mês, como a real.
	global_mood += -0.07 * global_mood + rng.randfn(0.0, 0.02) - 0.6 * (world.global_risk - _last_risk)
	global_mood = clampf(global_mood, -1.0, 0.6)
	_last_risk = world.global_risk
	# Governos estrangeiros apertados vendem participações; regimes fechados às vezes tomam empresas.
	if world.countries.is_empty():
		return
	var c: Country = world.countries[rng.randi() % world.countries.size()]
	if not c.alive or c == world.player or not markets.has(c.iso):
		return
	var m: Dictionary = markets[c.iso]
	if c.debt_ratio > c.debt_tol * 1.1 and c.dem >= 4.0 and rng.randf() < 0.3:
		var target := _pick(m, func(co): return float(co.state) > 0.3)
		if not target.is_empty():
			privatize(world, c, String(target.name), 0.5)
	elif c.dem < 3.0 and rng.randf() < 0.02:
		var target := _pick(m, func(co): return float(co.state) < 0.1 and int(co.sector) in [Sectors.MINING, Sectors.PUBLIC, Sectors.FINANCE])
		if not target.is_empty():
			nationalize(world, c, String(target.name), 1.0)


static func _pick(m: Dictionary, filter: Callable) -> Dictionary:
	var best: Dictionary = {}
	for co: Dictionary in m.list:
		if filter.call(co) and (best.is_empty() or float(co.value) > float(best.value)):
			best = co
	return best


# --- Privatizar e estatizar ---------------------------------------------------------------

## Vende fraction da participação do Estado. A receita entra de uma vez no Tesouro.
## Fechada, a empresa abre o capital para isso. Devolve a nota para a auditoria da norma.
func privatize(world: GameWorld, c: Country, name_: String, fraction: float) -> String:
	var m: Dictionary = markets.get(c.iso, {})
	var co := find(m, name_)
	if co.is_empty() or float(co.state) <= 0.0:
		return ""
	var sold := float(co.state) * clampf(fraction, 0.0, 1.0)
	if sold <= 0.0:
		return ""
	var proceeds := sold * float(co.value) * (1.0 - PRIVATIZE_DISCOUNT)
	co.state = float(co.state) - sold
	if co.state < 0.005:
		co.state = 0.0
	if not co.listed:
		if m.exchange == "":
			m.exchange = tr("Bolsa de Valores de %s") % c.name
		_list(c, m, co, world, false)
	c.extra_rev_bucket += proceeds
	m.mood = float(m.mood) + 0.02
	_log(m, world, "privatizacao", co, proceeds)
	if c == world.player or c.y_usd() > world.world_gdp() * 0.01:
		world.emit_news(tr("%s privatiza %d%% de %s e arrecada %s.") % [c.name, int(roundf(sold * 100.0)), co.name, UiKit.money(proceeds)], "economia", c)
	return tr("privatizou %s de %s") % [UiKit.pct(sold, 0), co.name]


## Compra ações até o Estado ter share do capital, pagando prêmio aos acionistas. Com tudo, sai da bolsa.
func nationalize(world: GameWorld, c: Country, name_: String, share: float) -> String:
	var m: Dictionary = markets.get(c.iso, {})
	var co := find(m, name_)
	var target := clampf(share, 0.0, 1.0)
	if co.is_empty() or float(co.state) >= target - 0.001:
		return ""
	var bought := target - float(co.state)
	var cost := bought * float(co.value) * (1.0 + TAKEOVER_PREMIUM)
	co.state = target
	c.extra_spend_bucket += cost
	m.mood = float(m.mood) - 0.04
	if target >= 0.999 and co.listed:
		co.listed = false
	_log(m, world, "estatizacao", co, cost)
	if c == world.player or c.y_usd() > world.world_gdp() * 0.01:
		world.emit_news(tr("%s estatiza %s: o Estado passa a ter %d%% do capital, a um custo de %s.") % [c.name, co.name, int(roundf(target * 100.0)), UiKit.money(cost)], "economia", c)
	return tr("estatizou %s de %s") % [UiKit.pct(bought, 0), co.name]


# --- Consultas ------------------------------------------------------------------------------

static func find(m: Dictionary, name_: String) -> Dictionary:
	for co: Dictionary in m.get("list", []):
		if co.name == name_:
			return co
	return {}


func market_of(iso: String) -> Dictionary:
	return markets.get(iso, {})


func companies_of(iso: String) -> Array:
	return markets.get(iso, {}).get("list", [])


## {nome: participação do Estado} das empresas do país, para o compilador das normas.
func state_shares(iso: String) -> Dictionary:
	var out := {}
	for co: Dictionary in companies_of(iso):
		out[String(co.name)] = float(co.state)
	return out


static func control_of(co: Dictionary) -> String:
	var s: float = co.state
	if s <= 0.0:
		return TranslationServer.translate("Privada")
	return TranslationServer.translate("Estatal") if s >= 0.5 else TranslationServer.translate("Mista")


static func price_of(co: Dictionary) -> float:
	return float(co.value) / maxf(float(co.shares), 0.0001)


## P/L da empresa; zero quando dá prejuízo.
static func pe_of(co: Dictionary) -> float:
	return float(co.value) / float(co.profit) if float(co.profit) > 0.0 else 0.0


# --- Salvar e carregar ------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"markets": markets.duplicate(true), "global_mood": global_mood, "last_risk": _last_risk, "next_id": next_id,
		"rng_seed": _rng.seed, "rng_state": _rng.state,
	}


func from_dict(d: Dictionary, world: GameWorld) -> void:
	if not d.has("markets"):
		setup(world)
		return
	markets = d.markets.duplicate(true)
	global_mood = float(d.get("global_mood", 0.0))
	_last_risk = float(d.get("last_risk", world.global_risk))
	next_id = int(d.get("next_id", 1))
	_rng.seed = int(d.get("rng_seed", 1))
	_rng.state = int(d.get("rng_state", 0))
