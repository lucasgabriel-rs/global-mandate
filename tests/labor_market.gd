extends SceneTree
## Mercado de trabalho: desemprego reage à recessão (Okun), salário real, salário mínimo e informalidade.
## Uso: godot --headless --path . --script tests/labor_market.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


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
	print("RESULTADO: %d falhas" % failures)
	quit()


## Uma recessão forte nos EUA leva o desemprego bem acima da base, e o salário real cai em relação ao normal.
func _recession() -> void:
	var calm := _fresh()
	_months(calm, 18)
	var hit := _fresh()
	_months(hit, 18, -0.10)
	var u0: float = calm.player.unemp
	var u1: float = hit.player.unemp
	_check(hit.player.growth_yoy() < calm.player.growth_yoy() - 0.02, "choque derruba o PIB: %.1f%% contra %.1f%%" % [hit.player.growth_yoy() * 100.0, calm.player.growth_yoy() * 100.0])
	_check(u1 > u0 + 0.025, "desemprego sobe na recessão: %.1f%% contra %.1f%%" % [u1 * 100.0, u0 * 100.0])
	_check(u1 < 0.25, "desemprego da recessão não é absurdo: %.1f%%" % (u1 * 100.0))
	_check(hit.player.real_wage < calm.player.real_wage, "salário real menor na recessão: %.3f contra %.3f" % [hit.player.real_wage, calm.player.real_wage])
	_check(hit.player.informal > calm.player.informal, "informalidade cresce na recessão: %.1f%% contra %.1f%%" % [hit.player.informal * 100.0, calm.player.informal * 100.0])
	_check(calm.player.real_wage > 0.9 and calm.player.real_wage < 1.15, "salário real estável sem choque: %.3f" % calm.player.real_wage)


## Mínimo muito acima do salário mediano corta empregos e empurra gente para a informalidade.
func _minimum_wage() -> void:
	var low := _fresh("BRA")
	var high := _fresh("BRA")
	var c: Country = high.player
	var amount := c.gdp_pc() * 0.6 / 12.0 * 1.3
	high.legislation._stand("minwage", "valor", {"value": amount}, -1, 1.0e9)
	_months(low, 24)
	_months(high, 24)
	_check(high.player.minwage_ratio > 1.0, "índice de Kaitz do mínimo alto: %.2f" % high.player.minwage_ratio)
	_check(high.player.law_unemp > low.player.law_unemp + 0.02, "mínimo alto pesa no desemprego: %.3f contra %.3f" % [high.player.law_unemp, low.player.law_unemp])
	_check(high.player.unemp > low.player.unemp + 0.015, "desemprego maior com mínimo alto: %.1f%% contra %.1f%%" % [high.player.unemp * 100.0, low.player.unemp * 100.0])
	_check(high.player.informal > low.player.informal + 0.03, "informalidade maior com mínimo alto: %.1f%% contra %.1f%%" % [high.player.informal * 100.0, low.player.informal * 100.0])


func _informal_base() -> void:
	var world := _fresh()
	var usa: Country = world.by_iso["USA"]
	var bra: Country = world.by_iso["BRA"]
	var ind: Country = world.by_iso["IND"]
	_check(usa.informal < 0.15, "EUA com pouca informalidade: %.0f%%" % (usa.informal * 100.0))
	_check(bra.informal > 0.25 and bra.informal < 0.5, "Brasil com informalidade de renda média: %.0f%%" % (bra.informal * 100.0))
	_check(ind.informal > bra.informal, "Índia mais informal que o Brasil: %.0f%%" % (ind.informal * 100.0))
