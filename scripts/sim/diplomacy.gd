class_name Diplomacy
extends RefCounted
## Relações bilaterais, comércio gravitacional, sanções, tarifas, tratados e guerras.

const BLOC_AFFINITY := {
	"NATO": 42, "EU": 30, "G7": 18, "USMCA": 30, "AUKUS": 30, "QUAD": 18, "BRICS": 16, "SCO": 12,
	"CSTO": 35, "GCC": 32, "ASEAN": 18, "AU": 8, "ARAB": 12, "MERCOSUL": 22, "RCEP": 6, "G20": 3,
}
const TRADE_BLOCS := ["EU", "USMCA", "ASEAN", "MERCOSUL", "GCC", "RCEP"]
const DEFENSE_BLOCS := ["NATO", "CSTO"]
# Relações de partida fora do que os blocos explicam.
const PAIRS := {
	"RUS-UKR": -95, "USA-RUS": -62, "USA-CHN": -35, "USA-IRN": -85, "USA-PRK": -90, "ISR-IRN": -95,
	"ISR-SYR": -70, "ISR-LBN": -75, "ISR-PSE": -90, "IND-PAK": -75, "CHN-IND": -35, "CHN-TWN": -80, "CHN-JPN": -35,
	"KOR-PRK": -90, "JPN-PRK": -70, "SAU-IRN": -25, "ARM-AZE": -75, "GRC-TUR": -25, "MAR-DZA": -60,
	"ETH-ERI": -35, "RWA-COD": -70, "USA-VEN": -60, "USA-CUB": -55, "RUS-POL": -70, "RUS-EST": -70,
	"RUS-LVA": -70, "RUS-LTU": -70, "RUS-GBR": -62, "RUS-DEU": -50, "RUS-FRA": -48, "RUS-FIN": -55,
	"RUS-SWE": -50, "RUS-CAN": -55, "RUS-JPN": -40, "RUS-GEO": -60, "CHN-PHL": -40, "CHN-VNM": -15,
	"USA-ISR": 75, "USA-GBR": 85, "USA-JPN": 75, "USA-KOR": 75, "USA-TWN": 55, "USA-AUS": 80, "USA-CAN": 75,
	"USA-MEX": 45, "USA-UKR": 50, "USA-SAU": 40, "USA-PHL": 50, "RUS-CHN": 65, "RUS-BLR": 90, "RUS-PRK": 55,
	"RUS-IRN": 50, "RUS-SYR": 30, "CHN-PRK": 50, "CHN-PAK": 70, "IND-RUS": 45, "RUS-VEN": 45, "RUS-CUB": 45,
	"CHN-IRN": 40, "GBR-UKR": 60, "DEU-UKR": 50, "POL-UKR": 60, "FRA-UKR": 45, "CAN-UKR": 50, "SAU-ARE": 55,
	"ALG-MAR": -60, "PAK-SAU": 55, "JPN-KOR": 20, "IND-USA": 35, "BRA-ARG": 30, "TUR-AZE": 75, "ARM-TUR": -60,
	"GBR-AUS": 70, "ISR-ARE": 25, "EGY-ISR": 10, "SDN-ARE": -25, "BLR-POL": -60, "TWN-JPN": 35,
}
const INITIAL_ALLIANCES := [
	"USA-JPN", "USA-KOR", "USA-PHL", "USA-AUS", "USA-TWN", "USA-ISR", "RUS-BLR", "RUS-PRK", "CHN-PRK",
	"SAU-PAK", "GBR-AUS",
]
const WESTERN_SANCTIONERS := ["USA", "GBR", "CAN", "AUS", "JPN", "CHE", "NOR", "KOR", "NZL"]
const INITIAL_SANCTIONS := {"RUS": 2, "IRN": 2, "PRK": 2, "BLR": 1, "SYR": 1, "VEN": 1, "MMR": 1}

var n := 0
var relations := PackedFloat32Array()
var rel_base := PackedFloat32Array()
var shares := PackedFloat32Array()
var factor := PackedFloat32Array()
var sanctions := {}     # int(a*n+b) -> nível (a sanciona b)
var tariffs := {}       # int(a*n+b) -> tarifa extra que a impõe a b
var fta := {}           # int(min*n+max) -> true (acordo fora dos blocos)
var alliances := {}     # int(min*n+max) -> true
var wars: Array = []
var next_war_id := 1


