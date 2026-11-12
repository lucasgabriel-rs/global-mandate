class_name Demography
extends RefCounted
## Demography in three age groups (0-14, 15-64, 65+): birth rate, mortality, aging and
## migration between countries. Total population stays in Country.pop; the groups are fractions of it.
## Runs on the simulation thread: no nodes or signals here.

const DT := 1.0 / 12.0
## Annual mortality of young people and adults; the rest of the deaths fall on the elderly.
const MORT_YOUNG := 0.0015
const MORT_ADULT := 0.003
## Migration: attraction difference (see _pull) below which nobody moves, annual rate per point
## of difference beyond it, refugees per year in war and annual caps, as a fraction of the population.
const NEUTRAL := 1.0
const RATE_IN := 0.0025
const RATE_OUT := 0.0025
const REFUGEES := 0.01
const MAX_IN := 0.008
const MAX_OUT := 0.04
## Part of social spending that is pensions and grows with the share of the elderly.
const PENSION_SHARE := 0.55
## Extra withdrawals per year from the working age when young people are lacking: where the birth rate has already fallen, the
## generations reaching 65 are larger than those entering at 15, and the country ages fast.
const AGING := 0.010
## Starting age structure (young 0-14, elderly 65+) of the largest countries, close to the
## UN estimates for 2024. The others use the income and growth formula.
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


## How rich the country is on a 0-1 scale (US$ 800 to US$ 50 thousand per capita).
static func _rich(pc_usd: float) -> float:
	return clampf(log(maxf(pc_usd, 1.0) / 800.0) / log(62.5), 0.0, 1.0)


## Plausible initial structure from income and population growth (% per year).
## `mig` is the initial net migration (fraction per year), already contained in `popg`.
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
	# Deaths per inhabitant: the elderly weigh; poor countries have higher mortality at all ages.
	c.death = clampf(0.004 + 0.055 * c.old + 0.004 * (1.0 - rich), 0.004, 0.016)
	c.birth = maxf(c.popg - mig + c.death, 0.005)
	c.birth0 = c.birth
	c.migration = mig
	# Stationary flows: with today's rates, the groups keep their weight in the first year.
	# Migrants enter as adults; `g` is the total growth, with migration.
	var g := c.birth - c.death + mig
	c.mort_old = maxf((c.death - MORT_YOUNG * c.young - MORT_ADULT * c.adult) / c.old, 0.02)
	c.k_young = clampf(c.birth / c.young - g - MORT_YOUNG, 0.03, 0.12)
	c.k_adult = clampf((c.k_young * c.young + mig - (g + MORT_ADULT) * c.adult) / c.adult, 0.004, 0.05)
	c.k_adult += AGING * maxf(1.0 - c.young / 0.25, 0.0)


## Old saves have no groups: builds the structure in the first step.
static func ensure(c: Country) -> void:
	if c.adult <= 0.0:
		init_country(c)


## One month of births, deaths and aging. Migration comes in through step_world.
static func step_month(c: Country, world: GameWorld) -> void:
	if not c.alive:
		return
	ensure(c)
	var rich := _rich(c.gdp_pc())
	# Longevity gain: elderly mortality falls ~1.5% a year.
	c.mort_old *= 1.0 - 0.015 * DT
	# Demographic transition: the birth rate falls slowly when income rises; war and crisis postpone children.
	var pc_rel := (c.y / maxf(c.pop, 0.001)) / maxf(c.pc0, 0.001)
	var b_target := c.birth0 * pow(clampf(pc_rel, 0.3, 3.0), -0.6)
	b_target *= 1.0 - 0.15 * c.mobilization - 0.15 * maxf(0.4 - c.stability, 0.0)
	c.birth += (maxf(b_target, 0.004) - c.birth) * 0.01
	# Health spending above the base lengthens life; war kills adults.
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


## Annexed territory: the population that arrives brings the age structure and rates of where it came from.
## Call before adding `pop` into `to.pop`. The bases (adult0, old0, birth0) are also mixed, so that
## work and pensions do not jump just because the country got bigger.
static func absorb(to: Country, from: Country, pop: float) -> void:
	if pop <= 0.0:
		return
	ensure(to)
	ensure(from)
	var w := pop / maxf(to.pop + pop, 0.001)
	for f: String in ["young", "adult", "old", "adult0", "old0", "birth", "birth0", "death", "k_young", "k_adult", "mort_old"]:
		to.set(f, lerpf(float(to.get(f)), float(from.get(f)), w))


## Labor supply relative to population: fewer people of working age, fewer workers.
static func labor_factor(c: Country) -> float:
	if c.adult0 <= 0.0:
		return 1.0
	return c.adult / c.adult0


## Extra spending (fraction of GDP) on pensions because there are more elderly people than at the start.
static func pension_extra(c: Country) -> float:
	if c.old0 <= 0.0:
		return 0.0
	return c.sp_social * PENSION_SHARE * (c.old / c.old0 - 1.0)


## A country's attraction for migrants: income, peace and stability.
static func _pull(c: Country, world: GameWorld) -> float:
	var v := log(maxf(c.gdp_pc(), 300.0) / 1000.0)
	v += 2.0 * (c.stability - 0.5)
	if world.diplomacy.in_war(c.idx):
		v -= 1.5
	v -= 3.0 * c.occupied
	return v


## People entering (positive) or leaving (negative) each country in a month, in millions.
## Per-inhabitant rates: whoever is well above the weighted average attracts, whoever is well below loses;
## the middle band barely moves. War and occupation add refugees. Inflows and outflows
## are scaled to offset each other: migration does not change the world population.
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
	# Only those with somewhere to go migrate: the larger side shrinks until it equals the smaller.
	var moved := minf(leaving, arriving)
	var s_out := moved / leaving if leaving > 0.0 else 0.0
	var s_in := moved / arriving if arriving > 0.0 else 0.0
	for i in n:
		net[i] = inn[i] * s_in - out[i] * s_out
	return net


## Initial net migration rate of each country, so the birth rate does not count twice the
## growth that in the data already includes immigrants.
static func init_world(world: GameWorld) -> void:
	var net := _flows(world)
	for c: Country in world.countries:
		if c.alive:
			init_country(c, net[c.idx] / maxf(c.pop * DT, 0.000001))


## Monthly migration, after all countries have closed births and deaths.
static func step_world(world: GameWorld) -> void:
	var net := _flows(world)
	for c: Country in world.countries:
		if not c.alive:
			continue
		var moved: float = net[c.idx]
		# Whoever migrates is almost always an adult of working age.
		_set_bands(c, c.young * c.pop, maxf(c.adult * c.pop + moved, 0.001), c.old * c.pop)
		c.migration += (moved / maxf(c.pop * DT, 0.000001) - c.migration) * 0.2
