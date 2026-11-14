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


func _transfers() -> void:
	var w := _world()
	var gov: StateGov = StateGov.create(w, _root(w, "BRA")).gov
	var ruling: Dictionary = w.politics.ruling_party("BRA")
	var far: Dictionary = ruling
	for p: Dictionary in w.politics.data_of("BRA").parties:
		if Politics.distance(ruling, p) > Politics.distance(ruling, far):
			far = p
	gov.party_id = int(ruling.id)
	var allied := gov.monthly_transfer(w)
	var allied_affinity := gov.affinity(w)
	gov.party_id = int(far.id)
	_check(allied_affinity > gov.affinity(w) and allied > gov.monthly_transfer(w), "a governor from the ruling party gets more transfers")
	_check(is_equal_approx(allied_affinity, 1.0), "affinity is 1 for the ruling party")
	# A funding request raises the transfers, and has a cooldown.
	gov.party_id = int(ruling.id)
	gov.step_month(w)
	var base := gov.transfers_in
	var granted := false
	for seed_value in range(1, 60):
		w.rng.seed = seed_value
		var g: StateGov = StateGov.create(w, _root(w, "BRA")).gov
		g.party_id = int(ruling.id)
		g.step_month(w)
		var r := g.request_funds(w)
		if r.ok:
			granted = true
			_check(g.transfers_in > base and float(r.amount) > 0.0, "a granted request raises the transfers")
			var again := g.request_funds(w)
			_check(not again.ok and g.request_wait(w) > 0, "a second request inside the cooldown is refused")
			break
	_check(granted, "some request is granted")
	_check(gov.transfers_in > 0.0 and gov.revenue(w) >= gov.transfers_in, "transfers count as revenue")


func _integration() -> void:
	var w := GameWorld.new()
	w.setup(7)
	var bra: Country = w.by_iso["BRA"]
	_check(w.governor == null and w.role() == "head", "country mode by default")
	var r := w.set_governor(_root(w, "BRA"), "normal")
	_check(r.ok and w.governor is StateGov, "a unit can be chosen at the start")
	_check(w.role() == "governor" and w.player == bra and w.governed() == null, "the player is tied to the union, which the AI runs")
	_check(w.governor.party_id >= 0 and w.governor.party_id == int(w.politics.data_of("BRA").player_party), "the governor belongs to a party of the union")
	_check(w.office_title() == "Governador", "the title comes from the unit type")
	_check(w.governor.transfers_in > 0.0, "transfers are already flowing on the first day")
	var y0 := bra.y
	for i in 400:
		w.tick_day()
	_check(bra.y != y0 and w.governor.debt >= 0.0 and w.governor.transfers_in > 0.0, "the union and the state keep evolving")
	_check(w.legislation.role(w) == "governor" and not w.legislation.can(w, "present"), "the governor does not present national norms")
	var again := GameWorld.new()
	again.setup(7)
	again.load_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	_check(again.governor != null and again.governor.unit_id == w.governor.unit_id and again.role() == "governor", "the governor survives a save")
	_check(is_equal_approx(again.governor.approval, w.governor.approval) and again.governor.party_id == w.governor.party_id, "approval and party survive a save")
	_check(again.governor.last_request_month == w.governor.last_request_month and is_equal_approx(again.governor.debt, w.governor.debt), "state accounts survive a save")
	for i in 5:
		again.tick_day()
	_check(again.day_index == w.day_index + 5, "a loaded governor game keeps running")


func _governed(iso := "BRA") -> GameWorld:
	var w := GameWorld.new()
	w.setup(7)
	w.set_governor(_root(w, iso), "normal")
	return w


## Forces the election of the unit to happen now with the given approval of whoever holds the executive.
func _vote(w: GameWorld, approval: float) -> void:
	w.governor.approval = approval
	w.governor.next_election = w.year_float() - 0.01
	w.check_governor_election()


func _election() -> void:
	var w := _governed()
	_check(w.governor.next_election > w.year_float(), "a democratic union schedules the unit election")
	_vote(w, 0.95)
	_check(w.role() == "governor" and w.governor.next_election > w.year_float(), "a popular governor is re-elected and the next election is scheduled")
	_vote(w, 0.05)
	_check(w.role() == "unit_opposition" and w.governor.incumbent_party != w.governor.party_id, "an unpopular governor loses and goes to the opposition")
	_vote(w, 0.95)
	_check(w.role() == "unit_opposition", "the opposition does not win against a popular incumbent")
	_vote(w, 0.05)
	_check(w.role() == "governor" and w.governor.incumbent_party == w.governor.party_id, "the opposition wins against an unpopular incumbent")
	# A union without elections never schedules one.
	var cn := _governed("CHN")
	_check(cn.governor.next_election == -1.0, "a dictatorship has no unit election")
	cn.year += 5
	cn.check_governor_election()
	_check(cn.role() == "governor", "five years later the governor is still in office")


