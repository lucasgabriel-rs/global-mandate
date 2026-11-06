class_name NationAI
extends RefCounted
## Comportamento das nações não controladas pelo jogador. Cada governo age todo mês conforme a bússola do
## líder: à esquerda gasta e tributa mais, à direita corta e abre o comércio; o autoritário arma o país,
## briga mais e governa por decreto; o libertário investe em educação e prefere acordos.

const BASE_ACTIVITY := 0.2
const IDEOLOGY_RATE := 0.012
const DECREE_CHANCE := 0.06
const PARTNER_DRAWS := 5
const INITIATIVE_SHARE := 0.25
## Só vira notícia o que envolve o jogador ou economias que somam ao menos esta parte do PIB mundial.
const NEWS_SHARE := 0.012


static func step_month(c: Country, world: GameWorld) -> void:
	if not c.alive or c == world.governed():
		return
	_fiscal(c, world)
	_defense(c, world)
	_relation_drift(c, world)
	var mind := _mind(c, world)
	_ideology_drift(c, mind)
	_central_bank(c, world, mind)
	if c.dem < Politics.FREE_PARLIAMENT_DEM and world.rng.randf() < DECREE_CHANCE:
		_decree(c, world, mind)
	if world.rng.randf() < _activity(c, world):
		_foreign_agenda(c, world, mind)
	if world.rng.randf() < _activity(c, world) * INITIATIVE_SHARE:
		_initiative(c, world, mind)
	if world.rng.randf() < 1.0 / 6.0:
		_foreign_policy(c, world)


## econ: -1 esquerda a +1 direita. social: -1 autoritário a +1 libertário. hawk: disposição para o conflito.
static func _mind(c: Country, world: GameWorld) -> Dictionary:
	var leader: Dictionary = world.politics.leader_of(c.iso)
	var econ := float(leader.get("econ", 0.0))
	var social := float(leader.get("social", 0.0))
	return {"econ": econ, "social": social, "hawk": clampf(0.3 - social * 0.5 + (0.15 if c.dem < 4.0 else 0.0), 0.0, 1.0)}


## Economias maiores têm mais interesses pelo mundo e agem com mais frequência.
static func _activity(c: Country, world: GameWorld) -> float:
	return clampf(BASE_ACTIVITY + sqrt(c.y_usd() / maxf(world.world_gdp(), 1.0)) * 1.2, 0.0, 0.8)


## Devagar, o orçamento vai para onde as ideias do líder apontam. O ajuste fiscal cuida do que sobrar.
static func _ideology_drift(c: Country, mind: Dictionary) -> void:
	var rate := IDEOLOGY_RATE
	var econ: float = mind.econ
	var social: float = mind.social
	c.sp_social += (float(c.sp0.get("social", c.sp_social)) * (1.0 - econ * 0.35) - c.sp_social) * rate
	c.sp_education += (float(c.sp0.get("education", c.sp_education)) * (1.0 + social * 0.25) - c.sp_education) * rate
	c.sp_health += (float(c.sp0.get("health", c.sp_health)) * (1.0 - econ * 0.2) - c.sp_health) * rate
	c.tariff += (clampf(0.04 - econ * 0.05 - social * 0.03, 0.0, 0.25) - c.tariff) * rate * 0.5


## Só quem manda no banco central mexe no juro: um líder de esquerda ou impopular segura a taxa por um tempo,
## abaixo do que a inflação pediria, e a credibilidade cobra o preço. Banco independente nunca passa por aqui.
static func _central_bank(c: Country, world: GameWorld, mind: Dictionary) -> void:
	if c.cb_independent or c.peg != 0:
		c.rate_manual = false
		return
	if c.rate_manual:
		c.rate_set = maxf(c.pi_yoy + c.r_n - 0.01, 0.0)
		c.cred = maxf(c.cred - 0.003, 0.05)
		if world.rng.randf() < 0.08:
			c.rate_manual = false
	elif (float(mind.econ) < -0.2 or c.approval < 0.35) and world.rng.randf() < 0.03:
		c.rate_manual = true
		c.rate_set = maxf(c.pi_yoy + c.r_n - 0.01, 0.0)
		if NationAI._notable(c, null, world):
			world.emit_news(TranslationServer.translate("O governo de %s pressiona o banco central e segura os juros.") % c.name, "economia", c)


