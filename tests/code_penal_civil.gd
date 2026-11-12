extends SceneTree
## Criminal and Civil Codes: initial text, effect in force, approved change and repeal.
## Usage: godot --headless --path . --script tests/code_penal_civil.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _advance(world: GameWorld, days: int) -> void:
	for i in days:
		world.player.next_election = 9999.0
		world.tick_day()


func _field_of(program: Dictionary, type: String, key: String, match_key := "", match_value: Variant = null) -> Variant:
	for block: Dictionary in LawProgram.all_blocks(program):
		if block.type == type and (match_key == "" or block.fields.get(match_key) == match_value):
			return block.fields.get(key)
	return null


func _set_field(program: Dictionary, type: String, key: String, value: Variant, match_key := "", match_value: Variant = null) -> void:
	for block: Dictionary in LawProgram.all_blocks(program):
		if block.type == type and (match_key == "" or block.fields.get(match_key) == match_value):
			block.fields[key] = value


func _init() -> void:
	var world := GameWorld.new()
	world.setup()
	world.set_player(world.by_iso["BRA"], "normal")
	world.leader = Character.random(world.rng)
	var c := world.player
	var leg: Legislation = world.legislation
	_seeds(world, leg)
	_seed_varies(world)
	# First month: the initial texts execute and the indicators appear.
	_advance(world, 40)
	var penal := leg.code_standing("penal")
	var civil := leg.code_standing("civil")
	_check(penal.has("armas") and penal.has("orcamento_policia") and penal.has("crime:trafico"), "the initial Criminal Code is in force:" + str(penal.keys()))
	_check(civil.has("propriedade") and civil.has("abertura_empresa"), "the initial Civil Code is in force:" + str(civil.keys()))
	var crime0 := float(c.code_stats.get("criminalidade", -1.0))
	var trust0 := float(c.code_stats.get("seguranca_juridica", -1.0))
	_check(crime0 > 0.0 and crime0 < 1.0, "criminalidade entre 0 e 1: %.3f" % crime0)
	_check(trust0 > 0.0 and trust0 < 1.0, "legal security between 0 and 1: %.3f" % trust0)
	_reform_penal(world, leg, crime0)
	_reform_civil(world, leg, trust0)
	_revoke(world, leg)
	print("RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _seeds(world: GameWorld, leg: Legislation) -> void:
	for id: String in ["penal", "civil"]:
		var norm := leg.code_norm(id)
		_check(not norm.is_empty() and norm.type == "complementar" and norm.get("base_code", false), "the country starts with the code %s as a complementary law in force" % id)
		if norm.is_empty():
			continue
		var compiled := LawCompiler.compile(norm.program, leg.compile_context("complementar"))
		_check(compiled.ok, "the initial text of the %s code compiles: %s" % [id, str(compiled.get("errors", []))])
		print(compiled.text.left(600))


## A closed and poor regime starts with another code: death penalty, weapons banned.
func _seed_varies(world: GameWorld) -> void:
	var closed: Country = null
	var open: Country = null
	for c: Country in world.countries:
		if closed == null and c.dem < 3.0:
			closed = c
		if open == null and c.dem > 8.5 and c.gdp_pc() > 40000.0:
			open = c
	if closed == null or open == null:
		_check(false, "find a closed regime and a rich democracy")
		return
	var penal := LawCodes.get_code("penal")
	var hard := penal.seed_program(world, closed)
	var soft := penal.seed_program(world, open)
	_check(_field_of(hard, "pn_death", "status") == "crimes_graves" and _field_of(soft, "pn_death", "status") == "abolida", "death penalty: %s in %s, %s in %s" % [_field_of(hard, "pn_death", "status"), closed.iso, _field_of(soft, "pn_death", "status"), open.iso])
	_check(_field_of(hard, "pn_guns", "regime") == "proibido", "the closed regime bans weapons")
	var civil := LawCodes.get_code("civil")
	var days_rich := float(_field_of(civil.seed_program(world, open), "cv_business", "days"))
	var days_closed := float(_field_of(civil.seed_program(world, closed), "cv_business", "days"))
	_check(days_rich < days_closed, "opening a company is faster in %s (%d days) than in %s (%d)" % [open.iso, days_rich, closed.iso, days_closed])


func _reform_penal(world: GameWorld, leg: Legislation, crime0: float) -> void:
	var c := world.player
	var bill := leg.start_code_bill(world, "penal")
	_check(int(bill.get("amends", -1)) == int(leg.code_norm("penal").id), "the criminal reform amends the code in force")
	_set_field(bill.program, "pn_budget", "value", 3.0, "area", "policia")
	_set_field(bill.program, "pn_budget", "value", 0.6, "area", "prisoes")
	_set_field(bill.program, "pn_guns", "regime", "proibido")
	var compiled := leg.compile_norm(bill)
	_check(compiled.ok, "a reforma penal compila")
	var spend0 := c.law_spend
	leg._enter_force(world, bill)
	var penal := leg.code_standing("penal")
	_check(is_equal_approx(float(penal.get("orcamento_policia", {}).get("share", 0.0)), 0.03), "police now get 3% of GDP")
	_check(String(penal.get("armas", {}).get("regime", "")) == "proibido", "weapons become banned")
	_advance(world, 31)
	var crime1 := float(c.code_stats.criminalidade)
	_advance(world, 150)
	var crime2 := float(c.code_stats.criminalidade)
	print("crime: %.3f → %.3f → %.3f" % [crime0, crime1, crime2])
	_check(crime2 < crime1 and crime1 <= crime0 + 0.01, "more police and fewer weapons lower crime gradually")
	_check(crime0 - crime2 < 0.25, "the drop is neither instant nor absurd")
	_check(c.law_spend > spend0, "extra policing enters spending: %.4f → %.4f of GDP" % [spend0, c.law_spend])


func _reform_civil(world: GameWorld, leg: Legislation, trust0: float) -> void:
	var c := world.player
	var bill := leg.start_code_bill(world, "civil")
	_set_field(bill.program, "cv_property", "mode", "sem_indenizacao")
	_set_field(bill.program, "cv_contracts", "level", "restrita")
	_set_field(bill.program, "cv_business", "days", 120)
	_set_field(bill.program, "cv_business", "steps", 20)
	_check(leg.compile_norm(bill).ok, "a reforma civil compila")
	leg._enter_force(world, bill)
	_advance(world, 120)
	var trust := float(c.code_stats.seguranca_juridica)
	print("legal security: %.3f → %.3f; invest %.3f, tfp %.4f" % [trust0, trust, c.law_invest, c.law_tfp])
	_check(trust < trust0 - 0.05, "expropriating without paying and freezing contracts brings down legal security")
	_check(c.law_tfp < 0.0, "bureaucracy weighs on productivity")


func _revoke(world: GameWorld, leg: Legislation) -> void:
	for id: String in ["penal", "civil"]:
		leg.revoke_now(world, leg.code_norm(id), "Teste", "Teste")
	_check(leg.code_standing("penal").is_empty() and leg.code_standing("civil").is_empty(), "repealing the codes clears what they kept")
	_advance(world, 35)
	_check(leg.code_standing("penal").is_empty() and leg.code_norm("penal").is_empty(), "once repealed, the code does not run again")
