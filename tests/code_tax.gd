extends SceneTree
## Tax Code: the initial text reproduces the starting burden, brackets change collection by law,
## repealing restores what applied and evasion responds to rates and enforcement.
## Usage: godot --headless --path . --script tests/code_tax.gd

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


## Starting the match with the block-based code changes no burden, in very different countries.
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
		_check(not code.is_empty() and code.type == "complementar" and code.get("base_code", false), "%s: Tax Code is a complementary law" % iso)
		_check(leg.code_standing("tributario").size() > 15, "%s: the code is in force since the start (%d items)" % [iso, leg.code_standing("tributario").size()])
		var after := [c.tax_income, c.tax_consumption, c.tax_corporate, c.tariff]
		var same := true
		for i in 4:
			same = same and absf(float(before[i]) - float(after[i])) < 1e-6
		_check(same, "%s: burdens equal to the starting ones %s -> %s" % [iso, str(before), str(after)])
		var revenue0 := c.tax_total()
		for m in 3:
			_to_month_end(probe)
		_check(absf(c.tax_total() - revenue0) < 1e-6, "%s: three months later the legal burden is the same" % iso)
		# Only the Tax part: other codes (Criminal, Rights...) also move evasion.
		var own: Dictionary = LawCodes.get_code("tributario").monthly(probe, c, leg)
		var own_evasion := float(own.get("evasion", 0.0))
		var own_gini := float(own.get("inequality", 0.0))
		_check(absf(own_evasion) < 1e-6 and absf(own_gini) < 0.02, "%s: no extra starting effect (evasion %.4f, Gini %.4f)" % [iso, own_evasion, own_gini])
		_check(c.code_stats.has("carga_tributaria") and c.code_stats.has("progressividade") and c.code_stats.has("sonegacao"), "%s: code indicators" % iso)
		if iso == "BRA":
			for b: Dictionary in LawProgram.all_blocks(code.program):
				print("  ", LawProgram.block_text(b))


## Raising the income tax brackets by amending the code increases the burden on income.
func _bracket_by_law() -> void:
	var world := _fresh("BRA")
	var c := world.player
	var leg: Legislation = world.legislation
	var income0 := c.tax_income
	var bill := leg.start_code_bill(world, "tributario")
	_check(int(bill.get("amends", -1)) == int(leg.code_norm("tributario").id), "the project amends the code in force")
	for b: Dictionary in _blocks_of(bill, "tr_irpf_faixa"):
		b.fields.aliquota = float(b.fields.aliquota) + 10.0
	for b: Dictionary in _blocks_of(bill, "tr_irpf_topo"):
		b.fields.aliquota = float(b.fields.aliquota) + 10.0
	var cut := leg.start_code_bill(world, "tributario")
	for b: Dictionary in _blocks_of(cut, "tr_irpf_topo"):
		b.fields.aliquota = 5.0
	_check(float(leg.position_for(world, bill).econ) < float(leg.position_for(world, cut).econ), "raising income tax goes further left than cutting it")
	_check(leg.popularity_of(world, bill) < leg.popularity_of(world, cut), "raising income tax is less popular than cutting it")
	leg.delete_draft(int(cut.id))
	_force_majority(world)
	var r := leg.present(world, bill)
	_check(r.ok, "projeto apresentado: " + str(r.get("msg", "")))
	_settle(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "the amendment takes effect:" + bill.state)
	print("  income: ", income0, " -> ", c.tax_income)
	_check(c.tax_income > income0 + 0.005, "higher brackets collect more")
	var top := float(leg.code_standing("tributario").irpf_topo.aliquota)
	_check(top > 30.0, "the code in force has the new rate: %.1f%%" % top)
	var after := c.tax_income
	_to_month_end(world)
	_check(absf(c.tax_income - after) < 1e-9, "the end of the month does not undo the law")


## A standalone law with a new bracket applies while in force; once repealed, the code's text returns.
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
	_check(law.state == Legislation.STATE_IN_FORCE, "the standalone law takes effect:" + law.state)
	_check(c.tax_income > income0 + 0.0005, "a higher top rate collects more: %.4f -> %.4f" % [income0, c.tax_income])
	leg.revoke_now(world, law, "Teste", "Teste")
	_to_month_end(world)
	_check(absf(c.tax_income - income0) < 1e-6, "once repealed, the burden goes back to the previous value: %.5f" % c.tax_income)
	_check(is_equal_approx(float(leg.code_standing("tributario").irpf_topo.aliquota), top0), "the top goes back to the code's: %.1f%%" % top0)


## A high rate without enforcement makes evasion grow; more enforcement reduces it.
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
	print("  evasion: ", stat0, " -> ", c.code_stats.sonegacao, " (law_evasion ", evasion0, " -> ", c.law_evasion, ")")
	_check(c.law_evasion > evasion0 + 0.02, "a high rate without enforcement increases evasion")
	var lax := c.law_evasion
	tr.apply(world, leg, "tr_fiscalizacao", {"verba": 0.6}, 1.0, int(code.id), prio + 2.0)
	_to_month_end(world)
	_check(c.law_evasion < lax, "more budget for the Tax Authority reduces evasion: %.4f -> %.4f" % [lax, c.law_evasion])
	_check(float(c.code_stats.progressividade) > 0.0, "progressividade medida: %.3f" % float(c.code_stats.progressividade))
