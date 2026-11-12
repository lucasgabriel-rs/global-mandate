class_name Economy
extends RefCounted
## Modelo macroeconômico semiestrutural: oferta de Solow (capital, trabalho, capital humano, PTF),
## hiato do produto com demanda agregada, curva de Phillips com expectativas parcialmente
## ancoradas, regra de Taylor, paridade de juros/PPC no câmbio, restrição orçamentária e dívida
## com prêmio de risco endógeno, balanço de pagamentos e ciclo de crédito.

const ALPHA := 0.36
const DELTA := 0.05
const DT := 1.0 / 12.0
## Democracias consolidadas e a zona do euro têm banco central independente; o resto responde ao governo.
const CB_INDEPENDENT_DEM := 6.0
const KY := 3.0
const OKUN := 0.40
const KAPPA := 0.30
const MAX_RATE := 1.2
const RATINGS := ["AAA", "AA", "A", "BBB", "BB", "B", "CCC", "CC"]
## Economias acima desta fatia do PIB mundial viram notícia quando entram em recessão ou mudam de nota.
const NEWS_SHARE := 0.02


static func init_country(c: Country, row: Dictionary, world: GameWorld) -> void:
	var gdp: float = row.gdp
	c.y = gdp
	c.y0 = gdp
	c.y_pot = gdp
	c.pop = row.pop
	c.popg = row.popg / 100.0
	c.g0 = row.g / 100.0
	c.labor = c.pop
	c.capital = KY * gdp
	c.human = 1.0
	c.gap = 0.0
	c.tfp = gdp / (pow(c.capital, ALPHA) * pow(c.labor, 1.0 - ALPHA))
	c.pc0 = gdp / c.pop
	# PTF inicial implícita na tendência: em estado estacionário K cresce como Y.
	c.g_tfp0 = maxf((1.0 - ALPHA) * (c.g0 - c.popg), -0.01)
	c.inv_share0 = (DELTA + c.g0) * KY

	var pc: float = c.pc0 * 1000.0
	var advanced := pc > 24000.0
	var infl: float = row.infl / 100.0
	c.pi_target = 0.02 if advanced else (0.03 if pc > 8000.0 else 0.05)
	c.pi_core = clampf(infl, -0.01, 3.0)
	c.pi_yoy = infl
	c.pi_e = lerpf(infl, c.pi_target, 0.5)
	c.cred = clampf(0.25 + 0.06 * c.dem + (0.2 if advanced else 0.0) - 0.6 * maxf(infl - 0.1, 0.0), 0.15, 0.95)
	c.rate = row.rate / 100.0
	c.rate_set = c.rate
	# Juro neutro: tendência de crescimento, mais o prêmio que cada país já paga hoje.
	c.r_n = 0.007 + 0.35 * c.g0 if advanced else 0.012 + 0.35 * c.g0
	if infl < 0.15:
		c.r_n = clampf(lerpf(c.r_n, c.rate - c.pi_e, 0.5), 0.003, 0.06)
	c.rgap = clampf(c.rate - c.pi_e - c.r_n, -0.05, 0.08)
	c.p_hist = PackedFloat32Array()
	for i in 13:
		c.p_hist.append(pow(1.0 + clampf(infl, -0.1, 3.0), float(i - 12) / 12.0))

	c.unemp = row.unemp / 100.0
	c.unemp_n = c.unemp
	c.dem = row.dem
	c.peg = row.peg
	c.cb_independent = c.dem >= CB_INDEPENDENT_DEM or c.peg == 2
	c.reserves = maxf(row.res, 0.1)
	c.nukes = row.nukes
	c.troops = maxf(row.troops, 0.5)
	c.troops0 = c.troops
	c.aggression = clampf(0.65 - 0.07 * c.dem, 0.03, 0.65)

	# Commodities
	c.prod = PackedFloat32Array([row.oil, row.gas, row.grain, row.metal, row.chip])
	c.use = PackedFloat32Array([0, 0, 0, 0, 0])

	var rev: float = row.rev / 100.0
	var mil: float = row.mil / 100.0
	c.debt_ratio = row.debt / 100.0
	var reserve_currency: bool = c.iso in ["USA", "JPN", "GBR", "CHE"] or c.peg == 2
	var fx_share := 0.0 if reserve_currency else (0.05 if advanced else clampf(0.55 - pc / 40000.0, 0.15, 0.55))
	c.debt_fx = gdp * c.debt_ratio * fx_share
	c.debt_loc = gdp * c.debt_ratio * (1.0 - fx_share)
	var tol := 0.95 if advanced else (0.6 if pc > 8000.0 else 0.45)
	if c.iso == "USA":
		tol = 1.4
	c.debt_tol = maxf(tol, c.debt_ratio * 0.92)
	c.avg_rate = clampf(c.rate * 0.6 + 0.02, 0.005, 0.25)
	if c.iso == "JPN":
		c.avg_rate = 0.008
	# Dívida concessional: o serviço inicial não passa de ~1/4 da receita.
	c.avg_rate = minf(c.avg_rate, 0.25 * rev / maxf(c.debt_ratio, 0.01))

	var target_deficit: float = row.def / 100.0
	var interest_gdp := c.avg_rate * c.debt_ratio
	var primary := maxf(rev + target_deficit - interest_gdp - mil, 0.03)
	c.sp_defense = mil
	c.sp_social = primary * 0.42
	c.sp_health = primary * 0.20
	c.sp_education = primary * 0.16
	c.sp_infra = primary * 0.10
	c.sp_admin = primary * 0.12
	c.sp0 = {
		"social": c.sp_social, "health": c.sp_health, "education": c.sp_education,
		"infra": c.sp_infra, "defense": c.sp_defense, "admin": c.sp_admin,
	}
	c.tax_income = rev * 0.45
	c.tax_consumption = rev * 0.38
	c.tax_corporate = rev * 0.17
	c.tax0 = rev
	c.g_ref = c.spend_total()
	c.t_ref = rev

	c.ca0 = row.ca / 100.0
	c.x_share = row.exp / 100.0
	c.stability = clampf(0.25 + 0.035 * c.dem + 0.08 * log(maxf(pc, 400.0) / 400.0), 0.15, 0.95)
	c.approval = clampf(0.47 + world.rng.randf_range(-0.07, 0.07), 0.2, 0.75)
	c.inequality = clampf(0.47 - 0.012 * c.dem - 0.000001 * pc, 0.24, 0.55)
	c.inequality0 = c.inequality
	c.next_election = world.year_float() + world.rng.randf_range(0.2, 4.0)
	c.conf = 0.6
	c.mil_stock = _mil_stock_init(c, gdp * mil, pc)
	var score := _risk_premium(c, world)
	c.risk = score
	c.risk0 = score
	c.yield_gov = c.rate + 0.005 + score
	c.avg_fx = minf(0.045 + score, c.avg_rate * 1.0 if c.avg_rate < 0.045 else 0.09)
	if pc < 12000.0:
		c.yield_mult = clampf(c.avg_rate / maxf(c.yield_gov, 0.001), 0.4, 1.0)


