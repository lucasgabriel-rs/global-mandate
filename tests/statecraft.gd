extends SceneTree
## Tests of opposition, politicians, compass, ministers and conversations, without the interface.
## Usage: godot --headless --path . -s tests/statecraft.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _world(iso := "BRA", seed_value := 7) -> GameWorld:
	var w := GameWorld.new()
	w.setup(seed_value)
	w.leader = Character.random(w.rng)
	w.leader.econ = 0.0
	w.leader.social = 0.0
	w.set_player(w.by_iso[iso], "normal")
	return w


func _average(members: Array, key: String) -> float:
	var total := 0.0
	for m: Dictionary in members:
		total += float(m[key])
	return total / members.size()


func _init() -> void:
	_compass()
	_cabinet()
	_opposition()
	_dialogue()
	_no_time_limit()
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)


func _compass() -> void:
	var w := _world()
	var pol := w.politics
	var bad := []
	var same := 0
	var all := 0
	for c: Country in w.countries:
		for p: Dictionary in pol.data_of(c.iso).parties:
			if p.members.size() < 2 or absf(float(p.econ) - _average(p.members, "econ")) > 0.0001 or absf(float(p.social) - _average(p.members, "social")) > 0.0001:
				bad.append("%s:%s" % [c.iso, p.short])
			var m0: Dictionary = p.members[0]
			var m1: Dictionary = p.members[1]
			all += 1
			if m0.econ == m1.econ and m0.social == m1.social:
				same += 1
	_check(bad.is_empty(), "each party's compass is the average of its politicians %s" % str(bad.slice(0, 3)))
	_check(same == 0, "each politician has their own compass (%d equal out of %d)" % [same, all])
	_check(not pol.leader_of("ARG").is_empty() and not pol.leader_of("ARG").has("player"), "a foreign leader is a politician")
	# The player enters, changes the average; leaves, the average goes back.
	var data := pol.data_of("BRA")
	var mine := pol.player_party(w)
	_check(mine.members[0].get("player", false), "the player leads their own party")
	var other: Dictionary = {}
	for p: Dictionary in data.parties:
		if p.id != mine.id:
			other = p
			break
	var before := float(other.econ)
	_check(pol.join_party(w, other.id).ok, "party switch")
	_check(absf(float(w.leader.econ) - before) < 0.0001, "whoever joins adopts the party's ideas")
	w.leader.econ = 1.0
	w.leader.social = 1.0
	pol.sync_player(w)
	_check(float(other.econ) > before and absf(float(other.econ) - _average(other.members, "econ")) < 0.0001, "the party's average includes the player")
	_check(absf(float(mine.econ) - _average(mine.members, "econ")) < 0.0001 and not _has_player(mine), "the old party recalculates without the player")
	w.leader.econ = -1.0
	var moved := float(other.econ)
	pol.sync_player(w)
	_check(float(other.econ) < moved, "changing ideas moves the party's compass")
	var again := 0
	for m: Dictionary in other.members:
		if m.get("player", false):
			again += 1
	_check(again == 1, "the player appears only once")
	var old := w.to_dict()
	for iso: String in old.politics.countries:
		var d: Dictionary = old.politics.countries[iso]
		d.erase("next_member")
		for p: Dictionary in d.parties:
			p.erase("members")
	var w2 := GameWorld.new()
	w2.setup(7)
	w2.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(not w2.politics.leader_of("ARG").is_empty(), "old save gets politicians")


func _has_player(party: Dictionary) -> bool:
	for m: Dictionary in party.members:
		if m.get("player", false):
			return true
	return false