func _directory() -> void:
	var w := _governed()
	var gov: StateGov = w.governor
	var pol := w.politics
	var mine := pol.player_party(w)
	mine["funds"] = 100.0
	_check(pol.directory_fund(w) < pol.party_fund(w) and pol.directory_fund(w) > 0.0, "the directory holds only a share of the party fund")
	_check(not pol.criticize(w).ok, "a governor in office does not use the opposition tools")
	_check(not pol.censure(w).ok, "there is no motion of censure without a state assembly")
	_vote(w, 0.05)
	var union_approval: float = w.player.approval
	gov.approval = 0.5
	_check(pol.criticize(w).ok and gov.approval < 0.5, "criticism lowers the approval of the state executive")
	_check(w.player.approval == union_approval, "and leaves the union's approval alone")
	var bonus0 := gov.campaign_bonus
	_check(pol.campaign(w).ok and gov.campaign_bonus > bonus0, "a campaign builds up for the next election")
	mine["funds"] = 0.0
	_check(not pol.criticize(w).ok, "without money the directory cannot act")
	# The national party line: a leader far from the party is vetoed.
	var party := pol.player_party(w)
	_check(not pol.national_veto(w), "a leader at the party's own compass is not vetoed")
	var far := {"econ": 1.0, "social": 1.0}
	for corner in [{"econ": -1.0, "social": -1.0}, {"econ": -1.0, "social": 1.0}, {"econ": 1.0, "social": -1.0}]:
		if Politics.distance(corner, party) > Politics.distance(far, party):
			far = corner
	w.leader["econ"] = far.econ
	w.leader["social"] = far.social
	_check(pol.national_veto(w), "a leader far from the national line is vetoed")


## Puts the leader's compass at (or as far as possible from) the ruling party of a country.
func _compass(w: GameWorld, iso: String, close: bool) -> void:
	var ruling: Dictionary = w.politics.ruling_party(iso)
	var spot := {"econ": float(ruling.econ), "social": float(ruling.social)}
	if not close:
		var far := {"econ": 1.0, "social": 1.0}
		for corner in [{"econ": -1.0, "social": -1.0}, {"econ": -1.0, "social": 1.0}, {"econ": 1.0, "social": -1.0}]:
			if Politics.distance(corner, ruling) > Politics.distance(far, ruling):
				far = corner
		spot = far
	w.leader["econ"] = spot.econ
	w.leader["social"] = spot.social


## Moves the governed unit to another country by annexing the union.
func _annexed_by(iso: String, close: bool) -> GameWorld:
	var w := _governed("BRA")
	_compass(w, iso, close)
	w.diplomacy.annex(w.by_iso[iso], w.by_iso["BRA"], w)
	w.check_governor_unit()
	return w


func _union_change() -> void:
	var arg: Country = _world("ARG").by_iso["ARG"]
	_check(arg.dem >= 4.0 and (_world("CHN").by_iso["CHN"] as Country).dem < 4.0, "the test countries have the expected regimes")
	# Democracy: the player picks the party, and the compass decides the post.
	var kept := _annexed_by("ARG", true)
	_check(kept.governor.union_iso == "ARG" and kept.player.iso == "ARG" and kept.governor.pending_party, "a democratic union asks which party to join")
	var pick := int(kept.politics.ruling_party("ARG").id)
	kept.governor.choose_party(kept, pick)
	_check(kept.role() == "governor" and kept.governor.party_id == pick and not kept.governor.pending_party, "a close compass keeps the post and the chosen party")
	var removed := _annexed_by("ARG", false)
	removed.governor.choose_party(removed, int(removed.politics.ruling_party("ARG").id))
	_check(removed.role() == "unit_opposition" and removed.governor.party_id >= 0, "a far compass loses the post but joins the chosen party")
	# Dictatorship: no choice. Removed means game over, kept means the ruling party.
	var served := _annexed_by("CHN", true)
	_check(served.role() == "governor" and not served.over and served.governor.party_id == int(served.politics.ruling_party("CHN").id) and not served.governor.pending_party, "a dictatorship that keeps the governor enrolls them in the ruling party")
	_check(served.governor.next_election == -1.0, "and the unit has no election there")
	var purged := _annexed_by("CHN", false)
	_check(purged.over, "a dictatorship that removes the governor ends the game")


