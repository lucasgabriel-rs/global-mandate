extends SceneTree
## Tests of the governor mode (units governed by the player), without the interface.
## Usage: godot --headless --path . -s tests/governor.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _world(iso := "BRA") -> GameWorld:
	var w := GameWorld.new()
	w.setup(7)
	w.set_player(w.by_iso[iso], "normal")
	return w


## First-level unit of a country, by position in its list.
func _root(w: GameWorld, iso: String, i := 0) -> int:
	return int(w.subdivisions.roots_of(iso)[i])


func _core() -> void:
	var w := _world()
	var sub := w.subdivisions
	var bra: Country = w.by_iso["BRA"]
	var made := StateGov.create(w, _root(w, "BRA"))
	_check(made.ok and made.gov is StateGov, "a first-level unit can be governed")
	# A municipality is not playable.
	var muni := -1
	for id: int in sub.units:
		if int(sub.units[id].parent) >= 0 and sub.units[id].owner == "BRA":
			muni = id
			break
	_check(muni >= 0 and not StateGov.create(w, muni).ok, "a municipality is refused")
	# The states of a country never add up to more than the country.
	var total := 0.0
	for id: int in sub.roots_of("BRA"):
		total += (StateGov.create(w, id).gov as StateGov).gdp(w)
	_check(total <= bra.y_usd() * 1.0001 and total > bra.y_usd() * 0.9, "state GDPs add up to the national GDP (%.0f of %.0f)" % [total, bra.y_usd()])
	# Budget limits come from the competences table.
	var gov: StateGov = made.gov
	_check(gov.set_spend("education", 0.05).ok and is_equal_approx(float(gov.spend.education), 0.05), "the state sets spending in an area it decides")
	var fr := _world("FRA")
	var fgov: StateGov = StateGov.create(fr, _root(fr, "FRA")).gov
	_check(not fgov.set_spend("health", 0.05).ok, "a unitary region cannot set spending in a union area")
	_check(not fgov.set_tax(0.1).ok and gov.set_tax(0.03).ok, "the tax rate follows the competence over taxes")
	# One-way flow: the state never writes into the national accounts.
	var before := [bra.y, bra.pop, bra.revenue, bra.spending, bra.debt_loc]
	for i in 12:
		gov.step_month(w)
	_check([bra.y, bra.pop, bra.revenue, bra.spending, bra.debt_loc] == before, "twelve state months leave the national accounts untouched")
	# A country with one first-level unit cannot be played by unit.
	var small := _world("LUX")
	var keep := _root(small, "LUX")
	for id: int in small.subdivisions.roots_of("LUX").duplicate():
		if id != keep:
			small.subdivisions.delete_unit(id)
	_check(not StateGov.create(small, keep).ok, "a country with a single first-level unit is refused")


func _init() -> void:
	_core()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