func _cabinet() -> void:
	var w := _world()
	var pol := w.politics
	var data := pol.data_of("BRA")
	var filled := 0
	for p: Dictionary in Politics.PORTFOLIOS:
		if not pol.minister(w, p.id).is_empty():
			filled += 1
	_check(filled == Politics.PORTFOLIOS.size(), "the initial cabinet fills the %d portfolios (%d)" % [Politics.PORTFOLIOS.size(), filled])
	var parties := {}
	var outside := 0
	for e: Dictionary in data.cabinet.values():
		parties[e.party] = true
		if not int(e.party) in data.coalition:
			outside += 1
	_check(outside == 0, "ministers come from the coalition")
	_check(parties.size() == mini(data.coalition.size(), Politics.PORTFOLIOS.size()), "portfolios split among the allies")
	# Appointment rules.
	var post := "finance"
	var options := pol.eligible_ministers(w, post)
	_check(not options.is_empty(), "there are candidates")
	var outsider: Dictionary = {}
	for p: Dictionary in data.parties:
		if not p.id in data.coalition:
			outsider = p
	if not outsider.is_empty():
		_check(not pol.appoint(w, post, outsider.id, outsider.members[0].id).ok, "someone outside the coalition does not become a minister")
	var me := pol.player_politician(w)
	_check(not pol.appoint(w, post, pol.player_party(w).id, me.id).ok, "the player is not their own minister")
	var other_post: Dictionary = data.cabinet.foreign
	_check(not pol.appoint(w, post, other_post.party, other_post.member).ok, "nobody holds several portfolios")
	var best: Dictionary = options[0]
	_check(pol.appoint(w, post, best.party.id, best.member.id).ok and pol.minister(w, post).id == best.member.id, "nomeia")
	pol.dismiss_minister(w, post)
	_check(pol.minister(w, post).is_empty() and is_equal_approx(pol.minister_competence(w, post), 0.3), "pasta vaga funciona mal")
	# Effect: compare with good and bad ones, starting from the same state.
	var good := _with_cabinet(0.95)
	var bad := _with_cabinet(0.1)
	_check(good.cred > bad.cred and good.stability > bad.stability and good.approval > bad.approval, "competence changes the country (cred %.3f/%.3f, stab %.3f/%.3f, appr %.3f/%.3f)" % [good.cred, bad.cred, good.stability, bad.stability, good.approval, bad.approval])
	# A party that leaves takes the ministers along.
	var w2 := _world()
	var d2 := w2.politics.data_of("BRA")
	var partner: int = -1
	for id: int in d2.coalition:
		if id != int(d2.ruling):
			partner = id
	_check(partner >= 0, "test case: there is an ally in the coalition")
	_check(w2.politics.dismiss(w2, partner).ok, "tira aliado")
	var left := 0
	for e: Dictionary in d2.cabinet.values():
		if int(e.party) == partner:
			left += 1
	_check(left == 0, "an ally that leaves takes the ministers along")
	# An ally with no portfolio ends up leaving.
	var w3 := _world()
	var d3 := w3.politics.data_of("BRA")
	for post3: String in d3.cabinet.keys():
		d3.cabinet.erase(post3)
	var size0: int = d3.coalition.size()
	for i in 300:
		w3.politics.step_month(w3)
	_check(d3.coalition.size() < size0, "an ally with no ministry abandons the government")
	# Salvar.
	var w4 := _world()
	w4.politics.dismiss_minister(w4, "health")
	var w5 := GameWorld.new()
	w5.setup(7)
	w5.load_dict(bytes_to_var(var_to_bytes(w4.to_dict())))
	_check(w5.politics.minister(w5, "health").is_empty() and not w5.politics.minister(w5, "finance").is_empty(), "save keeps the cabinet")


func _with_cabinet(competence: float) -> Country:
	var w := _world()
	var data := w.politics.data_of("BRA")
	for p: Dictionary in data.parties:
		for m: Dictionary in p.members:
			m.competence = competence
	w.player.approval = 0.5
	w.player.stability = 0.5
	w.player.cred = 0.5
	for i in 12:
		w.politics._step_cabinet(w, data)
	return w.player


