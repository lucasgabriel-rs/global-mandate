class_name Proposals
extends RefCounted
## Concrete proposal that a foreign leader brings to the player when starting a conversation: treaty, peace, ultimatum,
## request for help or offer. The player accepts, refuses or counterproposes, and each answer really moves the game.
## The proposal stays in world.offers[iso] until it is answered or expires.

const KINDS := ["treaty", "peace", "threat", "request", "offer"]
const EXPIRE_MONTHS := 6
const POOR_RATIO := 0.5
const TRADE_ALTERNATIVES := ["fta", "investment", "customs"]
const SOFT_ALTERNATIVES := ["nonaggression", "arms", "extradition", "climate"]


## This leader's open proposal, or {} if there is none or it expired.
static func pending(world: GameWorld, target: Country) -> Dictionary:
	var offer: Dictionary = world.offers.get(target.iso, {})
	if offer.is_empty():
		return offer
	if world.months_elapsed - int(offer.get("month", 0)) > EXPIRE_MONTHS:
		world.offers.erase(target.iso)
		return {}
	return offer


## Chooses what the leader brings, according to war, relation, ideas and relative wealth. Always returns something usable.
static func make(world: GameWorld, target: Country) -> Dictionary:
	var d := world.diplomacy
	var me := world.player
	var rel: float = d.relation(me.idx, target.idx)
	var offer := {"kind": "offer", "type": "", "month": world.months_elapsed}
	if d.at_war(me.idx, target.idx):
		offer.kind = "peace"
		return offer
	var best := ""
	var best_score := -999.0
	for type: String in Treaties.TYPES:
		if not world.treaties.between(me, target, type).is_empty():
			continue
		var score := world.treaties.goodwill(world, world.politics.player_party(world), target, type, me) - float(Treaties.TYPES[type].need)
		if score > best_score:
			best_score = score
			best = type
	var poor: bool = target.y_usd() < me.y_usd() * POOR_RATIO
	if rel < -25.0 or (rel < 0.0 and best_score < -10.0):
		offer.kind = "threat"
	elif best != "" and best_score > 0.0 and not (poor and world.rng.randf() < 0.5):
		offer.kind = "treaty"
		offer.type = best
	elif poor and rel > -10.0:
		offer.kind = "request"
	elif best != "" and best_score > -15.0:
		offer.kind = "treaty"
		offer.type = best
	elif rel >= 0.0:
		offer.kind = "offer"
	else:
		offer.kind = "threat"
	return offer


static func guess_amount(world: GameWorld, target: Country, from_player: bool) -> float:
	return (world.player if from_player else target).y_usd() * 0.001


static func _type_label(type: String) -> String:
	return TranslationServer.translate(Treaties.TYPES[type].label).to_lower()


## What the leader says when presenting the proposal.
static func text(world: GameWorld, target: Country, offer: Dictionary) -> String:
	match String(offer.kind):
		"treaty":
			return TranslationServer.translate("Proponho um tratado de %s entre nossos países. %s") % [_type_label(offer.type), TranslationServer.translate(Treaties.TYPES[offer.type].desc)]
		"peace":
			return TranslationServer.translate("Esta guerra já custou demais aos dois lados. Proponho cessar fogo e voltar às fronteiras de antes.")
		"threat":
			return TranslationServer.translate("Exijo que você reduza a presença militar perto das minhas fronteiras e pare de apoiar meus rivais. Caso contrário, haverá consequências.")
		"request":
			return TranslationServer.translate("Meu país atravessa dias difíceis. Peço uma ajuda de US$ %.1f bi para o meu povo.") % guess_amount(world, target, true)
		"offer":
			return TranslationServer.translate("Quero um gesto de amizade: meu governo envia US$ %.1f bi em apoio ao seu orçamento.") % guess_amount(world, target, false)
	return ""


