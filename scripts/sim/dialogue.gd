class_name Dialogue
extends RefCounted
## Conversations with leaders of other countries. The leader answers according to the relation between the countries, the player's
## foreign minister and, above all, ideas: the distance between their compass and that of the player's party, and what they
## themselves think of each subject. A right-wing leader likes to open markets; an authoritarian does not yield to threats.

const TURNS_PER_MEETING := 3
const COOLDOWN_MONTHS := 1
const NEED_FTA := 15.0
const NEED_ALLIANCE := 55.0
const NEED_SANCTION := 40.0
const THREAT_POWER_RATIO := 1.5
const SUMMIT_TREATY_CHANCE := 0.2


static func wait_months(world: GameWorld, target: Country) -> int:
	var last: int = world.talks.get(target.iso, -9999)
	return maxi(last + COOLDOWN_MONTHS - world.months_elapsed, 0)


## Opens the conversation. Returns {ok, msg} and, if it works, the greeting in greeting.
static func start(world: GameWorld, target: Country, invited := false) -> Dictionary:
	if not world.in_office:
		return {"ok": false, "msg": TranslationServer.translate("Na oposição, você não fala em nome do país.")}
	if target == world.player or not target.alive:
		return {"ok": false, "msg": TranslationServer.translate("Não há com quem conversar.")}
	if wait_months(world, target) > 0 and not invited:
		return {"ok": false, "msg": TranslationServer.translate("Vocês conversaram há pouco. Tente no mês que vem.")}
	world.talks[target.iso] = world.months_elapsed
	world.talk_turns[target.iso] = TURNS_PER_MEETING
	var hello := greeting(world, target)
	var key := ChatLog.country_key(target.iso)
	ChatLog.add(world, key, false, hello)
	# Whoever starts the conversation arrives with a concrete proposal in hand.
	if invited:
		var offer := Proposals.pending(world, target)
		if offer.is_empty():
			offer = Proposals.make(world, target)
			world.offers[target.iso] = offer
		ChatLog.add(world, key, false, Proposals.text(world, target, offer))
	return {"ok": true, "msg": "", "greeting": hello}


## Answers the open proposal: "accept", "refuse" or "counter". Does not spend the conversation's lines.
static func answer(world: GameWorld, target: Country, choice: String) -> Dictionary:
	var offer := Proposals.pending(world, target)
	if offer.is_empty():
		return {"ok": false, "accepted": false, "reply": TranslationServer.translate("Não há proposta em aberto.")}
	var label := ""
	for c: Dictionary in Proposals.choices(world, target, offer):
		if c.id == choice:
			label = c.label
	if label == "":
		return {"ok": false, "accepted": false, "reply": TranslationServer.translate("Não entendi o que você quis dizer.")}
	var key := ChatLog.country_key(target.iso)
	ChatLog.add(world, key, true, label)
	world.offers.erase(target.iso)
	var r := Proposals.resolve(world, target, offer, choice)
	ChatLog.add(world, key, false, r.reply, r.accepted)
	r["ok"] = true
	return r


## Lines still left in the current conversation with the leader.
static func turns_left(world: GameWorld, target: Country) -> int:
	return int(world.talk_turns.get(target.iso, 0))


## The chosen line goes into the history, with the leader's reply. Each line spends one of the conversation's.
static func say(world: GameWorld, target: Country, id: String) -> Dictionary:
	var label := ""
	for o: Dictionary in options(world, target):
		if o.id == id:
			label = o.label
	if label == "" or turns_left(world, target) <= 0:
		return {"accepted": false, "reply": TranslationServer.translate("Não entendi o que você quis dizer."), "ok": false}
	var key := ChatLog.country_key(target.iso)
	ChatLog.add(world, key, true, label)
	var r := choose(world, target, id)
	world.talk_turns[target.iso] = turns_left(world, target) - 1
	ChatLog.add(world, key, false, r.reply, r.accepted)
	r["ok"] = true
	return r


static func leader_of(world: GameWorld, target: Country) -> Dictionary:
	return world.politics.leader_of(target.iso)


## 0 when ideas are opposite and 1 when they are equal: the leader's compass against the player party's.
static func affinity(world: GameWorld, target: Country) -> float:
	var theirs := leader_of(world, target)
	var mine := world.politics.player_party(world)
	if theirs.is_empty() or mine.is_empty():
		return 0.5
	return clampf(1.0 - Politics.distance(mine, theirs) / 2.8, 0.0, 1.0)


