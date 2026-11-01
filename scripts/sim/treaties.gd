class_name Treaties
extends RefCounted
## Tratados como na vida real: negociação, assinatura, ratificação em cada país, vigência por um prazo, e denúncia
## com aviso prévio. Só depois de ratificado por todos o tratado produz efeito.

const STATE_RATIFYING := "Em ratificação"
const STATE_FORCE := "Em vigor"
const STATE_DENOUNCED := "Denunciado"
const STATE_ENDED := "Encerrado"
const STATE_EXPIRED := "Expirado"
const STATE_REJECTED := "Não ratificado"
const STATE_BROKEN := "Rompido"
const NOTICE_MONTHS := 6
const PARTNER_RATIFY_MONTHS := [1, 3]

## need: quanto de boa vontade o outro lado exige. econ e social: onde o tratado cai na bússola, para os parlamentos
## e para o líder da outra parte. term: duração em anos, 0 para indefinido.
const TYPES := {
	"fta": {"label": "Livre comércio", "desc": "Elimina barreiras ao comércio entre as partes.", "need": 15.0, "econ": 0.6, "social": 0.3, "term": 0},
	"customs": {"label": "União aduaneira", "desc": "Livre comércio e tarifa comum. Exige muita confiança.", "need": 40.0, "econ": 0.3, "social": 0.2, "term": 0},
	"defense": {"label": "Defesa mútua", "desc": "Um ataque a uma parte é um ataque à outra.", "need": 55.0, "econ": 0.2, "social": -0.5, "term": 0},
	"nonaggression": {"label": "Não agressão", "desc": "As partes se comprometem a não atacar uma à outra. Romper tem preço alto.", "need": -10.0, "econ": 0.0, "social": 0.3, "term": 10},
	"arms": {"label": "Controle de armas", "desc": "Limita os gastos militares das duas partes e reduz a tensão.", "need": 5.0, "econ": -0.1, "social": 0.5, "term": 10},
	"climate": {"label": "Cooperação climática", "desc": "Metas comuns de emissões. Custa um pouco de produtividade e agrada o eleitor.", "need": 0.0, "econ": -0.5, "social": 0.5, "term": 15},
	"extradition": {"label": "Extradição", "desc": "Criminosos deixam de ter refúgio. Dá estabilidade às duas partes.", "need": 5.0, "econ": 0.0, "social": -0.3, "term": 0},
	"investment": {"label": "Proteção de investimentos", "desc": "Garantias para o capital estrangeiro, que passa a render mais.", "need": 10.0, "econ": 0.7, "social": 0.1, "term": 20},
}
## Tratados multilaterais que já existem, pelos blocos do cenário.
const FOUNDING := {
	"NATO": {"title": "Tratado do Atlântico Norte", "type": "defense"}, "EU": {"title": "Tratado da União Europeia", "type": "customs"},
	"USMCA": {"title": "Acordo Estados Unidos, México e Canadá", "type": "fta"}, "MERCO": {"title": "Tratado de Assunção (Mercosul)", "type": "customs"},
	"MERCOSUR": {"title": "Tratado de Assunção (Mercosul)", "type": "customs"}, "ASEAN": {"title": "Carta da ASEAN", "type": "fta"},
	"SCO": {"title": "Carta de Xangai", "type": "extradition"}, "AUKUS": {"title": "Pacto AUKUS", "type": "defense"},
}

var items: Array = []
var next_id := 1
## Busca rápida: a IA consulta tratados entre pares o tempo todo. Bilaterais por par e tipo; multilaterais à parte.
var _pairs := {}
var _multi: Array = []


func setup(world: GameWorld) -> void:
	var groups := {}
	for c: Country in world.countries:
		for bloc: String in c.blocs:
			if FOUNDING.has(bloc):
				groups.get_or_add(FOUNDING[bloc].title, {"type": FOUNDING[bloc].type, "parties": []}).parties.append(c.iso)
	for title: String in groups:
		if groups[title].parties.size() >= 2:
			_add(title, groups[title].type, groups[title].parties, STATE_FORCE, world, 0)


func _add(title: String, type: String, parties: Array, state: String, world: GameWorld, term: int) -> Dictionary:
	var t := {
		"id": next_id, "title": title, "type": type, "parties": parties, "state": state, "signed": world.date_string().get_slice("  ", 0),
		"term": term, "expires_month": world.months_elapsed + term * 12 if term > 0 else -1, "ratified": {}, "partner_due": -1, "ended_month": -1,
	}
	next_id += 1
	items.append(t)
	_index(t)
	return t


