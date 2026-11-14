class_name Economy
extends RefCounted
## Semi-structural macroeconomic model: Solow supply (capital, labor, human capital, TFP),
## output gap with aggregate demand, Phillips curve with partially anchored expectations,
## Taylor rule, interest-rate/PPP parity in the exchange rate, budget constraint and debt
## with endogenous risk premium, balance of payments and credit cycle.

const ALPHA := 0.36
const DELTA := 0.05
const DT := 1.0 / 12.0
## Consolidated democracies and the euro area have an independent central bank; the rest answer to the government.
const CB_INDEPENDENT_DEM := 6.0
const KY := 3.0
const OKUN := 0.50
## Okun in differences: each point of growth below trend adds this to unemployment.
const OKUN_GROWTH := 0.50
const KAPPA := 0.30
const MAX_RATE := 1.2
const RATINGS := ["AAA", "AA", "A", "BBB", "BB", "B", "CCC", "CC"]
## Economies above this share of world GDP make news when they enter recession or change rating.
const NEWS_SHARE := 0.02
## Starting sovereign funds: [share of commodity revenue, share of surplus, maximum annual withdrawal].
## Norway: all the oil revenue and the 3% rule. China and Singapore live on surpluses.
const SWF_POLICY := {
	"NOR": [1.0, 0.0, 0.03], "SAU": [0.15, 0.3, 0.01], "ARE": [0.25, 0.3, 0.02], "KWT": [0.1, 0.5, 0.01],
	"QAT": [0.2, 0.3, 0.02], "CHN": [0.0, 0.0, 0.0], "SGP": [0.0, 0.5, 0.02],
}
## Long-term real return of a global portfolio; withdrawing above it eats the principal.
const SWF_SAFE_DRAW := 0.04
## Starting capital controls, 0-1.
const CAP_CONTROLS := {"CHN": 0.6, "IND": 0.3, "ARG": 0.5, "VNM": 0.3}


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
	# Initial TFP implied by the trend: in steady state K grows like Y.
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
	# Neutral rate: trend growth, plus the premium each country already pays today.
	c.r_n = 0.007 + 0.35 * c.g0 if advanced else 0.012 + 0.35 * c.g0
	if infl < 0.15:
		c.r_n = clampf(lerpf(c.r_n, c.rate - c.pi_e, 0.5), 0.003, 0.06)
	c.rgap = clampf(c.rate - c.pi_e - c.r_n, -0.05, 0.08)
	c.p_hist = PackedFloat32Array()
	for i in 13:
		c.p_hist.append(pow(1.0 + clampf(infl, -0.1, 3.0), float(i - 12) / 12.0))

	c.unemp = row.unemp / 100.0
	c.unemp_n = c.unemp
	c.informal0 = informal_base(c.pc0 * 1000.0)
	c.informal = c.informal0
	c.real_wage = 1.0
	c.dem = row.dem
	c.peg = row.peg
	c.cb_independent = c.dem >= CB_INDEPENDENT_DEM or c.peg == 2
	# Rich central banks let the exchange rate float; emerging ones hold back part of the jolts.
	c.fx_lean = 0.05 if c.dem >= 7.5 else 0.3
	c.reserves = maxf(row.res, 0.1)
	c.swf = float(row.get("swf", 0.0))
	var swf_policy: Array = SWF_POLICY.get(c.iso, [0.0, 0.0, 0.0])
	c.swf_active = c.swf > 0.0
	if c.swf_active:
		c.swf_rent_share = swf_policy[0]
		c.swf_surplus_share = swf_policy[1]
		c.swf_limit = swf_policy[2]
	c.cap_controls = CAP_CONTROLS.get(c.iso, 0.0)
	c.dollarization = 0.0 if c.peg != 0 else clampf(row.infl / 100.0 * 1.2, 0.0, 0.6)
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
	# Concessional debt: the initial service is at most ~1/4 of revenue.
	c.avg_rate = minf(c.avg_rate, 0.25 * rev / maxf(c.debt_ratio, 0.01))
	_init_debt_profile(c, advanced, pc)

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
	update_curve(c, world)
	c.yield_gov = c.curve[TENOR_10Y]
	c.avg_fx = minf(0.045 + score, c.avg_rate * 1.0 if c.avg_rate < 0.045 else 0.09)
	if pc < 12000.0:
		c.yield_mult = clampf(c.avg_rate / maxf(c.yield_gov, 0.001), 0.4, 1.0)


static func _mil_stock_init(_c: Country, spend: float, pc: float) -> float:
	# PPP adjustment: low-income countries buy more military power per dollar.
	var ppp := clampf(pow(60000.0 / maxf(pc, 500.0), 0.35), 1.0, 3.0)
	return maxf(spend * ppp * 0.35 / 0.06, 0.1)


