class_name FormulaExplain
extends RefCounted
## Conteúdo da janela "Como funciona": para cada indicador, a fórmula, os números atuais do país e uma
## explicação curta. Os cálculos vêm de EconFormulas, os mesmos que a simulação usa.

const KEYS := ["gdp", "inflation", "rate", "fx", "trade", "fiscal", "tax", "inequality", "oil", "industry", "partners", "unemp"]


static func _p(v: float, d := 1) -> String:
	return UiKit.pct(v, d)


static func _n(v: float, d := 2) -> String:
	return UiKit.num(v, d)


## Devolve {title, formula, numbers, body} para o indicador `key` do país `c`.
static func build(key: String, c: Country, world: GameWorld) -> Dictionary:
	var F := EconFormulas
	match key:
		"gdp":
			var s := c.inv_share0
			var ky := c.capital / maxf(c.y_pot, 0.001)
			var ky_star := F.solow_ky(s, c.popg, maxf(float(c.hist.get("_gtfp", c.g_tfp0)) / (1.0 - Economy.ALPHA), 0.0), Economy.DELTA)
			return {
				"title": TranslationServer.translate("PIB potencial: modelo de Solow"),
				"formula": "Y = A · K^α · (h·L)^(1−α)      K/Y* = s / (n + g + δ)",
				"numbers": TranslationServer.translate("α = %s  ·  s = %s  ·  n = %s  ·  δ = %s\nK/Y hoje = %s  ·  K/Y de equilíbrio = %s  ·  hiato do produto = %s") % [
					_n(Economy.ALPHA), _p(s), _p(c.popg), _p(Economy.DELTA), _n(ky, 1), _n(ky_star, 1), _p(c.gap)],
				"body": TranslationServer.translate("O PIB de longo prazo depende de capital, trabalho, educação e produtividade (A). Investir acima da depreciação aproxima o capital do equilíbrio; daí em diante, só a produtividade sustenta o crescimento."),
			}
		"inflation":
			var mon := float(c.hist.get("_seign", 0.0))
			return {
				"title": TranslationServer.translate("Inflação: curva de Phillips e equação quantitativa"),
				"formula": TranslationServer.translate("π = πe + κ·hiato + choques      M·V = P·Y"),
				"numbers": TranslationServer.translate("πe = %s  ·  κ = %s  ·  hiato = %s  →  núcleo-alvo ≈ %s\nV = %s  ·  senhoriagem = %s/ano  ·  imposto inflacionário = %s/ano") % [
					_p(c.pi_e), _n(Economy.KAPPA), _p(c.gap), _p(F.phillips(c.pi_e, Economy.KAPPA, c.gap)),
					_n(F.VELOCITY, 1), UiKit.money(mon * c.p / maxf(c.e, 0.001)), UiKit.money(float(c.hist.get("_inftax", 0.0)) * c.p / maxf(c.e, 0.001))],
				"body": TranslationServer.translate("Com a economia acima do potencial os preços aceleram; expectativas ancoradas seguram a inflação. Financiar o déficit emitindo moeda aumenta M e, com V e Y dados, o nível de preços sobe na mesma proporção."),
			}
		"rate":
			return {
				"title": TranslationServer.translate("Juros: regra de Taylor"),
				"formula": TranslationServer.translate("i = r* + πe + 0,6·(π − π*) + 0,5·hiato"),
				"numbers": TranslationServer.translate("r* = %s  ·  πe = %s  ·  π = %s  ·  meta π* = %s  ·  hiato = %s\nTaxa sugerida = %s  ·  taxa atual = %s") % [
					_p(c.r_n), _p(c.pi_e), _p(c.pi_yoy), _p(c.pi_target), _p(c.gap), _p(clampf(F.taylor(c.r_n, c.pi_e, c.pi_target, c.gap, 0.6, 0.5) + 0.6 * (c.pi_yoy - c.pi_e), 0.0, Economy.MAX_RATE)), _p(c.rate)],
				"body": TranslationServer.translate("O banco central sobe o juro mais que a inflação (princípio de Taylor) para que o juro real aumente e esfrie a demanda. Bancos centrais sem independência podem seguir o governo em vez da regra."),
			}
		"fx":
			var us := world.usa
			return {
				"title": TranslationServer.translate("Câmbio: paridade do poder de compra e Balassa-Samuelson"),
				"formula": "E = P / P*      ΔE ≈ π − π*      Δq = (1−γ)·[(aT−aN) − (aT*−aN*)]",
				"numbers": TranslationServer.translate("PPC: E = %s  ·  câmbio atual = %s\nDepreciação pela PPC = %s/ano  ·  Balassa-Samuelson acumulado = %s") % [
					_n(F.ppp_rate(c.p, us.p)), _n(c.e), _p(F.ppp_depreciation(c.pi_core, us.pi_core)), _p(-float(c.hist.get("_bs", 0.0)))],
				"body": TranslationServer.translate("No longo prazo a moeda perde valor na proporção da inflação a mais que a dos EUA. Países que ganham produtividade mais rápido veem o câmbio real se apreciar, porque os serviços ficam mais caros."),
			}
		"trade":
			var rer_j := float(c.hist.get("_rer_j", c.rer))
			return {
				"title": TranslationServer.translate("Balança comercial: Marshall-Lerner e curva J"),
				"formula": TranslationServer.translate("εx + εm > 1      ΔBC ≈ d · (ajuste · (εx + εm) − 1)"),
				"numbers": TranslationServer.translate("εx = %s  ·  εm = %s  ·  soma = %s\nCâmbio real = %s  ·  câmbio real que os volumes já sentem = %s  ·  conta corrente = %s do PIB") % [
					_n(F.ELAST_X), _n(F.ELAST_M), _n(F.ELAST_X + F.ELAST_M), _n(c.rer), _n(rer_j), _p(c.ca_ratio)],
				"body": TranslationServer.translate("Depois de uma desvalorização, as importações encarecem na hora, mas os volumes levam cerca de um ano para reagir: a balança piora antes de melhorar. Como as elasticidades somam mais que 1, o efeito final é positivo."),
			}
		"fiscal":
			var t := clampf(c.tax_total() + c.law_tax, 0.05, 0.6)
			var m := clampf(c.m_share, 0.02, 0.8)
			var theta := F.ricardian_share(c.debt_ratio, c.debt_tol)
			return {
				"title": TranslationServer.translate("Política fiscal: multiplicador keynesiano"),
				"formula": "k = 1 / (1 − c·(1 − t) + m)      kT = c·k·(1 − θ)",
				"numbers": TranslationServer.translate("c = %s  ·  t = %s  ·  m = %s  →  k = %s\nFração ricardiana θ = %s  →  multiplicador do imposto = %s") % [
					_n(F.MPC), _p(t), _p(m), _n(F.keynes_multiplier(F.MPC, t, m)), _p(theta, 0), _n(F.tax_multiplier(F.MPC, t, m, theta))],
				"body": TranslationServer.translate("Cada real de gasto vira renda de alguém, que consome parte dela. Impostos e importações vazam do circuito. Com a economia aquecida, parte do estímulo vira juro e preço. Corte de imposto rende menos: as famílias poupam parte, à espera do imposto futuro, ainda mais com dívida alta."),
			}
		"tax":
			var t := c.tax_total()
			return {
				"title": TranslationServer.translate("Arrecadação: curva de Laffer"),
				"formula": "R = t · B0 · ((1 − t) / (1 − t0))^ε      t* = 1 / (1 + ε)",
				"numbers": TranslationServer.translate("ε = %s  ·  carga de partida t0 = %s  ·  carga atual t = %s\nBase tributável = %s da original  ·  alíquota de arrecadação máxima t* = %s") % [
					_n(F.LAFFER_ETI), _p(c.tax0), _p(t), _p(F.laffer_base(t, c.tax0), 0), _p(F.laffer_peak())],
				"body": TranslationServer.translate("Imposto mais alto desestimula trabalho, investimento e declaração da renda. Até t* a arrecadação ainda sobe; acima, cai."),
			}
		"inequality":
			var q := F.quintile_shares(c.inequality)
			return {
				"title": TranslationServer.translate("Desigualdade: curva de Lorenz e índice de Gini"),
				"formula": "G = 1 − 2·∫ L(p) dp",
				"numbers": TranslationServer.translate("Gini = %s\nFatia da renda por quinto da população: %s · %s · %s · %s · %s") % [
					_n(c.inequality), _p(q[0]), _p(q[1]), _p(q[2]), _p(q[3]), _p(q[4])],
				"body": TranslationServer.translate("A curva de Lorenz mostra quanto da renda os p% mais pobres recebem. Quanto mais ela se afasta da diagonal, maior o Gini: 0 é igualdade total, 1 é um só com tudo."),
			}
		"oil":
			var mk := world.markets
			return {
				"title": TranslationServer.translate("Petróleo e minérios: regra de Hotelling"),
				"formula": "(P − CMg)t = (P − CMg)0 · (1 + r)^t",
				"numbers": TranslationServer.translate("r = %s  ·  anos = %s  ·  renda de escassez do petróleo = %s do preço\nPreço de tendência = US$ %s  ·  preço atual = US$ %s") % [
					_p(Markets.HOTELLING_R), _n(mk.years, 1), _p(Markets.HOTELLING_RENT[Markets.OIL], 0),
					_n(F.hotelling_price(Markets.P0[Markets.OIL], Markets.HOTELLING_RENT[Markets.OIL], Markets.HOTELLING_R, mk.years) * world.global_price_index(), 0), _n(mk.price[Markets.OIL], 0)],
				"body": TranslationServer.translate("Petróleo deixado no chão é um ativo: só vale extrair hoje se a renda do recurso crescer como o juro. Por isso o preço real dos recursos esgotáveis tende a subir com o tempo."),
			}
		"industry":
			var rent := c.comm_exports / maxf(c.y_usd(), 0.001)
			var rent0 := float(c.hist.get("_rent0", rent))
			return {
				"title": TranslationServer.translate("Indústria: doença holandesa"),
				"formula": TranslationServer.translate("Δ(indústria/PIB) ≈ −0,5 · Δ(renda de recursos/PIB)"),
				"numbers": TranslationServer.translate("Renda de commodities = %s do PIB (partida: %s)\nEfeito na indústria = %s do PIB  ·  fatia atual da indústria = %s") % [
					_p(rent), _p(rent0), _p(F.dutch_disease(rent - rent0)), _p(c.sector_share[Sectors.INDUSTRY] if c.sector_share.size() == Sectors.COUNT else 0.0)],
				"body": TranslationServer.translate("Um boom de commodities traz dólares, aprecia o câmbio real e puxa trabalhadores e capital para os recursos e os serviços. A indústria perde competitividade."),
			}
		"partners":
			return {
				"title": TranslationServer.translate("Comércio: modelo gravitacional"),
				"formula": "Tij = G · Yi^%s · Yj^%s / Dij^%s" % [_n(F.GRAVITY_MASS), _n(F.GRAVITY_MASS), _n(F.GRAVITY_DIST)],
				"numbers": TranslationServer.translate("PIB do país = %s  ·  exportações = %s  ·  importações = %s") % [UiKit.money(c.y_usd()), UiKit.money(c.exports), UiKit.money(c.imports)],
				"body": TranslationServer.translate("Países comerciam mais com parceiros grandes e próximos. Blocos comerciais, a mesma região e boas relações aumentam o fluxo; sanções e tarifas o reduzem."),
			}
		_:
			return {
				"title": TranslationServer.translate("Desemprego: lei de Okun"),
				"formula": TranslationServer.translate("u = u* − β · hiato"),
				"numbers": TranslationServer.translate("u* = %s  ·  β = %s  ·  hiato = %s  →  desemprego-alvo = %s  ·  atual = %s") % [
					_p(c.unemp_n), _n(Economy.OKUN), _p(c.gap), _p(c.unemp_n + c.law_unemp - Economy.OKUN * c.gap), _p(c.unemp)],
				"body": TranslationServer.translate("Quando o PIB fica abaixo do potencial, as empresas demitem. Desemprego alto por muito tempo eleva a própria taxa natural (histerese)."),
			}

