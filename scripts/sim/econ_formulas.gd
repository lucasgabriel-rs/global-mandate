class_name EconFormulas
extends RefCounted
## Leis e fórmulas de livro-texto usadas pela simulação, como funções puras: a Economia, os Mercados e os
## Setores chamam estas funções, os testes as comparam com casos de manual e a janela "Como funciona"
## mostra cada uma com os números do país. Taxas em fração ao ano (0,05 = 5%).
## Fora daqui ficam Okun (sessão de trabalho), paridade de juros (câmbio) e dinâmica da dívida/Fisher.

## Velocidade-renda da moeda ampla (M2 ≈ 45% do PIB nominal): V = P·Y / M.
const VELOCITY := 2.2
## Propensão marginal a consumir das famílias.
const MPC := 0.6
## Fração ricardiana: parte de um corte de imposto que as famílias poupam à espera do imposto futuro.
const RICARDIAN_BASE := 0.3
## Elasticidade da renda tributável (estimativa central de Saez, Slemrod e Giertz, 2012): a arrecadação
## máxima fica em t* = 1/(1+ε) ≈ 77%.
const LAFFER_ETI := 0.3
## Elasticidades-preço de exportação e importação no longo prazo (Marshall-Lerner: soma > 1).
const ELAST_X := 0.6
const ELAST_M := 0.5
## Meses para os volumes do comércio responderem ao câmbio real (curva J).
const J_LAG_MONTHS := 12.0
## Peso dos bens comercializáveis na cesta de consumo (Balassa-Samuelson).
const TRADABLE_SHARE := 0.45
## Elasticidades do modelo gravitacional estimadas na literatura.
const GRAVITY_MASS := 0.9
const GRAVITY_DIST := 1.05


# --- Moeda -------------------------------------------------------------------------------------------

## Equação quantitativa M·V = P·Y resolvida para o nível de preços.
static func quantity_price(m: float, v: float, y: float) -> float:
	return m * v / maxf(y, 1e-9)


## Em taxas: π = μ + Δv − g (crescimento da moeda, da velocidade e do produto real).
static func quantity_inflation(money_growth: float, velocity_growth: float, real_growth: float) -> float:
	return (1.0 + money_growth) * (1.0 + velocity_growth) / (1.0 + real_growth) - 1.0


## Crescimento da moeda causado pela emissão para cobrir o déficit: μ = emissão / M = (emissão / PY)·V.
static func monetized_money_growth(financed_share: float, deficit_ratio: float, v := VELOCITY) -> float:
	return clampf(financed_share, 0.0, 1.0) * maxf(deficit_ratio, 0.0) * v


## Senhoriagem real: S = ΔM / P.
static func seigniorage(delta_m: float, p: float) -> float:
	return delta_m / maxf(p, 1e-9)


## Imposto inflacionário: perda real dos detentores de moeda, π/(1+π) · M/P.
static func inflation_tax(pi: float, real_balances: float) -> float:
	return pi / (1.0 + pi) * real_balances


# --- Setor externo -----------------------------------------------------------------------------------

## Condição de Marshall-Lerner: a desvalorização melhora a balança se |εx| + |εm| > 1.
static func marshall_lerner(ex: float, em: float) -> bool:
	return absf(ex) + absf(em) > 1.0


## Variação da balança comercial (fração das exportações, partindo de balança equilibrada) após uma
## desvalorização real d (log), com os volumes ajustados na fração `adjust` (0 = impacto, 1 = longo prazo).
## Impacto: as importações ficam mais caras antes de os volumes mudarem → piora (fundo da curva J).
static func j_curve(d: float, ex: float, em: float, adjust: float) -> float:
	var a := clampf(adjust, 0.0, 1.0)
	return d * (a * (absf(ex) + absf(em)) - 1.0)


## Câmbio real que os volumes do comércio "enxergam": média móvel exponencial com defasagem J_LAG_MONTHS.
static func lagged_rer(prev: float, rer: float, lag_months := J_LAG_MONTHS) -> float:
	return exp(log(prev) + (log(rer) - log(prev)) / maxf(lag_months, 1.0))


