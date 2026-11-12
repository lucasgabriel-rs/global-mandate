extends SceneTree
## Código de Direitos e deveres: texto inicial, efeito só do que muda, Constituição e serviço militar.
## Uso: godot --headless --path . --script tests/direitos.gd

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


func _types(program: Dictionary) -> Array:
	return LawProgram.all_blocks(program).map(func(b): return String(b.type))


func _settle(world: GameWorld, norm: Dictionary, limit := 200) -> void:
	for i in limit:
		world.player.next_election = 9999.0
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


## Aprova o rascunho direto, sem depender do parlamento.
func _enact(world: GameWorld, norm: Dictionary) -> void:
	for party: Dictionary in world.politics.data_of(world.player.iso).parties:
		norm.get_or_add("deals", {})[str(party.id)] = true
	var r: Dictionary = world.legislation.present(world, norm)
	_check(r.ok, "apresenta: %s" % r.msg)
	_settle(world, norm)


func _init() -> void:
	_catalog()
	_seed()
	_change()
	_dictatorship()
	print("RESULT: %d failures" % failures)
	quit()


func _catalog() -> void:
	var cats := LawCatalog.categories().filter(func(c): return c.get("code", "") == "direitos")
	_check(cats.size() == 1, "o código tem categoria na paleta")
	var ids := LawCatalog.in_category("direitos").map(func(b): return b.id)
	for id: String in ["dr_right", "dr_suspend", "dr_duty", "dr_military", "dr_school", "dr_censor", "dr_regulate", "dr_block", "dr_emergency"]:
		_check(id in ids and LawCodes.owner_of(id) != null, "bloco %s registrado" % id)
	for b: Dictionary in LawCatalog.in_category("direitos"):
		for key: String in b.get("fields", {}):
			_check(b.fields[key].t != "text", "%s.%s não pede texto livre" % [b.id, key])
	_check(LawCatalog.choice_list("dr_right").has("imprensa") and LawCatalog.choice_list("dr_right").has("aborto"), "lista fechada de direitos")


func _seed() -> void:
	var world := _fresh("BRA")
	var leg := world.legislation
	var code := leg.code_norm("direitos")
	_check(not code.is_empty() and code.type == "complementar" and code.get("base_code", false), "o Brasil começa com o código como lei complementar")
	var types := _types(code.program)
	_check("dr_military" in types and "dr_school" in types and "dr_right" in types, "texto inicial com direitos, escola e serviço militar: %s" % str(types))
	_check(LawCompiler.compile(code.program, leg.compile_context("complementar")).ok, "o texto inicial compila")
	var c := world.player
	var troops0 := c.troops0
	var approval := c.law_approval
	world.legislation.step_month(world)
	var got: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	var total := 0.0
	for k: String in got:
		total += absf(float(got[k]))
	_check(total < 1e-6, "sem mudança, o código não mexe em nada: %s" % str(got))
	_check(is_equal_approx(c.troops0, troops0), "o efetivo de base fica como estava")
	_check(float(c.code_stats.get("liberdades", -1.0)) > 60.0, "o Brasil tem índice de liberdades alto: %s" % str(c.code_stats.get("liberdades")))
	print("  aprovação das leis: ", approval, " -> ", c.law_approval)


