extends SceneTree
## Conversation with party leaders: asking them to support or vote against a law in procedure.
## Usage: godot --headless --path . -s tests/party_talk.gd

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


## Law in procedure at the indicated compass position, with all parties in the center.
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
	_check(not list.is_empty() and list.all(func(p): return int(p.id) != int(data.player_party)), "contacts are the other parties")
	_check(int(list[0].seats) >= int(list[-1].seats), "from largest to smallest")
	_check(not PartyTalk.leader_of(list[0]).is_empty(), "each party has a leader")
	_check(PartyTalk.options(w, list[0]).is_empty(), "with no law being voted there is nothing to ask")
	_bill(w, {"econ": 0.0, "social": 0.0})
	var ids: Array = PartyTalk.options(w, list[0]).map(func(o): return String(o.id).split(":")[0])
	_check("sound" in ids and "ask_yes" in ids and "ask_no" in ids, "with an open law: sound out, ask for support and ask for a vote against:" + str(ids))


func _stance_and_chance() -> void:
	var w := _world()
	var leg: Legislation = w.legislation
	var data: Dictionary = w.politics.data_of("BRA")
	var norm := _bill(w, {"econ": 0.9, "social": -1.0}, 1.0)
	norm.position = {"econ": 0.9, "social": -0.2}
	var party: Dictionary = PartyTalk.contacts(w)[0]
	_check(not leg.chat_stance(w, norm, party), "distant law: the party would vote against")
	var against := leg.chat_factors(w, norm, party, false)
	var for_it := leg.chat_factors(w, norm, party, true)
	_check(against.aligned and float(against.chance) > float(for_it.chance), "asking for what it would do anyway is easier: %.2f against %.2f" % [against.chance, for_it.chance])
	# Affinity with your party helps turn the vote.
	var mine: Dictionary = w.politics.player_party(w)
	mine.econ = -1.0
	mine.social = 1.0
	var chance_far := float(leg.chat_factors(w, norm, party, true).chance)
	mine.econ = party.econ
	mine.social = party.social
	var chance_near := float(leg.chat_factors(w, norm, party, true).chance)
	_check(chance_near > chance_far, "a party with close ideas listens better: %.2f > %.2f" % [chance_near, chance_far])
	# The law's popularity weighs for and against the request.
	var good := norm.duplicate(true)
	var bad := norm.duplicate(true)
	good.state = norm.state
	var pop := leg.popularity_of(w, norm)
	_check(pop > 0.0 and pop < 1.0, "law popularity: %.2f" % pop)
	_check(float(leg.chat_factors(w, norm, party, true).pop) == pop, "popularity enters the factors")
	_check(bad.size() > 0 and data.parties.size() > 1, "there are parties to talk to")


func _effect_on_vote() -> void:
	var w := _world()
	var leg: Legislation = w.legislation
	var data: Dictionary = w.politics.data_of("BRA")
	var norm := _bill(w, {"econ": 0.0, "social": 0.0})
	# Everyone agrees with the law: a support request always becomes an agreement.
	var party: Dictionary = PartyTalk.contacts(w)[0]
	var r := leg.chat_request(w, norm, int(party.id), true)
	_check(r.ok and r.accepted and norm.deals[str(party.id)] == true, "whoever already supports closes the vote:" + str(r.msg))
	# The agreement decides the vote: the party votes as agreed.
	var roll := leg.roll_call(w, norm)
	var row: Dictionary = roll.tally.filter(func(t): return t.party == party.short)[0]
	_check(int(row.yes) >= int(party.seats) * 0.9, "caucus votes in favor after the agreement")
	# Asking it to vote against a law it supports: if it accepts, the vote changes; if it refuses, it does not.
	var second: Dictionary = PartyTalk.contacts(w)[1]
	var against := leg.chat_request(w, norm, int(second.id), false)
	var changed: bool = norm.get("deals", {}).has(str(second.id))
	_check(against.ok and (changed == against.accepted), "accepting becomes an agreement, refusing changes nothing:" + str(against.msg))
	if changed:
		_check(not norm.deals[str(second.id)], "the agreement is a vote against")
	_check(not leg.chat_request(w, norm, int(data.player_party), true).ok, "the player's own party is not a contact")
	# End of the vote: it is no longer possible to ask.
	norm.state = Legislation.STATE_REJECTED
	_check(not leg.chat_request(w, norm, int(PartyTalk.contacts(w)[2].id), true).ok, "with no vote ahead there is no request")