static func _mil_stock_init(_c: Country, spend: float, pc: float) -> float:
	# Ajuste PPC: países de renda baixa compram mais poder militar por dólar.
	var ppp := clampf(pow(60000.0 / maxf(pc, 500.0), 0.35), 1.0, 3.0)
	return maxf(spend * ppp * 0.35 / 0.06, 0.1)


## Completa o setor externo depois que os mercados de commodities foram montados.
static func finish_init(c: Country, world: GameWorld) -> void:
	var m := world.markets
	var gdp := c.y
	var comm_x := 0.0
	var comm_m := 0.0
	for i in 5:
		var net := c.prod[i] - c.use[i]
		if net > 0.0:
			comm_x += m.value_usd(i, net)
		else:
			comm_m += m.value_usd(i, -net)
	# A tabela é aproximada: nunca deixa as exportações não-commodity abaixo de 2% do PIB.
	var total_x := maxf(c.x_share * gdp, comm_x + 0.02 * gdp)
	var x_nc := total_x - comm_x
	var m_total := total_x - c.ca0 * gdp
	var m_nc := m_total - comm_m
	c.ca_resid = 0.0
	if m_nc < 0.02 * gdp:
		c.ca_resid = (0.02 * gdp - m_nc)
		m_nc = 0.02 * gdp
	c.x_share = x_nc / gdp
	c.m_share = m_nc / gdp
	c.exports = total_x
	c.imports = m_nc + comm_m
	c.ca = c.ca0 * gdp
	c.ca_ratio = c.ca0
	# Parte da receita pública vem de renda de commodities (Golfo, Noruega, Angola...).
	var rent := minf(comm_x * 0.55, c.tax0 * gdp * 0.75)
	c.rent_take = rent / maxf(comm_x, 0.001)
	var new_tax := c.tax0 - rent / gdp
	var k := new_tax / maxf(c.tax0, 0.001)
	c.tax_income *= k
	c.tax_consumption *= k
	c.tax_corporate *= k
	c.tax0 = new_tax
	c.t_ref = new_tax
	c.comm_exports = comm_x
	for i in 5:
		c.p_ref[i] = 1.0
	# As contas do ano e a nota já valem no primeiro dia, antes da primeira etapa mensal.
	_fiscal_flows(c)
	c.rating = _rating_from(c.risk)
	Demography.init_country(c)


static func step_month(c: Country, world: GameWorld) -> void:
	if not c.alive:
		return
	_supply(c, world)
	_demand(c, world)
	_prices(c, world)
	_monetary(c, world)
	_exchange(c, world)
	_external(c, world)
	_fiscal(c, world)
	_labor_and_politics(c, world)
	_credit_cycle(c, world)
	Sectors.step_month(c, world)
	_record(c, world)