## Sem parlamento livre, o líder muda as regras sozinho.
static func _decree(c: Country, world: GameWorld, mind: Dictionary) -> void:
	var text := ""
	var pick := world.rng.randf()
	if float(mind.hawk) > 0.45 and pick < 0.5:
		c.sp_defense = minf(c.sp_defense * 1.08, 0.2)
		c.stability = minf(c.stability + 0.01, 0.97)
		text = TranslationServer.translate("%s reforça as forças armadas por decreto.")
	elif float(mind.econ) < 0.0:
		c.sp_social = minf(c.sp_social * 1.05, 0.3)
		c.approval = minf(c.approval + 0.01, 0.95)
		text = TranslationServer.translate("%s amplia subsídios à população por decreto.")
	else:
		c.tax_corporate = maxf(c.tax_corporate * 0.95, 0.005)
		text = TranslationServer.translate("%s corta impostos de empresas por decreto.")
	if _notable(c, null, world):
		world.emit_news(text % c.name, "politica", c)


static func _notable(a: Country, b: Variant, world: GameWorld) -> bool:
	if b != null and (a == world.player or b == world.player):
		return true
	var size := a.y_usd() + (float(b.y_usd()) if b != null else 0.0)
	return size > world.world_gdp() * NEWS_SHARE


## 0 com ideias opostas e 1 com ideias iguais.
static func _affinity(mind: Dictionary, o: Country, world: GameWorld) -> float:
	var other: Dictionary = world.politics.leader_of(o.iso)
	var gap := Vector2(float(mind.econ) - float(other.get("econ", 0.0)), float(mind.social) - float(other.get("social", 0.0))).length()
	return clampf(1.0 - gap / 2.0, 0.0, 1.0)


## Escolhe com quem lidar: de alguns países sorteados, o que mais desperta amizade ou rivalidade.
static func _pick_partner(c: Country, world: GameWorld, mind: Dictionary) -> Country:
	var d := world.diplomacy
	var best: Country = null
	var best_weight := -1.0
	for k in PARTNER_DRAWS:
		var o: Country = world.countries[world.rng.randi_range(0, d.n - 1)]
		if o == c or not o.alive:
			continue
		var near := 1.5 if c.center.distance_to(o.center) < 520.0 else 0.6
		var weight := (absf(d.relation(c.idx, o.idx)) / 100.0 + absf(_affinity(mind, o, world) - 0.5) + 0.1) * near * sqrt(maxf(o.y_usd(), 1.0))
		if weight > best_weight:
			best_weight = weight
			best = o
	return best


static func _foreign_agenda(c: Country, world: GameWorld, mind: Dictionary) -> void:
	var o := _pick_partner(c, world, mind)
	if o == null:
		return
	var d := world.diplomacy
	var player := world.governed()
	var rng := world.rng
	var affinity := _affinity(mind, o, world)
	var rel := d.relation(c.idx, o.idx)
	# A distância entre as ideias pesa aos poucos na relação.
	d.add_relation(c.idx, o.idx, (affinity - 0.5) * 3.0)
	var level := d.sanction_level(c.idx, o.idx)
	if level > 0 and rel > -15.0:
		d.set_sanction(c, o, 0, world)
		_say(c, o, world, TranslationServer.translate("%s suspende as sanções contra %s."), "diplomacia")
	elif rel > 55.0 and affinity > 0.55 and not d.allied(c.idx, o.idx) and o != player and rng.randf() < 0.25:
		world.treaties.ai_sign(world, c, o, "defense")
	elif rel > 20.0 and affinity > 0.35 and float(mind.econ) > -0.5 and not d.has_fta(c.idx, o.idx, world) and o != player and rng.randf() < 0.3:
		if world.treaties.ai_sign(world, c, o, "fta"):
			_say(c, o, world, TranslationServer.translate("%s e %s fecham acordo de livre comércio."), "diplomacia")
	elif rel > 5.0 or affinity > 0.65:
		d.add_relation(c.idx, o.idx, rng.randf_range(2.0, 5.0))
		if rng.randf() < 0.15:
			_say(c, o, world, TranslationServer.translate("%s recebe uma missão de %s e estreita os laços."), "diplomacia", true)
	elif rel < -45.0 and level == 0 and c.y_usd() > 40.0 and not d.at_war(c.idx, o.idx) and rng.randf() < 0.3 + float(mind.hawk) * 0.4:
		d.set_sanction(c, o, 2 if rel < -70.0 else 1, world)
		_say(c, o, world, TranslationServer.translate("%s impõe sanções a %s."), "crise" if o == player else "diplomacia")
	elif rel < -15.0 and float(mind.econ) < 0.2 and rng.randf() < 0.2 and not d.tariffs.has(d.key(c.idx, o.idx)):
		d.set_tariff_on(c, o, 0.15, world)
		_say(c, o, world, TranslationServer.translate("%s impõe tarifa de 15%% aos produtos de %s."), "economia")
	elif rel < 0.0 or affinity < 0.35:
		d.add_relation(c.idx, o.idx, -rng.randf_range(2.0, 4.0 + float(mind.hawk) * 6.0))
		if rng.randf() < 0.4:
			_say(c, o, world, TranslationServer.translate("%s critica publicamente o governo de %s."), "diplomacia")