## Completes the external sector after the commodity markets have been set up.
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
	# The table is approximate: it never lets non-commodity exports fall below 2% of GDP.
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
	# Part of public revenue comes from commodity rents (Gulf, Norway, Angola...).
	var rent := minf(comm_x * 0.55, c.tax0 * gdp * 0.75)
	c.rent_take = rent / maxf(comm_x, 0.001)
	# The sovereign fund keeps part of the revenue and returns the withdrawal: the rest of the taxes closes the starting account.
	var swf_net := c.swf * c.swf_limit - rent * c.swf_rent_share
	c.rent_ref = rent
	var new_tax := c.tax0 - rent / gdp - swf_net / gdp
	if new_tax < 0.02 and c.swf_limit > 0.0:
		c.swf_limit = maxf(c.swf_limit - (0.02 - new_tax) * gdp / maxf(c.swf, 0.001), 0.0)
		new_tax = c.tax0 - rent / gdp - (c.swf * c.swf_limit - rent * c.swf_rent_share) / gdp
	var k := new_tax / maxf(c.tax0, 0.001)
	c.tax_income *= k
	c.tax_consumption *= k
	c.tax_corporate *= k
	c.tax0 = new_tax
	c.t_ref = new_tax
	c.comm_exports = comm_x
	for i in 5:
		c.p_ref[i] = 1.0
	# The year's accounts and the rating already apply on the first day, before the first monthly step.
	_fiscal_flows(c)
	c.swf_flow0 = (c.swf_in - c.swf_out) / maxf(c.y_usd(), 0.001)
	c.res_ratio0 = c.reserves / maxf(c.y_usd(), 0.001)
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
	# Labor supply responds to income taxation (low elasticity).
	var tax_wedge := clampf((c.tax_income - c.tax0 * 0.45) * 0.25, -0.03, 0.08)
	var labor := c.pop * Demography.labor_factor(c) * (1.0 - tax_wedge) * (1.0 - 0.12 * c.mobilization) * (1.0 + clampf(c.law_labor, -0.1, 0.05))

	var r_effect := clampf(1.0 - 2.5 * c.rgap, 0.5, 1.4)
	var conf_effect := clampf(0.7 + 0.5 * c.conf, 0.6, 1.2)
	var corp_effect := clampf(1.0 - 1.2 * (c.tax_corporate - c.tax0 * 0.17), 0.6, 1.2)
	var infra_extra: float = c.sp_infra - float(c.sp0.get("infra", c.sp_infra))
	var inv_share := c.inv_share0 * r_effect * conf_effect * corp_effect * (1.0 + c.law_invest) * Corruption.invest_factor(c) + infra_extra * 0.8
	var crowding := clampf(1.0 - 0.15 * maxf(c.debt_ratio / c.debt_tol - 1.0, 0.0), 0.75, 1.0)
	inv_share *= crowding
	c.capital += (inv_share * c.y - DELTA * c.capital) * DT
	c.capital = maxf(c.capital, c.y_pot * 0.8)

	# Convergence: the richer relative to its own base, the smaller the easy TFP gain.
	var pc_rel := (c.y / c.pop) / maxf(c.pc0, 0.001)
	var converge := -0.006 * log(maxf(pc_rel, 0.2))
	var edu_extra: float = c.sp_education - float(c.sp0.get("education", c.sp_education))
	var health_extra: float = c.sp_health - float(c.sp0.get("health", c.sp_health))
	var g_tfp := c.g_tfp0 + converge
	g_tfp += 0.10 * edu_extra + 0.05 * health_extra
	g_tfp += 0.012 * clampf(c.trade_loss, -0.3, 0.2)
	g_tfp -= 0.012 * maxf(0.45 - c.stability, 0.0)
	g_tfp += clampf(c.law_tfp, -0.01, 0.01)
	# Inequality moves slowly toward the country's base plus what the laws push.
	c.inequality += (clampf(c.inequality0 + c.law_inequality, 0.2, 0.65) - c.inequality) * 0.02
	c.human *= 1.0 + clampf(0.15 * edu_extra, -0.004, 0.006) * DT
	c.tfp *= 1.0 + g_tfp * DT
	c.hist["_gtfp"] = g_tfp
	c.damage = maxf(c.damage - 0.05 * DT * c.damage - 0.01 * DT, 0.0)
	var base := EconFormulas.cobb_douglas(c.tfp, c.capital, c.human * labor, ALPHA)
	c.y_pot = base * (1.0 - c.occupied * 0.85) * (1.0 - c.damage) * (1.0 + c.supply_shock) * (1.0 + Sectors.boost_total(c))
	c.supply_shock *= 0.97


