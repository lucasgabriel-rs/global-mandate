extends SceneTree
## Conversa com líderes partidários: pedir que apoiem ou votem contra uma lei em tramitação.
## Uso: godot --headless --path . -s tests/party_talk.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _program(type: String) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2.ZERO)
	var block := LawProgram.new_block(program, type)
	block.fields["name"] = "X"
	stack.blocks.append(block)
	return program


func _world() -> GameWorld:
	var w := GameWorld.new()
	w.setup(7)
	w.leader = Character.random(w.rng)
	w.set_player(w.by_iso["BRA"], "normal")
	return w


## Lei em tramitação na posição indicada da bússola, com todos os partidos no centro.
func _bill(w: GameWorld, position: Dictionary, spread := 0.0) -> Dictionary:
	var leg: Legislation = w.legislation
	var data: Dictionary = w.politics.data_of("BRA")
	data.coalition = [data.ruling]
	for p: Dictionary in data.parties:
		p.econ = spread
		p.social = spread
	var norm: Dictionary = leg.new_norm(w, "ordinaria")
	norm.title = "Lei de teste"
	norm.ementa = "Teste"
	norm.program = _program("rg_restrict")
	leg.present(w, norm)
	norm.position = position
	return norm


func _init() -> void:
	_contacts()
	_stance_and_chance()
	_effect_on_vote()
	_closed_after_answer()
	_log_and_save()
	_hook()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)


func _contacts() -> void:
	var w := _world()
	var data: Dictionary = w.politics.data_of("BRA")
	var list := PartyTalk.contacts(w)
	_check(not list.is_empty() and list.all(func(p): return int(p.id) != int(data.player_party)), "contatos são os outros partidos")
	_check(int(list[0].seats) >= int(list[-1].seats), "do maior para o menor")
	_check(not PartyTalk.leader_of(list[0]).is_empty(), "cada partido tem um líder")
	_check(PartyTalk.options(w, list[0]).is_empty(), "sem lei em votação não há o que pedir")
	_bill(w, {"econ": 0.0, "social": 0.0})
	var ids: Array = PartyTalk.options(w, list[0]).map(func(o): return String(o.id).split(":")[0])
	_check("sound" in ids and "ask_yes" in ids and "ask_no" in ids, "com lei aberta: sondar, pedir apoio e pedir voto contra: " + str(ids))


func _stance_and_chance() -> void:
	var w := _world()
	var leg: Legislation = w.legislation
	var data: Dictionary = w.politics.data_of("BRA")
	var norm := _bill(w, {"econ": 0.9, "social": -1.0}, 1.0)
	norm.position = {"econ": 0.9, "social": -0.2}
	var party: Dictionary = PartyTalk.contacts(w)[0]
	_check(not leg.chat_stance(w, norm, party), "lei distante: o partido votaria contra")
	var against := leg.chat_factors(w, norm, party, false)
	var for_it := leg.chat_factors(w, norm, party, true)
	_check(against.aligned and float(against.chance) > float(for_it.chance), "pedir o que ele já faria é mais fácil: %.2f contra %.2f" % [against.chance, for_it.chance])
	# Afinidade com o seu partido ajuda a virar o voto.
	var mine: Dictionary = w.politics.player_party(w)
	mine.econ = -1.0
	mine.social = 1.0
	var chance_far := float(leg.chat_factors(w, norm, party, true).chance)
	mine.econ = party.econ
	mine.social = party.social
	var chance_near := float(leg.chat_factors(w, norm, party, true).chance)
	_check(chance_near > chance_far, "partido de ideias próximas escuta melhor: %.2f > %.2f" % [chance_near, chance_far])
	# Popularidade da lei pesa a favor e contra o pedido.
	var good := norm.duplicate(true)
	var bad := norm.duplicate(true)
	good.state = norm.state
	var pop := leg.popularity_of(w, norm)
	_check(pop > 0.0 and pop < 1.0, "popularidade da lei: %.2f" % pop)
	_check(float(leg.chat_factors(w, norm, party, true).pop) == pop, "popularidade entra nos fatores")
	_check(bad.size() > 0 and data.parties.size() > 1, "há partidos para conversar")