static func _supply(c: Country, world: GameWorld) -> void:
	Demography.step_month(c, world)
	# Oferta de trabalho responde à tributação da renda (elasticidade baixa).
	var tax_wedge := clampf((c.tax_income - c.tax0 * 0.45) * 0.25, -0.03, 0.08)
	var labor := c.pop * Demography.labor_factor(c) * (1.0 - tax_wedge) * (1.0 - 0.12 * c.mobilization) * (1.0 + clampf(c.law_labor, -0.1, 0.05))

	var r_effect := clampf(1.0 - 2.5 * c.rgap, 0.5, 1.4)
	var conf_effect := clampf(0.7 + 0.5 * c.conf, 0.6, 1.2)
	var corp_effect := clampf(1.0 - 1.2 * (c.tax_corporate - c.tax0 * 0.17), 0.6, 1.2)
	var infra_extra: float = c.sp_infra - float(c.sp0.get("infra", c.sp_infra))
	var inv_share := c.inv_share0 * r_effect * conf_effect * corp_effect * (1.0 + c.law_invest) + infra_extra * 0.8
	var crowding := clampf(1.0 - 0.15 * maxf(c.debt_ratio / c.debt_tol - 1.0, 0.0), 0.75, 1.0)
	inv_share *= crowding
	c.capital += (inv_share * c.y - DELTA * c.capital) * DT
	c.capital = maxf(c.capital, c.y_pot * 0.8)

	# Convergência: quanto mais rico em relação à própria base, menor o ganho fácil de PTF.
	var pc_rel := (c.y / c.pop) / maxf(c.pc0, 0.001)
	var converge := -0.006 * log(maxf(pc_rel, 0.2))
	var edu_extra: float = c.sp_education - float(c.sp0.get("education", c.sp_education))
	var health_extra: float = c.sp_health - float(c.sp0.get("health", c.sp_health))
	var g_tfp := c.g_tfp0 + converge
	g_tfp += 0.10 * edu_extra + 0.05 * health_extra
	g_tfp += 0.012 * clampf(c.trade_loss, -0.3, 0.2)
	g_tfp -= 0.012 * maxf(0.45 - c.stability, 0.0)
	g_tfp += clampf(c.law_tfp, -0.01, 0.01)
	# A desigualdade anda devagar até a base do país mais o que as leis empurram.
	c.inequality += (clampf(c.inequality0 + c.law_inequality, 0.2, 0.65) - c.inequality) * 0.02
	c.human *= 1.0 + clampf(0.15 * edu_extra, -0.004, 0.006) * DT
	c.tfp *= 1.0 + g_tfp * DT
	c.damage = maxf(c.damage - 0.05 * DT * c.damage - 0.01 * DT, 0.0)
	var base := c.tfp * pow(c.capital, ALPHA) * pow(c.human * labor, 1.0 - ALPHA)
	c.y_pot = base * (1.0 - c.occupied * 0.85) * (1.0 - c.damage) * (1.0 + c.supply_shock) * (1.0 + Sectors.boost_total(c))
	c.supply_shock *= 0.97


static func _demand(c: Country, world: GameWorld) -> void:
	var m := world.markets
	# Política monetária atua com defasagem (média móvel de ~9 meses do juro real).
	var r := c.rate - c.pi_e
	c.rgap += (clampf(r - c.r_n, -0.08, 0.15) - c.rgap) * 0.11
	var monetary := -0.45 * c.rgap

	# Impulso fiscal: efeito da VARIAÇÃO da postura; a referência se adapta em ~2 anos.
	var g := c.spend_total() + c.mobilization * 0.02 + c.law_spend
	var t := c.tax_total() + c.law_tax
	var mult_g := 0.9 if c.gap < -0.01 else 0.5
	var debt_drag := clampf(1.0 - 0.5 * maxf(c.debt_ratio / c.debt_tol - 1.0, 0.0), 0.3, 1.0)
	var fiscal := (mult_g * (g - c.g_ref) - 0.45 * (t - c.t_ref)) * debt_drag
	c.g_ref += (g - c.g_ref) * 0.04
	c.t_ref += (t - c.t_ref) * 0.04

	# Demanda externa ponderada pelos parceiros reais + atritos de comércio.
	var trade := world.diplomacy.trade_channel(c, world)
	c.ext_demand = trade.x
	c.trade_loss += (float(trade.loss) - c.trade0 - c.trade_loss) * 0.08
	var openness := clampf(c.x_share, 0.0, 1.0)
	# Portos e aeroportos saturados (logistics < 1) travam parte do comércio exterior.
	var ext := openness * (1.1 * c.ext_demand + 0.8 * c.trade_loss + 0.3 * clampf(c.logistics - 1.0, -0.4, 0.2))
	var rer_effect := clampf(0.5 * openness * log(c.rer / c.rer_ref), -0.06, 0.06)
	c.rer_ref += (c.rer - c.rer_ref) * 0.01

	# Termos de troca: variação de preço ponderada pela posição líquida em cada commodity.
	var tot := 0.0
	for i in 5:
		var rel := m.relative_price(i, world)
		var net_val: float = m.value_usd(i, (c.prod[i] * c.prod_factor[i] - c.use[i])) / m.price[i] * float(Markets.P0[i])
		c.p_ref[i] += (rel - c.p_ref[i]) * 0.012
		tot += net_val / maxf(c.y0 * (c.y / c.y0), 0.001) * (rel - c.p_ref[i])
	tot = clampf(tot * 0.45, -0.08, 0.1)
	# Escassez de chips e energia é choque de oferta mesmo para quem tem saldo neutro.
	var shortage := -0.012 * maxf(log(maxf(m.relative_price(Markets.CHIP, world) / c.p_ref[Markets.CHIP], 0.1)), 0.0)
	shortage -= 0.012 * maxf(log(maxf(m.relative_price(Markets.OIL, world) / c.p_ref[Markets.OIL], 0.1)), 0.0)

	var confidence := 0.05 * (c.conf - 0.6)
	var credit := 0.25 * clampf(c.credit_gap, -0.15, 0.2) * 0.3
	var risk_drag := -0.3 * clampf(c.risk - c.risk0, 0.0, 0.15)
	c.demand_shock *= 0.965
	c.noise += -c.noise * 0.08 + world.rng.randfn(0.0, 0.0022)

	var target := monetary + fiscal + ext + rer_effect + tot + shortage + confidence + credit + risk_drag + c.demand_shock
	# O juro neutro já inclui a tendência; hiato positivo não se sustenta sem estímulo.
	c.gap += (clampf(target, -0.4, 0.12) - c.gap) * 0.13 + c.noise * 0.35
	c.gap = clampf(c.gap, -0.45, 0.13)
	c.y = c.y_pot * (1.0 + c.gap)


