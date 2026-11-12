extends SceneTree
## Câmbio e fundo soberano: intervenção do banco central com reservas, controle e fuga de capitais,
## dolarização, paridade descoberta, saldos de partida dos fundos, retorno, regra de saque, amortecedor
## de commodities, risco, aprovação e a Lei Cambial no centro legislativo.
## Uso: godot --headless --path . --script tests/fx_swf.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _fresh(iso: String, seed_value := 11) -> GameWorld:
	var world := GameWorld.new()
	world.setup(seed_value)
	world.set_player(world.by_iso[iso], "normal")
	world.leader = Character.random(world.rng)
	return world


func _force_majority(world: GameWorld) -> void:
	var data: Dictionary = world.politics.data_of(world.player.iso)
	for party: Dictionary in data.parties:
		party.econ = 0.0
		party.social = 0.0
	world.player.approval = 0.9


func _settle(world: GameWorld, norm: Dictionary, limit := 300) -> void:
	for i in limit:
		world.player.next_election = 9999.0
		_force_majority(world)
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


func _months(world: GameWorld, n: int) -> void:
	for i in int(n * 30.4167):
		world.player.next_election = world.year_float() + 2.0
		world.over = false
		world.tick_day()
	world.flush_events()


func _blocks_of(norm: Dictionary, type: String) -> Array:
	return LawProgram.all_blocks(norm.program).filter(func(b): return b.type == type)


func _init() -> void:
	_starting_funds()
	_intervention()
	_capital_flows()
	_uip()
	_fund_mechanics()
	_fund_law()
	_long_run()
	print("RESULTADO: %d falhas" % failures)
	quit(1 if failures > 0 else 0)


## Os sete fundos grandes começam perto dos saldos reais; quem não tem fundo começa com zero.
func _starting_funds() -> void:
	var world := GameWorld.new()
	world.setup(3)
	var real := {"NOR": 1800.0, "SAU": 940.0, "ARE": 1500.0, "KWT": 970.0, "QAT": 520.0, "CHN": 1330.0, "SGP": 1100.0}
	for iso: String in real:
		var c: Country = world.by_iso[iso]
		_check(c.swf_active and absf(c.swf / float(real[iso]) - 1.0) < 0.25, "%s começa com fundo de US$ %.0f bi (real ~%.0f)" % [iso, c.swf, real[iso]])
	_check(world.by_iso["BRA"].swf == 0.0 and not world.by_iso["BRA"].swf_active, "o Brasil começa sem fundo soberano")
	var nor: Country = world.by_iso["NOR"]
	_check(absf(nor.swf_limit - 0.03) < 0.006, "Noruega segue a regra dos 3%%: %.2f%%" % (nor.swf_limit * 100.0))
	_check(nor.swf_rent_share > 0.9, "a renda do petróleo norueguês vai toda para o fundo")


## Sob pressão de depreciação o banco central vende reservas e segura parte do movimento.
func _intervention() -> void:
	var results := {}
	for lean in [0.0, 0.7]:
		var world := GameWorld.new()
		world.setup(5)
		var c: Country = world.by_iso["BRA"]
		c.fx_lean = lean
		c.risk = c.risk0 + 0.15
		var e0 := c.e
		var r0 := c.reserves
		world.rng.seed = 99
		for m in 6:
			Economy._float_exchange(c, world)
		results[lean] = [c.e / e0, r0 - c.reserves, c.fx_interv]
	print("  câmbio sem intervenção x%.3f, com intervenção x%.3f; reservas vendidas %.1f" % [results[0.0][0], results[0.7][0], results[0.7][1]])
	_check(results[0.7][1] > 1.0 and results[0.7][2] > 0.0, "o banco central vende reservas quando a moeda cai (US$ %.1f bi)" % results[0.7][1])
	_check(absf(results[0.0][1]) < 0.5, "sem intervenção as reservas ficam paradas")
	_check(results[0.7][0] < results[0.0][0], "a intervenção segura a depreciação")
	# Com a moeda subindo, o banco central compra dólares.
	var world2 := GameWorld.new()
	world2.setup(5)
	var b: Country = world2.by_iso["BRA"]
	b.fx_lean = 0.7
	b.e *= 1.4
	var r1 := b.reserves
	Economy._float_exchange(b, world2)
	_check(b.reserves > r1 and b.fx_interv < 0.0, "com a moeda fraca demais o banco central compra reservas")
	# Sem reservas não há o que vender.
	b.reserves = 0.0
	b.risk = b.risk0 + 0.2
	Economy._float_exchange(b, world2)
	_check(b.reserves >= 0.0, "reservas nunca ficam negativas")


