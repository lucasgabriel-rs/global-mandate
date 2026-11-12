class_name PartyTalk
extends RefCounted
## Conversa do jogador com o líder de um partido do parlamento para pedir que apoie ou vote contra uma lei
## em tramitação. A decisão fica em Legislation.chat_request; aqui ficam os contatos, as falas e as respostas.

const MAX_LAWS := 4


## Partidos com cadeiras, exceto o do jogador, do maior para o menor.
static func contacts(world: GameWorld) -> Array:
	var data: Dictionary = world.politics.data_of(world.legislation.iso)
	var out: Array = data.get("parties", []).filter(func(p): return int(p.seats) > 0 and int(p.id) != int(data.player_party))
	out.sort_custom(func(a, b): return int(a.seats) > int(b.seats))
	return out


## Contato com que abrir a janela de conversas ao falar de uma lei: o maior partido fora o do jogador.
static func first_key(world: GameWorld) -> String:
	var list := contacts(world)
	return ChatLog.party_key(int(list[0].id)) if not list.is_empty() else ""


static func leader_of(party: Dictionary) -> Dictionary:
	for m: Dictionary in party.get("members", []):
		if not m.get("player", false):
			return m
	return {}


static func party_by_id(world: GameWorld, id: int) -> Dictionary:
	return world.politics.party_of(world.legislation.iso, id)


## Leis em tramitação que ainda passam por votação, as mais recentes primeiro.
static func open_laws(world: GameWorld) -> Array:
	var leg: Legislation = world.legislation
	var list: Array = leg.in_process().filter(func(n): return leg.can_negotiate(n))
	return list.slice(0, MAX_LAWS)


static func norm_by_id(world: GameWorld, id: int) -> Dictionary:
	return world.legislation.norms.get(id, world.legislation.norms.get(str(id), {}))


static func tags(world: GameWorld, party: Dictionary) -> String:
	var data: Dictionary = world.politics.data_of(world.legislation.iso)
	var role: String = TranslationServer.translate("governo") if int(party.id) in data.coalition else TranslationServer.translate("oposição")
	return "%s  ·  %d %s  ·  %s" % [party.name, int(party.seats), TranslationServer.translate("assentos"), role]


static func greeting(world: GameWorld, party: Dictionary) -> String:
	var mine: Dictionary = world.politics.player_party(world)
	var aff := clampf(1.0 - Politics.distance(party, mine) / 2.8, 0.0, 1.0)
	if aff >= 0.7:
		return TranslationServer.translate("Fala, colega. Em que o partido pode ajudar?")
	if aff <= 0.3:
		return TranslationServer.translate("Sabemos que pensamos diferente. Diga o que quer.")
	return TranslationServer.translate("Pois não. Qual lei você quer discutir?")


## Falas disponíveis agora. Cada uma: {id, label, hint}. id: "ask_yes:N", "ask_no:N" ou "sound:N".
static func options(world: GameWorld, party: Dictionary) -> Array:
	var leg: Legislation = world.legislation
	var out := []
	for norm: Dictionary in open_laws(world):
		var title: String = TranslationServer.translate(norm.title)
		var nid: int = int(norm.id)
		out.append({"id": "sound:%d" % nid, "norm": nid, "label": TranslationServer.translate("O que o partido acha de «%s»?") % title, "hint": TranslationServer.translate("Sonda a posição do partido. Não conta como pedido.")})
		if leg.chat_closed(norm, int(party.id)):
			continue
		out.append({"id": "ask_yes:%d" % nid, "norm": nid, "label": TranslationServer.translate("Peço que vocês apoiem «%s».") % title, "hint": TranslationServer.translate("Cada partido responde uma vez por lei. Vale como acordo de voto.")})
		out.append({"id": "ask_no:%d" % nid, "norm": nid, "label": TranslationServer.translate("Peço que vocês votem contra «%s».") % title, "hint": TranslationServer.translate("Cada partido responde uma vez por lei. Vale como acordo de voto.")})
	out.append_array(extra_offers(world, party))
	return out


## PONTO DE EXTENSÃO: falas extras com contrapartida (cargos, favores, verba do partido). A sessão que
## cuidar do orçamento partidário devolve aqui as falas e trata o id em choose_extra.
static func extra_offers(_world: GameWorld, _party: Dictionary) -> Array:
	return []