## Paridade do poder de compra relativa: depreciação esperada = (1+π)/(1+π*) − 1.
static func ppp_depreciation(pi: float, pi_foreign: float) -> float:
	return (1.0 + pi) / (1.0 + pi_foreign) - 1.0


## PPC absoluta: câmbio de equilíbrio E = P / P*.
static func ppp_rate(p: float, p_foreign: float) -> float:
	return p / maxf(p_foreign, 1e-9)


## Balassa-Samuelson: apreciação real anual = (1−γ)·[(aT − aN) − (aT* − aN*)], com γ o peso dos
## comercializáveis. Produtividade dos comercializáveis crescendo mais rápido encarece os serviços.
static func balassa_samuelson(g_t: float, g_n: float, g_t_f: float, g_n_f: float, gamma := TRADABLE_SHARE) -> float:
	return (1.0 - gamma) * ((g_t - g_n) - (g_t_f - g_n_f))


## Modelo gravitacional: T = G · Yi^a · Yj^b / D^θ.
static func gravity(yi: float, yj: float, dist: float, g := 1.0, a := GRAVITY_MASS, b := GRAVITY_MASS, theta := GRAVITY_DIST) -> float:
	return g * pow(maxf(yi, 0.0), a) * pow(maxf(yj, 0.0), b) / pow(maxf(dist, 1e-9), theta)


## Doença holandesa: queda da fatia da indústria quando a renda de recursos naturais sobe. Efeito
## gasto (câmbio real aprecia) mais efeito deslocamento de fatores; ~0,5 p.p. de indústria por p.p. de renda.
static func dutch_disease(resource_rent_change: float, k := 0.5) -> float:
	return -k * resource_rent_change


# --- Política fiscal ---------------------------------------------------------------------------------

## Multiplicador keynesiano numa economia aberta com imposto proporcional: 1 / (1 − c(1 − t) + m).
static func keynes_multiplier(c: float, t: float, m: float) -> float:
	return 1.0 / (1.0 - c * (1.0 - t) + m)


## Multiplicador do imposto: −c·k, reduzido pela fração ricardiana θ (0 = keynesiano, 1 = equivalência plena).
static func tax_multiplier(c: float, t: float, m: float, ricardian: float) -> float:
	return c * keynes_multiplier(c, t, m) * (1.0 - clampf(ricardian, 0.0, 1.0))


## Equivalência ricardiana parcial: quanto mais endividado o país, mais as famílias antecipam o imposto futuro.
static func ricardian_share(debt_ratio: float, debt_tol: float) -> float:
	return clampf(RICARDIAN_BASE + 0.25 * maxf(debt_ratio / maxf(debt_tol, 0.01) - 1.0, 0.0), 0.0, 0.8)


## Curva de Laffer com elasticidade da renda tributável: a base é B = B0·((1−t)/(1−t0))^ε.
static func laffer_base(t: float, t0: float, eti := LAFFER_ETI) -> float:
	return pow(maxf(1.0 - t, 0.01) / maxf(1.0 - t0, 0.01), eti)


static func laffer_revenue(t: float, t0: float, eti := LAFFER_ETI) -> float:
	return t * laffer_base(t, t0, eti)


## Alíquota que maximiza a arrecadação: t* = 1 / (1 + ε).
static func laffer_peak(eti := LAFFER_ETI) -> float:
	return 1.0 / (1.0 + eti)


# --- Crescimento, preços e juros ---------------------------------------------------------------------

## Produção Cobb-Douglas com capital humano: Y = A · K^α · (h·L)^(1−α).
static func cobb_douglas(a: float, k: float, hl: float, alpha: float) -> float:
	return a * pow(maxf(k, 1e-9), alpha) * pow(maxf(hl, 1e-9), 1.0 - alpha)


## Solow: capital por trabalhador efetivo no estado estacionário, k* = (s / (n + g + δ))^(1/(1−α)).
static func solow_k_star(s: float, n: float, g: float, delta: float, alpha: float) -> float:
	return pow(s / (n + g + delta), 1.0 / (1.0 - alpha))


static func solow_y_star(s: float, n: float, g: float, delta: float, alpha: float) -> float:
	return pow(solow_k_star(s, n, g, delta, alpha), alpha)