static func _demand(c: Country, world: GameWorld) -> void:
	var m := world.markets
	# Monetary policy acts with a lag (moving average of ~9 months of the real rate).
	var r := c.rate - c.pi_e
	c.rgap += (clampf(r - c.r_n, -0.08, 0.15) - c.rgap) * 0.11
	var monetary := -0.45 * c.rgap

	# Fiscal impulse: effect of the CHANGE in stance; the reference adapts in ~2 years.
	var g := c.spend_total() + c.mobilization * 0.02 + c.law_spend
	var t := c.tax_total() + c.law_tax
	# Keynesian multiplier 1/(1 − c(1 − t) + m); with a hot economy, part turns into interest and prices
	# (crowding out). On taxes, partial Ricardian equivalence makes part of the cut turn into saving.
	var k := EconFormulas.keynes_multiplier(EconFormulas.MPC, clampf(t, 0.05, 0.6), clampf(c.m_share, 0.02, 0.8))
	var mult_g := k * (0.8 if c.gap < -0.01 else 0.45)
	var mult_t := EconFormulas.tax_multiplier(EconFormulas.MPC, clampf(t, 0.05, 0.6), clampf(c.m_share, 0.02, 0.8), EconFormulas.ricardian_share(c.debt_ratio, c.debt_tol))
	c.hist["_mult_g"] = mult_g
	c.hist["_mult_t"] = mult_t
	var debt_drag := clampf(1.0 - 0.5 * maxf(c.debt_ratio / c.debt_tol - 1.0, 0.0), 0.3, 1.0)
	var fiscal := (mult_g * (g - c.g_ref) - mult_t * (t - c.t_ref)) * debt_drag
	c.g_ref += (g - c.g_ref) * 0.04
	c.t_ref += (t - c.t_ref) * 0.04

	# External demand weighted by real partners + trade frictions.
	var trade := world.diplomacy.trade_channel(c, world)
	c.ext_demand = trade.x
	c.trade_loss += (float(trade.loss) - c.trade0 - c.trade_loss) * 0.08
	var openness := clampf(c.x_share, 0.0, 1.0)
	# Saturated ports and airports (logistics < 1) block part of foreign trade.
	var ext := openness * (1.1 * c.ext_demand + 0.8 * c.trade_loss + 0.3 * clampf(c.logistics - 1.0, -0.4, 0.2))
	var rer_effect := clampf(0.5 * openness * log(c.rer / c.rer_ref), -0.06, 0.06)
	c.rer_ref += (c.rer - c.rer_ref) * 0.01

	# Terms of trade: price change weighted by the net position in each commodity.
	var tot := 0.0
	for i in 5:
		var rel := m.relative_price(i, world)
		var net_val: float = m.value_usd(i, (c.prod[i] * c.prod_factor[i] - c.use[i])) / m.price[i] * float(Markets.P0[i])
		c.p_ref[i] += (rel - c.p_ref[i]) * 0.012
		tot += net_val / maxf(c.y0 * (c.y / c.y0), 0.001) * (rel - c.p_ref[i])
	tot = clampf(tot * 0.45, -0.08, 0.1)
	# Chip and energy shortages are a supply shock even for those with a neutral balance.
	var shortage := -0.012 * maxf(log(maxf(m.relative_price(Markets.CHIP, world) / c.p_ref[Markets.CHIP], 0.1)), 0.0)
	shortage -= 0.012 * maxf(log(maxf(m.relative_price(Markets.OIL, world) / c.p_ref[Markets.OIL], 0.1)), 0.0)

	var confidence := 0.05 * (c.conf - 0.6)
	var credit := 0.25 * clampf(c.credit_gap, -0.15, 0.2) * 0.3
	var risk_drag := -0.3 * clampf(c.risk - c.risk0, 0.0, 0.15)
	c.demand_shock *= 0.965
	c.noise += -c.noise * 0.08 + world.rng.randfn(0.0, 0.0022)

	var target := monetary + fiscal + ext + rer_effect + tot + shortage + confidence + credit + risk_drag + c.demand_shock
	# The neutral rate already includes the trend; a positive gap does not sustain itself without stimulus.
	c.gap += (clampf(target, -0.4, 0.12) - c.gap) * 0.13 + c.noise * 0.35
	c.gap = clampf(c.gap, -0.45, 0.13)
	c.y = c.y_pot * (1.0 + c.gap)


static func _prices(c: Country, world: GameWorld) -> void:
	var m := world.markets
	# Expectations anchor: mixes a credible target with observed inflation.
	var anchor := c.cred * c.pi_target + (1.0 - c.cred) * c.pi_yoy
	c.pi_e += (anchor - c.pi_e) * 0.09
	var mon_push := 0.0
	if c.mon_fin > 0.0 or world.year_float() < c.default_until:
		var financed := c.mon_fin if world.year_float() >= c.default_until else maxf(c.mon_fin, 0.5)
		# Quantity equation M·V = P·Y: issuance makes money grow μ = (issuance/PY)·V, and with V and Y
		# given, the price level follows. Seigniorage = ΔM/P; inflation tax = π/(1+π)·M/P.
		mon_push = EconFormulas.monetized_money_growth(financed, c.deficit / maxf(c.y_nominal(), 0.001))
		c.hist["_seign"] = financed * maxf(c.deficit, 0.0) / maxf(c.p, 0.001)
	else:
		c.hist["_seign"] = 0.0
	c.hist["_inftax"] = EconFormulas.inflation_tax(maxf(c.pi_yoy, 0.0), c.y / EconFormulas.VELOCITY)
	var core_target := EconFormulas.phillips(c.pi_e, KAPPA, c.gap, mon_push + 0.08 * maxf(c.occupied - c.occ0, 0.0) + 0.04 * c.unrest)
	c.pi_core += (clampf(core_target, -0.03, 6.0) - c.pi_core) * 0.11
	# Local-currency inflation of imported inputs passes to the index as a level shock.
	var poor := clampf(1.0 - c.gdp_pc() / 30000.0, 0.0, 1.0)
	# Weight of raw materials in the index: partial pass-through to retail, larger in poor countries.
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
	# Only depreciation above purchasing power parity generates additional pass-through.
	var ppp_trend := log(1.0 + EconFormulas.ppp_depreciation(c.pi_core, world.usa.pi_core)) * DT
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
	# Credibility is gained slowly and lost fast.
	var miss := absf(c.pi_yoy - c.pi_target)
	var d_cred := 0.004 if miss < 0.015 else -clampf((miss - 0.015) * 0.03, 0.0, 0.015)
	d_cred -= c.mon_fin * 0.015
	# Stabilization plan: high real rate with recession signals commitment.
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
	# Taylor rule with the level of π in expectations and the reaction to the deviation of current inflation:
	# i = r* + πe + 0.6·(π − π*) + 0.5·gap.
	var target := EconFormulas.taylor(c.r_n, c.pi_e, c.pi_target, c.gap, 0.6, 0.5) + 0.6 * (c.pi_yoy - c.pi_e)
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
		_float_exchange(c, world)
	c.rer = c.e * us.p / c.p