func key(a: int, b: int) -> int:
	return a * n + b


func pair(a: int, b: int) -> int:
	return mini(a, b) * n + maxi(a, b)


func setup(world: GameWorld) -> void:
	n = world.countries.size()
	relations.resize(n * n)
	rel_base.resize(n * n)
	shares.resize(n * n)
	factor.resize(n * n)
	var by_iso := world.by_iso
	for i in n:
		var a: Country = world.countries[i]
		for j in n:
			var b: Country = world.countries[j]
			var v := 0.0
			if i != j:
				if a.region == b.region:
					v += 10.0
				for bloc in a.blocs:
					if bloc in b.blocs:
						v += float(BLOC_AFFINITY.get(bloc, 5))
				v += world.rng.randf_range(-6.0, 6.0)
				if a.dem >= 7.0 and b.dem >= 7.0:
					v += 10.0
				elif (a.dem >= 7.0 and b.dem < 3.0) or (a.dem < 3.0 and b.dem >= 7.0):
					v -= 10.0
			relations[i * n + j] = clampf(v, -60.0, 95.0)
			factor[i * n + j] = 1.0
	for i in n:
		for j in range(i + 1, n):
			var v: float = (relations[i * n + j] + relations[j * n + i]) * 0.5
			relations[i * n + j] = v
			relations[j * n + i] = v
	for code: String in PAIRS:
		var parts := code.split("-")
		if by_iso.has(parts[0]) and by_iso.has(parts[1]):
			set_relation(by_iso[parts[0]].idx, by_iso[parts[1]].idx, float(PAIRS[code]))
	rel_base = relations.duplicate()
	# Tratados de defesa dos blocos e bilaterais.
	for i in n:
		for j in range(i + 1, n):
			var a: Country = world.countries[i]
			var b: Country = world.countries[j]
			for bloc in DEFENSE_BLOCS:
				if bloc in a.blocs and bloc in b.blocs:
					alliances[pair(i, j)] = true
	for code: String in INITIAL_ALLIANCES:
		var parts := code.split("-")
		alliances[pair(by_iso[parts[0]].idx, by_iso[parts[1]].idx)] = true
	# Sanções em vigor.
	for target: String in INITIAL_SANCTIONS:
		var level: int = INITIAL_SANCTIONS[target]
		var t: Country = by_iso[target]
		for c: Country in world.countries:
			if c == t:
				continue
			if c.iso in WESTERN_SANCTIONERS or ("EU" in c.blocs and c.iso != "HUN"):
				sanctions[key(c.idx, t.idx)] = level
	if by_iso.has("CUB"):
		sanctions[key(by_iso["USA"].idx, by_iso["CUB"].idx)] = 1
	_compute_shares(world)
	_rebuild_factors(world)
	# Guerra em curso no início da partida.
	var w := _new_war(by_iso["RUS"], by_iso["UKR"], world, false)
	w.front = 18.0
	w.months = 34.0
	_sync_occupation(world)
	refresh_sanction_cache(world)
	# O PIB de 2024 já embute sanções, ocupação e perda de comércio em vigor.
	for c: Country in world.countries:
		c.trade0 = float(trade_channel(c, world).loss)
		c.press0 = sanction_pressure(c)
		c.occ0 = c.occupied
		if c.occupied > 0.0:
			c.tfp /= 1.0 - c.occupied * 0.85
	update_prod_factors(world)


func _compute_shares(world: GameWorld) -> void:
	for i in n:
		var a: Country = world.countries[i]
		var total := 0.0
		for j in n:
			if i == j:
				shares[i * n + j] = 0.0
				continue
			var b: Country = world.countries[j]
			var d := maxf(a.center.distance_to(b.center), 40.0)
			var w := pow(b.y_usd(), 0.9) / pow(d, 1.05)
			if a.region == b.region:
				w *= 1.4
			for bloc in TRADE_BLOCS:
				if bloc in a.blocs and bloc in b.blocs:
					w *= 2.2 if bloc != "RCEP" else 1.25
					break
			w *= clampf(1.0 + relations[i * n + j] / 140.0, 0.45, 1.6)
			shares[i * n + j] = w
			total += w
		for j in n:
			shares[i * n + j] /= maxf(total, 0.0001)