## O líder decide procurar outro líder por conta própria: outro governo da IA, ou o jogador.
static func _initiative(c: Country, world: GameWorld, mind: Dictionary) -> void:
	var o := _pick_partner(c, world, mind)
	if o == null:
		return
	if o == world.governed():
		world.request_talk(c)
	elif o != world.player:
		Dialogue.summit(world, c, o)


static func _say(a: Country, b: Country, world: GameWorld, text: String, kind: String, flip := false) -> void:
	if _notable(a, b, world):
		world.emit_news(text % ([b.name, a.name] if flip else [a.name, b.name]), kind, a)


static func _fiscal(c: Country, world: GameWorld) -> void:
	var yn := maxf(c.y_nominal(), 0.001)
	var def_ratio := c.deficit / yn
	var pressure := c.debt_ratio / c.debt_tol
	# Déficit que estabiliza a dívida, mais margem anticíclica.
	var nominal_g := c.g0 + minf(c.pi_target, 0.05)
	var target := nominal_g * minf(c.debt_ratio, c.debt_tol) - 0.45 * c.gap
	if pressure > 1.05 or c.risk > c.risk0 + 0.012:
		target -= 0.015 + 0.02 * maxf(pressure - 1.05, 0.0)
	# Superávit de quem vive de commodities é gasto devagar.
	var err := def_ratio - target
	var step := clampf(err * 0.04, -0.0012, 0.0015 if err < 0.06 else 0.004)
	if world.year_float() < c.default_until:
		step = maxf(step, 0.0008)
	if absf(step) < 0.00005:
		return
	var total := c.sp_social + c.sp_health + c.sp_education + c.sp_infra + c.sp_admin
	if total <= 0.02 and step > 0.0:
		return
	# Ajuste é 2/3 no gasto e 1/3 em tributos.
	var cut := step * 0.67 / maxf(total, 0.01)
	c.sp_social = maxf(c.sp_social * (1.0 - cut), 0.005)
	c.sp_health = maxf(c.sp_health * (1.0 - cut), 0.003)
	c.sp_education = maxf(c.sp_education * (1.0 - cut), 0.003)
	c.sp_infra = maxf(c.sp_infra * (1.0 - cut * 1.2), 0.002)
	c.sp_admin = maxf(c.sp_admin * (1.0 - cut), 0.003)
	var tax_step := step * 0.33 / maxf(c.tax_total(), 0.01)
	c.tax_income *= 1.0 + tax_step
	c.tax_consumption *= 1.0 + tax_step
	c.tax_corporate *= 1.0 + tax_step