## Floating exchange rate. Uncovered parity: i = i* + Δeᵉ + risk premium, so expected depreciation is
## i - i* - premium. The level jumps so that the expected return in hard currency equalizes; the central bank
## sells or buys reserves to hold back part of the move; capital flees when risk rises and
## dollarization takes strength away from the interest rate.
static func _float_exchange(c: Country, world: GameWorld) -> void:
	var us := world.usa
	var yusd := c.y_usd()
	_capital_flight(c, world, yusd)
	var premium := c.risk + 0.5 * c.cap_flight / maxf(yusd, 0.001)
	c.uip_dep = c.rate - us.rate - premium
	var rd := (c.rate - c.pi_e - c.r_n) - (us.rate - us.pi_e - us.r_n)
	var ppp := log(c.p / us.p)
	# The sovereign fund invests abroad: the revenue it keeps does not enter the foreign exchange market.
	var fund := (c.swf_in - c.swf_out) / maxf(c.e, 0.001) / maxf(yusd, 0.001) - c.swf_flow0
	var target := ppp - 1.1 * (1.0 - 0.6 * c.dollarization) * clampf(rd, -0.15, 0.2) - 0.7 * clampf(c.ca_ratio - c.ca0 - fund, -0.2, 0.2)
	# Balassa-Samuelson: whoever gains productivity faster than the US appreciates the real exchange rate.
	c.hist["_bs"] = float(c.hist.get("_bs", 0.0)) + EconFormulas.balassa_samuelson(float(c.hist.get("_gtfp", c.g_tfp0)), 0.0, float(us.hist.get("_gtfp", us.g_tfp0)), 0.0) * DT
	target -= float(c.hist["_bs"])
	target += 1.6 * clampf(c.risk - c.risk0, -0.03, 0.4) + 0.6 * clampf(world.global_risk - 0.2, -0.2, 0.8) * (0.0 if c.debt_tol > 0.9 else 0.25)
	target += 0.8 * c.cap_flight / maxf(yusd, 0.001)
	var le := log(c.e)
	var pressure := (target - le) * 0.10
	# Intervention: the central bank holds back the deviation, not the trend that inflation already explains, and only sells
	# what the reserves allow (3 months of imports = full slack).
	var dev := pressure - (c.pi_yoy - us.pi_yoy) * DT
	var lean := clampf(c.fx_lean, 0.0, 1.0)
	var cover := c.reserves / maxf(c.imports / 12.0, 0.001)
	if dev > 0.0:
		lean *= clampf(cover / 3.0, 0.0, 1.0)
	var held := 0.8 * lean * dev
	var sold := held * yusd * 0.6 + c.cap_flight * lean * DT
	# Outside crises, whoever intervenes slowly rebuilds (or returns) the starting cushion, which grows with
	# GDP in dollars. With a free exchange rate the central bank does not touch reserves.
	sold -= (c.res_ratio0 * yusd - c.reserves) * 0.15 * DT * clampf(c.fx_lean / 0.3, 0.0, 1.0)
	sold = minf(sold, c.reserves)
	c.reserves = maxf(c.reserves - sold, 0.0)
	c.fx_interv = sold * 12.0
	le += pressure - held + world.rng.randfn(0.0, 0.006)
	c.e = exp(le)


## Capital flight (annualized, US$ bn) and dollarization, which rises fast with high inflation and falls slowly.
static func _capital_flight(c: Country, world: GameWorld, yusd: float) -> void:
	var fear := (c.risk - c.risk0) * 8.0 + 3.0 * maxf(c.pi_yoy - 0.15, 0.0) + 0.5 * maxf(world.global_risk - 0.3, 0.0) + 0.5 * maxf(c.uip_dep * -1.0 - 0.05, 0.0)
	c.cap_flight = clampf(fear, 0.0, 1.0) * 0.06 * yusd * (1.0 - 0.85 * clampf(c.cap_controls, 0.0, 1.0)) * (1.0 + c.dollarization)
	var dz_target := clampf(1.5 * maxf(c.pi_yoy - 0.1, 0.0) + 0.3 * clampf(c.risk - c.risk0, 0.0, 0.5), 0.0, 0.8)
	c.dollarization += (dz_target - c.dollarization) * (0.02 if dz_target > c.dollarization else 0.003)