## Relation as the leader sees it in this conversation: includes affinity of ideas and the foreign minister.
static func goodwill(world: GameWorld, target: Country) -> float:
	var rel: float = world.diplomacy.relation(world.player.idx, target.idx)
	var chancellor: float = world.politics.minister_competence(world, "foreign")
	return rel + (affinity(world, target) - 0.5) * 30.0 + (chancellor - 0.5) * 20.0


## Disposition for confrontation: authoritarians have more, libertarians less.
static func hawkishness(leader: Dictionary) -> float:
	return clampf(0.35 - float(leader.get("social", 0.0)) * 0.55, 0.0, 1.0)


## What the leader is, in words, so the player knows who they are talking to.
static func temper(leader: Dictionary) -> String:
	var econ := float(leader.get("econ", 0.0))
	var social := float(leader.get("social", 0.0))
	var left_right: String = TranslationServer.translate("esquerda") if econ < -0.2 else (TranslationServer.translate("direita") if econ > 0.2 else TranslationServer.translate("centro"))
	var power: String = TranslationServer.translate("autoritário") if social < -0.2 else (TranslationServer.translate("libertário") if social > 0.2 else TranslationServer.translate("moderado"))
	return "%s, %s" % [left_right, power]


## One AI approaches another: the affinity between the leaders decides whether agreement or friction comes out.
static func summit(world: GameWorld, a: Country, b: Country) -> void:
	var la: Dictionary = world.politics.leader_of(a.iso)
	var lb: Dictionary = world.politics.leader_of(b.iso)
	if la.is_empty() or lb.is_empty():
		return
	var d := world.diplomacy
	var aff := clampf(1.0 - Politics.distance(la, lb) / 2.8, 0.0, 1.0)
	var rel: float = d.relation(a.idx, b.idx)
	d.add_relation(a.idx, b.idx, (aff - 0.45) * 12.0 + world.rng.randf_range(-2.0, 2.0))
	if aff > 0.55 and rel > -10.0 and world.rng.randf() < SUMMIT_TREATY_CHANCE:
		var best := ""
		var best_score := -999.0
		for type: String in Treaties.TYPES:
			var score := rel + (aff - 0.5) * 30.0 + Treaties.leader_bias(type, la) + Treaties.leader_bias(type, lb) - float(Treaties.TYPES[type].need)
			if score > best_score and world.treaties.between(a, b, type).is_empty():
				best_score = score
				best = type
		if best != "" and best_score > 0.0 and world.treaties.ai_sign(world, a, b, best):
			NationAI._say(a, b, world, TranslationServer.translate("%s e %s se reúnem e assinam tratado de {tipo}.").replace("{tipo}", TranslationServer.translate(Treaties.TYPES[best].label).to_lower()), "diplomacia")
			return
	if aff < 0.35:
		NationAI._say(a, b, world, TranslationServer.translate("Encontro de %s e %s termina em atrito."), "diplomacia")
	elif world.rng.randf() < 0.25:
		NationAI._say(a, b, world, TranslationServer.translate("%s e %s se reúnem para aproximar os governos."), "diplomacia")


static func greeting(world: GameWorld, target: Country) -> String:
	var rel: float = world.diplomacy.relation(world.player.idx, target.idx)
	var line: String = TranslationServer.translate("Seja direto. Não tenho muito tempo para o seu governo.")
	if world.diplomacy.at_war(world.player.idx, target.idx):
		line = TranslationServer.translate("Enquanto houver tropas na fronteira, esta conversa será curta.")
	elif rel >= 50.0:
		line = TranslationServer.translate("É sempre um prazer falar com um velho amigo. Em que posso ajudar?")
	elif rel >= 15.0:
		line = TranslationServer.translate("Bom falar com você. Nossos países têm muito a ganhar juntos.")
	elif rel > -15.0:
		line = TranslationServer.translate("Recebi o seu pedido de conversa. O que deseja discutir?")
	var a := affinity(world, target)
	if a >= 0.75:
		line += TranslationServer.translate(" Vejo que o seu partido pensa como eu.")
	elif a <= 0.3:
		line += TranslationServer.translate(" Sabemos que o seu partido e eu pensamos muito diferente.")
	return line


