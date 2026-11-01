class_name WorldEvents
extends RefCounted
## Choques exógenos e dilemas de governo. Cada dilema oferece escolhas com custos reais.

## Sorteio mensal de choques e dilemas, desligado por enquanto. O menu debug ainda dispara cada um.
const RANDOM_EVENTS := false


static func step_month(world: GameWorld) -> void:
	var rng := world.rng
	if RANDOM_EVENTS:
		# Choques globais raros, com frequência próxima da histórica.
		if rng.randf() < 1.0 / (12.0 * 4.0):
			_drought(world)
		if rng.randf() < 1.0 / (12.0 * 35.0) and world.year_float() > world.start_year + 2.0:
			_pandemic(world)
		if rng.randf() < 1.0 / (12.0 * 9.0):
			_supply_shock(world)
		if rng.randf() < 1.0 / (12.0 * 6.0):
			_tech_wave(world)
		if rng.randf() < 1.0 / 14.0:
			_regional_disaster(world)
		if rng.randf() < 1.0 / 18.0:
			_mass_protests(world)
	# OPEP+ administra a oferta conforme o preço real.
	var rel := world.markets.relative_price(Markets.OIL, world)
	if rel < 0.82 and world.markets.opec_quota < 0.07:
		world.markets.opec_quota += 0.01
		if world.markets.opec_quota >= 0.03 and rng.randf() < 0.3:
			world.emit_news("OPEP+ corta produção para sustentar o preço do petróleo.", "economia", null)
	elif rel > 1.2 and world.markets.opec_quota > -0.03:
		world.markets.opec_quota -= 0.01
	# Gargalo de Ormuz: alta probabilidade só com Irã em conflito direto.
	var iran: Country = world.by_iso.get("IRN")
	if iran and iran.alive:
		if world.markets.chokepoint == 0.0 and world.diplomacy.in_war(iran.idx) and rng.randf() < 0.1:
			world.markets.chokepoint = 0.12
			world.global_risk = clampf(world.global_risk + 0.2, 0.0, 1.0)
			world.emit_news("Irã fecha parcialmente o Estreito de Ormuz; petroleiros desviam rota.", "crise", iran)
		elif world.markets.chokepoint > 0.0 and not world.diplomacy.in_war(iran.idx):
			world.markets.chokepoint = 0.0
			world.emit_news("Estreito de Ormuz reaberto ao tráfego comercial.", "economia", iran)
	if RANDOM_EVENTS and world.governed() and rng.randf() < 1.0 / 7.0:
		_player_dilemma(world)


static func _drought(world: GameWorld) -> void:
	var m := world.markets
	m.shock[Markets.GRAIN] = clampf(m.shock[Markets.GRAIN] + world.rng.randf_range(0.05, 0.14), 0.0, 0.3)
	world.emit_news("El Niño e seca derrubam safras; preço de grãos dispara.", "economia", null)


static func _pandemic(world: GameWorld) -> void:
	world.global_risk = clampf(world.global_risk + 0.45, 0.0, 1.0)
	for c: Country in world.countries:
		if c.alive and c != world.governed():
			c.demand_shock -= world.rng.randf_range(0.04, 0.09)
			c.supply_shock -= 0.02
	world.emit_news("OMS declara pandemia: fronteiras fecham e atividade desaba no mundo inteiro.", "crise", null)
	var pl := world.governed()
	if pl:
		world.ask_player({
			"title": "Pandemia global",
			"text": "Um novo vírus se espalha rapidamente. Hospitais lotam e o comércio mundial trava. O que seu governo faz?",
			"options": [
				{"label": "Lockdown rígido e transferências de renda", "hint": "PIB cai forte agora, dívida +4% do PIB, mais aprovação", "fn": func():
					pl.demand_shock -= 0.10
					pl.supply_shock -= 0.015
					pl.debt_loc += pl.y_nominal() * 0.04
					pl.approval = minf(pl.approval + 0.08, 0.95)},
				{"label": "Medidas moderadas", "hint": "Queda intermediária; aprovação estável", "fn": func():
					pl.demand_shock -= 0.065
					pl.supply_shock -= 0.02
					pl.debt_loc += pl.y_nominal() * 0.015},
				{"label": "Manter a economia aberta", "hint": "PIB cai menos, mas mortes derrubam aprovação e estabilidade", "fn": func():
					pl.demand_shock -= 0.035
					pl.supply_shock -= 0.03
					pl.pop *= 0.997
					pl.approval = maxf(pl.approval - 0.16, 0.02)
					pl.stability = maxf(pl.stability - 0.08, 0.02)},
			],
		})


static func _supply_shock(world: GameWorld) -> void:
	var m := world.markets
	var i := world.rng.randi_range(Markets.GAS, Markets.CHIP)
	m.shock[i] = clampf(m.shock[i] + world.rng.randf_range(0.04, 0.1), 0.0, 0.3)
	var texts := {
		Markets.GAS: "Sabotagem em gasoduto aperta a oferta global de gás.",
		Markets.GRAIN: "Praga agrícola reduz estoques mundiais de grãos.",
		Markets.METAL: "Greves em grandes minas reduzem a oferta de metais.",
		Markets.CHIP: "Incêndio em fábrica de wafers causa escassez de semicondutores.",
	}
	world.emit_news(texts[i], "economia", null)