## Razão capital/produto de equilíbrio: K/Y = s / (n + g + δ).
static func solow_ky(s: float, n: float, g: float, delta: float) -> float:
	return s / (n + g + delta)


## Curva de Phillips aumentada pelas expectativas: π = πe + κ·hiato + choque de oferta.
## (Pela lei de Okun, κ·hiato equivale a −β(u − u*).)
static func phillips(pi_e: float, kappa: float, gap: float, supply_shock := 0.0) -> float:
	return pi_e + kappa * gap + supply_shock


## Regra de Taylor (1993): i = r* + π + φπ(π − π*) + φy·hiato, com φπ = φy = 0,5.
static func taylor(r_star: float, pi: float, pi_target: float, gap: float, phi_pi := 0.5, phi_y := 0.5) -> float:
	return r_star + pi + phi_pi * (pi - pi_target) + phi_y * gap


## Regra de Hotelling: a renda de escassez (preço − custo marginal) cresce à taxa de juro real.
static func hotelling_rent(rent0: float, r: float, years: float) -> float:
	return rent0 * pow(1.0 + r, years)


## Preço de um recurso esgotável: custo de extração mais a renda de Hotelling.
static func hotelling_price(p0: float, rent_share: float, r: float, years: float) -> float:
	return p0 * (1.0 - rent_share) + hotelling_rent(p0 * rent_share, r, years)


# --- Distribuição ------------------------------------------------------------------------------------

## Gini a partir de rendas individuais (fórmula da média das diferenças absolutas).
static func gini(incomes: PackedFloat64Array) -> float:
	var v := incomes.duplicate()
	v.sort()
	var n := v.size()
	if n == 0:
		return 0.0
	var acc := 0.0
	var total := 0.0
	for i in n:
		acc += (2.0 * (i + 1) - n - 1) * v[i]
		total += v[i]
	return acc / (n * maxf(total, 1e-12))


## Gini como 1 − 2·(área sob a curva de Lorenz), com pontos (p, L) em ordem e regra do trapézio.
static func gini_from_lorenz(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(1, points.size()):
		area += (points[i].x - points[i - 1].x) * (points[i].y + points[i - 1].y) * 0.5
	return 1.0 - 2.0 * area


## Curva de Lorenz lognormal com o Gini dado: L(p) = Φ(Φ⁻¹(p) − σ), σ = √2 · Φ⁻¹((G+1)/2).
static func lorenz(p: float, g: float) -> float:
	if p <= 0.0:
		return 0.0
	if p >= 1.0:
		return 1.0
	var sigma := sqrt(2.0) * norm_inv((clampf(g, 0.0, 0.99) + 1.0) * 0.5)
	return norm_cdf(norm_inv(p) - sigma)


## Fatia da renda de cada quinto da população, do mais pobre ao mais rico.
static func quintile_shares(g: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var prev := 0.0
	for q in range(1, 6):
		var l := lorenz(q / 5.0, g)
		out.append(l - prev)
		prev = l
	return out


static func norm_cdf(x: float) -> float:
	return 0.5 * (1.0 + _erf(x / sqrt(2.0)))


## Inversa da normal padrão (Acklam), erro < 1e-8.
static func norm_inv(p: float) -> float:
	var a := [-39.69683028665376, 220.9460984245205, -275.9285104469687, 138.3577518672690, -30.66479806614716, 2.506628277459239]
	var b := [-54.47609879822406, 161.5858368580409, -155.6989798598866, 66.80131188771972, -13.28068155288572]
	var c := [-0.007784894002430293, -0.3223964580411365, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783]
	var d := [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416]
	var q: float
	if p < 0.02425:
		q = sqrt(-2.0 * log(p))
		return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
	if p > 1.0 - 0.02425:
		q = sqrt(-2.0 * log(1.0 - p))
		return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
	q = p - 0.5
	var r := q * q
	return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0)


## erf por Abramowitz-Stegun 7.1.26 (erro < 1,5e-7).
static func _erf(x: float) -> float:
	var s := signf(x)
	x = absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return s * y