func _opposition() -> void:
	# Losing the election.
	var w := _world()
	var ended := {}
	w.game_ended.connect(func(r): ended.merge(r))
	var prompts := []
	w.prompt_requested.connect(func(p): prompts.append(p))
	var c := w.player
	c.dem = 7.0
	c.approval = 0.02
	c.next_election = w.year_float()
	var party0: int = w.politics.player_party(w).id
	w.check_player_politics(c)
	_check(not w.in_office and not w.over and ended.is_empty(), "losing the election does not end the game")
	_check(w.player == c and w.governed() == null, "stays in the country, without governing")
	_check(w.politics.player_party(w).id == party0, "stays in their own party")
	_check(w.politics.ruling_party(c.iso).id != party0, "another party governs")
	_check(prompts.size() >= 1 and prompts[-1].title == "Derrotado nas urnas", "avisa a derrota")
	_check(w.politics.data_of(c.iso).get("cabinet", {}).is_empty(), "cabinet falls with the government")
	# Without government powers.
	var t: Country = w.by_iso["ARG"]
	_check(not w.do_action("mission", t).ok, "no diplomacy")
	_check(not Dialogue.start(w, t).ok, "no conversations")
	_check(not w.politics.vote(w, "education").ok, "no projects")
	_check(not w.politics.set_budget(w, "sp_health", c.sp_health + 0.01).ok, "no budget")
	_check(not w.politics.appoint(w, "finance", party0, 0).ok, "no ministers")
	_check(not w.politics.invite(w, party0).ok, "no coalition")
	# The AI governs: 2 years ahead, with no pending decisions.
	var tax0 := c.tax_income + c.sp_social + c.sp_defense + c.sp_infra
	var count0 := prompts.size()
	c.next_election = 9999.0
	for i in 365 * 2:
		w.tick_day()
	_check(prompts.size() == count0, "the AI decides alone, with no windows for the player")
	_check(c.tax_income + c.sp_social + c.sp_defense + c.sp_infra != tax0, "the AI starts adjusting the country's taxes and spending")
	# Opposition actions.
	var approval0 := c.approval
	var support0 := float(w.politics.player_party(w).support)
	w.politics.player_party(w).funds = 1000.0
	_check(w.politics.criticize(w).ok and c.approval < approval0 and float(w.politics.player_party(w).support) > support0, "criticizing brings down the government and helps the party")
	support0 = float(w.politics.player_party(w).support)
	_check(w.politics.campaign(w).ok and float(w.politics.player_party(w).support) > support0, "campaigning makes the party grow")
	var mine := w.politics.player_party(w)
	mine.funds = 0.0
	_check(not w.politics.criticize(w).ok, "with no money in the fund it does not act")
	mine.funds = 1000.0
	var switch := w.politics.join_party(w, _other_party(w, party0), false)
	_check(switch.ok and not w.in_office, "can switch party in opposition, without returning to government")
	# Motion of no confidence.
	var w2 := _world()
	var c2 := w2.player
	c2.dem = 7.0
	w2.enter_opposition("Teste.", "Teste")
	w2.politics.hand_over(c2)
	var d2 := w2.politics.data_of(c2.iso)
	for p: Dictionary in d2.parties:
		p.seats = 0
	var rule: Dictionary = w2.politics.ruling_party(c2.iso)
	rule.seats = int(d2.seats_total)
	d2.coalition = [rule.id]
	var fail := w2.politics.censure(w2)
	_check(fail.ok and not fail.passed, "government with a majority resists the censure:" + str(fail.msg))
	rule.seats = 10
	var my2 := w2.politics.player_party(w2)
	my2.seats = int(d2.seats_total) - 10
	my2.support = 0.7
	Politics._normalize(d2)
	c2.approval = 0.05
	c2.next_election = 9999.0
	var pass_ := w2.politics.censure(w2)
	_check(pass_.ok and pass_.passed, "majority brings down the government:" + str(pass_.msg))
	_check(c2.next_election > w2.year_float(), "censure calls an election")
	_check(w2.in_office, "with an unpopular government, the opposition takes over")
	# Opposition election: the government's approval decides. The player's party starts as the largest rival.
	var result := {"baixa": 0, "alta": 0}
	for i in 20:
		for key: String in result:
			var e := _world("DEU", 300 + i)
			e.player.dem = 7.0
			e.enter_opposition("Teste.", "Teste")
			e.politics.hand_over(e.player)
			var de := e.politics.data_of("DEU")
			e.politics.player_party(e).support = 0.25
			e.politics.ruling_party("DEU").support = 0.4
			Politics._normalize(de)
			e.player.approval = 0.1 if key == "baixa" else 0.75
			e.player.next_election = e.year_float()
			e.check_player_politics(e.player)
			if e.in_office:
				result[key] += 1
	print("returns to power in 20 elections: ", result)
	_check(result.baixa >= 15, "an unpopular government makes the comeback easier")
	_check(result.alta <= 3, "a popular government makes the comeback harder")
	var back := _world("DEU", 300)
	back.player.dem = 7.0
	back.enter_opposition("Teste.", "Teste")
	back.politics.hand_over(back.player)
	back.politics.player_party(back).support = 0.45
	back.politics.ruling_party("DEU").support = 0.25
	Politics._normalize(back.politics.data_of("DEU"))
	back.player.approval = 0.05
	back.player.next_election = back.year_float()
	back.check_player_politics(back.player)
	_check(back.in_office and back.governed() == back.player, "vence e volta a governar")
	_check(back.politics.ruling_party("DEU").id == back.politics.player_party(back).id, "the player's party governs")
	_check(not back.politics.minister(back, "finance").is_empty(), "returns with a cabinet")
	_check(back.do_action("mission", back.by_iso["FRA"]).ok, "returns with diplomacy")
	# Save.
	var w3 := _world()
	w3.player.dem = 7.0
	w3.enter_opposition("Teste.", "Teste")
	var w4 := GameWorld.new()
	w4.setup(7)
	w4.load_dict(bytes_to_var(var_to_bytes(w3.to_dict())))
	_check(not w4.in_office, "save keeps the opposition")
	# Annexed country in opposition ends it.
	var w5 := _world()
	var ended5 := {}
	w5.game_ended.connect(func(r): ended5.merge(r))
	w5.player.dem = 7.0
	w5.enter_opposition("Teste.", "Teste")
	w5.player.next_election = 9999.0
	w5.diplomacy.annex(w5.by_iso["ARG"], w5.player, w5)
	for i in 40:
		w5.tick_day()
	_check(ended5.get("reason") == "golpe", "annexed country ends the career")
	w5.assume_new_character(Character.random(w5.rng))
	_check(w5.player == w5.by_iso["ARG"] and not w5.over, "the new character continues in whoever annexed")
	# Game over other than an election still applies.
	var w6 := _world()
	var ended6 := {}
	w6.game_ended.connect(func(r): ended6.merge(r))
	w6.player_lost_war(w6.by_iso["ARG"])
	_check(ended6.is_empty() and not w6.over and not w6.in_office, "military defeat in a democracy becomes opposition")
	var w7 := _world("CHN")
	var ended7 := {}
	w7.game_ended.connect(func(r): ended7.merge(r))
	w7.player_lost_war(w7.by_iso["USA"])
	_check(ended7.get("reason") == "golpe" and w7.over, "in a closed regime, military defeat brings down the leader")