static func choose_extra(_world: GameWorld, _party: Dictionary, _id: String) -> Dictionary:
	return {"ok": false, "accepted": false, "reply": TranslationServer.translate("Não entendi o que você quis dizer.")}


## Aplica a fala. Devolve {ok, accepted, reply}. O histórico da conversa também é atualizado.
static func say(world: GameWorld, party: Dictionary, id: String) -> Dictionary:
	var key := ChatLog.party_key(int(party.id))
	var label := ""
	for o: Dictionary in options(world, party):
		if o.id == id:
			label = o.label
	if label == "":
		return {"ok": false, "accepted": false, "reply": TranslationServer.translate("Não entendi o que você quis dizer.")}
	ChatLog.add(world, key, true, label)
	var r := choose(world, party, id)
	ChatLog.add(world, key, false, r.reply, r.accepted if r.get("ok", false) and not id.begins_with("sound:") else null)
	return r


static func choose(world: GameWorld, party: Dictionary, id: String) -> Dictionary:
	var leg: Legislation = world.legislation
	var parts := id.split(":")
	if parts.size() != 2:
		return choose_extra(world, party, id)
	var norm := norm_by_id(world, int(parts[1]))
	if norm.is_empty():
		return {"ok": false, "accepted": false, "reply": TranslationServer.translate("Essa lei não está mais em votação.")}
	var title: String = TranslationServer.translate(norm.title)
	match parts[0]:
		"sound":
			var deals: Dictionary = norm.get("deals", {})
			if deals.has(str(party.id)):
				return {"ok": true, "accepted": true, "reply": TranslationServer.translate("Já combinamos: vamos votar %s «%s».") % [TranslationServer.translate("a favor") if deals[str(party.id)] else TranslationServer.translate("contra"), title]}
			var yes := leg.chat_stance(world, norm, party)
			var pop := leg.popularity_of(world, norm)
			var line: String = TranslationServer.translate("Hoje votaríamos a favor de «%s».") % title if yes else TranslationServer.translate("Hoje votaríamos contra «%s».") % title
			line += TranslationServer.translate(" A lei agrada o eleitor.") if pop >= 0.6 else (TranslationServer.translate(" A lei é impopular.") if pop <= 0.4 else "")
			return {"ok": true, "accepted": yes, "reply": line}
		"ask_yes", "ask_no":
			var want_yes: bool = parts[0] == "ask_yes"
			var r := leg.chat_request(world, norm, int(party.id), want_yes)
			if not r.ok:
				return {"ok": false, "accepted": false, "reply": r.msg}
			return {"ok": true, "accepted": r.accepted, "reply": _answer(r, want_yes, title)}
	return choose_extra(world, party, id)


## Resposta falada: o motivo é o fator que mais pesou.
static func _answer(r: Dictionary, want_yes: bool, title: String) -> String:
	var aff: float = r.aff
	var pop: float = r.pop
	var gap: float = r.gap
	if r.accepted:
		if r.aligned:
			return TranslationServer.translate("Já era nossa ideia. Conte com os nossos votos %s «%s».") % [TranslationServer.translate("a favor de") if want_yes else TranslationServer.translate("contra"), title]
		if aff >= 0.65:
			return TranslationServer.translate("Por você, fechamos %s «%s». Mas fica o favor.") % [TranslationServer.translate("a favor de") if want_yes else TranslationServer.translate("contra"), title]
		return TranslationServer.translate("Não é o que defendemos, mas vamos votar %s «%s» desta vez.") % [TranslationServer.translate("a favor de") if want_yes else TranslationServer.translate("contra"), title]
	if want_yes:
		if gap >= 1.0:
			return TranslationServer.translate("«%s» vai contra tudo o que defendemos. Não contem conosco.") % title
		if pop <= 0.4:
			return TranslationServer.translate("«%s» é impopular com o nosso eleitor. Não vamos pagar essa conta.") % title
		return TranslationServer.translate("Ainda não estamos convencidos sobre «%s». A resposta é não.") % title
	if pop >= 0.6:
		return TranslationServer.translate("«%s» é popular. Votar contra custaria caro ao partido.") % title
	if aff <= 0.35:
		return TranslationServer.translate("Não vamos ajudar o seu partido a barrar «%s».") % title
	return TranslationServer.translate("Votar contra «%s» não combina com o que defendemos.") % title