func _index(t: Dictionary) -> void:
	if t.parties.size() == 2:
		_pairs.get_or_add(_key(t.parties[0], t.parties[1], t.type), []).append(t)
	else:
		_multi.append(t)


static func _key(a: String, b: String, type: String) -> String:
	return "%s|%s|%s" % [a, b, type] if a < b else "%s|%s|%s" % [b, a, type]


func get_by_id(id: int) -> Dictionary:
	for t: Dictionary in items:
		if int(t.id) == id:
			return t
	return {}


func between(a: Country, b: Country, type: String, states := [STATE_RATIFYING, STATE_FORCE, STATE_DENOUNCED]) -> Dictionary:
	for t: Dictionary in _pairs.get(_key(a.iso, b.iso, type), []):
		if t.state in states:
			return t
	for t: Dictionary in _multi:
		if t.type == type and t.state in states and a.iso in t.parties and b.iso in t.parties:
			return t
	return {}


func of_country(iso: String) -> Array:
	return items.filter(func(t): return iso in t.parties)


## O quanto esse líder gosta do tipo de tratado, pelas ideias dele. Vale para IA e para o jogador recebendo propostas.
static func leader_bias(type: String, leader: Dictionary) -> float:
	var def: Dictionary = TYPES[type]
	return (float(leader.get("econ", 0.0)) * float(def.econ) + float(leader.get("social", 0.0)) * float(def.social)) * 25.0


## O lado de lá aceita? Pesam a relação, a afinidade entre a bússola dele e a de quem propõe, e o gosto pelo tipo.
func goodwill(world: GameWorld, proposer: Dictionary, target: Country, type: String, from: Country) -> float:
	var theirs: Dictionary = world.politics.leader_of(target.iso)
	var rel: float = world.diplomacy.relation(from.idx, target.idx)
	var affinity := 0.5
	if not proposer.is_empty() and not theirs.is_empty():
		affinity = clampf(1.0 - Politics.distance(proposer, theirs) / 2.8, 0.0, 1.0)
	return rel + (affinity - 0.5) * 30.0 + leader_bias(type, theirs)


## O jogador propõe. Aceito, o tratado é assinado e vai à ratificação nos dois países.
func propose(world: GameWorld, target: Country, type: String) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": "Na oposição, você não negocia em nome do país."}
	if target == world.player or not target.alive:
		return {"ok": false, "msg": "Não há com quem negociar."}
	if not TYPES.has(type):
		return {"ok": false, "msg": "Tipo de tratado desconhecido."}
	if not between(world.player, target, type).is_empty():
		return {"ok": false, "msg": "Já existe um tratado desse tipo com %s." % target.name}
	var def: Dictionary = TYPES[type]
	var score := goodwill(world, world.politics.player_party(world), target, type, world.player)
	if world.diplomacy.at_war(world.player.idx, target.idx):
		score -= 200.0
	score += (world.politics.minister_competence(world, "foreign") - 0.5) * 20.0 + world.rng.randf_range(-5.0, 5.0)
	if score < float(def.need):
		return {"ok": true, "accepted": false, "msg": "%s recusou negociar: %s." % [target.name, "falta confiança" if world.diplomacy.relation(world.player.idx, target.idx) < float(def.need) else "as ideias do governo de lá são outras"]}
	return sign_with_player(world, target, type)


## Assinatura com o jogador: o tratado só vale depois do parlamento dos dois lados.
func sign_with_player(world: GameWorld, target: Country, type: String) -> Dictionary:
	var def: Dictionary = TYPES[type]
	var title := "Tratado de %s entre %s e %s" % [String(def.label).to_lower(), world.player.name, target.name]
	var t := _add(title, type, [world.player.iso, target.iso], STATE_RATIFYING, world, int(def.term))
	t.partner_due = world.months_elapsed + world.rng.randi_range(PARTNER_RATIFY_MONTHS[0], PARTNER_RATIFY_MONTHS[1])
	world.emit_news("%s e %s assinam: %s. Falta ratificar." % [world.player.name, target.name, def.label], "diplomacia", target)
	if world.player.dem >= Politics.FREE_PARLIAMENT_DEM:
		world.legislation.present_payload(world, {"kind": "treaty", "treaty": t.id}, "Ratificação: %s" % title, String(def.desc), {"econ": def.econ, "social": def.social})
	else:
		t.ratified[world.player.iso] = true
	return {"ok": true, "accepted": true, "treaty": t, "msg": "Assinado. Agora precisa ser ratificado pelos parlamentos."}


