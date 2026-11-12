extends SceneTree
## Demography: initial groups, aging, work, pensions and migration.
## Usage: godot --headless --path . --script tests/demography.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _init() -> void:
	var w := GameWorld.new()
	w.setup(7)
	var jpn: Country = w.by_iso["JPN"]
	var nga: Country = w.by_iso["NGA"]
	for c: Country in w.countries:
		if absf(c.young + c.adult + c.old - 1.0) > 0.001 or c.old <= 0.0 or c.young <= 0.0:
			_check(false, "groups sum to 1 in %s" % c.iso)
	_check(jpn.old > 0.22 and jpn.old > nga.old * 5.0, "Japan much older than Nigeria (%.2f, %.2f)" % [jpn.old, nga.old])
	_check(nga.young > 0.38, "Nigeria young (%.2f)" % nga.young)
	_check(nga.birth > jpn.birth * 2.0, "natalidade nigeriana bem maior")

	# Envelhecimento reduz trabalho e aumenta aposentadorias.
	var c: Country = w.by_iso["DEU"]
	var f0 := Demography.labor_factor(c)
	var p0 := Demography.pension_extra(c)
	var pop := c.pop
	c.adult -= 0.05
	c.old += 0.05
	_check(Demography.labor_factor(c) < f0, "more elderly, less work")
	_check(Demography.pension_extra(c) > p0 + 0.005, "more elderly, more pensions")
	c.adult += 0.05
	c.old -= 0.05

	# Migration: war drives people out and the world total barely changes.
	var ukr: Country = w.by_iso["UKR"]
	w.diplomacy.declare_war(w.by_iso["RUS"], ukr, w)
	var world0 := 0.0
	for x: Country in w.countries:
		world0 += x.pop
	var births := 0.0
	for i in 12:
		var before := 0.0
		for x: Country in w.countries:
			if x.alive:
				before += x.pop
		Demography.step_world(w)
		var after := 0.0
		for x: Country in w.countries:
			if x.alive:
				after += x.pop
		births += absf(after - before)
	_check(ukr.migration < -0.003, "war makes Ukraine lose people (%.4f)" % ukr.migration)
	_check(w.by_iso["USA"].migration > 0.0, "EUA recebem migrantes")
	_check(births < world0 * 0.0005, "migration preserves the world population")

	# A year of simulation keeps populations finite and coherent.
	var w2 := GameWorld.new()
	w2.setup(3)
	var bra0: float = w2.by_iso["BRA"].pop
	var usa2: Country = w2.by_iso["USA"]
	var usa0 := usa2.pop
	# The growth in the data already includes immigrants: the birth rate does not count migration again.
	_check(absf(usa2.birth - usa2.death + usa2.migration - usa2.popg) < 0.0005 and usa2.migration > 0.002, "USA: births + migration = growth in the data (mig %.4f)" % usa2.migration)
	var natural := usa2.birth - usa2.death
	for d in 365:
		w2.tick_day()
	var bra: Country = w2.by_iso["BRA"]
	_check(bra.pop > bra0 * 0.99 and bra.pop < bra0 * 1.02, "Brazil grows little in a year (%.1f → %.1f)" % [bra0, bra.pop])
	_check(absf(bra.young + bra.adult + bra.old - 1.0) < 0.001, "faixas seguem somando 1")
	_check(usa2.pop / usa0 - 1.0 > natural + 0.002, "migration comes in every month (USA %.2f%% in the year)" % ((usa2.pop / usa0 - 1.0) * 100.0))
	var jpn2: Country = w2.by_iso["JPN"]
	_check(jpn2.pop < w.by_iso["JPN"].pop, "Japan shrinks")

	# Annexation: whoever arrives brings their age structure; work does not jump.
	var deu: Country = w2.by_iso["DEU"]
	var nga2: Country = w2.by_iso["NGA"]
	var lf0 := Demography.labor_factor(deu)
	var young0 := deu.young
	w2.diplomacy.transfer(nga2, deu, 0.2, w2)
	_check(deu.young > young0 + 0.05, "annexing part of Nigeria rejuvenates Germany (%.2f → %.2f)" % [young0, deu.young])
	_check(absf(deu.young + deu.adult + deu.old - 1.0) < 0.001, "groups sum to 1 after the annexation")
	_check(absf(Demography.labor_factor(deu) - lf0) < 0.02, "the labor factor does not jump on annexation")
	# Old save without groups: the structure is built in the first step.
	var old_save := Country.from_dict(bra.to_dict())
	old_save.adult = 0.0
	Demography.ensure(old_save)
	_check(old_save.adult > 0.5, "old save gets groups")
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