## Available answers: {id: accept|refuse|counter, label, hint}.
static func choices(world: GameWorld, target: Country, offer: Dictionary) -> Array:
	var out := []
	match String(offer.kind):
		"treaty":
			out.append({"id": "accept", "label": TranslationServer.translate("Aceito o tratado."), "hint": TranslationServer.translate("Assina agora; cada parlamento ratifica depois.")})
			out.append({"id": "refuse", "label": TranslationServer.translate("Não me interessa."), "hint": TranslationServer.translate("Relação -2.")})
			var alt := alternative(world, target, offer)
			if alt != "":
				out.append({"id": "counter", "label": TranslationServer.translate("Contraproponho um tratado de %s.") % _type_label(alt), "hint": TranslationServer.translate("Ele pode aceitar ou não, conforme a confiança.")})
		"peace":
			out.append({"id": "accept", "label": TranslationServer.translate("Aceito cessar fogo."), "hint": TranslationServer.translate("A guerra termina sem mudar fronteiras.")})
			out.append({"id": "refuse", "label": TranslationServer.translate("Ainda não."), "hint": TranslationServer.translate("A guerra continua. Relação -3.")})
			out.append({"id": "counter", "label": TranslationServer.translate("Aceito, mas quero parte do território."), "hint": TranslationServer.translate("Só funciona se a frente favorece você.")})
		"threat":
			out.append({"id": "accept", "label": TranslationServer.translate("Vou ceder para ganhar tempo."), "hint": TranslationServer.translate("Relação +10; aprovação -4 pontos.")})
			out.append({"id": "refuse", "label": TranslationServer.translate("Rejeito o ultimato."), "hint": TranslationServer.translate("Aprovação +2 pontos; relação -8 e tensão maior.")})
			var alt := alternative(world, target, offer)
			if alt != "":
				out.append({"id": "counter", "label": TranslationServer.translate("Prefiro um tratado de %s.") % _type_label(alt), "hint": TranslationServer.translate("Troca a pressão por um compromisso formal.")})
		"request":
			out.append({"id": "accept", "label": TranslationServer.translate("Envio a ajuda."), "hint": TranslationServer.translate("Doa 0,1% do seu PIB.")})
			out.append({"id": "refuse", "label": TranslationServer.translate("Não posso agora."), "hint": TranslationServer.translate("Relação -3.")})
			out.append({"id": "counter", "label": TranslationServer.translate("Em vez de dinheiro, ofereço comércio."), "hint": TranslationServer.translate("Um acordo comercial, se ele topar.")})
		"offer":
			out.append({"id": "accept", "label": TranslationServer.translate("Aceito, com gratidão."), "hint": TranslationServer.translate("Recebe o dinheiro; relação +6.")})
			out.append({"id": "refuse", "label": TranslationServer.translate("Agradeço, mas dispenso."), "hint": TranslationServer.translate("Relação -1.")})
			out.append({"id": "counter", "label": TranslationServer.translate("Preciso do dobro."), "hint": TranslationServer.translate("Pode funcionar com quem gosta de você.")})
	return out


## Alternative treaty for the counterproposal, or "" if there is none. For a treaty, the lightest; for a request, a trade agreement.
static func alternative(world: GameWorld, target: Country, offer: Dictionary) -> String:
	var me := world.player
	var pool: Array = TRADE_ALTERNATIVES if offer.kind == "request" else Treaties.TYPES.keys()
	var best := ""
	for type: String in pool:
		if type == String(offer.get("type", "")) or not world.treaties.between(me, target, type).is_empty():
			continue
		if offer.kind == "threat" and not type in SOFT_ALTERNATIVES:
			continue
		if best == "" or float(Treaties.TYPES[type].need) < float(Treaties.TYPES[best].need):
			best = type
	return best