static func _prices(c: Country, world: GameWorld) -> void:
	var m := world.markets
	# Âncora de expectativas: mistura meta crível com inflação observada.
	var anchor := c.cred * c.pi_target + (1.0 - c.cred) * c.pi_yoy
	c.pi_e += (anchor - c.pi_e) * 0.09
	var mon_push := 0.0
	if c.mon_fin > 0.0 or world.year_float() < c.default_until:
		var financed := c.mon_fin if world.year_float() >= c.default_until else maxf(c.mon_fin, 0.5)
		mon_push = 2.2 * financed * maxf(c.deficit / maxf(c.y_nominal(), 0.001), 0.0)
	var core_target := c.pi_e + KAPPA * c.gap + mon_push + 0.08 * maxf(c.occupied - c.occ0, 0.0) + 0.04 * c.unrest
	c.pi_core += (clampf(core_target, -0.03, 6.0) - c.pi_core) * 0.11
	# Inflação em moeda dos insumos importados passa ao índice como choque de nível.
	var poor := clampf(1.0 - c.gdp_pc() / 30000.0, 0.0, 1.0)
	# Peso da matéria-prima no índice: repasse parcial ao varejo, maior em países pobres.
	var w_energy := 0.025
	var w_food := 0.015 + 0.07 * poor
	var hist_oil: float = c.hist.get("_poil", m.price[Markets.OIL])
	var hist_food: float = c.hist.get("_pfood", m.price[Markets.GRAIN])
	var d_oil := log(m.price[Markets.OIL] / hist_oil)
	var d_food := log(m.price[Markets.GRAIN] / hist_food)
	c.hist["_poil"] = m.price[Markets.OIL]
	c.hist["_pfood"] = m.price[Markets.GRAIN]
	var e_last: float = c.hist.get("_e", c.e)
	var depr := log(c.e / e_last)
	c.hist["_e"] = c.e
	# Só a depreciação acima da paridade de poder de compra gera repasse adicional.
	var ppp_trend := (log(1.0 + c.pi_core) - log(1.0 + world.usa.pi_core)) * DT
	var openness := clampf(c.m_share + 0.08, 0.05, 0.7)
	var passthrough := 0.35 * openness / 0.3
	var shock := w_energy * d_oil + w_food * d_food + clampf(passthrough, 0.05, 0.5) * (depr - ppp_trend)
	var one_off: float = float(c.hist.get("_oneoff", 0.0))
	c.hist["_oneoff"] = 0.0
	c.p *= exp(log(1.0 + c.pi_core) * DT + shock + one_off)
	c.p_hist.append(c.p)
	if c.p_hist.size() > 13:
		c.p_hist = c.p_hist.slice(c.p_hist.size() - 13)
	c.pi_yoy = c.p / c.p_hist[0] - 1.0
	# Credibilidade se ganha devagar e se perde rápido.
	var miss := absf(c.pi_yoy - c.pi_target)
	var d_cred := 0.004 if miss < 0.015 else -clampf((miss - 0.015) * 0.03, 0.0, 0.015)
	d_cred -= c.mon_fin * 0.015
	# Plano de estabilização: juro real alto com recessão sinaliza compromisso.
	if c.pi_yoy > 0.2 and c.rate - c.pi_e > 0.03:
		d_cred += 0.012
	c.cred = clampf(c.cred + d_cred, 0.08, 0.97)


static func _monetary(c: Country, world: GameWorld) -> void:
	if c.peg == 2:
		c.rate = world.ecb_rate
		return
	if c.peg == 1 and c != world.usa:
		c.rate = clampf(world.usa.rate + maxf(c.risk, 0.0) * 0.8 + 0.005, 0.0, MAX_RATE)
		return
	if c.rate_manual and not c.cb_independent:
		c.rate += (c.rate_set - c.rate) * 0.5
		return
	var target := c.r_n + c.pi_e + 0.6 * (c.pi_yoy - c.pi_target) + 0.5 * c.gap
	target = clampf(target, 0.0, MAX_RATE)
	c.rate += (target - c.rate) * 0.14


static func _exchange(c: Country, world: GameWorld) -> void:
	var us := world.usa
	if c == us:
		c.e = 1.0
		c.rer = 1.0
		return
	if c.peg == 2:
		c.e = world.eur_rate
	elif c.peg == 0:
		var rd := (c.rate - c.pi_e - c.r_n) - (us.rate - us.pi_e - us.r_n)
		var ppp := log(c.p / us.p)
		var target := ppp - 1.1 * clampf(rd, -0.15, 0.2) - 0.7 * clampf(c.ca_ratio - c.ca0, -0.2, 0.2)
		target += 1.6 * clampf(c.risk - c.risk0, -0.03, 0.4) + 0.6 * clampf(world.global_risk - 0.2, -0.2, 0.8) * (0.0 if c.debt_tol > 0.9 else 0.25)
		var le := log(c.e)
		le += (target - le) * 0.10 + world.rng.randfn(0.0, 0.006)
		c.e = exp(le)
	c.rer = c.e * us.p / c.p


