class_name Country
extends RefCounted
## Estado completo de um país. Taxas e razões são frações (0.05 = 5%).
## Valores monetários em bilhões de US$ a preços-base, salvo indicação.

# Identidade
var idx := 0
var iso := ""
var name := ""
var region := ""
var blocs := PackedStringArray()
var dem := 5.0                 # índice de democracia, 0-10
var peg := 0                   # 0 flutuante, 1 âncora no US$, 2 união monetária (euro)
var alive := true
var annexed_by := -1
var center := Vector2.ZERO
var area := 1.0

# Produção
var pop := 1.0                 # milhões
var popg := 0.0
var y := 1.0                   # PIB real
var y_pot := 1.0               # PIB potencial
var y0 := 1.0
var gap := 0.0
var capital := 1.0
var tfp := 1.0
var human := 1.0
var labor := 1.0
var g_tfp0 := 0.01
var g0 := 0.02
var pc0 := 1.0                 # PIB per capita inicial (real), referência de convergência
var inv_share0 := 0.2
var occupied := 0.0            # fração do território ocupada por inimigos
var damage := 0.0              # fração do potencial perdida por destruição recente

# Demanda / choques
var demand_shock := 0.0
var supply_shock := 0.0
var noise := 0.0
var conf := 0.6
var credit_gap := 0.0
var rgap := 0.0
var crisis_cooldown := 0.0

# Preços e moeda
var p := 1.0                   # nível de preços
var p_hist := PackedFloat32Array()
var pi_core := 0.02
var pi_e := 0.02
var pi_yoy := 0.02
var pi_target := 0.02
var cred := 0.7                # credibilidade do banco central, 0-1
var rate := 0.03               # taxa básica
var r_n := 0.01                # juro real neutro
## Independente, o banco central decide o juro sozinho: nem o governo do país, nem o jogador, escolhem.
var cb_independent := true
var rate_manual := false
var rate_set := 0.03
var e := 1.0                   # moeda local por US$ (índice, 1 no início)
var rer := 1.0
var rer_ref := 1.0

# Política fiscal (frações do PIB)
var tax_income := 0.1
var tax_consumption := 0.08
var tax_corporate := 0.03
var tax0 := 0.21
var rent_take := 0.0           # fatia estatal das receitas de exportação de commodities
var sp_social := 0.1
var sp_health := 0.05
var sp_education := 0.04
var sp_infra := 0.02
var sp_defense := 0.02
var sp_admin := 0.03
var sp0 := {}
var tariff := 0.0              # tarifa geral de importação
var mon_fin := 0.0             # fração do déficit financiada por emissão
var g_ref := 0.3
var t_ref := 0.3
var mobilization := 0.0
var aid_flow := 0.0            # ajuda externa líquida recebida, US$ bi/ano
var reparations := 0.0

# Contas públicas (fluxos anualizados)
var revenue := 0.0
var spending := 0.0
var interest := 0.0
var deficit := 0.0
var debt_loc := 0.0            # dívida em moeda local (unidades de preços-base)
var debt_fx := 0.0             # dívida em US$
var debt_ratio := 0.5
var debt_tol := 0.6
var avg_rate := 0.04
var avg_fx := 0.05             # custo médio da dívida em US$ (não paga juro nominal local)
var yield_gov := 0.05
var yield_mult := 1.0          # parte da dívida de países pobres é concessional
var risk := 0.01
var risk0 := 0.01
var rating := "BBB"
var default_until := -1.0      # ano até o qual está sem acesso ao mercado
var imf_program := 0.0         # meses restantes de programa com o FMI

# Setor externo (US$ bi/ano)
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
var trade_loss := 0.0
var trade0 := 0.0              # atritos já embutidos no PIB-base (sanções de 2024 etc.)
var press0 := 0.0
var occ0 := 0.0
var ext_demand := 0.0
var stock := 100.0             # índice da bolsa; quem o move é o Corporate

# Setores (ver Sectors): frações do PIB que somam 1, produto real por setor e impulsos externos
var sector_base := PackedFloat32Array()
var sector_bias := PackedFloat32Array()
var sector_share := PackedFloat32Array()
var sector_out := PackedFloat32Array()
## Ganho de produtividade por setor que outros sistemas aplicam (0.03 = +3%). Infraestrutura e empresas somam aqui.
var sector_boost := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var sector_drought := 0.0
## Dinheiro do mês, em US$ bi, que entra ou sai do Tesouro fora dos tributos e das normas:
## dividendos de estatais, venda de participações, obras em portos e aeroportos.
var extra_rev_bucket := 0.0
var extra_spend_bucket := 0.0
## Capacidade logística de portos e aeroportos frente à demanda: 1 é neutro, abaixo disso o comércio engasga.
var logistics := 1.0

# Commodities: produção/consumo-base por mercado e capacidade relativa
var prod := PackedFloat32Array([0, 0, 0, 0, 0])
var use := PackedFloat32Array([0, 0, 0, 0, 0])
var prod_factor := PackedFloat32Array([1, 1, 1, 1, 1])
var p_ref := PackedFloat32Array([1, 1, 1, 1, 1])

# Mercado de trabalho e política
var unemp := 0.05
var unemp_n := 0.05
var approval := 0.5
var stability := 0.6
var inequality := 0.38
var next_election := 0.0
## Efeitos das normas em vigor. Os "bucket" são o dinheiro do mês, em US$ bi.
var law_rev_bucket := 0.0
var law_spend_bucket := 0.0
var law_tax := 0.0             # peso anual dos tributos das normas, em fração do PIB
var law_spend := 0.0           # peso anual das despesas das normas, em fração do PIB
var law_approval := 0.0
var law_stability := 0.0
var law_invest := 0.0
var law_unemp := 0.0
var regime_age := 0.0
var unrest := 0.0
var influence := 0.0

# Militar
var troops := 10.0             # mil
var troops0 := 10.0
var mil_stock := 1.0           # estoque de equipamento, US$ bi PPC
var nukes := 0
var aggression := 0.2
var war_exhaustion := 0.0
var stance_offensive := false
var client_of := -1

# Séries mensais para gráficos
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
	# Saves antigos não têm o campo.
	if not d.has("cb_independent"):
		c.cb_independent = c.dem >= Economy.CB_INDEPENDENT_DEM or c.peg == 2
	return c
