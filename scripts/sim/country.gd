class_name Country
extends RefCounted
## Full state of a country. Rates and ratios are fractions (0.05 = 5%).
## Monetary values are in US$ billions at base prices unless noted.

# Identity
var idx := 0
var iso := ""
var name := ""
var region := ""
var blocs := PackedStringArray()
var dem := 5.0                 # democracy index, 0-10
var peg := 0                   # 0 floating, 1 pegged to the US$, 2 monetary union (euro)
var alive := true
var annexed_by := -1
var center := Vector2.ZERO
var area := 1.0

# Output
var pop := 1.0                 # millions
var popg := 0.0
# Demography (see Demography): population shares by age group and annual rates.
var young := 0.0               # 0-14 years
var adult := 0.0               # 15-64 years
var old := 0.0                 # 65+
var adult0 := 0.0
var old0 := 0.0
var birth := 0.0               # births per inhabitant per year
var birth0 := 0.0
var death := 0.0
var k_young := 0.0             # share of young people who become adults each year
var k_adult := 0.0             # share of adults who retire each year
var mort_old := 0.0
var migration := 0.0           # net migration per year, as a fraction of the population
var y := 1.0                   # real GDP
var y_pot := 1.0               # potential GDP
var y0 := 1.0
var gap := 0.0
var capital := 1.0
var tfp := 1.0
var human := 1.0
var labor := 1.0
var g_tfp0 := 0.01
var g0 := 0.02
var pc0 := 1.0                 # initial real GDP per capita, convergence reference
var inv_share0 := 0.2
var occupied := 0.0            # share of the territory occupied by enemies
var damage := 0.0              # share of potential output lost to recent destruction

# Demand / shocks
var demand_shock := 0.0
var supply_shock := 0.0
var noise := 0.0
var conf := 0.6
var credit_gap := 0.0
var rgap := 0.0
var crisis_cooldown := 0.0

# Prices and currency
var p := 1.0                   # price level
var p_hist := PackedFloat32Array()
var pi_core := 0.02
var pi_e := 0.02
var pi_yoy := 0.02
var pi_target := 0.02
var cred := 0.7                # central bank credibility, 0-1
var rate := 0.03               # policy rate
var r_n := 0.01                # neutral real rate
## When independent, the central bank sets the rate by itself: neither the country's government nor the player chooses it.
var cb_independent := true
var rate_manual := false
var rate_set := 0.03
## Last rate announced in the news (negative: none yet).
var rate_said := -1.0
var e := 1.0                   # local currency per US$ (index, 1 at the start)
var rer := 1.0
var rer_ref := 1.0

# Fiscal policy (fractions of GDP)
var tax_income := 0.1
var tax_consumption := 0.08
var tax_corporate := 0.03
var tax0 := 0.21
var rent_take := 0.0           # state share of commodity export revenue
var sp_social := 0.1
var sp_health := 0.05
var sp_education := 0.04
var sp_infra := 0.02
var sp_defense := 0.02
var sp_admin := 0.03
var sp0 := {}
var tariff := 0.0              # general import tariff
var mon_fin := 0.0             # share of the deficit financed by money issuance
var g_ref := 0.3
var t_ref := 0.3
var mobilization := 0.0
var aid_flow := 0.0            # net foreign aid received, US$ bn/year
var reparations := 0.0

# Public accounts (annualized flows)
var revenue := 0.0
var spending := 0.0
var interest := 0.0
var deficit := 0.0
var debt_loc := 0.0            # debt in local currency (base-price units)
var debt_fx := 0.0             # debt in US$
var debt_ratio := 0.5
var debt_tol := 0.6
var avg_rate := 0.04
var avg_fx := 0.05             # average cost of the US$ debt (pays no local nominal interest)
var yield_gov := 0.05
var yield_mult := 1.0          # part of poor countries' debt is concessional
var risk := 0.01
var risk0 := 0.01
var rating := "BBB"
var default_until := -1.0      # year until which the country has no market access
var imf_program := 0.0         # months left in the IMF program

# External sector (US$ bn/year)
var x_share := 0.2
var m_share := 0.2
var ca_resid := 0.0
var exports := 0.0
var imports := 0.0
var comm_exports := 0.0
var ca := 0.0
var ca_ratio := 0.0
var ca0 := 0.0
var reserves := 10.0
# Exchange rate: central bank intervention, capital controls, flight and dollarization
var fx_lean := 0.3             # how much of the exchange rate move the central bank holds back, 0-1
var fx_interv := 0.0           # net reserve sales in the month, annualized (US$ bn/year; negative = purchase)
var cap_controls := 0.0        # capital controls, 0 (free) to 1 (closed)
var cap_flight := 0.0          # capital outflow, annualized (US$ bn/year)
var dollarization := 0.0       # share of deposits and prices in dollars, 0-1
var uip_dep := 0.0             # depreciation expected by uncovered parity: i - i* - premium
var res_ratio0 := 0.0          # starting reserves as a share of dollar GDP: the cushion the central bank rebuilds
# Sovereign wealth fund (US$ bn): invests abroad, receives commodity revenue and surpluses
var swf := 0.0
var swf_active := false
var swf_rent_share := 0.0      # share of the state's commodity revenue that goes to the fund
var swf_surplus_share := 0.0   # share of the nominal surplus that goes to the fund
var swf_limit := 0.0           # maximum annual withdrawal, as a share of the balance
var swf_in := 0.0              # contribution for the year (local currency, bn/year)
var swf_out := 0.0             # withdrawal for the year (local currency, bn/year)
var swf_return := 0.0          # return of the last month, annualized
var swf_pain := 0.0            # approval lost for withdrawing above the return
var swf_flow0 := 0.0          # net flow of the fund at the start, share of GDP
var rent_ref := 0.0            # average commodity revenue, for the fund's buffer
var trade_loss := 0.0
var trade0 := 0.0              # frictions already built into the base GDP (2024 sanctions etc.)
var press0 := 0.0
var occ0 := 0.0
var ext_demand := 0.0
var stock := 100.0             # stock index; Corporate is what moves it

