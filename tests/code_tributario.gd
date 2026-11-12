extends SceneTree
## Código Tributário: o texto inicial reproduz a carga de partida, faixas mudam a arrecadação por lei,
## revogar devolve o que valia e a sonegação responde a alíquotas e fiscalização.
## Uso: godot --headless --path . --script tests/code_tributario.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _fresh(iso: String) -> GameWorld:
	var world := GameWorld.new()
	world.setup()
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


func _to_month_end(world: GameWorld) -> void:
	var month := world.month
	for i in 40:
		world.player.next_election = 9999.0
		world.tick_day()
		if world.month != month:
			return


func _blocks_of(norm: Dictionary, type: String) -> Array:
	return LawProgram.all_blocks(norm.program).filter(func(b): return b.type == type)


func _init() -> void:
	_seed_keeps_totals()
	_bracket_by_law()
	_revoke_restores()
	_evasion()
	print("RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)


## Começar a partida com o código em blocos não muda nenhuma carga, em países bem diferentes.
func _seed_keeps_totals() -> void:
	for iso: String in ["BRA", "USA", "SWE", "NGA", "SAU", "IND"]:
		var probe := GameWorld.new()
		probe.setup()
		var raw: Country = probe.by_iso[iso]
		var before := [raw.tax_income, raw.tax_consumption, raw.tax_corporate, raw.tariff]
		probe.set_player(raw, "normal")
		var c := probe.player
		var leg: Legislation = probe.legislation
		var code := leg.code_norm("tributario")
		_check(not code.is_empty() and code.type == "complementar" and code.get("base_code", false), "%s: Código Tributário é lei complementar" % iso)
		_check(leg.code_standing("tributario").size() > 15, "%s: o código vale desde o início (%d itens)" % [iso, leg.code_standing("tributario").size()])
		var after := [c.tax_income, c.tax_consumption, c.tax_corporate, c.tariff]
		var same := true
		for i in 4:
			same = same and absf(float(before[i]) - float(after[i])) < 1e-6
		_check(same, "%s: cargas iguais às de partida %s -> %s" % [iso, str(before), str(after)])
		var revenue0 := c.tax_total()
		for m in 3:
			_to_month_end(probe)
		_check(absf(c.tax_total() - revenue0) < 1e-6, "%s: três meses depois a carga legal é a mesma" % iso)
		# Só a parte do Tributário: outros códigos (Penal, Direitos...) também mexem na sonegação.
		var own: Dictionary = LawCodes.get_code("tributario").monthly(probe, c, leg)
		var own_evasion := float(own.get("evasion", 0.0))
		var own_gini := float(own.get("inequality", 0.0))
		_check(absf(own_evasion) < 1e-6 and absf(own_gini) < 0.02, "%s: sem efeito extra de partida (sonegação %.4f, Gini %.4f)" % [iso, own_evasion, own_gini])
		_check(c.code_stats.has("carga_tributaria") and c.code_stats.has("progressividade") and c.code_stats.has("sonegacao"), "%s: indicadores do código" % iso)
		if iso == "BRA":
			for b: Dictionary in LawProgram.all_blocks(code.program):
				print("  ", LawProgram.block_text(b))


## Subir as faixas do IRPF por alteração do código aumenta a carga sobre a renda.
func _bracket_by_law() -> void:
	var world := _fresh("BRA")
	var c := world.player
	var leg: Legislation = world.legislation
	var income0 := c.tax_income
	var bill := leg.start_code_bill(world, "tributario")
	_check(int(bill.get("amends", -1)) == int(leg.code_norm("tributario").id), "o projeto altera o código em vigor")
	for b: Dictionary in _blocks_of(bill, "tr_irpf_faixa"):
		b.fields.aliquota = float(b.fields.aliquota) + 10.0
	for b: Dictionary in _blocks_of(bill, "tr_irpf_topo"):
		b.fields.aliquota = float(b.fields.aliquota) + 10.0
	var cut := leg.start_code_bill(world, "tributario")
	for b: Dictionary in _blocks_of(cut, "tr_irpf_topo"):
		b.fields.aliquota = 5.0
	_check(float(leg.position_for(world, bill).econ) < float(leg.position_for(world, cut).econ), "subir o IRPF fica mais à esquerda que cortar")
	_check(leg.popularity_of(world, bill) < leg.popularity_of(world, cut), "subir o IRPF é menos popular que cortar")
	leg.delete_draft(int(cut.id))
	_force_majority(world)
	var r := leg.present(world, bill)
	_check(r.ok, "projeto apresentado: " + str(r.get("msg", "")))
	_settle(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "a alteração entra em vigor: " + bill.state)
	print("  renda: ", income0, " -> ", c.tax_income)
	_check(c.tax_income > income0 + 0.005, "faixas mais altas arrecadam mais")
	var top := float(leg.code_standing("tributario").irpf_topo.aliquota)
	_check(top > 30.0, "o código em vigor tem a alíquota nova: %.1f%%" % top)
	var after := c.tax_income
	_to_month_end(world)
	_check(absf(c.tax_income - after) < 1e-9, "o fim do mês não desfaz a lei")


## Uma lei avulsa com faixa nova vale enquanto está em vigor; revogada, volta o texto do código.
func _revoke_restores() -> void:
	var world := _fresh("BRA")
	var c := world.player
	var leg: Legislation = world.legislation
	var income0 := c.tax_income
	var top0 := float(leg.code_standing("tributario").irpf_topo.aliquota)
	var law := leg.new_norm(world, "complementar")
	law.title = "Alíquota de solidariedade"
	law.ementa = "Sobe a alíquota do topo."
	var stack := LawProgram.add_stack(law.program, LawProgram.new_block(law.program, "ev_enact"), Vector2.ZERO)
	var block := LawProgram.new_block(law.program, "tr_irpf_topo")
	block.fields.aliquota = top0 + 15.0
	stack.blocks.append(block)
	_force_majority(world)
	leg.present(world, law)
	_settle(world, law)
	_check(law.state == Legislation.STATE_IN_FORCE, "a lei avulsa entra em vigor: " + law.state)
	_check(c.tax_income > income0 + 0.0005, "alíquota do topo maior arrecada mais: %.4f -> %.4f" % [income0, c.tax_income])
	leg.revoke_now(world, law, "Teste", "Teste")
	_to_month_end(world)
	_check(absf(c.tax_income - income0) < 1e-6, "revogada, a carga volta ao valor anterior: %.5f" % c.tax_income)
	_check(is_equal_approx(float(leg.code_standing("tributario").irpf_topo.aliquota), top0), "o topo volta ao do código: %.1f%%" % top0)


## Alíquota alta sem fiscalização faz a sonegação crescer; mais fiscalização a reduz.
func _evasion() -> void:
	var world := _fresh("BRA")
	var c := world.player
	var leg: Legislation = world.legislation
	_to_month_end(world)
	var evasion0 := c.law_evasion
	var stat0 := float(c.code_stats.sonegacao)
	var code := leg.code_norm("tributario")
	var prio := leg._priority(code, {})
	var tr := LawCodes.get_code("tributario")
	tr.apply(world, leg, "tr_irpf_topo", {"aliquota": 55.0}, 1.0, int(code.id), prio + 1.0)
	tr.apply(world, leg, "tr_fiscalizacao", {"verba": 0.0}, 1.0, int(code.id), prio + 1.0)
	_to_month_end(world)
	print("  sonegação: ", stat0, " -> ", c.code_stats.sonegacao, " (law_evasion ", evasion0, " -> ", c.law_evasion, ")")
	_check(c.law_evasion > evasion0 + 0.02, "alíquota alta sem fiscalização aumenta a sonegação")
	var lax := c.law_evasion
	tr.apply(world, leg, "tr_fiscalizacao", {"verba": 0.6}, 1.0, int(code.id), prio + 2.0)
	_to_month_end(world)
	_check(c.law_evasion < lax, "mais orçamento para a Receita reduz a sonegação: %.4f -> %.4f" % [lax, c.law_evasion])
	_check(float(c.code_stats.progressividade) > 0.0, "progressividade medida: %.3f" % float(c.code_stats.progressividade))