func _lifecycle() -> void:
	var w := _governed("BRA")
	var sub := w.subdivisions
	var id: int = w.governor.unit_id
	var cap := sub.capital_of(id)
	_check(cap >= 0, "the governed state has a capital to follow")
	# A cut that leaves the capital in place keeps the governor on the same unit.
	var far_kid := -1
	var far := -1.0
	for kid: int in sub.children_of(id):
		var d := (sub.units[kid].center as Vector2).distance_to(sub.units[cap].center)
		if d > far:
			far = d
			far_kid = kid
	var away := _square(sub.units[far_kid].center, 0.25)
	_check(sub.split_unit(id, away, "LAM").ok, "the state can be cut away from its capital")
	w.check_governor_unit()
	_check(w.governor.unit_id == id and not w.over, "cutting the state elsewhere keeps the governor in place")
	# A cut around the capital takes the governor along with it.
	var around := _square(sub.units[cap].center, 0.25)
	var made := sub.split_unit(id, around, "LAM")
	_check(made.ok, "the state can be cut around its capital")
	w.check_governor_unit()
	_check(w.governor.unit_id == int(made.id) and sub.capital_of(w.governor.unit_id) == cap, "the governor follows the part that holds the capital")
	# The unit disappearing ends the game.
	sub.delete_unit(w.governor.unit_id)
	w.check_governor_unit()
	_check(w.over, "a unit that ceased to exist ends the game")


func _square(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])


func _review() -> void:
	# 1. A new character after a governor game over is not a governor any more.
	var over := _governed("BRA")
	over._finish("unidade", "x")
	over.assume_new_character(Character.random(over.rng, "BRA", "LAM"))
	_check(over.governor == null and over.role() in ["head", "opposition"], "a new character after a governor game over plays the country")
	# 2. A deleted unit does not raise errors before the game ends.
	var gone := _governed("BRA")
	gone.subdivisions.delete_unit(gone.governor.unit_id)
	_check(gone.governor.pop(gone) == 0.0 and gone.governor.monthly_transfer(gone) == 0.0 and gone.governor.gdp_share(gone) == 0.0, "a missing unit has no population, share or transfers")
	gone._on_month()
	_check(gone.over, "the month closes the game for a unit that no longer exists")
	# 3. Following the capital recomputes the GDP share of the new unit.
	var cut := _governed("BRA")
	var sub := cut.subdivisions
	var id: int = cut.governor.unit_id
	var cap := sub.capital_of(id)
	var made := sub.split_unit(id, _square(sub.units[cap].center, 0.25), "LAM")
	cut.governor.gdp_share(cut)
	cut.check_governor_unit()
	var fresh := StateGov.new()
	fresh.unit_id = cut.governor.unit_id
	fresh.union_iso = "BRA"
	_check(made.ok and cut.governor.unit_id != id and is_equal_approx(cut.governor.gdp_share(cut), fresh.gdp_share(cut)), "the GDP share follows the unit the governor holds now")
	# 4. A union change while in the opposition keeps the roles consistent.
	var stuck := _governed("BRA")
	stuck.governor.enter_unit_opposition(stuck, "x")
	_compass(stuck, "CHN", true)
	stuck.diplomacy.annex(stuck.by_iso["CHN"], stuck.by_iso["BRA"], stuck)
	stuck.check_governor_unit()
	_check(stuck.role() == "governor" and stuck.governor.incumbent_party == stuck.governor.party_id, "a dictatorship that keeps an opposition leader gives them the post")
	var dem := _governed("BRA")
	dem.governor.enter_unit_opposition(dem, "x")
	_compass(dem, "ARG", true)
	dem.diplomacy.annex(dem.by_iso["ARG"], dem.by_iso["BRA"], dem)
	dem.check_governor_unit()
	dem.governor.choose_party(dem, int(dem.politics.ruling_party("ARG").id))
	_check(dem.role() == "unit_opposition" and dem.governor.incumbent_party != dem.governor.party_id, "a democracy keeps the opposition leader in the opposition, with a rival in power")
	# 5. The budget moves the approval.
	var base_w := _governed("BRA")
	var plain: StateGov = StateGov.create(base_w, _root(base_w, "BRA")).gov
	var austere: StateGov = StateGov.create(base_w, _root(base_w, "BRA")).gov
	var generous: StateGov = StateGov.create(base_w, _root(base_w, "BRA")).gov
	austere.set_tax(0.15)
	for area: String in StateGov.DEFAULT_SPEND:
		austere.set_spend(area, 0.0)
		generous.set_spend(area, 0.05)
	for i in 36:
		for g: StateGov in [plain, austere, generous]:
			g.step_month(base_w)
	_check(austere.approval < plain.approval and generous.approval > plain.approval, "heavy taxes and no services sink the approval, generous services lift it (%.2f < %.2f < %.2f)" % [austere.approval, plain.approval, generous.approval])
	# 6. The governor is not the national leader of the ruling party.
	var seat := _governed("BRA")
	_check(not seat.politics.leader_of("BRA").get("player", false), "the AI-run union keeps its own leader")


func _init() -> void:
	_review()
	_core()
	_union_change()
	_lifecycle()
	_transfers()
	_integration()
	_election()
	_directory()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