static func _external(c: Country, world: GameWorld) -> void:
	var m := world.markets
	var yusd := c.y_usd()
	# J curve: volumes react to the real exchange rate with a lag, the dollar value reacts at once.
	# No longo prazo vale Marshall-Lerner (εx + εm = 1,1 > 1).
	var rer_j := EconFormulas.lagged_rer(float(c.hist.get("_rer_j", c.rer)), c.rer)
	c.hist["_rer_j"] = rer_j
	var rer_log := clampf(log(rer_j), -1.0, 1.0)
	var x_nc := c.x_share * yusd * (1.0 + EconFormulas.ELAST_X * rer_log) * (1.0 + 1.2 * c.ext_demand) * (1.0 + clampf(c.trade_loss, -0.9, 0.5))
	var tariff_cut := clampf(1.0 - 1.6 * c.tariff, 0.3, 1.0)
	var m_nc := c.m_share * yusd * (1.0 - EconFormulas.ELAST_M * rer_log) * (1.0 + 1.3 * c.gap) * tariff_cut * (1.0 + 0.5 * clampf(c.trade_loss, -0.9, 0.5))
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

	# Reserves: the peg absorbs the balance; a float intervenes little.
	var cap_flow := 0.0
	if c.peg == 1:
		_capital_flight(c, world, yusd)
		cap_flow = clampf((c.rate - world.usa.rate - c.risk * 0.5) * 2.0, -0.08, 0.08) * yusd * (1.0 - 0.7 * c.cap_controls)
		# Under the peg the central bank buys and sells whatever is needed at the fixed rate.
		c.fx_interv = -(c.ca + cap_flow) * 0.5 + c.cap_flight
		c.reserves += (c.ca + cap_flow - c.cap_flight * 2.0) * 0.5 * DT
	elif c.peg == 0:
		# Float: the exchange rate and foreign capital close the balance; the intervention comes out in `_float_exchange`.
		c.reserves += c.ca * 0.08 * (1.0 if c.ca > 0.0 else 0.0) * DT
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
	var b0 := c.debt_ratio
	var d0 := c.debt_loc + c.debt_fx * c.e
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
	_roll_debt(c, world)
	_fund_month(c, world)
	_debt_dynamics(c, b0, d0, yn)
	if c != world.governed():
		_fiscal_reaction(c)
	var old_rating := c.rating
	c.rating = _rating_for(c)
	if c.rating != old_rating and old_rating != "D" and world.year_float() >= c.default_until and _newsworthy(c, world):
		var down := RATINGS.find(c.rating) > RATINGS.find(old_rating)
		var rating_news: String = TranslationServer.translate("Agências rebaixam a nota de crédito de %s de %s para %s.") if down else TranslationServer.translate("Agências elevam a nota de crédito de %s de %s para %s.")
		world.emit_news(rating_news % [c.name, old_rating, c.rating], "crise" if down and c == world.player else "economia", c)
	_check_default(c, world)


## Revenue, spending, interest and deficit of the year, from the tax rates and spending in force. Consumes the loose
## money of the month (norms, state companies, works).
static func _fiscal_flows(c: Country) -> void:
	var yn := c.y_nominal()
	var yn_pot := c.y_pot * c.p
	var tax_rate := c.tax_total()
	# Laffer curve: the taxable base shrinks with (1 − t)^ε (ε = 0.3, peak at t* ≈ 77%), measured from the starting
	# burden. Cyclical elasticity of 1.1.
	var collection := clampf(EconFormulas.laffer_base(tax_rate, c.tax0), 0.55, 1.1) * (1.0 - clampf(c.law_evasion, -0.05, 0.3)) * Corruption.collection_factor(c)
	collection *= 1.0 - 0.5 * clampf(c.informal - c.informal0, -0.1, 0.4)
	var tax_rev := tax_rate * yn * (1.0 + 0.1 * c.gap) * collection
	var rent := c.comm_exports * c.e * c.rent_take
	var tariff_rev := c.tariff * c.imports * c.e * 0.7
	c.revenue = tax_rev + rent + tariff_rev + c.aid_flow * c.e * 0.85 + (c.law_rev_bucket + c.extra_rev_bucket) * 12.0 * c.e

	var prog := yn_pot * (c.sp_health + c.sp_education + c.sp_infra + c.sp_defense + c.sp_admin)
	# Automatic stabilizer: social spending rises when there is unemployment.
	var social := c.sp_social * yn_pot * (1.0 + 2.0 * clampf(c.unemp - c.unemp_n, -0.03, 0.2))
	# Pensions: more elderly people than at the start weigh on social spending.
	social += Demography.pension_extra(c) * yn_pot
	var war_cost := c.mobilization * 0.035 * yn_pot
	# Fixed-rate bonds pay the nominal coupon; indexed ones pay the real rate plus inflation accrual (accrual basis).
	var il := c.debt_loc * c.debt_il_share
	c.interest = (c.debt_loc - il) * c.avg_rate + il * (c.avg_real + c.pi_yoy) + c.debt_fx * c.e * c.avg_fx
	c.spending = prog + social + war_cost + c.interest + c.reparations * c.e + (c.law_spend_bucket + c.extra_spend_bucket) * 12.0 * c.e
	c.law_rev_bucket = 0.0
	c.law_spend_bucket = 0.0
	c.extra_rev_bucket = 0.0
	c.extra_spend_bucket = 0.0
	c.deficit = c.spending - c.revenue
	_fund_flows(c, rent)


## Sovereign fund contributions and withdrawals in the year, in local currency. The withdrawal follows the rule (share of the balance) and,
## when commodity revenue falls below the average, covers part of the fall up to another half limit.
static func _fund_flows(c: Country, rent: float) -> void:
	c.swf_in = 0.0
	c.swf_out = 0.0
	if not c.swf_active:
		return
	var surplus := maxf(-c.deficit, 0.0)
	c.swf_in = rent * c.swf_rent_share + surplus * c.swf_surplus_share
	var fund := c.swf * c.e
	var cushion := clampf((c.rent_ref - rent) * 0.5, 0.0, fund * c.swf_limit * 0.5)
	c.swf_out = minf(fund * c.swf_limit + cushion, fund)
	c.revenue += c.swf_out - c.swf_in
	c.deficit = c.spending - c.revenue