func _rebuild_factors(world: GameWorld) -> void:
	for i in n:
		for j in n:
			if i != j:
				factor[i * n + j] = _pair_factor(i, j, world)


func _pair_factor(i: int, j: int, _world: GameWorld) -> float:
	var f := 1.0
	if fta.has(pair(i, j)):
		f += 0.35
	f -= 2.2 * (float(tariffs.get(key(j, i), 0.0)))  # tarifa que j cobra das exportações de i
	var lvl := maxi(int(sanctions.get(key(i, j), 0)), int(sanctions.get(key(j, i), 0)))
	if lvl == 1:
		f *= 0.4
	elif lvl >= 2:
		f *= 0.12
	if at_war(i, j):
		f = 0.0
	return clampf(f, 0.0, 1.6)


func refresh_pair(i: int, j: int, world: GameWorld) -> void:
	factor[i * n + j] = _pair_factor(i, j, world)
	factor[j * n + i] = _pair_factor(j, i, world)


## Canal externo de um país: x = demanda dos parceiros (hiato ponderado) e
## loss = perda (<0) ou ganho (>0) de acesso a mercados, já com desvio de comércio.
func trade_channel(c: Country, world: GameWorld) -> Dictionary:
	var row := c.idx * n
	var x := 0.0
	var loss := 0.0
	var cs := world.countries
	for j in n:
		var s := shares[row + j]
		if s < 0.002:
			continue
		var o: Country = cs[j]
		if not o.alive:
			continue
		var f := factor[row + j]
		x += s * o.gap * f
		var df := f - 1.0
		# Parte do comércio perdido encontra outros destinos.
		loss += s * (df * 0.55 if df < 0.0 else df * 0.8)
	return {"x": x, "loss": clampf(loss, -0.9, 0.4)}


func sanction_pressure(c: Country) -> float:
	return clampf(_sanction_cache.get(c.idx, 0.0), 0.0, 1.0)


var _sanction_cache := {}


func refresh_sanction_cache(world: GameWorld) -> void:
	_sanction_cache.clear()
	var wg := maxf(world.world_gdp(), 1.0)
	for k: int in sanctions:
		var a: int = k / n
		var b: int = k % n
		if not world.countries[a].alive:
			continue
		var w: float = world.countries[a].y_usd() / wg
		_sanction_cache[b] = float(_sanction_cache.get(b, 0.0)) + w * (1.0 if int(sanctions[k]) >= 2 else 0.5)
	update_prod_factors(world)


func update_prod_factors(world: GameWorld) -> void:
	for c: Country in world.countries:
		if not c.alive:
			continue
		var pressure := maxf(sanction_pressure(c) - c.press0, 0.0)
		var war_loss := maxf(c.occupied - c.occ0, 0.0) + c.damage * 0.5
		var energy_loss := clampf(0.55 * pressure, 0.0, 0.45)
		for i in 5:
			var loss := war_loss
			if i <= Markets.GAS:
				loss += energy_loss
			elif i == Markets.CHIP:
				# Fábricas de chips dependem de cadeias globais: guerra derruba muito mais.
				loss = clampf(war_loss * 3.0 + (0.65 if is_invaded(c.idx) else 0.0), 0.0, 0.97)
			else:
				loss += 0.2 * pressure
			c.prod_factor[i] = clampf(1.0 - loss, 0.03, 1.0)


func relation(a: int, b: int) -> float:
	return relations[a * n + b]


func set_relation(a: int, b: int, v: float) -> void:
	var nv := clampf(v, -100.0, 100.0)
	relations[a * n + b] = nv
	relations[b * n + a] = nv


func add_relation(a: int, b: int, delta: float) -> void:
	set_relation(a, b, relation(a, b) + delta)


func allied(a: int, b: int) -> bool:
	return alliances.has(pair(a, b))


func has_fta(a: int, b: int, world: GameWorld) -> bool:
	if fta.has(pair(a, b)):
		return true
	var ca: Country = world.countries[a]
	var cb: Country = world.countries[b]
	for bloc in TRADE_BLOCS:
		if bloc in ca.blocs and bloc in cb.blocs:
			return true
	return false


