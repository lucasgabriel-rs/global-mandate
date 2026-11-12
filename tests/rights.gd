extends SceneTree
## Rights and duties code: initial text, effect only of what changes, Constitution and military service.
## Uso: godot --headless --path . --script tests/rights.gd

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


## Approves the draft directly, without depending on parliament.
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
	_check(cats.size() == 1, "the code has a category in the palette")
	var ids := LawCatalog.in_category("direitos").map(func(b): return b.id)
	for id: String in ["dr_right", "dr_suspend", "dr_duty", "dr_military", "dr_school", "dr_censor", "dr_regulate", "dr_block", "dr_emergency"]:
		_check(id in ids and LawCodes.owner_of(id) != null, "bloco %s registrado" % id)
	for b: Dictionary in LawCatalog.in_category("direitos"):
		for key: String in b.get("fields", {}):
			_check(b.fields[key].t != "text", "%s.%s does not ask for free text" % [b.id, key])
	_check(LawCatalog.choice_list("dr_right").has("imprensa") and LawCatalog.choice_list("dr_right").has("aborto"), "closed list of rights")


func _seed() -> void:
	var world := _fresh("BRA")
	var leg := world.legislation
	var code := leg.code_norm("direitos")
	_check(not code.is_empty() and code.type == "complementar" and code.get("base_code", false), "Brazil starts with the code as a complementary law")
	var types := _types(code.program)
	_check("dr_military" in types and "dr_school" in types and "dr_right" in types, "initial text with rights, school and military service: %s" % str(types))
	_check(LawCompiler.compile(code.program, leg.compile_context("complementar")).ok, "o texto inicial compila")
	var c := world.player
	var troops0 := c.troops0
	var approval := c.law_approval
	world.legislation.step_month(world)
	var got: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	var total := 0.0
	for k: String in got:
		total += absf(float(got[k]))
	_check(total < 1e-6, "with no change, the code does not move anything: %s" % str(got))
	_check(is_equal_approx(c.troops0, troops0), "the base force stays as it was")
	_check(float(c.code_stats.get("liberdades", -1.0)) > 60.0, "Brazil has a high freedom index: %s" % str(c.code_stats.get("liberdades")))
	print("  aprovação das leis: ", approval, " -> ", c.law_approval)


func _change() -> void:
	var world := _fresh("BRA")
	var leg := world.legislation
	var c := world.player
	var troops0 := c.troops0
	var bill := leg.start_code_bill(world, "direitos")
	_check(int(bill.amends) == int(leg.code_norm("direitos").id), "amending the code is a project that amends the norm")
	var program: Dictionary = bill.program
	# More barracks time, for everyone; internet censorship; suspends the strike (it is not in Art. 3).
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
	_check(leg.compile_norm(bill).ok, "the amendment compiles")
	# Suspending a right of Art. 3 generates a warning and a problem in the court.
	var guaranteed: Array = leg.param("rights", [])
	_check("expressao" in guaranteed, "Brazil's Constitution guarantees expression")
	var probe := LawProgram.new_block(program, "dr_suspend")
	probe.fields.right = "expressao"
	stack.blocks.append(probe)
	_check(leg.find_conflicts(bill).any(func(w): return String(w.text).contains("Constituição")), "suspending a guaranteed right warns in the editor")
	_check(leg._court_problem(bill) != "", "the court challenges the suspension of a guaranteed right")
	stack.blocks.erase(probe)
	_check(leg._court_problem(bill) == "", "without it, nothing to challenge")
	_enact(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "the amendment takes effect: %s" % bill.state)
	var now := CodeRights.current_state(leg)
	_check(now.get("military", {}).get("months", 0) == 24 and now.has("censor:internet"), "what applies is the new text: %s" % str(now.keys()))
	var got: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(float(got.approval) < 0.0 and float(got.invest) < 0.0, "censorship and a suspended strike cost approval and investment: %s" % str(got))
	_check(c.troops0 > troops0 and c.troops0 < troops0 * 2.01, "more draftees increase the force with a limit: %.1f -> %.1f" % [troops0, c.troops0])
	_check(float(got.labor) < 0.0, "whoever is in the barracks leaves the labor force")
	var once := c.troops0
	LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(is_equal_approx(c.troops0, once), "the force does not grow again every month")
	# The standalone law that already handles a right keeps it: it does not count twice.
	leg.standing.rights["greve"] = {"on": false, "norm": 999, "prio": 0.0}
	var again: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(float(again.approval) > float(got.approval), "strike counted only once, by the standalone law")
	leg.standing.rights.erase("greve")
	# Repealing the code returns the force and leaves only the Constitution.
	# The norm that amended the code also applies on its own: it leaves along with it.
	leg.revoke_now(world, leg.code_norm("direitos"), "teste", "teste")
	leg.revoke_now(world, bill, "teste", "teste")
	LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(c.troops0 < once, "without military service, the force falls: %.1f" % c.troops0)
	_check(CodeRights.right_level(leg, CodeRights.current_state(leg), "expressao") == 1.0, "expression remains guaranteed by the Constitution")
	# State of emergency: applies for its term.
	var decree := leg.new_norm(world, "complementar")
	decree.title = "Emergência"
	decree.ementa = "Estado de emergência."
	var s := LawProgram.add_stack(decree.program, LawProgram.new_block(decree.program, "ev_enact"), Vector2.ZERO)
	var em := LawProgram.new_block(decree.program, "dr_emergency")
	em.fields.days = 20
	s.blocks.append(em)
	_enact(world, decree)
	_check(decree.state == Legislation.STATE_IN_FORCE, "emergency decree in force")
	var during: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	var free_during := float(c.code_stats.liberdades)
	for i in 25:
		world.player.next_election = 9999.0
		world.tick_day()
	var after: Dictionary = LawCodes.get_code("direitos").monthly(world, c, leg)
	_check(float(c.code_stats.liberdades) > free_during, "once the term ends, freedoms come back: %.0f -> %.0f" % [free_during, float(c.code_stats.liberdades)])
	_check(float(during.stability) > float(after.stability), "the emergency gives stability while it lasts")


func _dictatorship() -> void:
	var world := _fresh("PRK")
	var code := world.legislation.code_norm("direitos")
	var types := _types(code.program)
	_check("dr_censor" in types and "dr_block" in types, "North Korea starts with censorship and blockade")
	LawCodes.get_code("direitos").monthly(world, world.player, world.legislation)
	_check(float(world.player.code_stats.liberdades) < 30.0, "low freedom index: %s" % str(world.player.code_stats.liberdades))