static func _defense(c: Country, world: GameWorld) -> void:
	var yusd := c.y_usd()
	# Estoque de equipamento acompanha o gasto, em parte corrigido por PPC.
	var ppp := clampf(pow(60000.0 / maxf(c.gdp_pc(), 500.0), 0.35), 1.0, 3.0)
	c.mil_stock += (c.sp_defense * yusd * ppp * 0.35 - 0.06 * c.mil_stock) / 12.0
	c.troops += (c.troops0 * (1.0 + c.mobilization) - c.troops) * 0.03
	var base: float = float(c.sp0.get("defense", 0.02)) * (1.0 - clampf(float(world.politics.leader_of(c.iso).get("social", 0.0)), -1.0, 1.0) * 0.4)
	var target := base
	if world.diplomacy.in_war(c.idx):
		target = maxf(base * 1.25, 0.05) if base < 0.1 else base
		c.mobilization = minf(c.mobilization + 0.015, 0.8)
	else:
		c.war_exhaustion = maxf(c.war_exhaustion - 0.012, 0.0)
		c.mobilization = maxf(c.mobilization - 0.02, 0.0)
		if world.global_tension > 0.55 and c.dem >= 6.0:
			target = base * 1.2
	c.sp_defense += (target - c.sp_defense) * 0.03


static func _relation_drift(c: Country, world: GameWorld) -> void:
	# Só alguns pares por mês: relações voltam devagar ao nível estrutural.
	var d := world.diplomacy
	for k in 4:
		var j := world.rng.randi_range(0, d.n - 1)
		if j == c.idx or d.at_war(c.idx, j):
			continue
		var cur := d.relation(c.idx, j)
		d.set_relation(c.idx, j, cur + (d.rel_base[c.idx * d.n + j] - cur) * 0.02)


static func _foreign_policy(c: Country, world: GameWorld) -> void:
	var d := world.diplomacy
	var cs := world.countries
	var j := world.rng.randi_range(0, d.n - 1)
	var o: Country = cs[j]
	if o == c or not o.alive:
		return
	var rel := d.relation(c.idx, j)
	# Acordos entre amigos.
	if rel > 25.0 and not d.has_fta(c.idx, j, world) and world.rng.randf() < 0.05 and o != world.governed():
		world.treaties.ai_sign(world, c, o, "fta")
		if c.y_usd() + o.y_usd() > world.world_gdp() * 0.03:
			world.emit_news(TranslationServer.translate("%s e %s fecham acordo de livre comércio.") % [c.name, o.name], "diplomacia", c)
	# Oferta ao jogador.
	var player := world.governed()
	if player and c != player:
		var pr := d.relation(c.idx, player.idx)
		if pr > 30.0 and not d.has_fta(c.idx, player.idx, world) and world.rng.randf() < 0.05:
			world.offer_fta(c)
		elif pr > 60.0 and not d.allied(c.idx, player.idx) and world.rng.randf() < 0.03:
			world.offer_alliance(c)
		elif pr < -45.0 and world.rng.randf() < 0.02:
			world.receive_threat(c)
	_maybe_war(c, world)


static func _maybe_war(c: Country, world: GameWorld) -> void:
	var d := world.diplomacy
	if d.in_war(c.idx) or c.stability < 0.2 or c.war_exhaustion > 0.3 or c.troops < 5.0:
		return
	if world.year_float() < world.start_year + 0.5:
		return
	var hawk: float = _mind(c, world).hawk
	var best: Country = null
	var best_score := 0.0
	for o: Country in world.countries:
		if o == c or not o.alive or d.allied(c.idx, o.idx) or o.client_of == c.idx or o.troops0 <= 1.0:
			continue
		if c.center.distance_to(o.center) > 520.0:
			continue
		var rel := d.relation(c.idx, o.idx)
		if rel > -55.0 + hawk * 20.0:
			continue
		# Tratado de não agressão segura quase todo mundo; só os mais belicosos ousam rasgar.
		if hawk < 0.7 and world.treaties.blocks_war(c, o):
			continue
		# Dissuasão: alianças e armas nucleares pesam na conta.
		var defenders := o.military_power()
		var nuclear_block := o.nukes > 0
		for a: Country in world.countries:
			if a != o and a.alive and d.allied(a.idx, o.idx):
				defenders += a.military_power() * 0.45
				nuclear_block = nuclear_block or a.nukes > 200
		if nuclear_block and not (c.nukes > 200 and rel < -75.0):
			continue
		var ratio := c.military_power() / maxf(defenders, 0.01)
		if ratio < 1.8 - hawk * 0.5:
			continue
		var score := ratio * -rel / 100.0
		if score > best_score:
			best_score = score
			best = o
	if best == null:
		return
	var chance := c.aggression * (0.15 + hawk) * clampf(best_score / 3.0, 0.3, 1.5)
	if world.rng.randf() < chance:
		d.declare_war(c, best, world)