## Lines available now. Each: {id, label, hint}.
static func options(world: GameWorld, target: Country) -> Array:
	var d := world.diplomacy
	var me := world.player
	var at_war: bool = d.at_war(me.idx, target.idx)
	var out := []
	if at_war:
		out.append({"id": "peace", "label": TranslationServer.translate("Proponho encerrarmos esta guerra."), "hint": TranslationServer.translate("A frente e o cansaço decidem.")})
		out.append({"id": "protest", "label": TranslationServer.translate("Sua agressão será lembrada."), "hint": TranslationServer.translate("Relação cai, e sua aprovação sobe um pouco.")})
		return out
	out.append({"id": "praise", "label": TranslationServer.translate("Quero elogiar a parceria entre nossos países."), "hint": TranslationServer.translate("Melhora a relação, mais ainda com ideias parecidas.")})
	if not d.has_fta(me.idx, target.idx, world):
		out.append({"id": "fta", "label": TranslationServer.translate("Vamos abrir nossos mercados um ao outro?"), "hint": TranslationServer.translate("Acordo de livre comércio, se houver confiança.")})
	if not d.allied(me.idx, target.idx):
		out.append({"id": "alliance", "label": TranslationServer.translate("Proponho um pacto de defesa mútua."), "hint": TranslationServer.translate("Precisa de muita confiança.")})
	out.append({"id": "aid", "label": TranslationServer.translate("Meu governo quer enviar ajuda ao seu povo."), "hint": TranslationServer.translate("Doa 0,1% do seu PIB.")})
	# The two treaties that best match their ideas, not yet signed.
	var theirs := leader_of(world, target)
	var types: Array = Treaties.TYPES.keys().filter(func(t): return t != "fta" and t != "defense" and world.treaties.between(me, target, t).is_empty())
	types.sort_custom(func(x, y): return Treaties.leader_bias(x, theirs) > Treaties.leader_bias(y, theirs))
	for type: String in types.slice(0, 2):
		out.append({"id": "treaty:" + type, "label": TranslationServer.translate("Proponho um tratado de %s.") % TranslationServer.translate(Treaties.TYPES[type].label).to_lower(), "hint": TranslationServer.translate(Treaties.TYPES[type].desc)})
	if float(theirs.get("social", 0.0)) < 0.0:
		out.append({"id": "rights", "label": TranslationServer.translate("Seu governo precisa respeitar os direitos do seu povo."), "hint": TranslationServer.translate("Agrada seu eleitor. Líderes autoritários não gostam nada disso.")})
	var enemy := enemy_to_sanction(world, target)
	if enemy:
		out.append({"id": "sanction", "label": TranslationServer.translate("Peço que você sancione %s.") % enemy.name, "hint": TranslationServer.translate("Só um aliado próximo aceitaria.")})
	out.append({"id": "protest", "label": TranslationServer.translate("Preciso protestar contra as ações do seu governo."), "hint": TranslationServer.translate("Relação cai, e sua aprovação sobe um pouco.")})
	out.append({"id": "threat", "label": TranslationServer.translate("Mude de postura ou haverá consequências."), "hint": TranslationServer.translate("Funciona com quem é bem mais fraco que você.")})
	return out


static func enemy_to_sanction(world: GameWorld, target: Country) -> Country:
	for w: Dictionary in world.diplomacy.wars:
		var side: Array = w.d if world.player.idx in w.a else (w.a if world.player.idx in w.d else [])
		for i: int in side:
			var enemy: Country = world.countries[i]
			if enemy != target and enemy.alive and world.diplomacy.sanction_level(target.idx, enemy.idx) == 0:
				return enemy
	return null