## One month of the fund: contribution, withdrawal and return of the global portfolio, 60% stocks (follows the US market of
## the previous month) and 40% bonds (US rate). Withdrawing above the safe return takes away approval.
static func _fund_month(c: Country, world: GameWorld) -> void:
	c.rent_ref += (c.comm_exports * c.e * c.rent_take - c.rent_ref) * DT / 3.0
	if not c.swf_active and c.swf <= 0.0:
		c.swf_pain = 0.0
		return
	var stock: PackedFloat32Array = world.usa.hist.get("stock", PackedFloat32Array())
	var equity := 0.0
	if stock.size() >= 2 and stock[-2] > 0.0:
		equity = clampf(log(stock[-1] / stock[-2]), -0.3, 0.3)
	var monthly := 0.6 * equity + 0.4 * world.usa.rate * DT + 0.001
	c.swf_return = monthly * 12.0
	c.swf = maxf(c.swf * exp(monthly) + (c.swf_in - c.swf_out) / maxf(c.e, 0.001) * DT, 0.0)
	if not c.swf_active:
		c.swf_pain = 0.0
		return
	var draw := c.swf_out / maxf(c.swf * c.e, 0.001)
	c.swf_pain = clampf((draw - SWF_SAFE_DRAW) * 1.5, 0.0, 0.12) if c.swf > 1.0 else 0.0


# --- Public debt: yield curve, bonds and rollover ---

## Tenors of the yield curve, in years.
const TENORS := [0.25, 1.0, 2.0, 5.0, 10.0, 30.0]
const TENOR_10Y := 4
## Scale (years) at which the curve moves from the short to the long rate (Nelson-Siegel factor).
const CURVE_TAU := 2.0
const TERM_PREMIUM := 0.004
## Countries with a large part of the debt indexed to inflation.
const IL_SHARE := {"BRA": 0.4, "CHL": 0.6, "ISR": 0.45, "COL": 0.3, "MEX": 0.15, "GBR": 0.25, "ARG": 0.3, "URY": 0.4, "TUR": 0.15, "ZAF": 0.2, "USA": 0.08, "FRA": 0.1, "ITA": 0.1, "SWE": 0.15, "AUS": 0.07, "CAN": 0.05}
const MATURITY := {"GBR": 14.0, "JPN": 9.0, "USA": 6.0, "MEX": 8.0, "BRA": 4.0, "TUR": 4.0, "ARG": 4.0, "CHE": 9.0}


static func _init_debt_profile(c: Country, advanced: bool, pc: float) -> void:
	c.debt_il_share = IL_SHARE.get(c.iso, 0.05 if advanced else (0.08 if pc > 8000.0 else 0.0))
	# Poor countries' debt is mostly official lending, with a long maturity.
	var m := 7.5 if advanced else (5.5 if pc > 8000.0 else (5.0 if pc > 3000.0 else 9.0))
	c.debt_maturity = MATURITY.get(c.iso, m)
	c.debt_mat0 = c.debt_maturity
	c.avg_real = clampf(c.avg_rate - c.pi_e, -0.01, 0.12)


static func _h(t: float) -> float:
	var x := t / CURVE_TAU
	return (1.0 - exp(-x)) / x


## Average expected inflation up to tenor t: starts at the current expectation and converges to the target
## as central bank credibility anchors the long horizon.
static func expected_inflation(c: Country, t: float) -> float:
	var long := clampf(lerpf(c.pi_e, c.pi_target, c.cred), -0.01, 3.0)
	return long + (c.pi_e - long) * _h(t)


## Nominal curve (two-factor Nelson-Siegel). Long end from the Fisher effect:
## i = r + πᵉ, plus term and credit risk premia.
static func update_curve(c: Country, _world: GameWorld) -> void:
	var short := c.rate + 0.7 * c.risk
	var long := c.r_n + expected_inflation(c, 30.0) + TERM_PREMIUM + c.risk
	var out := PackedFloat32Array()
	out.resize(TENORS.size())
	for i in TENORS.size():
		out[i] = maxf(long + (short - long) * _h(TENORS[i]), -0.01)
	c.curve = out


## Nominal yield at tenor t, interpolated on the curve.
static func yield_at(c: Country, t: float) -> float:
	if c.curve.is_empty():
		return c.yield_gov
	if t <= TENORS[0]:
		return c.curve[0]
	for i in range(1, TENORS.size()):
		if t <= TENORS[i]:
			var k: float = (t - TENORS[i - 1]) / (TENORS[i] - TENORS[i - 1])
			return lerpf(c.curve[i - 1], c.curve[i], k)
	return c.curve[TENORS.size() - 1]


## Real rate at tenor t (inverted Fisher: r = i − πᵉ).
static func real_yield_at(c: Country, t: float) -> float:
	return yield_at(c, t) - expected_inflation(c, t)


## Each month 1/maturity of the debt falls due, refinanced at today's rates. The market only accepts short
## bonds when risk rises, and the average maturity shortens.
static func _roll_debt(c: Country, world: GameWorld) -> void:
	update_curve(c, world)
	c.yield_gov = c.curve[TENOR_10Y]
	var m := maxf(c.debt_maturity, 0.5)
	var f := DT / m
	var y_new := yield_at(c, m)
	c.avg_rate += (y_new * c.yield_mult - c.avg_rate) * f
	c.avg_real += (clampf(real_yield_at(c, m), -0.02, 0.3) * c.yield_mult - c.avg_real) * f
	var usd := yield_at(world.usa, m) if world.usa != c else y_new
	c.avg_fx += ((usd + minf(c.risk, 0.25)) * c.yield_mult - c.avg_fx) * f
	var target := c.debt_mat0 * clampf(1.0 - 2.5 * c.risk, 0.3, 1.0)
	c.debt_maturity += (target - m) * f
	c.rollover = (c.debt_loc + c.debt_fx * c.e) * (1.0 - exp(-1.0 / m))