## Risco alto faz o capital fugir; controle de capitais segura a fuga; inflação alta dolariza.
func _capital_flows() -> void:
	var world := GameWorld.new()
	world.setup(5)
	var c: Country = world.by_iso["BRA"]
	c.risk = c.risk0 + 0.1
	c.cap_controls = 0.0
	Economy._capital_flight(c, world, c.y_usd())
	var free := c.cap_flight
	c.cap_controls = 0.75
	Economy._capital_flight(c, world, c.y_usd())
	var closed := c.cap_flight
	_check(free > 0.0, "risco acima do de partida faz o capital fugir (US$ %.0f bi/ano)" % free)
	_check(closed < free * 0.5, "cotas de capital cortam a fuga: %.0f -> %.0f" % [free, closed])
	var dz0 := c.dollarization
	c.pi_yoy = 0.6
	for m in 36:
		Economy._capital_flight(c, world, c.y_usd())
	_check(c.dollarization > dz0 + 0.2, "inflação de 60%% dolariza a economia: %.0f%% -> %.0f%%" % [dz0 * 100.0, c.dollarization * 100.0])
	var high := c.dollarization
	c.pi_yoy = 0.03
	for m in 12:
		Economy._capital_flight(c, world, c.y_usd())
	_check(c.dollarization < high and c.dollarization > high * 0.8, "a dolarização desce devagar quando a inflação cai")


## Paridade descoberta: i - i* = depreciação esperada + prêmio de risco.
func _uip() -> void:
	var world := GameWorld.new()
	world.setup(5)
	var c: Country = world.by_iso["BRA"]
	Economy._float_exchange(c, world)
	var premium := c.risk + 0.5 * c.cap_flight / maxf(c.y_usd(), 0.001)
	_check(absf(c.rate - world.usa.rate - (c.uip_dep + premium)) < 1e-6, "i = i* + Δeᵉ + prêmio (Δeᵉ = %.2f%%)" % (c.uip_dep * 100.0))
	var low := c.uip_dep
	c.rate += 0.05
	Economy._float_exchange(c, world)
	_check(c.uip_dep > low + 0.04, "juro mais alto eleva a depreciação esperada que o mercado aceita")


## Retorno, aporte, saque, amortecedor de commodities, risco e aprovação.
func _fund_mechanics() -> void:
	var world := GameWorld.new()
	world.setup(5)
	var nor: Country = world.by_iso["NOR"]
	Economy._fiscal_flows(nor)
	var out0 := nor.swf_out
	_check(nor.swf_in > 0.0 and out0 > 0.0, "o fundo norueguês recebe a renda do petróleo e paga o saque")
	var draw := out0 / (nor.swf * nor.e)
	_check(absf(draw - nor.swf_limit) < 0.005, "saque igual à regra quando a renda está na média: %.2f%%" % (draw * 100.0))
	# Petróleo despenca: a renda cai abaixo da média e o fundo cobre parte da queda.
	nor.rent_ref *= 2.0
	Economy._fiscal_flows(nor)
	_check(nor.swf_out > out0 * 1.2, "queda das commodities aumenta o saque: %.0f -> %.0f" % [out0, nor.swf_out])
	nor.rent_ref /= 2.0
	# O saldo é colchão de risco.
	var risk_with := Economy._risk_premium(nor, world)
	var keep := nor.swf
	nor.swf = 0.0
	var risk_without := Economy._risk_premium(nor, world)
	nor.swf = keep
	_check(risk_with < risk_without, "fundo grande reduz o prêmio de risco: %.2f%% x %.2f%%" % [risk_with * 100.0, risk_without * 100.0])
	# Sacar demais tira aprovação.
	nor.swf_limit = 0.03
	Economy._fiscal_flows(nor)
	Economy._fund_month(nor, world)
	_check(nor.swf_pain == 0.0, "saque de 3% não custa aprovação")
	nor.swf_limit = 0.12
	Economy._fiscal_flows(nor)
	Economy._fund_month(nor, world)
	_check(nor.swf_pain > 0.05, "saque de 12%% ao ano tira aprovação (%.1f pp)" % (nor.swf_pain * 100.0))
	# O fundo aplica fora: guardar mais renda não valoriza a moeda.
	var es := []
	for share in [0.0, 1.0]:
		var w := GameWorld.new()
		w.setup(5)
		var n: Country = w.by_iso["NOR"]
		n.swf_rent_share = share
		Economy._fiscal_flows(n)
		w.rng.seed = 7
		for m in 3:
			Economy._float_exchange(n, w)
		es.append(n.e)
	_check(es[1] >= es[0] - 1e-9, "aportes ao fundo não valorizam a coroa: %.4f x %.4f" % [es[0], es[1]])