static func _tech_wave(world: GameWorld) -> void:
	var leaders := []
	for c: Country in world.countries:
		if c.alive and c.gdp_pc() > 30000.0 and c.dem >= 6.0:
			leaders.append(c)
	if leaders.is_empty():
		return
	for c: Country in leaders:
		c.tfp *= 1.0 + world.rng.randf_range(0.001, 0.005)
	world.emit_news("Salto em inteligência artificial eleva produtividade em economias avançadas.", "economia", null)


static func _pick_country(world: GameWorld) -> Country:
	for attempt in 12:
		var c: Country = world.countries[world.rng.randi_range(0, world.countries.size() - 1)]
		if c.alive and c != world.governed():
			return c
	return world.countries[0]


static func _regional_disaster(world: GameWorld) -> void:
	var c := _pick_country(world)
	var hit := world.rng.randf_range(0.005, 0.03)
	c.capital *= 1.0 - hit
	c.demand_shock -= hit * 0.6
	var kinds := ["Terremoto", "Furacão", "Enchentes históricas", "Seca severa"]
	if c.y_usd() > world.world_gdp() * 0.002:
		world.emit_news("%s atinge %s; prejuízo de %.1f%% do capital do país." % [kinds[world.rng.randi() % kinds.size()], c.name, hit * 100.0], "economia", c)


static func _mass_protests(world: GameWorld) -> void:
	var c := _pick_country(world)
	if c.stability > 0.5 and world.rng.randf() < 0.7:
		return
	c.unrest = minf(c.unrest + 0.35, 1.0)
	c.stability = maxf(c.stability - 0.05, 0.02)
	if c.y_usd() > world.world_gdp() * 0.002:
		world.emit_news("Protestos em massa tomam as ruas de %s." % c.name, "politica", c)


static func _player_dilemma(world: GameWorld) -> void:
	var pl := world.governed()
	var pool := []
	pool.append(_dilemma_strike)
	pool.append(_dilemma_corruption)
	pool.append(_dilemma_disaster)
	if pl.credit_gap > 0.02 or pl.risk > pl.risk0 + 0.01:
		pool.append(_dilemma_bank)
	if world.markets.relative_price(Markets.OIL, world) > 1.25:
		pool.append(_dilemma_fuel)
	if world.markets.relative_price(Markets.GRAIN, world) > 1.25:
		pool.append(_dilemma_food)
	if pl.gdp_pc() > 12000.0:
		pool.append(_dilemma_migrants)
	if pl.gdp_pc() > 8000.0:
		pool.append(_dilemma_industry)
	var pick: Callable = pool[world.rng.randi_range(0, pool.size() - 1)]
	pick.call(world, pl)


static func _dilemma_strike(world: GameWorld, pl: Country) -> void:
	world.ask_player({
		"title": "Greve geral",
		"text": "Sindicatos paralisam portos e transportes e exigem reajuste acima da inflação.",
		"options": [
			{"label": "Negociar e conceder reajuste", "hint": "Inflação sobe; aprovação sobe", "fn": func():
				pl.pi_core += 0.008
				pl.sp_social += 0.002
				pl.approval = minf(pl.approval + 0.04, 0.95)},
			{"label": "Endurecer e esperar o desgaste", "hint": "PIB -0,5%, aprovação e estabilidade caem", "fn": func():
				pl.demand_shock -= 0.005
				pl.approval = maxf(pl.approval - 0.05, 0.02)
				pl.stability = maxf(pl.stability - 0.03, 0.02)},
		],
	})


static func _dilemma_corruption(_world: GameWorld, pl: Country) -> void:
	_world.ask_player({
		"title": "Escândalo de corrupção",
		"text": "A imprensa revela propinas em contratos de infraestrutura envolvendo ministros do seu governo.",
		"options": [
			{"label": "Demitir e abrir investigação independente", "hint": "Aprovação cai pouco agora; instituições ganham", "fn": func():
				pl.approval = maxf(pl.approval - 0.03, 0.02)
				pl.stability = minf(pl.stability + 0.03, 0.98)
				pl.dem = minf(pl.dem + 0.1, 10.0)},
			{"label": "Blindar os aliados", "hint": "Sem custo imediato, mas confiança e estabilidade corroem", "fn": func():
				pl.conf = maxf(pl.conf - 0.08, 0.05)
				pl.stability = maxf(pl.stability - 0.06, 0.02)
				pl.dem = maxf(pl.dem - 0.2, 0.0)},
		],
	})


