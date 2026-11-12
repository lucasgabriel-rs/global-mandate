extends SceneTree
## Runs the simulation without the interface and prints indicators to calibrate the model.
## Usage: godot --headless --path . -s tests/calibrate.gd -- [years] [seed] [scenario]

const WATCH := ["USA", "CHN", "DEU", "JPN", "IND", "BRA", "RUS", "UKR", "ARG", "TUR", "SAU", "NGA", "TWN"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 10
	var seed_value := int(args[1]) if args.size() > 1 else 42
	var scenario: String = args[2] if args.size() > 2 else ""
	var w := GameWorld.new()
	var news := []
	w.news_posted.connect(func(t, k, _c): news.append("[%s] %s" % [w.date_string(), t]))
	var t0 := Time.get_ticks_msec()
	w.setup(seed_value)
	print("setup ms: ", Time.get_ticks_msec() - t0)
	var issues := 0
	t0 = Time.get_ticks_msec()
	for y in years:
		for d in 365:
			w.tick_day()
			if scenario == "taiwan" and y == 2 and d == 0:
				w.diplomacy.declare_war(w.by_iso["CHN"], w.by_iso["TWN"], w)
			if scenario == "hormuz" and y == 2 and d == 0:
				w.markets.shock[Markets.OIL] = 0.18
				w.markets.shock[Markets.GAS] = 0.18
			if scenario != "" and d == 90 and y == 2:
				print("  3 months later: oil=%.0f gas=%.1f chip=%.0f" % [w.markets.price[0], w.markets.price[1], w.markets.price[4]])
			if scenario != "" and d == 270 and y == 2:
				print("  9 months later: oil=%.0f gas=%.1f chip=%.0f" % [w.markets.price[0], w.markets.price[1], w.markets.price[4]])
		issues += _report(w, 2025 + y)
	var ms := Time.get_ticks_msec() - t0
	print("time: %d ms for %d years (%.2f ms/day)" % [ms, years, float(ms) / (years * 365.0)])
	print("active wars: ", w.diplomacy.wars.map(func(x): return "%s>%s %.0f%%" % [w.countries[x.main_a].iso, w.countries[x.main_d].iso, x.front]))
	var dead := w.countries.filter(func(c): return not c.alive).map(func(c): return c.iso)
	print("annexed: ", dead)
	print("--- news (%d) ---" % news.size())
	for line in news.slice(maxi(0, news.size() - 45)):
		print(line)
	print("numeric problems: ", issues)
	quit(1 if issues > 0 else 0)


func _report(w: GameWorld, y: int) -> int:
	var total := 0.0
	var growth := 0.0
	var infl := PackedFloat32Array()
	var defaults := 0
	var bad := 0
	for c: Country in w.countries:
		if not c.alive:
			continue
		for v in [c.y, c.p, c.e, c.pi_yoy, c.rate, c.debt_ratio, c.unemp, c.risk, c.gap, c.capital, c.tfp]:
			if is_nan(v) or is_inf(v):
				bad += 1
				print("NaN in ", c.iso)
				break
		total += c.y_usd()
		growth += c.growth_yoy() * c.y_usd()
		infl.append(c.pi_yoy)
		if w.year_float() < c.default_until:
			defaults += 1
	infl.sort()
	var m := w.markets
	print("%d worldGDP=%.0f g=%.1f%% infl.med=%.1f%% risk=%.2f tension=%.2f defaults=%d | oil=%.0f gas=%.1f gr=%.0f met=%.0f chip=%.0f" % [
		y, total, growth / total * 100.0, infl[infl.size() / 2] * 100.0, w.global_risk, w.global_tension, defaults,
		m.price[0], m.price[1], m.price[2], m.price[3], m.price[4]])
	var parts := []
	for iso in WATCH:
		var c: Country = w.by_iso[iso]
		parts.append("%s g%.1f i%.0f u%.0f r%.0f d%.0f def%.0f e%.2f ap%.0f" % [iso, c.growth_yoy() * 100, c.pi_yoy * 100, c.unemp * 100, c.rate * 100, c.debt_ratio * 100, c.deficit / c.y_nominal() * 100, c.e, c.approval * 100])
	print("   ", " | ".join(parts))
	var demo := []
	for iso in WATCH:
		var c: Country = w.by_iso[iso]
		demo.append("%s pop%.0f j%.0f a%.0f i%.0f mig%+.2f" % [iso, c.pop, c.young * 100, c.adult * 100, c.old * 100, c.migration * 100])
	print("   pop: ", " | ".join(demo))
	return bad