## Applies the chosen line. Returns {reply, accepted}.
static func choose(world: GameWorld, target: Country, id: String) -> Dictionary:
	var d := world.diplomacy
	var me := world.player
	var theirs := leader_of(world, target)
	var econ := float(theirs.get("econ", 0.0))
	var hawk := hawkishness(theirs)
	var trust := goodwill(world, target) + world.rng.randf_range(-6.0, 6.0)
	if id.begins_with("treaty:"):
		return _treaty(world, target, id.trim_prefix("treaty:"))
	match id:
		"praise":
			d.add_relation(me.idx, target.idx, 1.0 + 7.0 * affinity(world, target))
			if affinity(world, target) < 0.3:
				return {"accepted": true, "reply": TranslationServer.translate("Elogios não mudam o que pensamos, mas agradeço a cortesia.")}
			return {"accepted": true, "reply": TranslationServer.translate("Palavras gentis, e bem-vindas. Vou lembrar disso.")}
		"fta":
			# Whoever is on the right likes to open markets, and the left is wary.
			if trust + econ * 25.0 < NEED_FTA:
				return {"accepted": false, "reply": TranslationServer.translate("Abrir assim destruiria empregos aqui. Não é o que defendo.") if econ < 0.0 else TranslationServer.translate("Meu parlamento não aceitaria. Ainda falta confiança entre nós.")}
			world.treaties.sign_with_player(world, target, "fta")
			return {"accepted": true, "reply": TranslationServer.translate("Temos um acordo. Assinamos agora, e cada parlamento ratifica depois.")}
		"alliance":
			# Whoever likes force values a pact; the libertarian prefers not to be tied down.
			if trust + (hawk - 0.35) * 20.0 < NEED_ALLIANCE:
				return {"accepted": false, "reply": TranslationServer.translate("Um pacto assim exige mais do que temos hoje. Sigamos conversando.")}
			world.treaties.sign_with_player(world, target, "defense")
			return {"accepted": true, "reply": TranslationServer.translate("Então está decidido: assinamos, e um ataque a um será um ataque ao outro assim que os parlamentos ratificarem.")}
		"aid":
			var aid := world.do_action("aid", target)
			if not aid.ok:
				return {"accepted": false, "reply": TranslationServer.translate("Agradeço a intenção, mas seu governo não tem como cumprir isso agora.")}
			if econ > 0.5:
				return {"accepted": true, "reply": TranslationServer.translate("Aceito, embora eu prefira comércio a caridade.")}
			return {"accepted": true, "reply": TranslationServer.translate("Meu povo agradece. Não vamos esquecer esse gesto.")}
		"sanction":
			var enemy := enemy_to_sanction(world, target)
			if enemy == null or trust < NEED_SANCTION:
				return {"accepted": false, "reply": TranslationServer.translate("Não vou comprar essa briga por você.")}
			d.set_sanction(target, enemy, 1, world)
			world.emit_news(TranslationServer.translate("%s impõe sanções a %s a pedido de %s.") % [target.name, enemy.name, me.name], "diplomacia", target)
			return {"accepted": true, "reply": TranslationServer.translate("Conte com isso. As sanções saem ainda hoje.")}
		"rights":
			d.add_relation(me.idx, target.idx, -3.0 - hawk * 10.0)
			me.approval = clampf(me.approval + 0.008, 0.02, 0.95)
			return {"accepted": false, "reply": TranslationServer.translate("Meu país não aceita lições. Cuide do seu povo, que eu cuido do meu.")}
		"protest":
			d.add_relation(me.idx, target.idx, -3.0 - hawk * 8.0)
			me.approval = clampf(me.approval + 0.01, 0.02, 0.95)
			return {"accepted": true, "reply": TranslationServer.translate("Registrado. Não espere que eu mude por causa disso.")}
		"threat":
			# An authoritarian only backs down before much greater force; a libertarian yields before fighting.
			var needed := 1.2 + hawk * 2.4
			if me.military_power() >= target.military_power() * needed:
				d.add_relation(me.idx, target.idx, -8.0)
				return {"accepted": true, "reply": TranslationServer.translate("Entendi o recado. Vamos rever nossa posição, por enquanto.")}
			d.add_relation(me.idx, target.idx, -8.0 - hawk * 14.0)
			return {"accepted": false, "reply": TranslationServer.translate("Você não está em condições de me ameaçar. Isso terá um preço.")}
		"peace":
			if world.action_wait("peace", target) > 0:
				return {"accepted": false, "reply": TranslationServer.translate("Sem uma proposta concreta, não há o que discutir.")}
			var r := world.do_action("peace", target)
			if not r.ok:
				return {"accepted": false, "reply": TranslationServer.translate("Não. Esta guerra só acaba nos meus termos.")}
			return {"accepted": true, "reply": TranslationServer.translate("Basta de sangue. Vamos aos termos.")}
	return {"accepted": false, "reply": TranslationServer.translate("Não entendi o que você quis dizer.")}


static func _treaty(world: GameWorld, target: Country, type: String) -> Dictionary:
	var r: Dictionary = world.treaties.propose(world, target, type)
	if r.get("accepted", false):
		return {"accepted": true, "reply": TranslationServer.translate("Aceito. Assinamos, e cada parlamento ratifica.")}
	return {"accepted": false, "reply": TranslationServer.translate("Isso não combina com o que eu defendo, ou ainda não confio o bastante.")}