func _change() -> void:
	var world := _fresh("BRA")
	var leg := world.legislation
	var c := world.player
	var troops0 := c.troops0
	var bill := leg.start_code_bill(world, "direitos")
	_check(int(bill.amends) == int(leg.code_norm("direitos").id), "alterar o código é um projeto que altera a norma")
	var program: Dictionary = bill.program
	# Mais tempo de quartel, para todos; censura da internet; suspende a greve (não está no Art. 3º).
	for b: Dictionary in LawProgram.all_blocks(program):
		if b.type == "dr_military":
			b.fields.months = 24
			b.fields.who = "todos"
	var stack: Dictionary = program.stacks[0]
	var censor := LawProgram.new_block(program, "dr_censor")
	censor.fields.outlet = "internet"
	stack.blocks.append(censor)
	var strike := LawProgram.new_block(program, "dr_suspend")
	strike.fields.right = "greve"
	stack.blocks.append(strike)
	_check(leg.compile_norm(bill).ok, "a alteração compila")
	# Suspender um direito do Art. 3º gera aviso e problema na corte.
	var guaranteed: Array = leg.param("rights", [])
	_check("expressao" in guaranteed, "a Constituição do Brasil garante a expressão")
	var probe := LawProgram.new_block(program, "dr_suspend")
	probe.fields.right = "expressao"
	stack.blocks.append(probe)
	_check(leg.find_conflicts(bill).any(func(w): return String(w.text).contains("Constituição")), "suspender direito garantido avisa no editor")
	_check(leg._court_problem(bill) != "", "a corte contesta a suspensão de direito garantido")
	stack.blocks.erase(probe)
	_check(leg._court_problem(bill) == "", "sem ela, nada a contestar")
	_enact(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "a alteração entra em vigor: %s" % bill.state)
	var now := CodeDireitos.current_state(leg)
	_check(now.get("military", {}).get("months", 0) == 24 and now.has("censor:internet"), "o que vale é o texto novo: %s" % str(now.keys()))
	var got: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(float(got.approval) < 0.0 and float(got.invest) < 0.0, "censura e greve suspensa custam aprovação e investimento: %s" % str(got))
	_check(c.troops0 > troops0 and c.troops0 < troops0 * 2.01, "mais convocados aumentam o efetivo com limite: %.1f -> %.1f" % [troops0, c.troops0])
	_check(float(got.labor) < 0.0, "quem está no quartel sai da força de trabalho")
	var once := c.troops0
	LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(is_equal_approx(c.troops0, once), "o efetivo não cresce de novo todo mês")
	# A lei avulsa que já cuida de um direito fica com ele: não conta duas vezes.
	leg.standing.rights["greve"] = {"on": false, "norm": 999, "prio": 0.0}
	var again: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(float(again.approval) > float(got.approval), "greve contada uma vez só, pela lei avulsa")
	leg.standing.rights.erase("greve")
	# Revogar o código devolve o efetivo e deixa só a Constituição.
	# A norma que alterou o código também vale por si: sai junto.
	leg.revoke_now(world, leg.code_norm("direitos"), "teste", "teste")
	leg.revoke_now(world, bill, "teste", "teste")
	LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(c.troops0 < once, "sem serviço militar, o efetivo cai: %.1f" % c.troops0)
	_check(CodeDireitos.right_level(leg, CodeDireitos.current_state(leg), "expressao") == 1.0, "a expressão segue garantida pela Constituição")
	# Estado de emergência: vale pelo prazo.
	var decree := leg.new_norm(world, "complementar")
	decree.title = "Emergência"
	decree.ementa = "Estado de emergência."
	var s := LawProgram.add_stack(decree.program, LawProgram.new_block(decree.program, "ev_enact"), Vector2.ZERO)
	var em := LawProgram.new_block(decree.program, "dr_emergency")
	em.fields.days = 20
	s.blocks.append(em)
	_enact(world, decree)
	_check(decree.state == Legislation.STATE_IN_FORCE, "decreto de emergência em vigor")
	var during: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	var free_during := float(c.code_stats.liberdades)
	for i in 25:
		world.player.next_election = 9999.0
		world.tick_day()
	var after: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(float(c.code_stats.liberdades) > free_during, "acabado o prazo, as liberdades voltam: %.0f -> %.0f" % [free_during, float(c.code_stats.liberdades)])
	_check(float(during.stability) > float(after.stability), "a emergência dá estabilidade enquanto dura")


func _dictatorship() -> void:
	var world := _fresh("PRK")
	var code := world.legislation.code_norm("direitos")
	var types := _types(code.program)
	_check("dr_censor" in types and "dr_block" in types, "a Coreia do Norte começa com censura e bloqueio")
	LawCodes.get_code("direitos").monthly(world, world.player, world.legislation)
	_check(float(world.player.code_stats.liberdades) < 30.0, "índice de liberdades baixo: %s" % str(world.player.code_stats.liberdades))