func sanction_level(a: int, b: int) -> int:
	return int(sanctions.get(key(a, b), 0))


func at_war(a: int, b: int) -> bool:
	for w: Dictionary in wars:
		if (a in w.a and b in w.d) or (a in w.d and b in w.a):
			return true
	return false


func in_war(a: int) -> bool:
	for w: Dictionary in wars:
		if a in w.a or a in w.d:
			return true
	return false


func is_invaded(a: int) -> bool:
	for w: Dictionary in wars:
		if a == w.main_d:
			return true
	return false


func war_between(a: int, b: int) -> Dictionary:
	for w: Dictionary in wars:
		if (a in w.a and b in w.d) or (a in w.d and b in w.a):
			return w
	return {}


func top_partners(c: Country, count: int, world: GameWorld) -> Array:
	var out := []
	var row := c.idx * n
	for j in n:
		var s := shares[row + j] * factor[row + j]
		if s > 0.001 and world.countries[j].alive:
			out.append([j, s])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out.slice(0, count)


# --- Ações ---------------------------------------------------------------

func set_sanction(a: Country, b: Country, level: int, world: GameWorld) -> void:
	var k := key(a.idx, b.idx)
	var before := int(sanctions.get(k, 0))
	if level <= 0:
		sanctions.erase(k)
		add_relation(a.idx, b.idx, 6.0)
	else:
		sanctions[k] = level
		if level > before:
			add_relation(a.idx, b.idx, -18.0 * (level - before))
	refresh_pair(a.idx, b.idx, world)
	refresh_sanction_cache(world)


func set_tariff_on(a: Country, b: Country, rate: float, world: GameWorld) -> void:
	var k := key(a.idx, b.idx)
	var before := float(tariffs.get(k, 0.0))
	if rate <= 0.0:
		tariffs.erase(k)
	else:
		tariffs[k] = rate
	add_relation(a.idx, b.idx, -(rate - before) * 80.0)
	refresh_pair(a.idx, b.idx, world)
	# Retaliação proporcional de quem tem peso para isso.
	if a != world.governed():
		return
	if rate > before and b.y_usd() > a.y_usd() * 0.05 and world.rng.randf() < 0.65:
		tariffs[key(b.idx, a.idx)] = rate * 0.8
		refresh_pair(a.idx, b.idx, world)
		world.emit_news(tr("%s retalia com tarifa de %d%% contra %s.") % [b.name, int(rate * 80.0), a.name], "economia", b)


func sign_fta(a: Country, b: Country, world: GameWorld) -> void:
	fta[pair(a.idx, b.idx)] = true
	add_relation(a.idx, b.idx, 10.0)
	refresh_pair(a.idx, b.idx, world)


func sign_alliance(a: Country, b: Country, world: GameWorld) -> void:
	alliances[pair(a.idx, b.idx)] = true
	add_relation(a.idx, b.idx, 12.0)
	world.emit_news(tr("%s e %s assinam pacto de defesa mútua.") % [a.name, b.name], "diplomacia", a)
	# Inimigos do novo aliado desconfiam.
	for c: Country in world.countries:
		if c != a and c != b and c.alive and relation(c.idx, b.idx) < -50.0:
			add_relation(c.idx, a.idx, -6.0)


func break_alliance(a: Country, b: Country, _world: GameWorld) -> void:
	alliances.erase(pair(a.idx, b.idx))
	add_relation(a.idx, b.idx, -25.0)


func on_government_change(c: Country, world: GameWorld) -> void:
	# Novo governo reposiciona a política externa, sobretudo em relação às grandes potências.
	for iso: String in ["USA", "CHN", "RUS"]:
		var o: Country = world.by_iso[iso]
		if o != c and o.alive:
			add_relation(c.idx, o.idx, world.rng.randf_range(-8.0, 8.0))
	if world.governed() and world.governed() != c:
		add_relation(c.idx, world.governed().idx, world.rng.randf_range(-10.0, 10.0))


# --- Guerra --------------------------------------------------------------