## Applies the answer. Returns {accepted, reply}.
static func resolve(world: GameWorld, target: Country, offer: Dictionary, choice: String) -> Dictionary:
	var d := world.diplomacy
	var me := world.player
	var kind := String(offer.kind)
	var no := func(reply: String, rel_delta: float) -> Dictionary:
		d.add_relation(me.idx, target.idx, rel_delta)
		return {"accepted": false, "reply": reply}
	match kind:
		"treaty":
			match choice:
				"accept":
					world.treaties.sign_with_player(world, target, offer.type)
					return {"accepted": true, "reply": TranslationServer.translate("Ótimo. Assinamos, e cada parlamento ratifica.")}
				"refuse":
					return no.call(TranslationServer.translate("É uma pena. A oferta fica para outra hora."), -2.0)
				_:
					var alt := alternative(world, target, offer)
					if alt != "" and world.treaties.propose(world, target, alt).get("accepted", false):
						return {"accepted": true, "reply": TranslationServer.translate("Esse formato serve. Assinamos, e cada parlamento ratifica.")}
					return no.call(TranslationServer.translate("Esse formato não me serve. Fiquemos como estamos."), -2.0)
		"peace":
			var w := d.war_between(me.idx, target.idx)
			if w.is_empty():
				return {"accepted": false, "reply": TranslationServer.translate("A guerra já acabou. Não há mais o que discutir.")}
			match choice:
				"accept":
					d.end_war_by_player(w, target, me, world, 0.0, TranslationServer.translate("Cessar-fogo entre %s e %s: as fronteiras voltam a ser as de antes.") % [me.name, target.name])
					return {"accepted": true, "reply": TranslationServer.translate("Então está feito. Chega de sangue.")}
				"refuse":
					return no.call(TranslationServer.translate("Que seja. A guerra segue, e a responsabilidade é sua."), -3.0)
				_:
					var pl_att: bool = me.idx in w.a
					var front: float = float(w.front) if pl_att else -float(w.front)
					if front > 5.0 and world.rng.randf() < 0.3 + target.war_exhaustion * 0.5:
						d.end_war_by_player(w, me, target, world, clampf(front / 100.0 * 0.4, 0.02, 0.3), TranslationServer.translate("Paz assinada: %s cede {pct} do território a %s.") % [target.name, me.name])
						return {"accepted": true, "reply": TranslationServer.translate("Aceito. Cedo o que pede, mas a guerra acaba aqui.")}
					return no.call(TranslationServer.translate("Território, não. Sem isso, seguimos lutando."), -3.0)
		"threat":
			match choice:
				"accept":
					d.add_relation(me.idx, target.idx, 10.0)
					me.approval = clampf(me.approval - 0.04, 0.02, 0.95)
					return {"accepted": true, "reply": TranslationServer.translate("Sábia decisão. Esta conversa não precisa ir mais longe.")}
				"refuse":
					me.approval = clampf(me.approval + 0.02, 0.02, 0.95)
					world.global_risk = clampf(world.global_risk + 0.02, 0.0, 1.0)
					return no.call(TranslationServer.translate("Você vai se arrepender."), -8.0)
				_:
					var alt := alternative(world, target, offer)
					if alt != "" and world.treaties.propose(world, target, alt).get("accepted", false):
						return {"accepted": true, "reply": TranslationServer.translate("Um compromisso por escrito acalma as coisas. Assinamos.")}
					return no.call(TranslationServer.translate("Papel não me convence. Quero atitudes."), -4.0)
		"request":
			match choice:
				"accept":
					var aid := world.do_action("aid", target)
					if not aid.ok:
						return {"accepted": false, "reply": TranslationServer.translate("Agradeço a intenção, mas seu governo não tem como cumprir isso agora.")}
					return {"accepted": true, "reply": TranslationServer.translate("Meu povo agradece. Não vamos esquecer esse gesto.")}
				"refuse":
					return no.call(TranslationServer.translate("Entendo. Procuraremos ajuda em outro lugar."), -3.0)
				_:
					var alt := alternative(world, target, offer)
					if alt != "" and world.treaties.propose(world, target, alt).get("accepted", false):
						return {"accepted": true, "reply": TranslationServer.translate("Comércio também ajuda. Aceito, e vamos assinar.")}
					d.add_relation(me.idx, target.idx, 2.0)
					return {"accepted": false, "reply": TranslationServer.translate("Prefiro ajuda direta, mas agradeço a boa vontade.")}
		"offer":
			var amount := guess_amount(world, target, false)
			match choice:
				"accept":
					_gift(world, target, amount)
					return {"accepted": true, "reply": TranslationServer.translate("Fico feliz em ajudar. Que isso aproxime nossos povos.")}
				"refuse":
					return no.call(TranslationServer.translate("Como quiser. A oferta está retirada."), -1.0)
				_:
					if world.rng.randf() < 0.25 + Dialogue.affinity(world, target) * 0.4:
						_gift(world, target, amount * 2.0)
						return {"accepted": true, "reply": TranslationServer.translate("Você pede muito, mas somos amigos. Fechado.")}
					return no.call(TranslationServer.translate("Isso é mais do que posso dar. Retiro a oferta."), -1.0)
	return {"accepted": false, "reply": TranslationServer.translate("Não entendi o que você quis dizer.")}


static func _gift(world: GameWorld, target: Country, amount: float) -> void:
	var me := world.player
	me.reserves += amount
	target.reserves = maxf(target.reserves - amount, 0.0)
	world.diplomacy.add_relation(me.idx, target.idx, 6.0)
	world.emit_news(TranslationServer.translate("%s envia US$ %.1f bi em apoio a %s.") % [target.name, amount, me.name], "diplomacia", target)
