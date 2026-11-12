class_name Markets
extends RefCounted
## Global commodity markets with storage theory: the price responds to the
## stock/consumption ratio; supply and demand react to the price with a lag.

const OIL := 0
const GAS := 1
const GRAIN := 2
const METAL := 3
const CHIP := 4
# i18n-begin
const NAMES := ["Petróleo", "Gás", "Grãos", "Metais", "Chips"]
# i18n-end
# i18n-begin
const UNITS := ["US$/bbl", "US$/MMBtu", "US$/t", "índice", "índice"]
# i18n-end
const P0 := [78.0, 9.0, 260.0, 100.0, 100.0]
# Conversion factor from physical unit/year to US$ bn/year at the base price.
# Oil: mb/d * 365 * US$78 / 1000. Gas: bcm * 36 MMBtu/thousand m³ * US$9 / 1000.
# Grains: Mt * US$260 / 1000. Metals and chips: share points in markets of
# ~US$ 1.4 tn and ~US$ 600 bn.
const VALUE_PER_UNIT := [28.47, 0.324, 0.26, 14.0, 6.0]
const DEMAND_ELAST := [0.12, 0.15, 0.10, 0.25, 0.30]
const SUPPLY_RESP := [0.20, 0.20, 0.45, 0.18, 0.12]
const PRICE_ELAST := [0.45, 0.55, 0.45, 0.60, 0.50]  # inverse sensitivity of price to stock
const VOL := [0.018, 0.022, 0.012, 0.012, 0.006]     # daily vol.
## Monthly step calibrated to reproduce the old daily model (8% a day pull toward the target and
## AR(1) noise with 0.97 memory): the same change from one month to the next (5.8% for oil) and the same
## oscillation around the target. The noise memory and the decay of shocks are the daily ones raised to 30.4.
const PRICE_PULL_MONTH := 0.76
const NOISE_KEEP_MONTH := 0.396
const NOISE_SD_MONTH := 3.75
const SHOCK_KEEP_MONTH := 0.928
const INCOME_ELAST := [0.45, 0.5, 0.3, 0.8, 1.0]     # demand grows less than GDP (efficiency gain)
const STOCK_YEARS := [0.10, 0.10, 0.30, 0.25, 0.15]  # normal stock, in years of consumption
const CAPACITY_TREND := [0.008, 0.012, 0.008, 0.02, 0.035]  # annual capacity expansion

var price := PackedFloat64Array(P0)
var inv := PackedFloat64Array([1, 1, 1, 1, 1])       # stock in years of consumption / norm
var supply := PackedFloat64Array([0, 0, 0, 0, 0])
var demand := PackedFloat64Array([0, 0, 0, 0, 0])
var supply0 := PackedFloat64Array([0, 0, 0, 0, 0])
var capacity := PackedFloat64Array([1, 1, 1, 1, 1])
var demand_trend := PackedFloat64Array([1, 1, 1, 1, 1])
var shock := PackedFloat64Array([0, 0, 0, 0, 0])
var noise := PackedFloat64Array([0, 0, 0, 0, 0])
var chokepoint := 0.0  # share of oil/gas supply blocked by a strait
var opec_quota := 0.0
var hist := {}


func setup(world: GameWorld) -> void:
	var total_prod := PackedFloat64Array([0, 0, 0, 0, 0])
	for c: Country in world.countries:
		for i in 5:
			total_prod[i] += c.prod[i]
	# Base consumption: different intensity per market, normalized to match production.
	var raw := PackedFloat64Array([0, 0, 0, 0, 0])
	var weights: Array = []
	for c: Country in world.countries:
		var g := c.y_usd()
		var w := [
			pow(g, 0.70) * pow(c.pop, 0.30),
			pow(g, 0.80) * pow(c.pop, 0.20),
			pow(g, 0.20) * pow(c.pop, 0.80),
			pow(g, 0.85) * pow(c.pop, 0.15),
			g,
		]
		weights.append(w)
		for i in 5:
			raw[i] += w[i]
	for ci in world.countries.size():
		var c: Country = world.countries[ci]
		for i in 5:
			c.use[i] = weights[ci][i] / raw[i] * total_prod[i]
	for i in 5:
		supply0[i] = total_prod[i]
		supply[i] = total_prod[i]
		demand[i] = total_prod[i]
	for i in 5:
		push_hist(i)


func value_usd(market: int, amount: float) -> float:
	return amount * float(VALUE_PER_UNIT[market]) * price[market] / float(P0[market])


## One month of market at once, at the start of each month, after the countries close the month.
func step_month(world: GameWorld, rng: RandomNumberGenerator) -> void:
	var dt := 1.0 / 12.0
	var s := PackedFloat64Array([0, 0, 0, 0, 0])
	var d := PackedFloat64Array([0, 0, 0, 0, 0])
	for c: Country in world.countries:
		if not c.alive:
			continue
		var activity := c.y / c.y0
		for i in 5:
			s[i] += c.prod[i] * c.prod_factor[i]
			d[i] += c.use[i] * pow(activity, INCOME_ELAST[i])
	for i in 5:
		var rel_price: float = price[i] / (P0[i] * world.global_price_index())
		var effective_d: float = d[i] * pow(rel_price, -DEMAND_ELAST[i])
		var effective_s: float = s[i] * capacity[i]
		if i <= GAS:
			effective_s *= 1.0 - chokepoint
		if i == OIL:
			effective_s *= 1.0 - opec_quota
		# Weather events and the like act as a temporary loss of supply.
		effective_s *= 1.0 - clampf(shock[i], -0.2, 0.6)
		supply[i] = effective_s
		demand[i] = effective_d
		# Stock as fractions of a year of normalized consumption; 1.0 = normal level.
		inv[i] = clampf(inv[i] + (effective_s - effective_d) / maxf(supply0[i], 0.001) * dt / float(STOCK_YEARS[i]), 0.35, 2.6)
		# Capacity investment follows the real price with a lag of years.
		capacity[i] *= 1.0 + (SUPPLY_RESP[i] * clampf(log(rel_price), -1.0, 1.2) + CAPACITY_TREND[i]) * dt
		capacity[i] = clampf(capacity[i], 0.4, 6.0)
		noise[i] = noise[i] * NOISE_KEEP_MONTH + rng.randfn(0.0, VOL[i] * NOISE_SD_MONTH)
		var target: float = log(P0[i] * world.global_price_index()) - log(inv[i]) / PRICE_ELAST[i] + noise[i]
		var lp: float = log(price[i])
		price[i] = exp(lp + (target - lp) * PRICE_PULL_MONTH)
		shock[i] *= SHOCK_KEEP_MONTH


func relative_price(market: int, world: GameWorld) -> float:
	return price[market] / (float(P0[market]) * world.global_price_index())


func push_hist(market: int) -> void:
	var a: PackedFloat32Array = hist.get(market, PackedFloat32Array())
	a.append(price[market])
	if a.size() > 480:
		a = a.slice(a.size() - 480)
	hist[market] = a


func to_dict() -> Dictionary:
	return {
		"price": price, "inv": inv, "supply": supply, "demand": demand, "supply0": supply0,
		"capacity": capacity, "shock": shock, "noise": noise, "chokepoint": chokepoint,
		"opec_quota": opec_quota, "hist": hist,
	}


func from_dict(d: Dictionary) -> void:
	for k in d:
		set(k, d[k])