func _new_war(att: Country, def: Country, world: GameWorld, announce := true) -> Dictionary:
	var w := {
		"id": next_war_id, "main_a": att.idx, "main_d": def.idx,
		"a": [att.idx], "d": [def.idx], "front": 0.0, "months": 0.0,
		"loss_a": 0.0, "loss_d": 0.0, "sup_a": 0.0, "sup_d": 0.0, "day": 0,
	}
	next_war_id += 1
	wars.append(w)
	refresh_pair(att.idx, def.idx, world)
	set_relation(att.idx, def.idx, minf(relation(att.idx, def.idx), -90.0))
	if announce:
		_join_allies(w, world)
	_compute_support(w, world)
	for i: int in w.a + w.d:
		var c: Country = world.countries[i]
		c.mobilization = maxf(c.mobilization, 0.35)
	return w


func declare_war(att: Country, def: Country, world: GameWorld) -> Dictionary:
	world.treaties.on_war(world, att, def)
	var w := _new_war(att, def, world)
	world.emit_news(tr("GUERRA: %s invade %s.") % [att.name, def.name], "guerra", att)
	# Efeito de união nacional: curto no agressor, forte em quem é atacado.
	att.approval = minf(att.approval + 0.04, 0.95)
	def.approval = minf(def.approval + 0.12, 0.95)
	var size: float = (att.y_usd() + def.y_usd()) / maxf(world.world_gdp(), 1.0)
	world.global_risk = clampf(world.global_risk + 0.1 + 1.2 * size, 0.0, 1.0)
	def.demand_shock -= 0.08
	att.demand_shock -= 0.02
	_world_reaction(att, def, world)
	world.war_declared(w, att, def)
	return w


func _join_allies(w: Dictionary, world: GameWorld) -> void:
	var att: Country = world.countries[w.main_a]
	var def: Country = world.countries[w.main_d]
	for c: Country in world.countries:
		if c == att or c == def or not c.alive:
			continue
		if allied(c.idx, def.idx) and not allied(c.idx, att.idx):
			if c == world.governed():
				world.ally_attacked(w, def, att)
			elif world.rng.randf() < 0.85:
				w.d.append(c.idx)
				_mark_enemies(c.idx, w.a, world)
		elif allied(c.idx, att.idx) and not allied(c.idx, def.idx) and relation(c.idx, def.idx) < -40.0:
			if c != world.governed() and world.rng.randf() < 0.3:
				w.a.append(c.idx)
				_mark_enemies(c.idx, w.d, world)


func join_war(c: Country, w: Dictionary, on_defense: bool, world: GameWorld) -> void:
	if on_defense:
		w.d.append(c.idx)
		_mark_enemies(c.idx, w.a, world)
	else:
		w.a.append(c.idx)
		_mark_enemies(c.idx, w.d, world)
	c.mobilization = maxf(c.mobilization, 0.25)
	world.emit_news(tr("%s entra na guerra entre %s e %s.") % [c.name, world.countries[w.main_a].name, world.countries[w.main_d].name], "guerra", c)


func _mark_enemies(idx: int, enemies: Array, world: GameWorld) -> void:
	for e: int in enemies:
		set_relation(idx, e, minf(relation(idx, e), -80.0))
		refresh_pair(idx, e, world)


func _world_reaction(att: Country, def: Country, world: GameWorld) -> void:
	for c: Country in world.countries:
		if c == att or c == def or not c.alive or c == world.governed():
			continue
		var rd := relation(c.idx, def.idx)
		var ra := relation(c.idx, att.idx)
		add_relation(c.idx, att.idx, -6.0 + (rd - ra) * 0.06)
		# Democracias grandes e amigas do agredido respondem com sanções.
		if c.dem >= 6.0 and rd > 15.0 and ra < 30.0 and c.y_usd() > 40.0 and not at_war(c.idx, att.idx):
			if world.rng.randf() < clampf(0.25 + rd / 100.0, 0.0, 0.9):
				sanctions[key(c.idx, att.idx)] = 2 if rd > 45.0 else 1
				refresh_pair(c.idx, att.idx, world)
	refresh_sanction_cache(world)