## Parlamento do jogador decidiu.
func on_player_ratification(world: GameWorld, id: int, approved: bool) -> void:
	var t := get_by_id(id)
	if t.is_empty() or t.state != STATE_RATIFYING:
		return
	if not approved:
		t.state = STATE_REJECTED
		for iso: String in t.parties:
			if iso != world.player.iso:
				var other: Country = world.by_iso[iso]
				world.diplomacy.add_relation(world.player.idx, other.idx, -8.0)
		world.emit_news("O parlamento rejeita: %s." % t.title, "diplomacia", world.player)
		return
	t.ratified[world.player.iso] = true
	_check_force(world, t)


func _check_force(world: GameWorld, t: Dictionary) -> void:
	for iso: String in t.parties:
		if not t.ratified.has(iso):
			return
	t.state = STATE_FORCE
	if int(t.term) > 0:
		t.expires_month = world.months_elapsed + int(t.term) * 12
	_apply(world, t, true)
	if world.player and world.player.iso in t.parties:
		world.emit_news("Entra em vigor: %s." % t.title, "diplomacia", world.player)


## Dois governos da IA fecham um tratado direto: ratificação sem drama, salvo se o parlamento de lá recusar.
func ai_sign(world: GameWorld, a: Country, b: Country, type: String) -> bool:
	if not between(a, b, type).is_empty():
		return false
	var def: Dictionary = TYPES[type]
	for c: Country in [a, b]:
		if c != world.player and not _parliament_accepts(world, c, def):
			return false
	var t := _add("Tratado de %s entre %s e %s" % [String(def.label).to_lower(), a.name, b.name], type, [a.iso, b.iso], STATE_FORCE, world, int(def.term))
	_apply(world, t, true)
	return true


func _parliament_accepts(world: GameWorld, c: Country, def: Dictionary) -> bool:
	if c.dem < Politics.FREE_PARLIAMENT_DEM:
		return true
	var data: Dictionary = world.politics.data_of(c.iso)
	var yes := 0
	for p: Dictionary in data.get("parties", []):
		var limit: float = Politics.COALITION_REBEL_DISTANCE if p.id in data.coalition else Politics.OPPOSITION_SUPPORT_DISTANCE
		if Politics.distance(p, def) <= limit:
			yes += int(p.seats)
	return yes * 2 > int(data.get("seats_total", 1))


## Liga ou desliga o que o tratado faz entre cada par de partes.
func _apply(world: GameWorld, t: Dictionary, on: bool) -> void:
	var d := world.diplomacy
	var parties: Array = t.parties
	for i in parties.size():
		var a: Country = world.by_iso.get(parties[i])
		if a == null or not a.alive:
			continue
		for j in range(i + 1, parties.size()):
			var b: Country = world.by_iso.get(parties[j])
			if b == null or not b.alive:
				continue
			match t.type:
				"fta", "customs":
					if on:
						d.sign_fta(a, b, world)
					else:
						d.fta.erase(d.pair(a.idx, b.idx))
						d.refresh_pair(a.idx, b.idx, world)
				"defense":
					if on:
						d.sign_alliance(a, b, world)
					else:
						d.break_alliance(a, b, world)
				_:
					if on:
						d.add_relation(a.idx, b.idx, 6.0)


## Efeitos contínuos e calendário: ratificação da outra parte, fim do aviso prévio e fim do prazo.
func step_month(world: GameWorld) -> void:
	for t: Dictionary in items:
		if t.state in [STATE_ENDED, STATE_EXPIRED, STATE_REJECTED, STATE_BROKEN]:
			continue
		match t.state:
			STATE_RATIFYING:
				if int(t.partner_due) >= 0 and world.months_elapsed >= int(t.partner_due):
					t.partner_due = -1
					_partner_decides(world, t)
			STATE_DENOUNCED:
				if world.months_elapsed >= int(t.ended_month):
					t.state = STATE_ENDED
					_apply(world, t, false)
					if world.player and world.player.iso in t.parties:
						world.emit_news("Deixa de valer: %s." % t.title, "diplomacia", world.player)
			STATE_FORCE:
				if int(t.expires_month) >= 0 and world.months_elapsed >= int(t.expires_month):
					t.state = STATE_EXPIRED
					_apply(world, t, false)
					if world.player and world.player.iso in t.parties:
						world.emit_news("Venceu o prazo: %s." % t.title, "diplomacia", world.player)
				else:
					_monthly_effect(world, t)