static func _external(c: Country, world: GameWorld) -> void:
	var m := world.markets
	var yusd := c.y_usd()
	var rer_log := clampf(log(c.rer), -1.0, 1.0)
	var x_nc := c.x_share * yusd * (1.0 + 0.6 * rer_log) * (1.0 + 1.2 * c.ext_demand) * (1.0 + clampf(c.trade_loss, -0.9, 0.5))
	var tariff_cut := clampf(1.0 - 1.6 * c.tariff, 0.3, 1.0)
	var m_nc := c.m_share * yusd * (1.0 - 0.5 * rer_log) * (1.0 + 1.3 * c.gap) * tariff_cut * (1.0 + 0.5 * clampf(c.trade_loss, -0.9, 0.5))
	var comm_x := 0.0
	var comm_m := 0.0
	var sanctions_disc := 1.0 - 0.25 * world.diplomacy.sanction_pressure(c)
	for i in 5:
		var demand_i := c.use[i] * pow(c.y / c.y0, Markets.INCOME_ELAST[i])
		var net := c.prod[i] * c.prod_factor[i] - demand_i
		if net > 0.0:
			comm_x += m.value_usd(i, net) * sanctions_disc
		else:
			comm_m += m.value_usd(i, -net)
	c.comm_exports = comm_x
	c.exports = x_nc + comm_x
	c.imports = m_nc + comm_m
	var fx_interest := c.debt_fx * c.avg_fx
	c.ca = c.exports - c.imports - fx_interest * 0.6 + c.ca_resid * (yusd / maxf(c.y0, 0.001)) + c.aid_flow - c.reparations
	c.ca_ratio = c.ca / maxf(yusd, 0.001)

	# Reservas: âncora absorve o balanço; flutuante intervém pouco.
	var cap_flow := 0.0
	if c.peg == 1:
		cap_flow = clampf((c.rate - world.usa.rate - c.risk * 0.5) * 2.0, -0.08, 0.08) * yusd
		c.reserves += (c.ca + cap_flow) * 0.5 * DT
	elif c.peg == 0:
		# Flutuante: o câmbio e o capital estrangeiro fecham o balanço. O banco central guarda parte dos
		# superávits e só queima reservas quando o capital foge (risco acima do de partida).
		var flight := clampf((c.risk - c.risk0) * 8.0, 0.0, 1.0)
		c.reserves += c.ca * 0.08 * (1.0 if c.ca > 0.0 else flight) * DT
	c.reserves = maxf(c.reserves, 0.0)
	if c.peg == 1 and c.reserves < c.imports / 12.0 * 0.7 and c.ca < 0.0:
		_break_peg(c, world)


static func _break_peg(c: Country, world: GameWorld) -> void:
	c.peg = 0
	var devaluation := world.rng.randf_range(1.3, 1.8)
	c.e *= devaluation
	c.conf = maxf(c.conf - 0.2, 0.1)
	c.demand_shock -= 0.03
	world.emit_news(TranslationServer.translate("%s abandona a âncora cambial: moeda desvaloriza %d%%.") % [c.name, int((devaluation - 1.0) * 100.0)], "crise", c)


static func _fiscal(c: Country, world: GameWorld) -> void:
	var yn := c.y_nominal()
	_fiscal_flows(c)

	var no_market := world.year_float() < c.default_until
	var financed_by_cb := c.mon_fin
	if no_market and c.deficit > 0.0:
		financed_by_cb = maxf(financed_by_cb, 0.7)
	var new_debt := c.deficit * DT * (1.0 - clampf(financed_by_cb, 0.0, 1.0)) if c.deficit > 0.0 else c.deficit * DT
	var fx_part := 0.0
	if c.debt_fx + c.debt_loc * 0.0 > 0.0:
		fx_part = c.debt_fx * c.e / maxf(c.debt_fx * c.e + c.debt_loc, 0.001)
	c.debt_loc += new_debt * (1.0 - fx_part)
	c.debt_fx += new_debt * fx_part / maxf(c.e, 0.001)
	if c.debt_loc < 0.0:
		c.debt_loc = 0.0
	if c.debt_fx < 0.0:
		c.debt_fx = 0.0
	c.debt_ratio = (c.debt_loc + c.debt_fx * c.e) / maxf(yn, 0.001)

	c.risk = _risk_premium(c, world)
	c.yield_gov = c.rate + 0.005 + c.risk
	# Dívida rola em ~6 anos: o custo médio segue o rendimento de mercado com atraso.
	c.avg_rate += (c.yield_gov * c.yield_mult - c.avg_rate) * DT / 6.0
	c.avg_fx += ((world.usa.rate + 0.005 + minf(c.risk, 0.25)) * c.yield_mult - c.avg_fx) * DT / 6.0
	var old_rating := c.rating
	c.rating = _rating_for(c)
	if c.rating != old_rating and old_rating != "D" and world.year_float() >= c.default_until and _newsworthy(c, world):
		var down := RATINGS.find(c.rating) > RATINGS.find(old_rating)
		var rating_news: String = TranslationServer.translate("Agências rebaixam a nota de crédito de %s de %s para %s.") if down else TranslationServer.translate("Agências elevam a nota de crédito de %s de %s para %s.")
		world.emit_news(rating_news % [c.name, old_rating, c.rating], "crise" if down and c == world.player else "economia", c)
	_check_default(c, world)