func _effect_on_vote() -> void:
	var w := _world()
	var leg: Legislation = w.legislation
	var data: Dictionary = w.politics.data_of("BRA")
	var norm := _bill(w, {"econ": 0.0, "social": 0.0})
	# Todos de acordo com a lei: pedido de apoio sempre vira acordo.
	var party: Dictionary = PartyTalk.contacts(w)[0]
	var r := leg.chat_request(w, norm, int(party.id), true)
	_check(r.ok and r.accepted and norm.deals[str(party.id)] == true, "quem já apoia fecha o voto: " + str(r.msg))
	# O acordo decide a votação: o partido vota como combinado.
	var roll := leg.roll_call(w, norm)
	var row: Dictionary = roll.tally.filter(func(t): return t.party == party.short)[0]
	_check(int(row.yes) >= int(party.seats) * 0.9, "bancada vota a favor depois do acordo")
	# Pedir que vote contra uma lei que ele apoia: se aceitar, o voto muda; se recusar, não muda.
	var second: Dictionary = PartyTalk.contacts(w)[1]
	var against := leg.chat_request(w, norm, int(second.id), false)
	var changed: bool = norm.get("deals", {}).has(str(second.id))
	_check(against.ok and (changed == against.accepted), "aceitar vira acordo, recusar não muda nada: " + str(against.msg))
	if changed:
		_check(not norm.deals[str(second.id)], "o acordo é de voto contra")
	_check(not leg.chat_request(w, norm, int(data.player_party), true).ok, "o próprio partido não é contato")
	# Fim da votação: não dá mais para pedir.
	norm.state = Legislation.STATE_REJECTED
	_check(not leg.chat_request(w, norm, int(PartyTalk.contacts(w)[2].id), true).ok, "sem votação pela frente não há pedido")


func _closed_after_answer() -> void:
	var w := _world()
	var leg: Legislation = w.legislation
	var norm := _bill(w, {"econ": 0.0, "social": 0.0})
	var party: Dictionary = PartyTalk.contacts(w)[0]
	leg.chat_request(w, norm, int(party.id), true)
	_check(leg.chat_closed(norm, int(party.id)), "partido que respondeu fica fechado para esta lei")
	_check(not leg.chat_request(w, norm, int(party.id), false).ok, "não dá para pedir de novo")
	var ids: Array = PartyTalk.options(w, party).map(func(o): return String(o.id).split(":")[0])
	_check("ask_yes" not in ids and "ask_no" not in ids and "sound" in ids, "só sondar continua disponível")
	var other: Dictionary = PartyTalk.contacts(w)[1]
	_check(not leg.chat_closed(norm, int(other.id)), "outro partido continua aberto")


func _log_and_save() -> void:
	var w := _world()
	var norm := _bill(w, {"econ": 0.0, "social": 0.0})
	var party: Dictionary = PartyTalk.contacts(w)[0]
	var key := ChatLog.party_key(int(party.id))
	var r := PartyTalk.say(w, party, "ask_yes:%d" % int(norm.id))
	var thread := ChatLog.thread(w, key)
	_check(thread.size() == 2 and thread[0].me and not thread[1].me and thread[1].text == r.reply, "pedido e resposta entram na conversa")
	_check(String(thread[0].date) != "", "mensagens têm a data do jogo")
	var sound := PartyTalk.say(w, party, "sound:%d" % int(norm.id))
	_check(sound.ok and ChatLog.thread(w, key).size() == 4, "sondar também conversa")
	_check(not PartyTalk.say(w, party, "ask_yes:999999").ok, "lei que não existe não responde")
	# Países também guardam o histórico.
	var t: Country = w.by_iso["ARG"]
	Dialogue.start(w, t)
	_check(Dialogue.turns_left(w, t) == Dialogue.TURNS_PER_MEETING and ChatLog.thread(w, ChatLog.country_key("ARG")).size() == 1, "saudação do líder abre a conversa")
	var said := Dialogue.say(w, t, "praise")
	_check(said.ok and ChatLog.thread(w, ChatLog.country_key("ARG")).size() == 3 and Dialogue.turns_left(w, t) == 2, "cada fala gasta um turno e entra no histórico")
	Dialogue.say(w, t, "praise")
	Dialogue.say(w, t, "praise")
	_check(not Dialogue.say(w, t, "praise").ok, "sem turnos a conversa acaba")
	# Save.
	var w2 := GameWorld.new()
	w2.setup(7)
	w2.load_dict(w.to_dict())
	_check(ChatLog.thread(w2, key).size() == ChatLog.thread(w, key).size() and ChatLog.thread(w2, ChatLog.country_key("ARG")).size() == 7, "o save guarda as conversas")


func _hook() -> void:
	var w := _world()
	var norm := _bill(w, {"econ": 0.9, "social": -1.0}, 1.0)
	var party: Dictionary = PartyTalk.contacts(w)[0]
	_check(w.legislation.counterpart_bonus(w, norm, party, true) == 0.0, "ponto de extensão das contrapartidas: sem contrapartida, 0")
	_check(PartyTalk.extra_offers(w, party).is_empty(), "sem falas extras por enquanto")
