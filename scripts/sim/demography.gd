class_name Demography
extends RefCounted
## Demografia em três faixas (0-14, 15-64, 65+): natalidade, mortalidade, envelhecimento e
## migração entre países. A população total continua em Country.pop; as faixas são frações dela.
## Roda na thread da simulação: nada de nós nem sinais aqui.

const DT := 1.0 / 12.0
## Mortalidade anual de jovens e adultos; o resto das mortes cai sobre os idosos.
const MORT_YOUNG := 0.0015
const MORT_ADULT := 0.003
## Migração: diferença de atração (ver _pull) abaixo da qual ninguém se muda, taxa anual por ponto
## de diferença além dela, refugiados ao ano em guerra e tetos anuais, em fração da população.
const NEUTRAL := 1.0
const RATE_IN := 0.0025
const RATE_OUT := 0.0025
const REFUGEES := 0.01
const MAX_IN := 0.008
const MAX_OUT := 0.04
## Parte do gasto social que é aposentadoria e cresce com a fatia de idosos.
const PENSION_SHARE := 0.55
## Retiradas extras por ano da idade ativa quando faltam jovens: onde a natalidade já caiu, as
## gerações que chegam aos 65 são maiores que as que entram aos 15, e o país envelhece rápido.
const AGING := 0.010
## Estrutura etária de partida (jovens 0-14, idosos 65+) dos maiores países, perto das
## estimativas da ONU para 2024. Os demais usam a fórmula de renda e crescimento.
const START := {
	"USA": [0.175, 0.18], "CHN": [0.165, 0.15], "JPN": [0.114, 0.296], "DEU": [0.14, 0.227],
	"IND": [0.25, 0.07], "BRA": [0.20, 0.11], "RUS": [0.17, 0.165], "GBR": [0.175, 0.19],
	"FRA": [0.17, 0.22], "ITA": [0.12, 0.245], "ESP": [0.135, 0.21], "CAN": [0.155, 0.195],
	"AUS": [0.18, 0.175], "KOR": [0.11, 0.195], "MEX": [0.24, 0.085], "IDN": [0.24, 0.07],
	"TUR": [0.215, 0.105], "SAU": [0.24, 0.03], "ARG": [0.225, 0.12], "NGA": [0.43, 0.03],
	"EGY": [0.33, 0.05], "PAK": [0.36, 0.045], "ZAF": [0.28, 0.065], "UKR": [0.15, 0.18],
	"POL": [0.15, 0.20], "IRN": [0.23, 0.08], "TWN": [0.115, 0.19], "THA": [0.15, 0.16],
	"VNM": [0.23, 0.10], "ETH": [0.40, 0.03], "BGD": [0.26, 0.065], "PHL": [0.29, 0.06],
	"COD": [0.46, 0.03], "ISR": [0.27, 0.125], "NLD": [0.155, 0.205], "SWE": [0.17, 0.205],
	"CHE": [0.15, 0.19], "GRC": [0.13, 0.23], "PRT": [0.125, 0.24], "COL": [0.21, 0.10],
	"CHL": [0.18, 0.14], "ARE": [0.15, 0.02],
}


## Quão rico é o país numa escala 0-1 (US$ 800 a US$ 50 mil per capita).
static func _rich(pc_usd: float) -> float:
	return clampf(log(maxf(pc_usd, 1.0) / 800.0) / log(62.5), 0.0, 1.0)