## Receita, gasto, juros e déficit do ano, a partir das alíquotas e do gasto em vigor. Consome o dinheiro
## avulso do mês (normas, estatais, obras).
static func _fiscal_flows(c: Country) -> void:
	var yn := c.y_nominal()
	var yn_pot := c.y_pot * c.p
	var tax_rate := c.tax_total()
	# Curva de Laffer: acima de ~48% a evasão corrói a arrecadação. Elasticidade cíclica de 1,1.
	var collection := clampf(1.0 - 2.2 * maxf(tax_rate - 0.48, 0.0) ** 1.3, 0.55, 1.0) * (1.0 - clampf(c.law_evasion, -0.05, 0.3))
	var tax_rev := tax_rate * yn * (1.0 + 0.1 * c.gap) * collection
	var rent := c.comm_exports * c.e * c.rent_take
	var tariff_rev := c.tariff * c.imports * c.e * 0.7
	c.revenue = tax_rev + rent + tariff_rev + c.aid_flow * c.e * 0.85 + (c.law_rev_bucket + c.extra_rev_bucket) * 12.0 * c.e

	var prog := yn_pot * (c.sp_health + c.sp_education + c.sp_infra + c.sp_defense + c.sp_admin)
	# Estabilizador automático: gasto social sobe quando há desemprego.
	var social := c.sp_social * yn_pot * (1.0 + 2.0 * clampf(c.unemp - c.unemp_n, -0.03, 0.2))
	# Aposentadorias: mais idosos que no início pesam no gasto social.
	social += Demography.pension_extra(c) * yn_pot
	var war_cost := c.mobilization * 0.035 * yn_pot
	c.interest = c.debt_loc * c.avg_rate + c.debt_fx * c.e * c.avg_fx
	c.spending = prog + social + war_cost + c.interest + c.reparations * c.e + (c.law_spend_bucket + c.extra_spend_bucket) * 12.0 * c.e
	c.law_rev_bucket = 0.0
	c.law_spend_bucket = 0.0
	c.extra_rev_bucket = 0.0
	c.extra_spend_bucket = 0.0
	c.deficit = c.spending - c.revenue


static func _risk_premium(c: Country, world: GameWorld) -> float:
	var ratio := c.debt_ratio / maxf(c.debt_tol, 0.1)
	var r := 0.003
	r += 0.03 * maxf(ratio - 0.75, 0.0) ** 2 * 4.0
	var yn := maxf(c.y_nominal(), 0.001)
	r += 0.25 * maxf(c.deficit / yn - 0.04, 0.0)
	r += 0.04 * maxf(0.5 - c.stability, 0.0)
	var cover := c.reserves / maxf(c.imports / 12.0, 0.001)
	r += 0.006 * maxf(3.0 - cover, 0.0) * (0.0 if c.peg == 2 else 1.0)
	var pc := c.gdp_pc()
	var ems := clampf(1.0 - pc / 30000.0, 0.0, 1.0)
	r += ems * (0.012 + 0.05 * world.global_risk)
	if c.interest > 0.0:
		r += 0.05 * maxf(c.interest / maxf(c.revenue, 0.001) - 0.25, 0.0)
	if world.year_float() < c.default_until:
		r += 0.08
	if c.iso == "USA":
		r *= 0.4
	return clampf(r, 0.0, 0.6)


## A nota só muda quando o risco passa do limite com folga de 20%: agências não oscilam todo mês, e
## um país perto de um limite não troca de nota a cada solavanco do risco global.
static func _rating_for(c: Country) -> String:
	var now := RATINGS.find(c.rating)
	if now < 0:
		return _rating_from(c.risk)
	var worse := RATINGS.find(_rating_from(c.risk * 0.8))
	if worse > now:
		return RATINGS[worse]
	var better := RATINGS.find(_rating_from(c.risk * 1.2))
	if better < now:
		return RATINGS[better]
	return c.rating


static func _rating_from(s: float) -> String:
	if s < 0.006: return "AAA"
	if s < 0.012: return "AA"
	if s < 0.02: return "A"
	if s < 0.035: return "BBB"
	if s < 0.06: return "BB"
	if s < 0.11: return "B"
	if s < 0.2: return "CCC"
	return "CC"


static func _check_default(c: Country, world: GameWorld) -> void:
	if world.year_float() < c.default_until:
		return
	# Juro real sobre a receita: inflação corrói a dívida local, e isso conta.
	var erosion := maxf(c.pi_yoy, 0.0) * c.debt_loc
	var burden := maxf(c.interest - erosion, 0.0) / maxf(c.revenue, 0.001)
	var fx_ratio := c.debt_fx * c.e / maxf(c.y_nominal(), 0.001)
	var trigger := burden > 0.55 or (c.risk > 0.3 and fx_ratio > 0.3) or (c.debt_ratio > c.debt_tol * 2.4 and c.risk > 0.15)
	var insolvent := c.debt_ratio > maxf(c.debt_tol * 3.0, 2.0) and c.iso != "JPN"
	if insolvent and c != world.governed():
		apply_default(c, world)
		return
	if not trigger or c.imf_program > 0.0:
		return
	if c == world.governed():
		world.offer_imf(c)
		return
	var roll := world.rng.randf()
	if roll < 0.04:
		apply_default(c, world)
	elif roll < 0.12:
		apply_imf(c, world)