func _compute_support(w: Dictionary, world: GameWorld) -> void:
	var a_main: Country = world.countries[w.main_a]
	var d_main: Country = world.countries[w.main_d]
	var sup_a := 0.0
	var sup_d := 0.0
	var grant_d := 0.0
	for c: Country in world.countries:
		if not c.alive or c.idx in w.a or c.idx in w.d:
			continue
		var ra := relation(c.idx, a_main.idx)
		var rd := relation(c.idx, d_main.idx)
		var budget := c.military_power() * 0.018
		if rd > 40.0 and ra < 10.0:
			sup_d += budget * rd / 80.0
			grant_d += c.y_usd() * 0.0012 * rd / 80.0
		elif ra > 40.0 and rd < 10.0:
			sup_a += budget * ra / 80.0
	w.sup_a = sup_a
	w.sup_d = sup_d
	# Doadores também financiam o orçamento de quem foi invadido.
	d_main.aid_flow = minf(grant_d, d_main.y_usd() * 0.35)


func side_power(side: Array, main: int, world: GameWorld) -> float:
	var total := 0.0
	for i: int in side:
		var c: Country = world.countries[i]
		if not c.alive:
			continue
		if i == main:
			total += c.military_power()
		else:
			var m: Country = world.countries[main]
			total += c.military_power() * (0.55 if c.region == m.region else 0.3)
	return total


func step_wars(world: GameWorld) -> void:
	for w: Dictionary in wars.duplicate():
		_step_war(w, world)
	_sync_occupation(world)


func _step_war(w: Dictionary, world: GameWorld) -> void:
	var dt := 1.0 / 30.4
	w.day = int(w.day) + 1
	w.months = float(w.months) + dt
	var att: Country = world.countries[w.main_a]
	var def: Country = world.countries[w.main_d]
	if w.day % 30 == 0:
		_compute_support(w, world)
	var pa: float = side_power(w.a, w.main_a, world) + minf(float(w.sup_a), att.military_power() * 0.6)
	var pd: float = side_power(w.d, w.main_d, world) + minf(float(w.sup_d), def.military_power() * 1.0)
	pa *= clampf(600.0 / maxf(att.center.distance_to(def.center), 150.0), 0.35, 1.0)
	var off_a := 1.25 if att.stance_offensive else 1.0
	var off_d := 1.25 if def.stance_offensive else 1.0
	var net := (pa * off_a - 1.45 * pd * off_d) / maxf(pa * off_a + 1.45 * pd * off_d, 0.01)
	if absf(net) < 0.08:
		net = 0.0
	var size_f := clampf(sqrt(900.0 / maxf(def.area, 5.0)), 0.12, 2.2)
	var fatigue := 0.35 + 0.65 / (1.0 + float(w.months) / 8.0)
	var speed := 0.42 * net * size_f * fatigue + world.rng.randfn(0.0, 0.015)
	w.front = clampf(float(w.front) + speed, -60.0, 100.0)

	# Atrito: quem enfrenta força maior perde proporcionalmente mais.
	var ratio := clampf(pd / maxf(pa, 0.01), 0.25, 4.0)
	var inten := 1.0 + (off_a - 1.0) + (off_d - 1.0)
	_attrit(att, 0.00022 * ratio * inten, w, "loss_a")
	_attrit(def, 0.00022 / ratio * inten, w, "loss_d")
	for i: int in w.a + w.d:
		var c: Country = world.countries[i]
		var share := 1.0 if i == w.main_a or i == w.main_d else 0.4
		c.war_exhaustion = minf(c.war_exhaustion + 0.00038 * share * (1.0 + ratio * 0.2), 1.0)
		if i != w.main_a and i != w.main_d:
			_attrit(c, 0.00006, w, "loss_a" if i in w.a else "loss_d")
	if float(w.front) > 0.5:
		def.damage = minf(def.damage + 0.00006 * (1.0 + float(w.front) * 0.02), 0.5)
		def.pop *= 1.0 - 0.00002
		def.capital *= 1.0 - 0.00003
	elif float(w.front) < -0.5:
		att.damage = minf(att.damage + 0.00006, 0.5)

	if float(w.front) >= 97.0:
		_capitulation(w, att, def, world)
		return
	if float(w.front) <= -50.0:
		if def == world.governed():
			world.player_repelled(w, att)
			return
		_end_war(w, world, tr("%s expulsa os invasores e força %s a recuar.") % [def.name, att.name], def, att, 0.0)
		return
	# Dissuasão falha: potência nuclear à beira da derrota total.
	if world.nuclear_check(w, att, def):
		return
	if w.day % 30 == 0:
		_ai_peace_check(w, att, def, world)