## Estrutura inicial plausível a partir da renda e do crescimento populacional (% ao ano).
## `mig` é a migração líquida inicial (fração ao ano), já contida em `popg`.
static func init_country(c: Country, mig: float = 0.0) -> void:
	var pc := c.gdp_pc()
	var rich := _rich(pc)
	var g_pct := c.popg * 100.0
	if START.has(c.iso):
		c.young = START[c.iso][0]
		c.old = START[c.iso][1]
	else:
		c.old = clampf(0.03 + 0.20 * rich - 0.04 * g_pct + (0.04 if g_pct < 0.0 else 0.0), 0.025, 0.30)
		c.young = clampf(0.13 + 0.10 * g_pct + 0.08 * (1.0 - rich), 0.11, 0.50)
	c.adult = 1.0 - c.young - c.old
	c.adult0 = c.adult
	c.old0 = c.old
	# Mortes por habitante: idosos pesam; países pobres têm mortalidade maior em todas as idades.
	c.death = clampf(0.004 + 0.055 * c.old + 0.004 * (1.0 - rich), 0.004, 0.016)
	c.birth = maxf(c.popg - mig + c.death, 0.005)
	c.birth0 = c.birth
	c.migration = mig
	# Fluxos estacionários: com as taxas de hoje, as faixas mantêm o peso no primeiro ano.
	# Os migrantes entram como adultos; `g` é o crescimento total, com a migração.
	var g := c.birth - c.death + mig
	c.mort_old = maxf((c.death - MORT_YOUNG * c.young - MORT_ADULT * c.adult) / c.old, 0.02)
	c.k_young = clampf(c.birth / c.young - g - MORT_YOUNG, 0.03, 0.12)
	c.k_adult = clampf((c.k_young * c.young + mig - (g + MORT_ADULT) * c.adult) / c.adult, 0.004, 0.05)
	c.k_adult += AGING * maxf(1.0 - c.young / 0.25, 0.0)


## Saves antigos não têm faixas: monta a estrutura na primeira etapa.
static func ensure(c: Country) -> void:
	if c.adult <= 0.0:
		init_country(c)


## Um mês de nascimentos, mortes e envelhecimento. Migração entra por step_world.
static func step_month(c: Country, world: GameWorld) -> void:
	if not c.alive:
		return
	ensure(c)
	var rich := _rich(c.gdp_pc())
	# Ganho de longevidade: a mortalidade dos idosos cai ~1,5% ao ano.
	c.mort_old *= 1.0 - 0.015 * DT
	# Transição demográfica: a natalidade cai devagar quando a renda sobe; guerra e crise adiam filhos.
	var pc_rel := (c.y / maxf(c.pop, 0.001)) / maxf(c.pc0, 0.001)
	var b_target := c.birth0 * pow(clampf(pc_rel, 0.3, 3.0), -0.6)
	b_target *= 1.0 - 0.15 * c.mobilization - 0.15 * maxf(0.4 - c.stability, 0.0)
	c.birth += (maxf(b_target, 0.004) - c.birth) * 0.01
	# Gasto em saúde acima da base alonga a vida; guerra mata adultos.
	var health_extra: float = c.sp_health - float(c.sp0.get("health", c.sp_health))
	var m_old := c.mort_old * clampf(1.0 - 2.0 * health_extra - 0.004 * rich, 0.7, 1.3)
	var war_mort := 0.004 * c.mobilization + 0.01 * c.occupied

	var y_n := c.young * c.pop
	var a_n := c.adult * c.pop
	var o_n := c.old * c.pop
	var born := c.birth * c.pop * DT
	var grow_up := c.k_young * y_n * DT
	var retire := c.k_adult * a_n * DT
	var d_y := MORT_YOUNG * y_n * DT
	var d_a := (MORT_ADULT + war_mort) * a_n * DT
	var d_o := m_old * o_n * DT
	y_n += born - grow_up - d_y
	a_n += grow_up - retire - d_a
	o_n += retire - d_o
	_set_bands(c, y_n, a_n, o_n)
	c.death = (d_y + d_a + d_o) / maxf(c.pop * DT, 0.000001)
	c.popg = c.birth - c.death + c.migration


static func _set_bands(c: Country, y_n: float, a_n: float, o_n: float) -> void:
	var total := maxf(y_n + a_n + o_n, 0.001)
	c.pop = total
	c.young = y_n / total
	c.adult = a_n / total
	c.old = o_n / total


## Território anexado: a população que chega traz a estrutura etária e as taxas de onde veio.
## Chamar antes de somar `pop` em `to.pop`. As bases (adult0, old0, birth0) também se misturam, para
## o trabalho e as aposentadorias não saltarem só porque o país ficou maior.
static func absorb(to: Country, from: Country, pop: float) -> void:
	if pop <= 0.0:
		return
	ensure(to)
	ensure(from)
	var w := pop / maxf(to.pop + pop, 0.001)
	for f: String in ["young", "adult", "old", "adult0", "old0", "birth", "birth0", "death", "k_young", "k_adult", "mort_old"]:
		to.set(f, lerpf(float(to.get(f)), float(from.get(f)), w))