static func apply_default(c: Country, world: GameWorld) -> void:
	c.debt_loc *= 0.55
	c.debt_fx *= 0.55
	c.default_until = world.year_float() + 3.0
	c.demand_shock -= 0.09
	c.conf = maxf(c.conf - 0.25, 0.05)
	c.cred = maxf(c.cred - 0.2, 0.08)
	c.approval = maxf(c.approval - 0.15, 0.03)
	c.stability = maxf(c.stability - 0.12, 0.03)
	c.rating = "D"
	world.global_risk = clampf(world.global_risk + 0.25 * sqrt(c.y_usd() / world.world_gdp()) + 0.02, 0.0, 1.0)
	world.emit_news(TranslationServer.translate("%s declara moratória da dívida soberana; credores aceitam corte de 45%%.") % c.name, "crise", c)


static func apply_imf(c: Country, world: GameWorld) -> void:
	var loan := c.y_usd() * 0.08
	c.reserves += loan
	c.debt_fx += loan * 0.6
	# Parte do programa reestrutura dívida antiga e reduz o peso de juros.
	c.debt_loc *= 0.92
	c.debt_fx *= 0.92
	c.yield_mult = maxf(c.yield_mult * 0.8, 0.35)
	c.avg_rate *= 0.85
	c.imf_program = 36.0
	# Condicionalidade: ajuste fiscal e câmbio flutuante.
	c.sp_social *= 0.94
	c.sp_admin *= 0.9
	c.sp_infra *= 0.92
	c.tax_consumption += 0.01
	c.mon_fin = 0.0
	c.conf = minf(c.conf + 0.08, 1.0)
	c.approval = maxf(c.approval - 0.08, 0.03)
	world.emit_news(TranslationServer.translate("FMI aprova pacote de US$ %.0f bi para %s, com ajuste fiscal.") % [loan, c.name], "economia", c)


static func _labor_and_politics(c: Country, world: GameWorld) -> void:
	var u_target := c.unemp_n + c.law_unemp - OKUN * c.gap + 0.25 * c.mobilization * -0.1
	c.unemp += (clampf(u_target, 0.005, 0.5) - c.unemp) * 0.1
	# Histerese: desemprego prolongado eleva a taxa natural.
	c.unemp_n += (c.unemp - c.unemp_n) * 0.002

	if c.imf_program > 0.0:
		c.imf_program -= 1.0

	var growth := c.growth_yoy()
	var infl_pain := clampf(c.pi_yoy - maxf(c.pi_target, 0.02) - 0.01, 0.0, 0.8)
	var u_pain := clampf(c.unemp - c.unemp_n, -0.03, 0.2)
	var growth_good := clampf(growth - c.g0 * 0.8, -0.12, 0.05)
	var tax_pain := maxf(c.tax_total() + c.law_tax - c.tax0, 0.0)
	var social_good: float = c.sp_social + c.sp_health + c.sp_education
	social_good -= float(c.sp0.get("social", 0.0)) + float(c.sp0.get("health", 0.0)) + float(c.sp0.get("education", 0.0))
	var target := 0.52 + c.law_approval
	target -= 0.9 * pow(infl_pain, 0.7)
	target -= 2.0 * u_pain
	target += 2.2 * growth_good
	target -= 1.4 * tax_pain
	target += 1.6 * clampf(social_good, -0.08, 0.06)
	target -= 0.25 * c.war_exhaustion
	target -= 0.25 * c.occupied
	target -= 0.5 * c.tariff
	target += 0.0 if c.client_of < 0 else -0.08
	var drift := 0.05 if c.dem >= 6.0 else 0.035
	c.approval += (clampf(target, 0.04, 0.9) - c.approval) * drift + world.rng.randfn(0.0, 0.005)
	c.approval = clampf(c.approval, 0.02, 0.95)

	var income := log(maxf(c.gdp_pc(), 300.0) / 300.0)
	var stab_target := 0.2 + 0.05 * income + 0.03 * c.dem + 0.3 * (c.approval - 0.45)
	stab_target -= 0.25 * clampf(infl_pain, 0.0, 0.5) + 0.8 * clampf(u_pain, 0.0, 0.2) + 0.4 * c.occupied + 0.2 * c.unrest
	stab_target -= 0.15 * c.inequality
	stab_target += c.law_stability
	c.stability += (clampf(stab_target, 0.03, 0.97) - c.stability) * 0.025
	c.unrest = maxf(c.unrest * 0.96, 0.0)
	c.conf += (clampf(0.35 + 0.4 * c.stability + 2.5 * clampf(growth - c.g0, -0.1, 0.05) - 1.2 * clampf(c.risk - c.risk0, 0.0, 0.3), 0.05, 1.0) - c.conf) * 0.08
	Corporate.update_index(c, world, growth)

	# Regimes fechados podem cair por golpe; democracias vão às urnas.
	var yf := world.year_float()
	# Na oposição, a eleição do país do jogador continua sendo tratada pelo mundo.
	if c != world.player:
		if c.dem >= 4.0 and yf >= c.next_election:
			_ai_election(c, world)
		elif c.dem < 4.0 and c.stability < 0.14 and world.rng.randf() < 0.012:
			_ai_coup(c, world)
	world.check_player_politics(c)


static func _ai_election(c: Country, world: GameWorld) -> void:
	c.next_election = world.year_float() + 4.0
	var incumbent_wins := world.politics.ai_election(world, c)
	if not incumbent_wins:
		c.approval = clampf(0.55 + world.rng.randf_range(-0.05, 0.08), 0.3, 0.75)
		if c.y_usd() > world.world_gdp() * 0.008:
			world.emit_news(TranslationServer.translate("Eleições em %s: oposição vence e promete mudar o rumo.") % c.name, "politica", c)
		world.diplomacy.on_government_change(c, world)


