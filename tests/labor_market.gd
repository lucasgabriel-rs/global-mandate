extends SceneTree
## Labor market: unemployment reacts to recession (Okun), real wage, minimum wage and informality.
## Usage: godot --headless --path . -s tests/labor_market.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _fresh(iso := "USA") -> GameWorld:
	var world := GameWorld.new()
	world.setup(7)
	world.leader = Character.random(world.rng)
	world.set_player(world.by_iso[iso], "normal")
	return world


func _months(world: GameWorld, n: int, shock := 0.0) -> void:
	for i in int(n * 30.4167):
		world.player.next_election = world.year_float() + 2.0
		world.over = false
		if shock != 0.0:
			world.player.demand_shock = shock
		world.tick_day()
	world.flush_events()


func _init() -> void:
	_recession()
	_minimum_wage()
	_informal_base()
	print("RESULT: ", failures, " failures")
	quit()


## A strong US recession takes unemployment well above baseline, and the real wage falls below normal.
func _recession() -> void:
	var calm := _fresh()
	_months(calm, 18)
	var hit := _fresh()
	_months(hit, 18, -0.10)
	var u0: float = calm.player.unemp
	var u1: float = hit.player.unemp
	_check(hit.player.growth_yoy() < calm.player.growth_yoy() - 0.02, "shock drags GDP down: %.1f%% vs %.1f%%" % [hit.player.growth_yoy() * 100.0, calm.player.growth_yoy() * 100.0])
	_check(u1 > u0 + 0.025, "unemployment rises in the recession: %.1f%% vs %.1f%%" % [u1 * 100.0, u0 * 100.0])
	_check(u1 < 0.25, "recession unemployment is not absurd: %.1f%%" % (u1 * 100.0))
	_check(hit.player.real_wage < calm.player.real_wage, "lower real wage in the recession: %.3f vs %.3f" % [hit.player.real_wage, calm.player.real_wage])
	_check(hit.player.informal > calm.player.informal, "informality grows in the recession: %.1f%% vs %.1f%%" % [hit.player.informal * 100.0, calm.player.informal * 100.0])
	_check(calm.player.real_wage > 0.9 and calm.player.real_wage < 1.15, "stable real wage without shock: %.3f" % calm.player.real_wage)


## A minimum wage far above the median wage cuts jobs and pushes people into informality.
func _minimum_wage() -> void:
	var low := _fresh("BRA")
	var high := _fresh("BRA")
	var c: Country = high.player
	var amount := c.gdp_pc() * 0.6 / 12.0 * 1.3
	high.legislation._stand("minwage", "valor", {"value": amount}, -1, 1.0e9)
	_months(low, 24)
	_months(high, 24)
	_check(high.player.minwage_ratio > 1.0, "Kaitz index of the high minimum wage: %.2f" % high.player.minwage_ratio)
	_check(high.player.law_unemp > low.player.law_unemp + 0.02, "high minimum wage weighs on unemployment: %.3f vs %.3f" % [high.player.law_unemp, low.player.law_unemp])
	_check(high.player.unemp > low.player.unemp + 0.015, "higher unemployment with high minimum wage: %.1f%% vs %.1f%%" % [high.player.unemp * 100.0, low.player.unemp * 100.0])
	_check(high.player.informal > low.player.informal + 0.03, "higher informality with high minimum wage: %.1f%% vs %.1f%%" % [high.player.informal * 100.0, low.player.informal * 100.0])


func _informal_base() -> void:
	var world := _fresh()
	var usa: Country = world.by_iso["USA"]
	var bra: Country = world.by_iso["BRA"]
	var ind: Country = world.by_iso["IND"]
	_check(usa.informal < 0.15, "US with little informality: %.0f%%" % (usa.informal * 100.0))
	_check(bra.informal > 0.25 and bra.informal < 0.5, "Brazil with middle-income informality: %.0f%%" % (bra.informal * 100.0))
	_check(ind.informal > bra.informal, "India more informal than Brazil: %.0f%%" % (ind.informal * 100.0))