## O fundo é criado pela Lei Cambial; o limite de saque muda por lei.
func _fund_law() -> void:
	var world := _fresh("BRA")
	var c := world.player
	var leg: Legislation = world.legislation
	_months(world, 1)
	_check(not leg.code_standing("cambial").is_empty(), "a Lei Cambial vale desde o início")
	_check(not c.swf_active, "o Brasil não tem fundo na lei de partida")
	var bill := leg.start_code_bill(world, "cambial")
	var stack: Dictionary = bill.program.stacks[0]
	var fund := LawProgram.new_block(bill.program, "fs_fundo")
	fund.fields.renda = 80.0
	fund.fields.superavit = 50.0
	stack.blocks.append(fund)
	var rule := LawProgram.new_block(bill.program, "fs_saque")
	rule.fields.limite = 3.0
	stack.blocks.append(rule)
	for b: Dictionary in _blocks_of(bill, "cb_controle"):
		b.fields.nivel = "imposto"
	_force_majority(world)
	var r := leg.present(world, bill)
	_check(r.ok, "projeto do fundo apresentado: " + str(r.get("msg", "")))
	_settle(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "a lei do fundo entra em vigor: " + bill.state)
	_months(world, 2)
	_check(c.swf_active and is_equal_approx(c.swf_rent_share, 0.8) and is_equal_approx(c.swf_limit, 0.03), "o fundo brasileiro existe com 80%% da renda e saque de 3%%")
	_check(is_equal_approx(c.cap_controls, 0.35), "o imposto sobre saída de capitais vale: %.2f" % c.cap_controls)
	_months(world, 12)
	_check(c.swf > 1.0, "o fundo acumula com a renda de commodities: US$ %.1f bi" % c.swf)
	_check(float(c.code_stats.get("fundo_soberano", -1.0)) == c.swf, "o código mostra o saldo do fundo")

	# Noruega: subir o saque para 10% por lei tira aprovação.
	var nw := _fresh("NOR")
	var nor := nw.player
	var nleg: Legislation = nw.legislation
	_months(nw, 1)
	_check(nor.swf_active and nor.swf_limit > 0.02, "a lei de partida da Noruega já tem o fundo e a regra")
	var change := nleg.start_code_bill(nw, "cambial")
	for b: Dictionary in _blocks_of(change, "fs_saque"):
		b.fields.limite = 10.0
	_force_majority(nw)
	nleg.present(nw, change)
	_settle(nw, change)
	_months(nw, 2)
	_check(is_equal_approx(nor.swf_limit, 0.10), "o limite de saque muda por lei: %.1f%%" % (nor.swf_limit * 100.0))
	_check(nor.swf_pain > 0.05, "sacar 10%% ao ano pesa na aprovação (%.1f pp)" % (nor.swf_pain * 100.0))


## Dez anos: reservas, câmbio e fundos finitos e dentro de faixas plausíveis.
func _long_run() -> void:
	var world := _fresh("BRA", 42)
	var start := {}
	for iso: String in ["NOR", "SAU", "CHN", "SGP", "BRA", "IND", "TUR", "ARG"]:
		var c: Country = world.by_iso[iso]
		start[iso] = [c.swf, c.reserves, c.e]
	_months(world, 120)
	var bad := 0
	for c: Country in world.countries:
		if not c.alive:
			continue
		for v: float in [c.e, c.reserves, c.swf, c.cap_flight, c.dollarization, c.fx_interv, c.uip_dep]:
			if is_nan(v) or is_inf(v):
				bad += 1
		if c.reserves < 0.0 or c.swf < 0.0:
			bad += 1
	_check(bad == 0, "nenhum NaN, infinito ou saldo negativo em 10 anos (%d ruins)" % bad)
	for iso: String in ["NOR", "SAU", "CHN", "SGP"]:
		var c: Country = world.by_iso[iso]
		var s0: float = start[iso][0]
		_check(c.swf > s0 * 0.6 and c.swf < s0 * 4.0, "%s: fundo plausível em 10 anos: %.0f -> %.0f" % [iso, s0, c.swf])
	for iso: String in ["BRA", "IND", "TUR", "ARG"]:
		var c: Country = world.by_iso[iso]
		var r0: float = start[iso][1]
		_check(c.reserves < r0 * 5.0 + 50.0, "%s: reservas sem explodir: %.0f -> %.0f" % [iso, r0, c.reserves])
