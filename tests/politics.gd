extends SceneTree
## Testes de partidos e parlamentos, sem interface.
## Uso: godot --headless --path . -s tests/politics.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FALHA: ", what)


func _world(iso := "BRA") -> GameWorld:
	var w := GameWorld.new()
	w.setup(7)
	w.set_player(w.by_iso[iso], "normal")
	return w


func _init() -> void:
	# Cenário.
	var w := _world()
	var pol := w.politics
	var bad := []
	var sizes := {}
	for c: Country in w.countries:
		var data := pol.data_of(c.iso)
		var seats := 0
		var support := 0.0
		for p: Dictionary in data.parties:
			seats += int(p.seats)
			support += float(p.support)
		if data.parties.size() < 2 or seats != int(data.seats_total) or absf(support - 1.0) > 0.001 or pol.ruling_party(c.iso).is_empty():
			bad.append(c.iso)
		if int(data.seats_total) < Politics.MIN_SEATS or int(data.seats_total) > Politics.MAX_SEATS:
			bad.append(c.iso + "(tamanho)")
		sizes[c.iso] = data.seats_total
	_check(bad.is_empty(), "os 170 países têm partidos e parlamento coerentes %s" % str(bad.slice(0, 5)))
	print("assentos: China %d, Brasil %d, Portugal %d, Luxemburgo %d" % [sizes.CHN, sizes.BRA, sizes.PRT, sizes.LUX])
	_check(sizes.CHN > sizes.BRA and sizes.BRA > sizes.PRT and sizes.PRT > sizes.LUX, "parlamento cresce com a população")
	var closed := 0
	var closed_bad := []
	for c: Country in w.countries:
		if c.dem < 4.0:
			closed += 1
			if pol.government_share(c.iso) < 0.5:
				closed_bad.append(c.iso)
	_check(closed > 0 and closed_bad.is_empty(), "regimes fechados têm partido dominante (%d regimes) %s" % [closed, str(closed_bad.slice(0, 5))])
	var again := GameWorld.new()
	again.setup(12345)
	_check(again.politics.data_of("BRA").parties[0].name == pol.data_of("BRA").parties[0].name, "partidos não dependem da semente da partida")

	# Sempre há partido do jogador.
	_check(not pol.player_party(w).is_empty(), "jogador entra em um partido ao assumir")
	_check(pol.player_party(w).id == pol.ruling_party("BRA").id, "partido do jogador governa")

	# Cláusula de barreira e maiores restos.
	var d := {"parties": [{"support": 0.5, "seats": 0}, {"support": 0.3, "seats": 0}, {"support": 0.18, "seats": 0}, {"support": 0.02, "seats": 0}], "seats_total": 101}
	Politics._allocate_seats(d)
	_check(d.parties[3].seats == 0, "abaixo de 3% não entra")
	_check(d.parties[0].seats + d.parties[1].seats + d.parties[2].seats == 101, "todos os assentos distribuídos")
	# Cotas: 51,53, 30,92 e 18,55. Os 2 assentos que sobram vão para os maiores restos: ,92 e ,55.
	_check(d.parties[0].seats == 51 and d.parties[1].seats == 31 and d.parties[2].seats == 19, "maiores restos sobre os votos válidos (%d, %d, %d)" % [d.parties[0].seats, d.parties[1].seats, d.parties[2].seats])

	# Escolher partido no início.
	var w2 := _world()
	var data2 := w2.politics.data_of("BRA")
	var ordered: Array = data2.parties.duplicate()
	ordered.sort_custom(func(a, b): return int(a.seats) < int(b.seats))
	var smallest: Dictionary = ordered[0]
	var approval0 := w2.player.approval
	_check(w2.politics.join_party(w2, smallest.id, true).ok, "entra em partido pequeno no início")
	_check(data2.ruling == smallest.id and data2.player_party == smallest.id, "ele passa a governar")
	_check(w2.player.approval == approval0, "no início não custa nada")
	_check(not w2.politics.join_party(w2, smallest.id).ok, "não entra de novo no próprio partido")
	var other: Dictionary = ordered[-1]
	_check(w2.politics.join_party(w2, other.id).ok and w2.player.approval < approval0, "trocar no meio custa aprovação")
	_check(not w2.politics.join_party(w2, smallest.id).ok and data2.player_party == other.id, "só troca uma vez por ano")

	# Fundar.
	var w3 := _world()
	var seats_total: int = w3.politics.data_of("BRA").seats_total
	_check(not w3.politics.found_party(w3, "  ", "centro", Color.RED, true).ok, "nome vazio é recusado")
	_check(not w3.politics.found_party(w3, "Sem Família", "xyz", Color.RED, true).ok, "família inválida é recusada")
	var f := w3.politics.found_party(w3, "Partido Novo Teste", "liberal", Color.RED, true)
	var mine := w3.politics.player_party(w3)
	_check(f.ok and mine.name == "Partido Novo Teste" and mine.color == Color.RED, "funda partido no início")
	_check(int(mine.seats) > 0, "partido fundado no início tem bancada (%d)" % int(mine.seats))
	var sum := 0
	for p: Dictionary in w3.politics.data_of("BRA").parties:
		sum += int(p.seats)
	_check(sum == seats_total, "assentos continuam fechando")
	_check(not w3.politics.found_party(w3, "partido novo teste", "centro", Color.BLUE).ok, "nome repetido é recusado")
	var mid := w3.politics.found_party(w3, "Dissidência", "verde", Color.GREEN)
	_check(mid.ok and int(w3.politics.player_party(w3).seats) == 0, "partido novo no meio do mandato não tem assentos")

	# Regime fechado: o partido do líder herda a dominância.
	var w4 := _world("CHN")
	var data4 := w4.politics.data_of("CHN")
	var minor: Dictionary = {}
	for p: Dictionary in data4.parties:
		if p.id != data4.ruling:
			minor = p
			break
	w4.politics.join_party(w4, minor.id, true)
	_check(data4.ruling == minor.id and w4.politics.government_share("CHN") > 0.5, "em regime fechado o partido do líder domina")
	var early4 := w4.politics.vote(w4, "early")
	_check(not early4.ok, "regime fechado não antecipa eleições: " + str(early4.msg))

	# Coalizão.
	var w5 := _world()
	var data5 := w5.politics.data_of("BRA")
	var outs: Array = data5.parties.filter(func(p): return not p.id in data5.coalition)
	print("coalizão inicial: ", data5.coalition.size(), " de ", data5.parties.size(), " partidos, ", w5.politics.government_seats("BRA"), " de ", data5.seats_total)
	if not outs.is_empty():
		var near: Dictionary = outs[0]
		var ruling := w5.politics.ruling_party("BRA")
		for p: Dictionary in outs:
			if Politics.distance(ruling, p) < Politics.distance(ruling, near):
				near = p
		w5.player.approval = 0.6
		var inv := w5.politics.invite(w5, near.id)
		print("convite: ", inv.msg)
		_check(inv.ok == (Politics.distance(ruling, near) <= Politics.COALITION_MAX_DISTANCE), "convite segue a distância ideológica")
		if inv.ok:
			_check(near.id in data5.coalition, "convidado entra")
			_check(w5.politics.dismiss(w5, near.id).ok and not near.id in data5.coalition, "tirar do governo funciona")
	_check(not w5.politics.dismiss(w5, data5.ruling).ok, "partido do governo não sai do governo")

	# Votações: com o parlamento controlado.
	var w6 := _world()
	var data6 := w6.politics.data_of("BRA")
	for p: Dictionary in data6.parties:
		p.seats = 0
	var party0: Dictionary = w6.politics.ruling_party("BRA")
	party0.seats = int(data6.seats_total)
	data6.coalition = [party0.id]
	var c6 := w6.player
	var social1 := c6.sp_social
	var v := w6.politics.vote(w6, "welfare")
	_check(v.ok and v.get("pending", false) and c6.sp_social == social1, "o projeto não vale na hora: " + str(v.msg))
	_check(not w6.politics.vote(w6, "welfare").ok, "tema não volta à pauta de imediato")
	_check(w6.politics.bill_wait(w6, "welfare") == Politics.BILL_COOLDOWN_MONTHS, "espera de 6 meses")
	_deliberate(w6, v.norm)
	_check(v.norm.state == Legislation.STATE_IN_FORCE and is_equal_approx(c6.sp_social, social1 + 0.01), "maioria aprova depois de deliberar: " + str(v.norm.state))
	# Governo sem assentos e oposição distante: rejeitado, sem efeito.
	for p: Dictionary in data6.parties:
		p.seats = 0
		p.econ = 1.0
		p.social = 1.0
	party0.seats = 1
	var far: Dictionary = {}
	for p: Dictionary in data6.parties:
		if p.id != party0.id:
			far = p
			break
	far.seats = int(data6.seats_total) - 1
	far.econ = 1.0
	far.social = -1.0
	var r := w6.politics.vote(w6, "education")
	var education0 := c6.sp_education
	_deliberate(w6, r.norm)
	_check(r.ok and r.norm.state == Legislation.STATE_REJECTED and c6.sp_education == education0, "sem votos é rejeitado e nada muda: " + str(r.norm.state))
	# 3/5 para antecipar eleições.
	var w7 := _world()
	var data7 := w7.politics.data_of("BRA")
	for p: Dictionary in data7.parties:
		p.seats = 0
	var ruler: Dictionary = w7.politics.ruling_party("BRA")
	ruler.seats = int(float(data7.seats_total) * 0.55)
	var rest: Dictionary = data7.parties[0] if data7.parties[0].id != ruler.id else data7.parties[1]
	rest.seats = int(data7.seats_total) - int(ruler.seats)
	rest.econ = 5.0
	data7.coalition = [ruler.id]
	var e := w7.politics.vote(w7, "early")
	_deliberate(w7, e.norm)
	_check(e.ok and e.norm.state == Legislation.STATE_REJECTED, "55%% não bastam para antecipar: " + str(e.norm.state))

	# Orçamento: o governo decide sozinho, salvo lei que obrigue o valor.
	var wb := _world()
	var pb := wb.politics
	var cb := wb.player
	var social0 := cb.sp_social
	_check(pb.set_budget(wb, "sp_social", social0 + 0.01).ok and is_equal_approx(cb.sp_social, social0 + 0.01), "o gasto muda na hora, sem votação")
	_check(not pb.set_budget(wb, "tax_income", 0.3).ok, "tributo não se muda pelo orçamento")
	var law: Dictionary = wb.legislation.new_norm(wb, "ordinaria")
	law.title = "Piso"
	law.ementa = "Teste"
	law.program = LawTemplates.budget_law("sp_health", 8.0)
	wb.legislation.present(wb, law)
	for p: Dictionary in pb.data_of("BRA").parties:
		p.econ = 0.0
		p.social = 0.0
	law.position = {"econ": 0.0, "social": 0.0}
	_deliberate(wb, law)
	_check(law.state == Legislation.STATE_IN_FORCE and is_equal_approx(cb.sp_health, 0.08), "a lei fixa o valor: " + str(law.state))
	var refused := pb.set_budget(wb, "sp_health", 0.02)
	_check(not refused.ok and is_equal_approx(cb.sp_health, 0.08), "com lei em vigor, o governo não muda: " + str(refused.msg))
	_check(pb.set_budget(wb, "sp_defense", 0.03).ok, "o resto do orçamento continua livre")
	wb.legislation.revoke_now(wb, law, "Teste", "Teste")
	_check(pb.set_budget(wb, "sp_health", 0.05).ok, "revogada a lei, o campo volta a ser livre")

	# Eleições do jogador: aprovação decide.
	var wins := {"alta": 0, "baixa": 0}
	for i in 20:
		var hi := GameWorld.new()
		hi.setup(100 + i)
		hi.set_player(hi.by_iso["DEU"], "normal")
		hi.player.approval = 0.62
		if hi.politics.player_election(hi).won:
			wins.alta += 1
		var lo := GameWorld.new()
		lo.setup(100 + i)
		lo.set_player(lo.by_iso["DEU"], "normal")
		lo.player.approval = 0.08
		if lo.politics.player_election(lo).won:
			wins.baixa += 1
	print("vitórias em 20 eleições: ", wins)
	_check(wins.alta >= 18, "aprovação alta vence quase sempre")
	_check(wins.baixa <= 2, "aprovação muito baixa perde quase sempre")
	var ended := {}
	var w8 := _world()
	w8.game_ended.connect(func(res): ended.merge(res))
	w8.player.approval = 0.02
	w8.player.dem = 7.0
	w8.player.next_election = w8.year_float()
	w8.check_player_politics(w8.player)
	_check(ended.is_empty() and not w8.over and not w8.in_office, "derrota nas urnas leva à oposição, sem encerrar o jogo")
	var seats8 := 0
	for p: Dictionary in w8.politics.data_of("BRA").parties:
		seats8 += int(p.seats)
	_check(seats8 == int(w8.politics.data_of("BRA").seats_total), "eleição redistribui todos os assentos")
	# Impeachment.
	var ended9 := {}
	var w9 := _world()
	w9.game_ended.connect(func(res): ended9.merge(res))
	w9.player.dem = 7.0
	w9.player.next_election = 9999.0
	var data9 := w9.politics.data_of("BRA")
	data9.coalition = [data9.ruling]
	for p: Dictionary in data9.parties:
		p.seats = 0
	var rule9: Dictionary = w9.politics.ruling_party("BRA")
	rule9.seats = 10
	(data9.parties[0] if data9.parties[0].id != rule9.id else data9.parties[1]).seats = int(data9.seats_total) - 10
	for i in 400:
		w9.player.approval = 0.1
		w9.check_player_politics(w9.player)
		if w9.over:
			break
	_check(ended9.get("reason") == "impeachment" and w9.over, "governo sem apoio e impopular pode sofrer impeachment, e a carreira acaba")

	# IA: oposição assume ao vencer.
	var w10 := _world()
	var arg: Country = w10.by_iso["ARG"]
	var before: int = w10.politics.ruling_party("ARG").id
	arg.approval = 0.02
	var stayed := true
	for tries in 6:
		stayed = w10.politics.ai_election(w10, arg)
		if not stayed:
			break
		arg.approval = 0.02
	_check(not stayed and w10.politics.ruling_party("ARG").id != before, "governo impopular perde a eleição na IA")
	var sum10 := 0
	for p: Dictionary in w10.politics.data_of("ARG").parties:
		sum10 += int(p.seats)
	_check(sum10 == int(w10.politics.data_of("ARG").seats_total), "parlamento da IA fecha os assentos")

	# Save.
	var w11 := _world()
	w11.politics.found_party(w11, "Salvo", "verde", Color.AQUA, true)
	w11.politics.vote(w11, "education")
	var w12 := GameWorld.new()
	w12.setup(7)
	w12.load_dict(bytes_to_var(var_to_bytes(w11.to_dict())))
	_check(w12.politics.player_party(w12).name == "Salvo" and w12.politics.bill_wait(w12, "education") > 0, "save guarda partido e pauta")
	var old := w11.to_dict()
	old.erase("politics")
	var w13 := GameWorld.new()
	w13.setup(7)
	w13.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(not w13.politics.player_party(w13).is_empty(), "save antigo ganha partido")

	# Longo prazo.
	var w14 := _world()
	for i in 365 * 12:
		w14.player.next_election = 9999.0
		w14.player.approval = 0.5
		w14.tick_day()
		if w14.over:
			break
	var broken := []
	for c: Country in w14.countries:
		var data := w14.politics.data_of(c.iso)
		var seats := 0
		for p: Dictionary in data.parties:
			seats += int(p.seats)
		if seats != int(data.seats_total) or w14.politics.ruling_party(c.iso).is_empty():
			broken.append(c.iso)
	_check(broken.is_empty(), "12 anos depois os parlamentos seguem coerentes %s" % str(broken.slice(0, 5)))

	print("RESULTADO: ", failures, " falhas")
	quit(1 if failures > 0 else 0)


func _deliberate(world: GameWorld, norm: Dictionary) -> void:
	for i in 120:
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.player.next_election = 9999.0
		world.tick_day()