static func _ai_coup(c: Country, world: GameWorld) -> void:
	c.stability = clampf(c.stability + 0.2, 0.0, 0.5)
	c.approval = 0.45
	c.conf = maxf(c.conf - 0.15, 0.05)
	c.demand_shock -= 0.03
	world.emit_news(TranslationServer.translate("Golpe de Estado em %s: junta militar assume o poder.") % c.name, "crise", c)
	world.diplomacy.on_government_change(c, world)


static func _credit_cycle(c: Country, world: GameWorld) -> void:
	# Ciclo de crédito (Schularick-Taylor): juro real baixo por muito tempo infla o crédito.
	var push := -0.5 * c.rgap + 0.4 * (c.growth_yoy() - c.g0) + 0.02 * (c.conf - 0.6)
	c.credit_gap += (push - 0.14 * c.credit_gap) * DT
	c.crisis_cooldown = maxf(c.crisis_cooldown - DT, 0.0)
	if c.crisis_cooldown > 0.0 or c.credit_gap < 0.06:
		return
	var hazard := 0.008 + 0.25 * (c.credit_gap - 0.06) + 0.03 * maxf(world.global_risk - 0.3, 0.0)
	if world.rng.randf() < hazard * DT * 3.0:
		banking_crisis(c, world)


static func banking_crisis(c: Country, world: GameWorld) -> void:
	var severity := clampf(0.04 + c.credit_gap * 0.5, 0.04, 0.12)
	c.demand_shock -= severity
	c.credit_gap = -0.1
	c.crisis_cooldown = 8.0
	c.conf = maxf(c.conf - 0.2, 0.05)
	c.debt_loc += c.y_nominal() * severity * 1.2  # socorro aos bancos entra na dívida pública
	world.global_risk = clampf(world.global_risk + 0.5 * sqrt(c.y_usd() / world.world_gdp()), 0.0, 1.0)
	world.emit_news(TranslationServer.translate("Crise bancária em %s: crédito congela e o Tesouro socorre bancos.") % c.name, "crise", c)


static func _newsworthy(c: Country, world: GameWorld) -> bool:
	return c == world.player or c.y_usd() > world.world_gdp() * NEWS_SHARE


## Recessão, inflação e juros do jogador viram manchete; de outras grandes economias, só a recessão.
static func _macro_news(c: Country, world: GameWorld) -> void:
	var g := c.growth_yoy()
	var s: PackedFloat32Array = c.hist.get("growth", PackedFloat32Array())
	if s.size() >= 13 and _newsworthy(c, world):
		var before := s[s.size() - 1]
		if g < 0.0 and before >= 0.0:
			world.emit_news(TranslationServer.translate("%s entra em recessão: o PIB encolhe %s em 12 meses.") % [c.name, UiKit.pct(-g)], "crise" if c == world.player else "economia", c)
		elif g >= 0.005 and before < 0.0:
			world.emit_news(TranslationServer.translate("%s sai da recessão: o PIB volta a crescer.") % c.name, "economia", c)
	if c != world.player:
		return
	var infl: PackedFloat32Array = c.hist.get("infl", PackedFloat32Array())
	if infl.size() >= 1:
		for limit: float in [0.1, 0.25, 0.5, 1.0]:
			if c.pi_yoy > limit and infl[infl.size() - 1] <= limit:
				world.emit_news(TranslationServer.translate("Inflação em %s passa de %s ao ano.") % [c.name, UiKit.pct(limit, 0)], "crise" if limit >= 0.25 else "economia", c)
	# O banco central anuncia quando o juro já andou meio ponto desde o último anúncio.
	if c.rate_said < 0.0:
		c.rate_said = c.rate
	elif absf(c.rate - c.rate_said) >= 0.005:
		var who: String = TranslationServer.translate("O BCE") if c.peg == 2 else TranslationServer.translate("O banco central de %s") % c.name
		var rate_news: String = TranslationServer.translate("%s eleva o juro básico para %s ao ano.") if c.rate > c.rate_said else TranslationServer.translate("%s reduz o juro básico para %s ao ano.")
		world.emit_news(rate_news % [who, UiKit.pct(c.rate, 2)], "economia", c)
		c.rate_said = c.rate


static func _record(c: Country, world: GameWorld) -> void:
	_macro_news(c, world)
	c.push_hist("y", c.y)
	_push_series(c)


## O ponto de partida de cada gráfico, para nenhum aparecer vazio no primeiro mês. O PIB real ("y") já
## entra no início e mede o crescimento em 12 meses; não pode repetir.
static func record_start(c: Country) -> void:
	_push_series(c)


static func _push_series(c: Country) -> void:
	c.push_hist("gdp", c.y_usd())
	c.push_hist("growth", c.growth_yoy())
	c.push_hist("infl", c.pi_yoy)
	c.push_hist("unemp", c.unemp)
	c.push_hist("debt", c.debt_ratio)
	c.push_hist("rate", c.rate)
	c.push_hist("deficit", c.deficit / maxf(c.y_nominal(), 0.001))
	c.push_hist("ca", c.ca_ratio)
	c.push_hist("fx", c.e)
	c.push_hist("approval", c.approval)
	c.push_hist("stability", c.stability)
	c.push_hist("stock", c.stock)
	c.push_hist("yield", c.yield_gov)