func _attrit(c: Country, rate: float, w: Dictionary, counter: String) -> void:
	var lost := c.troops * rate
	c.troops = maxf(c.troops - lost, 0.2)
	c.mil_stock = maxf(c.mil_stock * (1.0 - rate * 1.2), 0.01)
	w[counter] = float(w[counter]) + lost


func _sync_occupation(world: GameWorld) -> void:
	var occ := {}
	for w: Dictionary in wars:
		var f: float = w.front
		if f > 0.0:
			occ[w.main_d] = maxf(float(occ.get(w.main_d, 0.0)), f / 100.0)
		elif f < 0.0:
			occ[w.main_a] = maxf(float(occ.get(w.main_a, 0.0)), -f / 100.0)
	for c: Country in world.countries:
		c.occupied = float(occ.get(c.idx, 0.0))


func _ai_peace_check(w: Dictionary, att: Country, def: Country, world: GameWorld) -> void:
	# Ao lado do jogador, a paz só acontece por decisão dele.
	if world.governed() and (world.governed().idx in w.a or world.governed().idx in w.d):
		return
	var front: float = w.front
	var att_want := att.war_exhaustion * 0.8 + (0.3 if front >= 25.0 else 0.0) + (0.25 if float(w.months) > 24.0 else 0.0) + 0.5 * maxf(att.risk - 0.1, 0.0)
	var def_want := def.war_exhaustion * 0.6 + front * 0.008
	if att_want > 0.8 and def_want > 0.7 and world.rng.randf() < 0.1:
		var share := clampf(front * 0.004, 0.0, 0.35) if front > 10.0 else 0.0
		var msg := tr("Cessar-fogo entre %s e %s: as fronteiras antigas voltam a valer.") % [att.name, def.name]
		if share > 0.0:
			msg = tr("Tratado de paz: %s cede {pct} do território a %s.") % [def.name, att.name]
		elif absf(front) > 3.0 and world.rng.randf() < 0.35:
			# Paz sem vencedor em que os dois lados negociam uma nova linha de fronteira.
			var gainer := att if front > 0.0 else def
			var yielder := def if front > 0.0 else att
			_end_war(w, world, tr("Negociação entre %s e %s: %s cede {pct} do território.") % [att.name, def.name, yielder.name], gainer, yielder, absf(front) * 0.004)
			return
		_end_war(w, world, msg, att, def, share)


func _capitulation(w: Dictionary, att: Country, def: Country, world: GameWorld) -> void:
	if att == world.governed():
		world.player_won_war(w, def)
		return
	if def == world.governed():
		world.player_lost_war(att)
		wars.erase(w)
		return
	if att.dem < 4.0 or att.aggression > 0.4:
		annex(att, def, world)
		_end_war(w, world, tr("%s capitula e é anexado por %s.") % [def.name, att.name], att, def, 0.0)
	else:
		make_client(att, def, world)
		_end_war(w, world, tr("%s capitula; %s instala governo aliado.") % [def.name, att.name], att, def, 0.0)


func end_war_by_player(w: Dictionary, winner: Country, loser: Country, world: GameWorld, share: float, msg: String) -> void:
	_end_war(w, world, msg, winner, loser, share)


func _end_war(w: Dictionary, world: GameWorld, msg: String, gainer: Country, loser: Country, share: float) -> void:
	wars.erase(w)
	var text := msg
	if share > 0.0:
		var ceded := world.territories.auto_cede(loser, gainer, share, world)
		if ceded > 0.0:
			transfer(loser, gainer, ceded, world)
			text = msg.replace("{pct}", "%d%%" % int(ceded * 100.0))
		else:
			text = tr("Cessar-fogo entre %s e %s: nenhuma área do tamanho negociado, as fronteiras não mudam.") % [gainer.name, loser.name]
	world.emit_news(text, "guerra", gainer)
	for i: int in w.a + w.d:
		var c: Country = world.countries[i]
		c.war_exhaustion *= 0.55
		c.aid_flow = 0.0
		if not in_war(i):
			c.mobilization *= 0.25
			c.stance_offensive = false
	var ids: Array = w.a + w.d
	for i: int in ids:
		for j: int in ids:
			if i < j:
				refresh_pair(i, j, world)
	world.global_risk = clampf(world.global_risk - 0.05, 0.0, 1.0)
	_sync_occupation(world)