# Sectors (see Sectors): shares of GDP that sum to 1, real output per sector and external impulses
var sector_base := PackedFloat32Array()
var sector_bias := PackedFloat32Array()
var sector_share := PackedFloat32Array()
var sector_out := PackedFloat32Array()
## Productivity gain per sector that other systems apply (0.03 = +3%). Infrastructure and companies add to it.
var sector_boost := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var sector_drought := 0.0
## Money of the month, in US$ bn, that enters or leaves the Treasury outside taxes and norms:
## dividends of state companies, sale of stakes, works at ports and airports.
var extra_rev_bucket := 0.0
var extra_spend_bucket := 0.0
## Logistics capacity of ports and airports against demand: 1 is neutral, below it trade chokes.
var logistics := 1.0

# Commodities: base production/consumption per market and relative capacity
var prod := PackedFloat32Array([0, 0, 0, 0, 0])
var use := PackedFloat32Array([0, 0, 0, 0, 0])
var prod_factor := PackedFloat32Array([1, 1, 1, 1, 1])
var p_ref := PackedFloat32Array([1, 1, 1, 1, 1])

# Labor market and politics
var unemp := 0.05
var unemp_n := 0.05
var approval := 0.5
var stability := 0.6
var inequality := 0.38
var next_election := 0.0
## Effects of the norms in force. The "bucket" fields are the money of the month, in US$ bn.
var law_rev_bucket := 0.0
var law_spend_bucket := 0.0
## The same money added up since the last monthly closing of the norms: Economy zeroes the "bucket" fields on
## the country's fiscal step day, which does not coincide with the closing.
var law_rev_month := 0.0
var law_spend_month := 0.0
var law_tax := 0.0             # annual weight of the norms' taxes, as a fraction of GDP
var law_spend := 0.0           # annual weight of the norms' spending, as a fraction of GDP
var law_approval := 0.0
var law_stability := 0.0
var law_invest := 0.0
var law_unemp := 0.0
# Channels of the legal codes (LawCode.monthly): inequality, labor supply, productivity and evasion.
var law_inequality := 0.0      # deviation of the Gini from the country's base
var law_labor := 0.0           # extra or missing share of labor supply
var law_tfp := 0.0             # extra annual TFP growth
var law_evasion := 0.0         # share of revenue lost to tax evasion
# Corruption (see Corruption): real level, starting level and what public opinion sees, from 0 to 1.
var corruption := 0.0
var corruption0 := 0.0
var corr_seen := 0.0
var inequality0 := 0.38        # starting Gini, to which inequality slowly returns
## Own indicators of the codes (crime, pension coverage...), by key.
var code_stats := {}
var regime_age := 0.0
var unrest := 0.0
var influence := 0.0

# Military
var troops := 10.0             # thousands
var troops0 := 10.0
var mil_stock := 1.0           # equipment stock, US$ bn PPP
var nukes := 0
var aggression := 0.2
var war_exhaustion := 0.0
var stance_offensive := false
var client_of := -1

# Monthly series for charts
var hist := {}


func y_usd() -> float:
	return y * p / e


func y_nominal() -> float:
	return y * p


func gdp_pc() -> float:
	return y_usd() * 1000.0 / maxf(pop, 0.001)


func growth_yoy() -> float:
	var s: PackedFloat32Array = hist.get("y", PackedFloat32Array())
	if s.size() < 13:
		return g0
	return y / maxf(s[s.size() - 13], 0.0001) - 1.0


func tax_total() -> float:
	return tax_income + tax_consumption + tax_corporate


func spend_total() -> float:
	return sp_social + sp_health + sp_education + sp_infra + sp_defense + sp_admin


func military_power() -> float:
	var tech := clampf(0.55 + 0.17 * log(maxf(gdp_pc(), 300.0) / 1000.0), 0.45, 1.25)
	var morale := clampf(0.55 + 0.6 * stability - 0.3 * war_exhaustion, 0.25, 1.1)
	return pow(maxf(mil_stock, 0.01), 0.65) * pow(maxf(troops, 0.1), 0.35) * tech * morale * (1.0 + 0.7 * mobilization)


## Rescales the past real GDP when the territory changes: growth then compares the country with
## itself within the current borders, and annexing or ceding land does not show up as growth or recession.
func rebase_territory(ratio: float) -> void:
	var s: PackedFloat32Array = hist.get("y", PackedFloat32Array())
	for i in s.size():
		s[i] *= ratio
	hist["y"] = s


func push_hist(key: String, value: float) -> void:
	var s: PackedFloat32Array = hist.get(key, PackedFloat32Array())
	s.append(value)
	if s.size() > 480:
		s = s.slice(s.size() - 480)
	hist[key] = s


func to_dict() -> Dictionary:
	var out := {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[prop.name] = get(prop.name)
	return out


static func from_dict(d: Dictionary) -> Country:
	var c := Country.new()
	for k in d:
		c.set(k, d[k])
	# Old saves do not have the field.
	if not d.has("cb_independent"):
		c.cb_independent = c.dem >= Economy.CB_INDEPENDENT_DEM or c.peg == 2
	return c