## How much of the debt falls due in each of the next years (nominal local currency).
static func maturities(c: Country, years := 5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := c.debt_loc + c.debt_fx * c.e
	var m := maxf(c.debt_maturity, 0.5)
	for k in years:
		out.append(d * (exp(-k / m) - exp(-(k + 1) / m)))
	return out


## Breaks down the monthly change of the debt-to-GDP ratio by the exact identity
## Δb = (i − g)/(1 + g)·b − primary balance + adjustment (exchange rate, money issuance, defaults).
static func _debt_dynamics(c: Country, b0: float, _d0: float, yn: float) -> void:
	if c._yn_prev <= 0.0:
		c._yn_prev = yn
		return
	var g := yn / c._yn_prev - 1.0
	var i := c.interest * DT / maxf(b0 * c._yn_prev, 0.001)
	var snow := debt_snowball(b0, i, g)
	var pb := (c.revenue - (c.spending - c.interest)) * DT / maxf(yn, 0.001)
	var change := c.debt_ratio - b0
	var a: Dictionary = c._dyn_acc
	a.snowball += snow
	a.primary += pb
	a.change += change
	a.adjust += change - snow + pb
	a.n += 1
	if a.n >= 12:
		c.debt_dyn = {"snowball": a.snowball, "primary": a.primary, "adjust": a.adjust, "change": a.change}
		c._dyn_acc = {"snowball": 0.0, "primary": 0.0, "adjust": 0.0, "change": 0.0, "n": 0}
	c._yn_prev = yn


## Snowball effect: (r − g)/(1 + g)·b.
static func debt_snowball(b: float, r: float, g: float) -> float:
	return (r - g) / (1.0 + g) * b


## Bohn rule for AI governments: with debt above tolerance, the primary balance reacts and discretionary
## spending is cut gradually; once debt is back below, the cut is undone.
const FISCAL_KEYS := ["sp_social", "sp_health", "sp_education", "sp_infra", "sp_admin"]


static func _fiscal_reaction(c: Country) -> void:
	var yn := maxf(c.y_nominal(), 0.001)
	var pb := (c.revenue - (c.spending - c.interest)) / yn
	var excess := c.debt_ratio / maxf(c.debt_tol, 0.1) - 0.85
	var pb_target := clampf(0.06 * excess, -0.02, 0.035)
	var gap := pb_target - pb
	for key in FISCAL_KEYS:
		var base: float = c.sp0.get(key.trim_prefix("sp_"), c.get(key))
		var v: float = c.get(key)
		if excess > 0.0 and gap > 0.0:
			v = maxf(v * (1.0 - minf(gap, 0.04) * 0.15), base * 0.65)
		elif excess < -0.1 and v < base:
			v += (base - v) * 0.01
		c.set(key, v)


static func _risk_premium(c: Country, world: GameWorld) -> float:
	var ratio := c.debt_ratio / maxf(c.debt_tol, 0.1)
	var r := 0.003
	r += 0.03 * maxf(ratio - 0.75, 0.0) ** 2 * 4.0
	var yn := maxf(c.y_nominal(), 0.001)
	r += 0.25 * maxf(c.deficit / yn - 0.04, 0.0)
	r += 0.04 * maxf(0.5 - c.stability, 0.0)
	var cover := c.reserves / maxf(c.imports / 12.0, 0.001)
	r += 0.006 * maxf(3.0 - cover, 0.0) * (0.0 if c.peg == 2 else 1.0)
	# A large sovereign fund is a cushion: it pays the external debt if needed. Capital controls scare.
	r -= 0.02 * clampf(c.swf / maxf(c.y_usd(), 0.001), 0.0, 1.5)
	r += 0.004 * c.cap_controls
	r += Corruption.risk_extra(c)
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


## The rating only changes when risk passes the threshold with a 20% margin: agencies do not oscillate every month, and
## a country near a threshold does not change rating at every jolt of global risk.
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
	# Real interest on revenue: inflation erodes local debt, and that counts.
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
	# Part of the program restructures old debt and reduces the weight of interest.
	c.debt_loc *= 0.92
	c.debt_fx *= 0.92
	c.yield_mult = maxf(c.yield_mult * 0.8, 0.35)
	c.avg_rate *= 0.85
	c.imf_program = 36.0
	# Conditionality: fiscal adjustment and a floating exchange rate.
	c.sp_social *= 0.94
	c.sp_admin *= 0.9
	c.sp_infra *= 0.92
	c.tax_consumption += 0.01
	c.mon_fin = 0.0
	c.conf = minf(c.conf + 0.08, 1.0)
	c.approval = maxf(c.approval - 0.08, 0.03)
	world.emit_news(TranslationServer.translate("FMI aprova pacote de US$ %.0f bi para %s, com ajuste fiscal.") % [loan, c.name], "economia", c)


static func _labor_and_politics(c: Country, world: GameWorld) -> void:
	_labor_market(c, world)
	# Hysteresis: prolonged unemployment raises the natural rate.
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
	target -= c.swf_pain
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

	# Closed regimes may fall by coup; democracies go to the polls.
	var yf := world.year_float()
	# In opposition, the election of the player's country is still handled by the world.
	if c != world.player:
		if c.dem >= 4.0 and yf >= c.next_election:
			_ai_election(c, world)
		elif c.dem < 4.0 and c.stability < 0.14 and world.rng.randf() < 0.012:
			_ai_coup(c, world)
	world.check_player_politics(c)


## Labor market: Okun's law, real wage and informality.
static func _labor_market(c: Country, world: GameWorld) -> void:
	# Okun in levels (gap) and in differences (growth below trend), with layoffs faster than hiring.
	# Where informality is large, part of the shock turns into odd jobs, not open unemployment.
	var cushion := 1.0 - 0.5 * clampf(c.informal0, 0.0, 0.8)
	var slack := -OKUN * c.gap * (1.4 if c.gap < 0.0 else 1.0)
	var growth_gap := clampf(c.g0 - c.growth_yoy(), -0.06, 0.15)
	slack += OKUN_GROWTH * growth_gap
	var u_target := c.unemp_n + c.law_unemp + slack * cushion - 0.025 * c.mobilization
	var speed := 0.14 if u_target > c.unemp else 0.07
	c.unemp += (clampf(u_target, 0.005, 0.45) - c.unemp) * speed
	var u_gap := c.unemp - c.unemp_n

	# Informality: grows with unemployment, with a minimum wage above productivity and with law rigidity.
	var inf_target := c.informal0 + 0.6 * clampf(u_gap, -0.03, 0.2) + 0.25 * maxf(c.minwage_ratio - 0.8, 0.0)
	inf_target += 0.5 * clampf(c.law_evasion, -0.05, 0.3)
	c.informal += (clampf(inf_target, 0.02, 0.9) - c.informal) * 0.03

	# Real wage: follows labor productivity, falls with labor market slack and with inflation above expected
	# (adjustments come late). A high minimum wage pulls the base up, informality pulls it down.
	var productivity := (c.y / maxf(c.pop * (1.0 - c.unemp), 0.001)) / maxf(c.pc0 / (1.0 - c.unemp_n), 0.001)
	var w_target := productivity * (1.0 - 1.2 * clampf(u_gap, -0.03, 0.2)) * (1.0 + 0.04 * clampf(c.minwage_ratio - 0.5, -0.3, 0.7))
	w_target *= 1.0 - 0.3 * (c.informal - c.informal0)
	c.real_wage += (maxf(w_target, 0.2) - c.real_wage) * 0.03
	c.real_wage *= 1.0 - clampf(c.pi_yoy - c.pi_e, -0.05, 0.5) * DT * 0.5
	c.real_wage = clampf(c.real_wage, 0.2, 5.0)
	if c == world.player and u_gap > 0.03 and c.unemp > 0.08 and world.rng.randf() < 0.05:
		world.emit_news(TranslationServer.translate("Desemprego em %s chega a %.1f%%; demissões se espalham.") % [c.name, c.unemp * 100.0], "economia", c)


## Starting informality from GDP per capita (US$): ~10% in rich countries, ~40% in middle income, ~60% in poor ones.
static func informal_base(gdp_pc_usd: float) -> float:
	var f := clampf(log(maxf(gdp_pc_usd, 1.0) / 1000.0) / log(60.0), 0.0, 1.0)
	return clampf(0.75 - 0.65 * f, 0.08, 0.8)


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
	# Credit cycle (Schularick-Taylor): a low real rate for too long inflates credit.
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
	c.debt_loc += c.y_nominal() * severity * 1.2  # bank rescue enters public debt
	world.global_risk = clampf(world.global_risk + 0.5 * sqrt(c.y_usd() / world.world_gdp()), 0.0, 1.0)
	world.emit_news(TranslationServer.translate("Crise bancária em %s: crédito congela e o Tesouro socorre bancos.") % c.name, "crise", c)


static func _newsworthy(c: Country, world: GameWorld) -> bool:
	return c == world.player or c.y_usd() > world.world_gdp() * NEWS_SHARE


## Recession, inflation and interest of the player make headlines; for other large economies, only recession.
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
	# The central bank announces when the rate has moved half a point since the last announcement.
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


## The starting point of each chart, so none appears empty in the first month. Real GDP ("y") already
## enters at the start and measures growth over 12 months; it must not repeat.
static func record_start(c: Country) -> void:
	_push_series(c)


static func _push_series(c: Country) -> void:
	c.push_hist("gdp", c.y_usd())
	c.push_hist("growth", c.growth_yoy())
	c.push_hist("infl", c.pi_yoy)
	c.push_hist("unemp", c.unemp)
	c.push_hist("real_wage", c.real_wage)
	c.push_hist("informal", c.informal)
	c.push_hist("debt", c.debt_ratio)
	c.push_hist("rate", c.rate)
	c.push_hist("deficit", c.deficit / maxf(c.y_nominal(), 0.001))
	c.push_hist("ca", c.ca_ratio)
	c.push_hist("fx", c.e)
	c.push_hist("approval", c.approval)
	c.push_hist("stability", c.stability)
	c.push_hist("stock", c.stock)
	c.push_hist("yield", c.yield_gov)
	c.push_hist("reserves", c.reserves)
	c.push_hist("swf", c.swf)
