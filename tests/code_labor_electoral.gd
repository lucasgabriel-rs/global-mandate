extends SceneTree
## Labor and Electoral Codes: seeding, minimum wage and unemployment, electoral threshold and reelection.
## Usage: godot --headless --path . --script tests/code_labor_electoral.gd

var failures := 0
## Priority above any norm: the test fixes the value on top of the original text.
const PRIO := 1e12


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _fresh(iso := "BRA") -> GameWorld:
	var world := GameWorld.new()
	world.setup(7)
	world.leader = Character.random(world.rng)
	world.set_player(world.by_iso[iso], "normal")
	return world


func _months(world: GameWorld, n: int) -> void:
	for i in int(n * 30.4167) + 1:
		world.player.next_election = world.year_float() + 2.0
		world.over = false
		world.tick_day()
	world.flush_events()


func _put_value(world: GameWorld, code_id: String, op: String, values: Dictionary) -> void:
	var leg: Legislation = world.legislation
	LawCodes.get_code(code_id).apply(world, leg, op, values, 1.0, int(leg.code_norm(code_id).id), PRIO)


func _init() -> void:
	_seeds()
	_minimum_wage()
	_threshold()
	_reelection()
	print("RESULT: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _seeds() -> void:
	for iso: String in ["BRA", "USA", "CHN", "DEU"]:
		var world := _fresh(iso)
		var leg: Legislation = world.legislation
		for id: String in ["trabalhista", "eleitoral"]:
			var norm := leg.code_norm(id)
			_check(not norm.is_empty() and norm.get("base_code", false) and norm.type == "complementar", "%s starts with the code %s as a complementary law" % [iso, id])
			if norm.is_empty():
				continue
			var compiled := LawCompiler.compile(norm.program, leg.compile_context(norm.type))
			_check(compiled.ok, "the initial text of the %s code of %s compiles" % [id, iso])
		_months(world, 2)
		var stats: Dictionary = world.player.code_stats
		for key: String in ["cobertura_previdencia", "deficit_previdencia", "rigidez_trabalho", "comparecimento"]:
			_check(stats.has(key), "%s guarda %s" % [iso, key])
		_check(leg.code_standing("trabalhista").has("jornada") and leg.code_standing("eleitoral").has("barreira"), "%s: the seeded text takes effect" % iso)
		_check(absf(world.player.law_unemp) < 0.01, "%s: the original code does not move unemployment (%.3f)" % [iso, world.player.law_unemp])


## The same country, with and without a high minimum wage: unemployment rises over time.
func _minimum_wage() -> void:
	var base := _fresh()
	var high := _fresh()
	_months(base, 1)
	_months(high, 1)
	var wage := high.player.gdp_pc() * 0.6 / 12.0 * 1.6
	_put_value(high, "trabalhista", "tb_minwage", {"amount": wage})
	_check(absf(float(high.legislation.standing.minwage.valor.value) - wage) < 0.01, "the labor block writes the minimum wage in the same place as the advanced one")
	_months(base, 18)
	_months(high, 18)
	print("  unemployment: base %.2f%%, high minimum %.2f%%" % [base.player.unemp * 100.0, high.player.unemp * 100.0])
	_check(high.player.unemp > base.player.unemp + 0.01, "a high minimum wage raises unemployment over time")
	# Retiring later increases labor supply and reduces the pension deficit.
	var deficit0 := float(base.player.code_stats.deficit_previdencia)
	var labor0 := base.player.law_labor
	_put_value(base, "trabalhista", "tb_retirement", {"men": 70, "women": 70, "years": 20})
	_months(base, 1)
	_check(base.player.law_labor > labor0, "retiring later increases labor supply")
	_check(float(base.player.code_stats.deficit_previdencia) < deficit0, "retiring later reduces the pension deficit")
	var stab0 := base.player.law_stability
	_put_value(base, "trabalhista", "tb_strike", {"sector": "privado", "mode": "proibida"})
	_months(base, 1)
	_check(base.player.law_stability < stab0, "proibir a greve numa democracia tira estabilidade")


## The same election, with the same draw, under two electoral thresholds.
func _threshold() -> void:
	var world := _fresh()
	_months(world, 1)
	var c := world.player
	var data: Dictionary = world.politics.data_of(c.iso)
	var neutral := func(_p: Dictionary) -> float: return 1.0
	var low_data: Dictionary = data.duplicate(true)
	world.rng.seed = 99
	var low := Elections.run(world, c, low_data, neutral)
	_put_value(world, "eleitoral", "el_threshold", {"pct": 12})
	var high_data: Dictionary = data.duplicate(true)
	world.rng.seed = 99
	var high := Elections.run(world, c, high_data, neutral)
	var low_parties := 0
	var high_parties := 0
	var small_seats := 0
	for p: Dictionary in low.parties:
		low_parties += 1 if int(p.seats) > 0 else 0
	for p: Dictionary in high.parties:
		high_parties += 1 if int(p.seats) > 0 else 0
		if float(p.vote) < 0.12:
			small_seats += int(p.seats)
	print("  partidos com cadeiras: barreira original %d, barreira de 12%% %d" % [low_parties, high_parties])
	_check(is_equal_approx(float(high.threshold), 0.12), "the election uses the Electoral Code's threshold")
	_check(high_parties < low_parties and small_seats == 0, "a higher threshold takes the small parties out of parliament")
	# Below the constitutional floor, the Constitution applies.
	_put_value(world, "eleitoral", "el_threshold", {"pct": 0})
	var floor_rules := CodeElectoral.rules_for(world, c)
	_check(float(floor_rules.threshold) >= float(world.legislation.param("threshold", 3)) / 100.0 - 0.0001, "the code does not lower the threshold below the Constitution's")
	# The system belongs to the Constitution.
	_put_value(world, "eleitoral", "el_system", {"system": "fptp"})
	_check(String(CodeElectoral.rules_for(world, c).system) == "", "the Constitution defines the system, not the code")
	var before := float(c.code_stats.comparecimento)
	_put_value(world, "eleitoral", "el_vote", {"mode": "facultativo" if String(world.legislation.code_standing("eleitoral").voto.mode) == "obrigatorio" else "obrigatorio"})
	_months(world, 1)
	_check(absf(float(c.code_stats.comparecimento) - before) > 0.1, "compulsory voting changes turnout")


func _reelection() -> void:
	var world := _fresh()
	_months(world, 1)
	_put_value(world, "eleitoral", "el_reelection", {"mode": "ilimitada"})
	_check(CodeElectoral.may_run_again(world), "unlimited reelection lets them run")
	_put_value(world, "eleitoral", "el_reelection", {"mode": "uma"})
	_check(CodeElectoral.may_run_again(world), "in the first term, a single reelection lets them run")
	world.mandates = 1
	_check(not CodeElectoral.may_run_again(world), "after one reelection, there is no other")
	world.mandates = 0
	_put_value(world, "eleitoral", "el_reelection", {"mode": "proibida"})
	var result: Dictionary = world.politics.player_election(world)
	_check(result.barred and not result.won, "reelection banned: the player does not stay in office")