## Oferta de trabalho relativa à população: menos gente em idade ativa, menos trabalhadores.
static func labor_factor(c: Country) -> float:
	if c.adult0 <= 0.0:
		return 1.0
	return c.adult / c.adult0


## Gasto extra (fração do PIB) com aposentadorias por haver mais idosos que no início.
static func pension_extra(c: Country) -> float:
	if c.old0 <= 0.0:
		return 0.0
	return c.sp_social * PENSION_SHARE * (c.old / c.old0 - 1.0)


## Atração de um país para migrantes: renda, paz e estabilidade.
static func _pull(c: Country, world: GameWorld) -> float:
	var v := log(maxf(c.gdp_pc(), 300.0) / 1000.0)
	v += 2.0 * (c.stability - 0.5)
	if world.diplomacy.in_war(c.idx):
		v -= 1.5
	v -= 3.0 * c.occupied
	return v


## Pessoas que entram (positivo) ou saem (negativo) de cada país em um mês, em milhões.
## Taxas por habitante: quem está bem acima da média ponderada atrai, quem está bem abaixo perde;
## a faixa do meio quase não se mexe. Guerra e ocupação somam refugiados. Entradas e saídas
## são escaladas para se compensarem: a migração não mexe na população mundial.
static func _flows(world: GameWorld) -> PackedFloat32Array:
	var n := world.countries.size()
	var pulls := PackedFloat32Array()
	pulls.resize(n)
	var mean := 0.0
	var total := 0.0
	for c: Country in world.countries:
		if not c.alive:
			continue
		ensure(c)
		pulls[c.idx] = _pull(c, world)
		mean += pulls[c.idx] * c.pop
		total += c.pop
	var net := PackedFloat32Array()
	net.resize(n)
	if total <= 0.0:
		return net
	mean /= total
	var out := PackedFloat32Array()
	out.resize(n)
	var inn := PackedFloat32Array()
	inn.resize(n)
	var leaving := 0.0
	var arriving := 0.0
	for c: Country in world.countries:
		if not c.alive:
			continue
		var d: float = pulls[c.idx] - mean
		var dz := signf(d) * maxf(absf(d) - NEUTRAL, 0.0)
		if dz > 0.0:
			inn[c.idx] = minf(dz * RATE_IN, MAX_IN) * c.pop * DT
			arriving += inn[c.idx]
		var rate := maxf(-dz, 0.0) * RATE_OUT + 0.03 * c.occupied
		if world.diplomacy.in_war(c.idx):
			rate += REFUGEES
		if rate > 0.0:
			out[c.idx] = minf(rate, MAX_OUT) * c.pop * DT
			leaving += out[c.idx]
	# Só migra quem tem para onde ir: o lado maior encolhe até igualar o menor.
	var moved := minf(leaving, arriving)
	var s_out := moved / leaving if leaving > 0.0 else 0.0
	var s_in := moved / arriving if arriving > 0.0 else 0.0
	for i in n:
		net[i] = inn[i] * s_in - out[i] * s_out
	return net


## Taxa de migração líquida inicial de cada país, para a natalidade não contar duas vezes o
## crescimento que nos dados já inclui imigrantes.
static func init_world(world: GameWorld) -> void:
	var net := _flows(world)
	for c: Country in world.countries:
		if c.alive:
			init_country(c, net[c.idx] / maxf(c.pop * DT, 0.000001))


## Migração mensal, depois que todos os países fecharam nascimentos e mortes.
static func step_world(world: GameWorld) -> void:
	var net := _flows(world)
	for c: Country in world.countries:
		if not c.alive:
			continue
		var moved: float = net[c.idx]
		# Quem migra é quase sempre adulto em idade de trabalhar.
		_set_bands(c, c.young * c.pop, maxf(c.adult * c.pop + moved, 0.001), c.old * c.pop)
		c.migration += (moved / maxf(c.pop * DT, 0.000001) - c.migration) * 0.2
