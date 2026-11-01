extends SceneTree
## Verifica se as alavancas do jogador têm o efeito econômico esperado.
## Compara cada política com um controle, com a mesma semente e sem eventos do jogador.
## Uso: godot --headless --path . -s tests/policy.gd

const YEARS := 4
var failures := 0


func run(iso: String, policy: Callable, years := YEARS) -> Country:
	var w := GameWorld.new()
	w.setup(1234)
	w.set_player(w.by_iso[iso], "normal")
	policy.call(w.player, w)
	for d in 365 * years:
		w.player.next_election = 9999.0
		w.tick_day()
	return w.player


func check(name_: String, cond: bool, detail: String) -> void:
	print("%s  %s  (%s)" % ["ok   " if cond else "FALHA", name_, detail])
	if not cond:
		failures += 1


func _init() -> void:
	var noop := func(_c, _w): pass
	var base := run("BRA", noop)
	print("controle BRA %da: g=%.1f%% i=%.1f%% r=%.1f%% d=%.0f%% def=%.1f%% ap=%.0f%% e=%.2f K=%.0f" % [YEARS, base.growth_yoy()*100, base.pi_yoy*100, base.rate*100, base.debt_ratio*100, base.deficit/base.y_nominal()*100, base.approval*100, base.e, base.capital])

	var tight := run("BRA", func(c, _w):
		c.cb_independent = false
		c.rate_manual = true
		c.rate_set = c.rate + 0.08, 2)
	var base2 := run("BRA", noop, 2)
	check("juro alto reduz inflação", tight.pi_yoy < base2.pi_yoy, "%.1f%% vs %.1f%%" % [tight.pi_yoy*100, base2.pi_yoy*100])
	check("juro alto esfria o PIB", tight.y < base2.y, "%.0f vs %.0f" % [tight.y, base2.y])
	check("juro alto valoriza o câmbio", tight.e < base2.e, "%.2f vs %.2f" % [tight.e, base2.e])
	check("juro alto encarece a dívida", tight.avg_rate > base2.avg_rate, "%.2f%% vs %.2f%%" % [tight.avg_rate*100, base2.avg_rate*100])

	var stim := run("BRA", func(c, _w): c.sp_social += 0.04, 1)
	var base1 := run("BRA", noop, 1)
	check("gasto maior aumenta o PIB no curto prazo", stim.y > base1.y, "%.0f vs %.0f" % [stim.y, base1.y])
	check("gasto maior aumenta a dívida", stim.debt_loc + stim.debt_fx > base1.debt_loc + base1.debt_fx, "%.0f vs %.0f" % [stim.debt_loc+stim.debt_fx, base1.debt_loc+base1.debt_fx])
	check("gasto maior aumenta a inflação", stim.pi_yoy > base1.pi_yoy, "%.1f%% vs %.1f%%" % [stim.pi_yoy*100, base1.pi_yoy*100])

	var tax := run("BRA", func(c, _w): c.tax_income += 0.04, 2)
	check("imposto maior reduz o déficit", tax.deficit < base2.deficit, "%.0f vs %.0f" % [tax.deficit, base2.deficit])
	check("imposto maior reduz a aprovação", tax.approval < base2.approval, "%.0f%% vs %.0f%%" % [tax.approval*100, base2.approval*100])

	var printing := run("BRA", func(c, _w): c.mon_fin = 0.8, 3)
	var base3 := run("BRA", noop, 3)
	check("emissão monetária gera inflação", printing.pi_yoy > base3.pi_yoy + 0.01, "%.1f%% vs %.1f%%" % [printing.pi_yoy*100, base3.pi_yoy*100])
	check("emissão monetária destrói credibilidade", printing.cred < base3.cred, "%.2f vs %.2f" % [printing.cred, base3.cred])
	check("emissão monetária deprecia o câmbio", printing.e > base3.e, "%.2f vs %.2f" % [printing.e, base3.e])

	var base15 := run("KOR", noop, 15)
	var edu := run("KOR", func(c, _w):
		c.sp_education += 0.02
		c.sp_infra += 0.01, 15)
	var base_y: float = base15.y_pot
	check("educação e infraestrutura elevam o potencial em 15 anos", edu.y_pot > base_y, "%.0f vs %.0f" % [edu.y_pot, base_y])

	var tariff := run("BRA", func(c, _w): c.tariff = 0.3, 2)
	check("tarifa reduz importações", tariff.imports < base2.imports, "%.0f vs %.0f" % [tariff.imports, base2.imports])

	# Embargo a um grande exportador de petróleo encarece o barril para todos.
	var w1 := GameWorld.new()
	w1.setup(99)
	var w2 := GameWorld.new()
	w2.setup(99)
	var sau: Country = w2.by_iso["SAU"]
	for c: Country in w2.countries:
		if c.iso in ["USA", "CHN", "IND", "JPN", "DEU", "FRA", "GBR", "KOR", "ITA", "CAN"]:
			w2.diplomacy.set_sanction(c, sau, 2, w2)
	# O pico vem nos primeiros meses; depois a OPEP+ e a demanda reequilibram o mercado.
	for d in 120:
		w1.tick_day()
		w2.tick_day()
	check("embargo a grande exportador encarece o petróleo", w2.markets.price[0] > w1.markets.price[0] * 1.1, "$%.0f vs $%.0f" % [w2.markets.price[0], w1.markets.price[0]])
	print("falhas: ", failures)
	quit(1 if failures > 0 else 0)