func _closed_after_answer() -> void:
	var w := _world()
	var leg: Legislation = w.legislation
	var norm := _bill(w, {"econ": 0.0, "social": 0.0})
	var party: Dictionary = PartyTalk.contacts(w)[0]
	leg.chat_request(w, norm, int(party.id), true)
	_check(leg.chat_closed(norm, int(party.id)), "the party that answered is closed for this law")
	_check(not leg.chat_request(w, norm, int(party.id), false).ok, "it cannot be asked again")
	var ids: Array = PartyTalk.options(w, party).map(func(o): return String(o.id).split(":")[0])
	_check("ask_yes" not in ids and "ask_no" not in ids and "sound" in ids, "only sounding out remains available")
	var other: Dictionary = PartyTalk.contacts(w)[1]
	_check(not leg.chat_closed(norm, int(other.id)), "another party remains open")


func _log_and_save() -> void:
	var w := _world()
	var norm := _bill(w, {"econ": 0.0, "social": 0.0})
	var party: Dictionary = PartyTalk.contacts(w)[0]
	var key := ChatLog.party_key(int(party.id))
	var r := PartyTalk.say(w, party, "ask_yes:%d" % int(norm.id))
	var thread := ChatLog.thread(w, key)
	_check(thread.size() == 2 and thread[0].me and not thread[1].me and thread[1].text == r.reply, "request and answer enter the conversation")
	_check(String(thread[0].date) != "", "messages have the game's date")
	var sound := PartyTalk.say(w, party, "sound:%d" % int(norm.id))
	_check(sound.ok and ChatLog.thread(w, key).size() == 4, "sounding out also converses")
	_check(not PartyTalk.say(w, party, "ask_yes:999999").ok, "a law that does not exist does not answer")
	# Countries also keep the history.
	var t: Country = w.by_iso["ARG"]
	Dialogue.start(w, t)
	_check(Dialogue.turns_left(w, t) == Dialogue.TURNS_PER_MEETING and ChatLog.thread(w, ChatLog.country_key("ARG")).size() == 1, "the leader's greeting opens the conversation")
	var said := Dialogue.say(w, t, "praise")
	_check(said.ok and ChatLog.thread(w, ChatLog.country_key("ARG")).size() == 3 and Dialogue.turns_left(w, t) == 2, "each line spends a turn and goes into the history")
	Dialogue.say(w, t, "praise")
	Dialogue.say(w, t, "praise")
	_check(not Dialogue.say(w, t, "praise").ok, "with no turns the conversation ends")
	# Save.
	var w2 := GameWorld.new()
	w2.setup(7)
	w2.load_dict(w.to_dict())
	_check(ChatLog.thread(w2, key).size() == ChatLog.thread(w, key).size() and ChatLog.thread(w2, ChatLog.country_key("ARG")).size() == 7, "the save keeps the conversations")


func _hook() -> void:
	var w := _world()
	var norm := _bill(w, {"econ": 0.9, "social": -1.0}, 1.0)
	var party: Dictionary = PartyTalk.contacts(w)[0]
	_check(w.legislation.counterpart_bonus(w, norm, party, true) == 0.0, "counterpart extension point: with no counterpart, 0")
	_check(PartyTalk.extra_offers(w, party).is_empty(), "no extra lines for now")
