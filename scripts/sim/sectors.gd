class_name Sectors
extends RefCounted
## Setores da economia: o PIB dividido em dez atividades. A composição de partida vem da renda
## per capita e da produção de commodities; depois, cada setor reage ao ciclo do seu jeito
## (construção sente o juro, mineração sente o preço do minério, turismo sente a guerra).
## Outros sistemas (portos, aeroportos, empresas) mexem nos setores por `sector_boost`.

const AGRO := 0
const MINING := 1
const INDUSTRY := 2
const CONSTRUCTION := 3
const TRADE := 4
const TRANSPORT := 5
const FINANCE := 6
const TECH := 7
const TOURISM := 8
const PUBLIC := 9
const COUNT := 10
const NAMES := [
	"Agropecuária", "Mineração e energia", "Indústria", "Construção", "Comércio",
	"Transporte e logística", "Serviços financeiros", "Tecnologia e comunicação", "Turismo", "Serviços públicos",
]
## Quanto cada setor amplifica o hiato do produto: construção oscila muito, serviço público quase nada.
const CYCLE_BETA := [0.3, 0.5, 1.5, 2.5, 1.2, 1.3, 1.4, 1.0, 1.8, 0.0]
## A composição estrutural muda devagar: uma fração por ano em direção ao que a renda pede.
const STRUCTURAL_PACE := 0.03


## Composição "natural" para a renda e a dotação de recursos do país, somando 1.
static func structural_shares(c: Country, world: GameWorld) -> PackedFloat32Array:
	var pc := maxf(c.gdp_pc(), 300.0)
	var gdp := maxf(c.y_usd(), 0.001)
	var m := world.markets
	var rich := clampf(log(pc / 3000.0) / 3.0, 0.0, 1.0)
	var v := PackedFloat32Array()
	v.resize(COUNT)
	var grain := m.value_usd(Markets.GRAIN, c.prod[Markets.GRAIN] * c.prod_factor[Markets.GRAIN]) / gdp
	var extract := 0.0
	for i: int in [Markets.OIL, Markets.GAS, Markets.METAL]:
		extract += m.value_usd(i, c.prod[i] * c.prod_factor[i]) / gdp
	var chips := m.value_usd(Markets.CHIP, c.prod[Markets.CHIP] * c.prod_factor[Markets.CHIP]) / gdp
	v[AGRO] = clampf(0.30 * pow(pc / 1000.0, -0.6) + 0.5 * grain, 0.006, 0.45)
	v[MINING] = clampf(0.015 + 0.55 * extract, 0.01, 0.55)
	v[INDUSTRY] = clampf(0.10 + 0.08 * exp(-pow(log(pc / 12000.0), 2.0) / 2.0) + 0.6 * chips, 0.05, 0.35)
	v[CONSTRUCTION] = 0.055 + 0.25 * (c.inv_share0 - 0.2)
	v[TRADE] = 0.12
	v[TRANSPORT] = 0.045 + 0.04 * clampf(c.x_share, 0.0, 1.0)
	v[FINANCE] = 0.025 + 0.055 * rich
	v[TECH] = 0.01 + 0.06 * rich + 0.3 * chips
	v[TOURISM] = 0.025 + 0.01 * (1.0 - rich)
	v[PUBLIC] = clampf(0.6 * (c.sp_health + c.sp_education + c.sp_admin) + 0.3 * c.sp_defense, 0.04, 0.25)
	var total := 0.0
	for x in v:
		total += maxf(x, 0.002)
	for i in COUNT:
		v[i] = maxf(v[i], 0.002) / total
	return v


static func init_country(c: Country, world: GameWorld) -> void:
	c.sector_base = structural_shares(c, world)
	c.sector_share = c.sector_base.duplicate()
	c.sector_out = PackedFloat32Array()
	c.sector_out.resize(COUNT)
	for i in COUNT:
		c.sector_out[i] = c.y * c.sector_share[i]
	if c.sector_boost.size() != COUNT:
		c.sector_boost = PackedFloat32Array()
		c.sector_boost.resize(COUNT)
	c.sector_drought = 0.0


## Ganho de produtividade agregado dos impulsos setoriais: a Economia multiplica o potencial por (1 + isto).
static func boost_total(c: Country) -> float:
	if c.sector_boost.size() != COUNT or c.sector_share.size() != COUNT:
		return 0.0
	var t := 0.0
	for i in COUNT:
		t += c.sector_share[i] * c.sector_boost[i]
	return t