func transfer(from: Country, to: Country, share: float, world: GameWorld) -> void:
	var to_pop0 := to.pop
	var to_cap0 := to.capital
	var pop := from.pop * share
	var cap := from.capital * share * 0.8
	from.pop -= pop
	from.capital -= from.capital * share
	to.capital += cap
	Demography.absorb(to, from, pop)
	to.pop += pop
	for i in 5:
		var moved := from.prod[i] * share
		from.prod[i] -= moved
		to.prod[i] += moved
		var used := from.use[i] * share
		from.use[i] -= used
		to.use[i] += used
	from.y_pot *= 1.0 - share
	from.y *= 1.0 - share
	from.y0 *= 1.0 - share
	var gdp_moved := from.y0 * share / maxf(1.0 - share, 0.01)
	var gain := (to.y0 + gdp_moved) / maxf(to.y0, 0.001)
	# A área nova produz o que já produzia: sem esse ajuste, a população anexada passaria a render com
	# a produtividade de quem ganhou, e um país rico que anexa um pobre quase dobraria o PIB do nada.
	var factors := pow(to.capital / maxf(to_cap0, 0.001), Economy.ALPHA) * pow(to.pop / maxf(to_pop0, 0.001), 1.0 - Economy.ALPHA)
	to.tfp *= gain / maxf(factors, 0.001)
	# A base de renda por habitante da convergência acompanha a média do país novo.
	to.pc0 *= gain / maxf(to.pop / maxf(to_pop0, 0.001), 0.001)
	# O PIB de quem ganha sobe aos poucos, com o capital e a população novos; o histórico já passa a
	# contar o território como se sempre tivesse sido dele.
	from.rebase_territory(1.0 - share)
	to.rebase_territory(gain)
	to.y0 += gdp_moved
	world.refresh_map = true


func annex(winner: Country, loser: Country, world: GameWorld) -> void:
	transfer(loser, winner, 0.92, world)
	winner.debt_loc += loser.debt_loc * 0.3
	loser.alive = false
	loser.annexed_by = winner.idx
	for w: Dictionary in wars.duplicate():
		if loser.idx in w.a:
			w.a.erase(loser.idx)
		if loser.idx in w.d:
			w.d.erase(loser.idx)
		if w.main_a == loser.idx or w.main_d == loser.idx:
			wars.erase(w)
	var to_erase := []
	for k: int in sanctions:
		if k / n == loser.idx or k % n == loser.idx:
			to_erase.append(k)
	for k: int in to_erase:
		sanctions.erase(k)
	for c: Country in world.countries:
		if c.client_of == loser.idx:
			c.client_of = -1
		if c.annexed_by == loser.idx:
			c.annexed_by = winner.idx
	# Anexação custa caro na reputação internacional.
	for c: Country in world.countries:
		if c.alive and c != winner:
			add_relation(c.idx, winner.idx, -10.0)
	world.global_risk = clampf(world.global_risk + 0.06, 0.0, 1.0)
	refresh_sanction_cache(world)
	world.refresh_map = true


func make_client(winner: Country, loser: Country, world: GameWorld) -> void:
	loser.client_of = winner.idx
	set_relation(winner.idx, loser.idx, 70.0)
	alliances[pair(winner.idx, loser.idx)] = true
	loser.stability = maxf(loser.stability - 0.1, 0.05)
	sanctions.erase(key(winner.idx, loser.idx))
	sanctions.erase(key(loser.idx, winner.idx))
	refresh_pair(winner.idx, loser.idx, world)
	world.refresh_map = true


func to_dict() -> Dictionary:
	return {
		"relations": relations, "rel_base": rel_base, "shares": shares, "factor": factor,
		"sanctions": sanctions, "tariffs": tariffs, "fta": fta, "alliances": alliances,
		"wars": wars, "next_war_id": next_war_id, "n": n,
	}


func from_dict(d: Dictionary) -> void:
	for k in d:
		set(k, d[k])