func _other_party(w: GameWorld, not_id: int) -> int:
	for p: Dictionary in w.politics.data_of(w.player.iso).parties:
		if p.id != not_id:
			return p.id
	return not_id


func _dialogue() -> void:
	var w := _world()
	var d := w.diplomacy
	var me := w.player
	var t: Country = w.by_iso["ARG"]
	var open := Dialogue.start(w, t)
	_check(open.ok and String(open.greeting) != "" and true, "abrir conversa: " + str(open.get("greeting", "")))
	_check(not Dialogue.start(w, t).ok, "one conversation a month with each leader")
	_check(Dialogue.start(w, w.by_iso["CHL"]).ok, "another leader can talk")
	_check(not Dialogue.start(w, me).ok, "does not talk to themselves")
	# High and low relation decide.
	d.set_relation(me.idx, t.idx, 90.0)
	var ids := Dialogue.options(w, t).map(func(o): return o.id)
	_check("praise" in ids and "protest" in ids and "threat" in ids and "alliance" in ids and "aid" in ids, "peace lines:" + str(ids))
	var yes := Dialogue.choose(w, t, "alliance")
	_check(yes.accepted and not w.treaties.between(me, t, "defense").is_empty(), "amigo aceita o pacto: " + str(yes.reply))
	d.sign_alliance(me, t, w)
	var w2 := _world()
	var t2: Country = w2.by_iso["ARG"]
	w2.diplomacy.set_relation(w2.player.idx, t2.idx, -40.0)
	var no := Dialogue.choose(w2, t2, "alliance")
	_check(not no.accepted and not w2.diplomacy.allied(w2.player.idx, t2.idx), "hostil recusa o pacto: " + str(no.reply))
	var rel0: float = w2.diplomacy.relation(w2.player.idx, t2.idx)
	_check(Dialogue.choose(w2, t2, "praise").accepted and w2.diplomacy.relation(w2.player.idx, t2.idx) > rel0, "praise improves the relation")
	# Compass: same relations, different ideas.
	var near := _affinity_world(true)
	var far := _affinity_world(false)
	_check(Dialogue.affinity(near, near.by_iso["ARG"]) > Dialogue.affinity(far, far.by_iso["ARG"]), "ideias parecidas aproximam")
	_check(Dialogue.goodwill(near, near.by_iso["ARG"]) > Dialogue.goodwill(far, far.by_iso["ARG"]), "affinity weighs on goodwill")
	# Threat: the weak yields, the strong reacts.
	var w3 := _world("USA")
	var weak: Country = w3.by_iso["URY"]
	var strong: Country = w3.by_iso["CHN"]
	strong.troops *= 3.0
	strong.mil_stock *= 3.0
	_check(Dialogue.choose(w3, weak, "threat").accepted, "the weak yields to the threat")
	var r0: float = w3.diplomacy.relation(w3.player.idx, strong.idx)
	var mine0 := w3.player.mil_stock
	w3.player.mil_stock = minf(mine0, strong.mil_stock)
	_check(not Dialogue.choose(w3, strong, "threat").accepted and w3.diplomacy.relation(w3.player.idx, strong.idx) < r0, "the strong reacts to the threat")
	# At war the lines change.
	var w4 := _world()
	var t4: Country = w4.by_iso["ARG"]
	w4.diplomacy.declare_war(w4.player, t4, w4)
	var war_ids := Dialogue.options(w4, t4).map(func(o): return o.id)
	_check("peace" in war_ids and not "alliance" in war_ids and not "fta" in war_ids, "at war, only peace and protest:" + str(war_ids))
	# Chanceler.
	var bad_c := _world()
	var good_c := _world()
	var bd := bad_c.politics.data_of("BRA")
	bd.cabinet.erase("foreign")
	var gd := good_c.politics.data_of("BRA")
	for p: Dictionary in gd.parties:
		for m: Dictionary in p.members:
			m.competence = 1.0
	_check(Dialogue.goodwill(good_c, good_c.by_iso["ARG"]) > Dialogue.goodwill(bad_c, bad_c.by_iso["ARG"]), "bom chanceler ajuda")
	var w5 := _world()
	Dialogue.start(w5, w5.by_iso["ARG"])
	var w6 := GameWorld.new()
	w6.setup(7)
	w6.load_dict(bytes_to_var(var_to_bytes(w5.to_dict())))
	_check(Dialogue.wait_months(w6, w6.by_iso["ARG"]) > 0, "save keeps the wait")


func _affinity_world(near: bool) -> GameWorld:
	var w := _world()
	var theirs := w.politics.leader_of("ARG")
	w.leader.econ = float(theirs.econ) if near else (-1.0 if float(theirs.econ) > 0.0 else 1.0)
	w.leader.social = float(theirs.social) if near else (-1.0 if float(theirs.social) > 0.0 else 1.0)
	w.politics.sync_player(w)
	return w


func _no_time_limit() -> void:
	# Goes past the old 2060 limit without ending the game.
	var w := _world()
	var ended := {}
	w.game_ended.connect(func(r): ended.merge(r))
	w.year = 2059
	w.month = 11
	w.day = 25
	for i in 40:
		w.player.next_election = 9999.0
		w.tick_day()
	_check(w.year == 2060 and ended.is_empty() and not w.over, "2060 does not end the game:" + w.date_string())
