extends Node
## Propostas dos líderes que puxam conversa e a agenda de contatos.
## Uso: godot --path . -- --ui-diplomacy --shots=/caminho/da/pasta

var main: Node
var out := "user://shots"
var failures := 0


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out)
	await _run()
	print("RESULT: %d failures" % failures)
	get_tree().quit()


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


func _shot(name_: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _chat() -> ChatWindow:
	for child: Node in main.modal_root.get_children():
		if child is ChatWindow and not child.is_queued_for_deletion():
			return child
	return null


func _agenda() -> AgendaWindow:
	for child: Node in main.modal_root.get_children():
		if child is AgendaWindow and not child.is_queued_for_deletion():
			return child
	return null


func _run() -> void:
	while main.loading or main.world == null:
		await get_tree().process_frame
	main.join_sim()
	main._pick_start(main.world.by_iso["BRA"])
	main._begin(Character.random(main.world.rng), {})
	main._set_speed(0)
	await _frames(5)
	var w: GameWorld = main.world
	var me: Country = w.player
	await _situations(w, me)
	await _every_answer(w, me)
	await _chat_flow(w)
	await _agenda_flow(w)
	_check(w.to_dict().has("offers"), "as propostas em aberto vão para o save")


## A situação diplomática decide o que o líder traz, e sempre há o que aceitar ou recusar.
func _situations(w: GameWorld, me: Country) -> void:
	var usa: Country = w.by_iso["USA"]
	var d := w.diplomacy
	d.set_relation(me.idx, usa.idx, -60.0)
	_check(Proposals.make(w, usa).kind == "threat", "relação péssima traz ultimato")
	d.set_relation(me.idx, usa.idx, 70.0)
	var friendly := Proposals.make(w, usa)
	_check(friendly.kind == "treaty" and Treaties.TYPES.has(friendly.type), "relação ótima traz tratado (%s)" % friendly.get("type", ""))
	var poor: Country = null
	for c: Country in w.countries:
		if c.alive and c != me and c.y_usd() < me.y_usd() * 0.2:
			poor = c
			break
	if poor:
		d.set_relation(me.idx, poor.idx, 5.0)
		for t: String in Treaties.TYPES:
			if w.treaties.between(me, poor, t).is_empty():
				w.treaties._add("teste", t, [me.iso, poor.iso], Treaties.STATE_FORCE, w, 0)
		var seen := Proposals.make(w, poor)
		_check(seen.kind == "request" or seen.kind == "offer", "país pobre, sem tratado a propor, pede ajuda ou oferece (%s)" % seen.kind)
	var enemy: Country = w.by_iso["ARG"]
	d.declare_war(me, enemy, w)
	_check(Proposals.make(w, enemy).kind == "peace", "em guerra, o líder propõe paz")
	d.wars.clear()
	var ok := 0
	var total := 0
	for c: Country in w.countries.slice(0, 60):
		if not c.alive or c == me:
			continue
		var offer := Proposals.make(w, c)
		total += 1
		var ids := Proposals.choices(w, c, offer).map(func(x): return x.id)
		if offer.kind in Proposals.KINDS and Proposals.text(w, c, offer) != "" and "accept" in ids and "refuse" in ids:
			ok += 1
	_check(ok == total and total > 20, "todo líder tem proposta utilizável com aceitar e recusar: %d de %d" % [ok, total])


## Cada tipo de proposta resolve as três respostas, com efeito real e sem deixar a proposta pendurada.
func _every_answer(w: GameWorld, me: Country) -> void:
	var d := w.diplomacy
	for kind: String in Proposals.KINDS:
		for choice: String in ["accept", "refuse", "counter"]:
			var target: Country = w.by_iso["DEU"]
			d.wars.clear()
			for t: String in Treaties.TYPES:
				for item: Dictionary in w.treaties.items.duplicate():
					if t == item.type and target.iso in item.parties and me.iso in item.parties:
						w.treaties.items.erase(item)
			w.treaties._pairs.clear()
			for item: Dictionary in w.treaties.items:
				w.treaties._index(item)
			if kind == "peace":
				d.declare_war(me, target, w)
			d.set_relation(me.idx, target.idx, 40.0)
			var offer := {"kind": kind, "type": "climate" if kind == "treaty" else "", "month": w.months_elapsed}
			w.offers[target.iso] = offer
			var rel0: float = d.relation(me.idx, target.idx)
			var reserves0 := me.reserves
			var debt0 := me.debt_loc
			var treaties0 := w.treaties.items.size()
			var r := Dialogue.answer(w, target, choice)
			var label := "%s/%s" % [kind, choice]
			_check(r.ok and String(r.reply) != "", label + ": responde com uma fala")
			_check(not w.offers.has(target.iso), label + ": a proposta sai da pauta")
			var rel1: float = d.relation(me.idx, target.idx)
			var moved: bool = absf(rel1 - rel0) > 0.01 or w.treaties.items.size() != treaties0 or me.reserves != reserves0 or me.debt_loc != debt0 or d.wars.is_empty() != (kind != "peace")
			if kind == "peace" and choice == "refuse":
				moved = rel1 < rel0 and not d.wars.is_empty()
			_check(moved, label + ": mexe no jogo")
			d.wars.clear()
	_check(Dialogue.answer(w, w.by_iso["DEU"], "accept").ok == false, "sem proposta, não há o que responder")


## O líder que vem até o jogador chega com a proposta no chat, e os botões respondem a ela.
func _chat_flow(w: GameWorld) -> void:
	var fra: Country = w.by_iso["FRA"]
	var me: Country = w.player
	w.talks.erase(fra.iso)
	w.diplomacy.wars.clear()
	w.diplomacy.set_relation(me.idx, fra.idx, 60.0)
	w.offers[fra.iso] = {"kind": "treaty", "type": "climate", "month": w.months_elapsed}
	for item: Dictionary in w.treaties.items.duplicate():
		if item.type == "climate" and fra.iso in item.parties and me.iso in item.parties:
			w.treaties.items.erase(item)
	w.treaties._pairs.clear()
	for item: Dictionary in w.treaties.items:
		w.treaties._index(item)
	main._open_talk(fra, true)
	await _frames(4)
	var chat := _chat()
	_check(chat != null and chat.current == "pais:FRA", "a conversa com o líder abre")
	var thread := ChatLog.thread(w, "pais:FRA")
	_check(thread.size() >= 2 and String(thread[-1].text).contains("cooperação climática"), "o líder abre com a proposta no chat")
	for id: String in ["accept", "refuse", "counter"]:
		_check(chat.find_child("say_offer_" + id, true, false) != null, "botão de resposta: " + id)
	await _shot("d1_proposta")
	(chat.find_child("say_offer_accept", true, false) as Button).pressed.emit()
	await _frames(3)
	_check(not w.treaties.between(me, fra, "climate").is_empty(), "aceitar assina o tratado")
	_check(chat.find_child("say_offer_accept", true, false) == null, "depois da resposta os botões somem")
	_check(chat.find_child("say_praise", true, false) != null, "a conversa segue com as falas de sempre")
	await _shot("d2_depois_de_aceitar")
	main._close_modal(chat)
	await _frames(2)


func _agenda_flow(w: GameWorld) -> void:
	main.open_agenda()
	await _frames(3)
	var agenda := _agenda()
	_check(agenda != null, "a agenda abre")
	var parties := PartyTalk.contacts(w).size()
	var countries := w.countries.filter(func(c): return c.alive and c != w.player).size()
	var rows := agenda.find_children("agenda_party_*", "", true, false).size()
	_check(rows == parties and parties > 0, "a agenda lista os líderes partidários: %d de %d" % [rows, parties])
	rows = agenda.find_children("agenda_country_*", "", true, false).size()
	_check(rows == countries, "a agenda lista os líderes de países: %d de %d" % [rows, countries])
	await _shot("d3_agenda")
	var search: LineEdit = agenda.find_child("search", true, false)
	search.text = "ger"
	search.text_changed.emit("ger")
	await _frames(2)
	var found := agenda.find_children("agenda_country_*", "", true, false).size()
	_check(found > 0 and found < countries, "a busca filtra os contatos: %d" % found)
	search.text = ""
	search.text_changed.emit("")
	await _frames(2)
	# Chama um país sem conversa em curso: a conversa começa e o histórico abre.
	var jpn: Country = w.by_iso["JPN"]
	w.talks.erase(jpn.iso)
	w.talk_turns.erase(jpn.iso)
	(agenda.find_child("agenda_country_JPN", true, false).find_child("talk", true, false) as Button).pressed.emit()
	await _frames(4)
	_check(_agenda() == null, "a agenda fecha ao escolher")
	var chat := _chat()
	_check(chat != null and chat.current == "pais:JPN", "a conversa com o país escolhido abre")
	_check(Dialogue.turns_left(w, jpn) > 0 and not ChatLog.thread(w, "pais:JPN").is_empty(), "o líder atende e cumprimenta")
	# Dentro da janela de conversas, a agenda troca de contato sem abrir outra janela.
	(chat.find_child("open_agenda", true, false) as Button).pressed.emit()
	await _frames(3)
	agenda = _agenda()
	_check(agenda != null, "a agenda abre de dentro das conversas")
	var party_id := int(PartyTalk.contacts(w)[0].id)
	(agenda.find_child("agenda_party_%d" % party_id, true, false).find_child("talk", true, false) as Button).pressed.emit()
	await _frames(4)
	var chats: Array = main.modal_root.get_children().filter(func(c): return c is ChatWindow and not c.is_queued_for_deletion())
	_check(chats.size() == 1 and chat.current == "partido:%d" % party_id, "escolher um partido troca o contato na mesma janela")
	await _shot("d4_partido")
	main._close_modal(chat)
	await _frames(2)