static func _dilemma_disaster(world: GameWorld, pl: Country) -> void:
	var hit := world.rng.randf_range(0.006, 0.02)
	pl.capital *= 1.0 - hit
	world.ask_player({
		"title": "Desastre natural",
		"text": "Um desastre destruiu %.1f%% do capital produtivo do país. Milhares estão desabrigados." % (hit * 100.0),
		"options": [
			{"label": "Reconstrução financiada com dívida", "hint": "Dívida +%.1f%% do PIB; recuperação rápida" % (hit * 150.0), "fn": func():
				pl.debt_loc += pl.y_nominal() * hit * 1.5
				pl.capital *= 1.0 + hit * 0.7
				pl.approval = minf(pl.approval + 0.03, 0.95)},
			{"label": "Ajuda mínima, contas em dia", "hint": "Sem nova dívida; aprovação cai", "fn": func():
				pl.approval = maxf(pl.approval - 0.07, 0.02)},
		],
	})


static func _dilemma_bank(world: GameWorld, pl: Country) -> void:
	world.ask_player({
		"title": "Banco sistêmico em risco",
		"text": "Um dos maiores bancos do país sofre corrida de depositantes. O regulador pede uma decisão hoje.",
		"options": [
			{"label": "Socorro público integral", "hint": "Dívida +5% do PIB; evita pânico", "fn": func():
				pl.debt_loc += pl.y_nominal() * 0.05
				pl.credit_gap *= 0.6
				pl.approval = maxf(pl.approval - 0.03, 0.02)},
			{"label": "Deixar quebrar e proteger só depósitos", "hint": "Dívida +1%; recessão por contágio, disciplina no crédito", "fn": func():
				pl.debt_loc += pl.y_nominal() * 0.01
				pl.demand_shock -= 0.035
				pl.credit_gap = -0.05
				world.global_risk = clampf(world.global_risk + 0.5 * sqrt(pl.y_usd() / world.world_gdp()), 0.0, 1.0)},
		],
	})


static func _dilemma_fuel(_world: GameWorld, pl: Country) -> void:
	_world.ask_player({
		"title": "Combustível em alta",
		"text": "O preço internacional do petróleo disparou e caminhoneiros ameaçam bloquear rodovias.",
		"options": [
			{"label": "Subsidiar o combustível por um ano", "hint": "Custo de 1% do PIB; segura a inflação e a aprovação", "fn": func():
				pl.debt_loc += pl.y_nominal() * 0.01
				pl.pi_core -= 0.004
				pl.approval = minf(pl.approval + 0.03, 0.95)},
			{"label": "Repassar o preço", "hint": "Contas preservadas; inflação e aprovação pioram", "fn": func():
				pl.pi_core += 0.005
				pl.approval = maxf(pl.approval - 0.05, 0.02)},
		],
	})


static func _dilemma_food(_world: GameWorld, pl: Country) -> void:
	_world.ask_player({
		"title": "Alimentos caros",
		"text": "A alta global de grãos pesa na cesta básica. Há filas e protestos nos bairros mais pobres.",
		"options": [
			{"label": "Vale-alimentação emergencial", "hint": "Gasto social +0,3% do PIB", "fn": func():
				pl.sp_social += 0.003
				pl.approval = minf(pl.approval + 0.03, 0.95)},
			{"label": "Restringir exportações agrícolas", "hint": "Inflação menor; parceiros reclamam e renda agrícola cai", "fn": func():
				pl.pi_core -= 0.003
				pl.demand_shock -= 0.004
				for j in _world.diplomacy.n:
					if _world.diplomacy.shares[pl.idx * _world.diplomacy.n + j] > 0.05:
						_world.diplomacy.add_relation(pl.idx, j, -4.0)},
			{"label": "Não intervir", "hint": "Risco de agitação social", "fn": func():
				pl.unrest = minf(pl.unrest + 0.25, 1.0)
				pl.approval = maxf(pl.approval - 0.04, 0.02)},
		],
	})


static func _dilemma_migrants(_world: GameWorld, pl: Country) -> void:
	_world.ask_player({
		"title": "Onda migratória",
		"text": "Centenas de milhares chegam às fronteiras fugindo de crises vizinhas. O debate divide o país.",
		"options": [
			{"label": "Acolher e integrar", "hint": "Mais força de trabalho a longo prazo; custo social e tensão", "fn": func():
				pl.pop *= 1.004
				pl.sp_social += 0.001
				pl.approval = maxf(pl.approval - 0.03, 0.02)},
			{"label": "Fechar as fronteiras", "hint": "Popular em curto prazo; relações internacionais pioram", "fn": func():
				pl.approval = minf(pl.approval + 0.02, 0.95)
				pl.dem = maxf(pl.dem - 0.05, 0.0)},
		],
	})


static func _dilemma_industry(_world: GameWorld, pl: Country) -> void:
	_world.ask_player({
		"title": "Política industrial",
		"text": "Ministros propõem um programa de subsídios para atrair fábricas de alta tecnologia e reduzir dependência externa.",
		"options": [
			{"label": "Aprovar o programa", "hint": "Dívida +1,5% do PIB; produtividade sobe com o tempo", "fn": func():
				pl.debt_loc += pl.y_nominal() * 0.015
				pl.g_tfp0 += 0.0012
				pl.prod[Markets.CHIP] += 0.2},
			{"label": "Rejeitar e manter o ajuste", "hint": "Nada muda; mercado aprova", "fn": func():
				pl.conf = minf(pl.conf + 0.02, 1.0)},
		],
	})