func _partner_decides(world: GameWorld, t: Dictionary) -> void:
	var def: Dictionary = TYPES[t.type]
	for iso: String in t.parties:
		if t.ratified.has(iso) or (world.player and iso == world.player.iso):
			continue
		var c: Country = world.by_iso[iso]
		if not _parliament_accepts(world, c, def):
			t.state = STATE_REJECTED
			world.emit_news("O parlamento de %s rejeita: %s." % [c.name, t.title], "diplomacia", c)
			return
		t.ratified[iso] = true
	_check_force(world, t)


func _monthly_effect(world: GameWorld, t: Dictionary) -> void:
	for iso: String in t.parties:
		var c: Country = world.by_iso.get(iso)
		if c == null or not c.alive:
			continue
		match t.type:
			"arms":
				c.sp_defense = maxf(c.sp_defense * 0.999, float(c.sp0.get("defense", c.sp_defense)) * 0.7)
				c.stability = minf(c.stability + 0.0003, 0.97)
			"climate":
				c.tfp *= 0.99998
				c.approval = minf(c.approval + 0.0003, 0.95)
			"extradition":
				c.stability = minf(c.stability + 0.0002, 0.97)
			"investment":
				c.capital *= 1.00015


## Sair de um tratado: vale depois do aviso prévio, e a outra parte não gosta.
func denounce(world: GameWorld, id: int) -> Dictionary:
	var t := get_by_id(id)
	var pl := world.player
	if t.is_empty() or t.state != STATE_FORCE or not pl.iso in t.parties:
		return {"ok": false, "msg": "Esse tratado não está em vigor para o seu país."}
	if not world.in_office:
		return {"ok": false, "msg": "Na oposição, você não denuncia tratados."}
	for iso: String in t.parties:
		if iso != pl.iso:
			world.diplomacy.add_relation(pl.idx, world.by_iso[iso].idx, -10.0)
	if t.parties.size() > 2:
		# Multilateral: sai só quem denunciou; os outros seguem. Não há efeito para eles.
		_leave(world, t, pl)
		return {"ok": true, "msg": "Seu país deixa: %s." % t.title}
	t.state = STATE_DENOUNCED
	t.ended_month = world.months_elapsed + NOTICE_MONTHS
	world.emit_news("%s denuncia: %s. Deixa de valer em %d meses." % [pl.name, t.title, NOTICE_MONTHS], "diplomacia", pl)
	return {"ok": true, "msg": "Denúncia registrada. O tratado deixa de valer em %d meses." % NOTICE_MONTHS}


func _leave(world: GameWorld, t: Dictionary, c: Country) -> void:
	for iso: String in t.parties:
		if iso != c.iso and t.type == "defense":
			var other: Country = world.by_iso[iso]
			if world.diplomacy.allied(c.idx, other.idx):
				world.diplomacy.break_alliance(c, other, world)
	t.parties = t.parties.filter(func(x): return x != c.iso)
	world.emit_news("%s deixa: %s." % [c.name, t.title], "diplomacia", c)


## Guerra entre partes rompe o que havia. Atacar quem assinou não agressão pesa no mundo inteiro.
func on_war(world: GameWorld, att: Country, def: Country) -> void:
	for t: Dictionary in items:
		if t.state in [STATE_FORCE, STATE_RATIFYING, STATE_DENOUNCED] and att.iso in t.parties and def.iso in t.parties and t.parties.size() == 2:
			if t.type == "nonaggression":
				att.approval = maxf(att.approval - 0.03, 0.02)
				world.emit_news("%s rasga o tratado de não agressão com %s." % [att.name, def.name], "crise", att)
				for other: Country in world.countries:
					if other != att and other != def and other.alive:
						world.diplomacy.add_relation(other.idx, att.idx, -2.0)
			_apply(world, t, false)
			t.state = STATE_BROKEN


func blocks_war(att: Country, def: Country) -> bool:
	return not between(att, def, "nonaggression", [STATE_FORCE]).is_empty()


func to_dict() -> Dictionary:
	return {"items": items, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	items = d.get("items", [])
	next_id = d.get("next_id", 1)
	for t: Dictionary in items:
		_index(t)