## Desvios específicos de cada setor neste mês, em fração do produto do setor.
static func _specific(c: Country, world: GameWorld) -> PackedFloat32Array:
	var m := world.markets
	var s := PackedFloat32Array()
	s.resize(COUNT)
	var energy := 0.5 * (log(m.relative_price(Markets.OIL, world)) + log(m.relative_price(Markets.METAL, world)))
	s[AGRO] = 0.25 * log(m.relative_price(Markets.GRAIN, world)) - c.sector_drought
	s[MINING] = 0.35 * energy
	s[INDUSTRY] = -0.15 * maxf(log(m.relative_price(Markets.CHIP, world)), 0.0) + 0.3 * clampf(c.ext_demand, -0.2, 0.2) * clampf(c.x_share, 0.0, 1.0)
	var infra_extra: float = c.sp_infra - float(c.sp0.get("infra", c.sp_infra))
	s[CONSTRUCTION] = -1.5 * c.rgap + 3.0 * infra_extra + 0.8 * clampf(c.credit_gap, -0.15, 0.2)
	s[TRADE] = 0.3 * clampf(c.conf - 0.6, -0.4, 0.4) * 0.2
	s[TRANSPORT] = 0.4 * clampf(c.ext_demand, -0.2, 0.2) + 0.5 * c.trade_loss
	s[FINANCE] = 0.6 * clampf(c.credit_gap, -0.15, 0.2) - 1.0 * clampf(c.risk - c.risk0, 0.0, 0.2)
	s[TECH] = 0.5 * (c.human - 1.0)
	var war := 0.25 if world.diplomacy.in_war(c.idx) else 0.0
	s[TOURISM] = -war - 0.4 * c.unrest - 0.3 * maxf(world.global_risk - 0.2, 0.0) - 0.5 * c.occupied
	s[PUBLIC] = 0.6 * (c.spend_total() - c.g_ref)
	return s


## Etapa mensal: depois que a Economia fechou o PIB do mês, reparte-o entre os setores.
static func step_month(c: Country, world: GameWorld) -> void:
	if c.sector_share.size() != COUNT:
		init_country(c, world)
	if world.month == 0:
		var target := structural_shares(c, world)
		for i in COUNT:
			c.sector_base[i] += (target[i] - c.sector_base[i]) * STRUCTURAL_PACE
	# Secas e quebras de safra: raras, curtas e mais prováveis onde a agricultura pesa mais.
	c.sector_drought *= 0.8
	if world.rng.randf() < 0.004:
		c.sector_drought = world.rng.randf_range(0.08, 0.25)
		if c == world.player:
			world.emit_news("Quebra de safra em %s: a agropecuária encolhe." % c.name, "economia", c)
	var spec := _specific(c, world)
	var weights := PackedFloat32Array()
	weights.resize(COUNT)
	var total := 0.0
	for i in COUNT:
		var w := c.sector_base[i] * maxf(1.0 + float(CYCLE_BETA[i]) * c.gap + clampf(spec[i], -0.5, 0.4) + c.sector_boost[i], 0.05)
		weights[i] = w
		total += w
	# A soma dos setores fecha no PIB. Cada setor se ajusta aos poucos, para não pular de um mês para outro.
	for i in COUNT:
		var share := weights[i] / total
		c.sector_share[i] += (share - c.sector_share[i]) * 0.25
	var norm := 0.0
	for i in COUNT:
		norm += c.sector_share[i]
	for i in COUNT:
		c.sector_share[i] /= norm
		c.sector_out[i] = c.y * c.sector_share[i]
	if c == world.player:
		for i in COUNT:
			c.push_hist("sec_%d" % i, c.sector_out[i])


## Crescimento em 12 meses do produto real do setor (só o país do jogador guarda a série).
static func growth_of(c: Country, i: int) -> float:
	var s: PackedFloat32Array = c.hist.get("sec_%d" % i, PackedFloat32Array())
	if s.size() < 13:
		return c.growth_yoy()
	return s[s.size() - 1] / maxf(s[s.size() - 13], 0.0001) - 1.0


## PIB do setor em US$ bi correntes.
static func output_usd(c: Country, i: int) -> float:
	return c.y_usd() * c.sector_share[i]
