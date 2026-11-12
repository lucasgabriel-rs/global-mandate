extends SceneTree
## Testes da corrupção, sem interface: neutralidade sem ações, preço no fundo, escândalo, investigação e save.
## Uso: godot --headless --path . -s tests/corruption.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FALHA: ", what)


func _world(iso := "BRA", seed_value := 7) -> GameWorld:
	var w := GameWorld.new()
	w.setup(seed_value)
	w.set_player(w.by_iso[iso], "normal")
	w.politics.player_party(w).funds = 100000.0
	return w


func _month(w: GameWorld) -> void:
	w._on_month()


func _norm(w: GameWorld) -> Dictionary:
	return {"id": 99, "type": "ordinaria", "number": 1, "year": 2025, "title": "Teste", "state": Legislation.STATE_PROCESS, "process": {"steps": ["vote"], "at": 0}}


func _init() -> void:
	# Neutralidade: sem ações, nada na economia muda e o desvio fica em zero.
	var a := _world()
	var b := _world()
	var c := a.player
	_check(absf(c.corruption - c.corruption0) < 1e-9 and Corruption.drift(c) == 0.0, "desvio começa zero")
	_check(Corruption.risk_extra(c) == 0.0 and Corruption.invest_factor(c) == 1.0 and Corruption.collection_factor(c) == 1.0, "sem ação, nenhum canal da economia mexe")
	for i in 24:
		_month(a)
		_month(b)
	_check(absf(a.player.risk - b.player.risk) < 1e-12 and absf(a.player.y - b.player.y) < 1e-9, "mundos iguais seguem iguais")
	_check(Corruption.drift(a.player) == 0.0 and a.corruption.scandals == 0, "24 meses sem ação: sem desvio, sem escândalo")
	var risk_before := a.player.risk

	# Países: índice de partida coerente com democracia e renda.
	var base := _world("NOR")
	var poor := _world("SDN")
	_check(base.player.corruption0 < poor.player.corruption0, "Noruega menos corrupta que o Sudão (%.2f < %.2f)" % [base.player.corruption0, poor.player.corruption0])

	# Ações custam do fundo e sobem o índice.
	var w := _world()
	var cor := w.corruption
	var pl := w.player
	var fund0 := w.politics.party_fund(w)
	var level0 := pl.corruption
	var r := cor.favor_allies(w)
	_check(r.ok, "favorecer aliados funciona: " + str(r.msg))
	_check(w.politics.party_fund(w) < fund0 and pl.corruption > level0 and cor.heat > 0.0, "ação tira do fundo e sobe índice e exposição")
	_check(not cor.favor_allies(w).ok, "espera entre ações iguais")
	var fund1 := w.politics.party_fund(w)
	r = cor.embezzle(w)
	_check(r.ok and w.politics.party_fund(w) > fund1, "caixa dois enche o fundo")
	r = cor.skim(w)
	_check(r.ok and cor.stash > 0.0 and cor.score_bonus(w) > 0.0, "desvio vai para o patrimônio e conta pontos")
	# Sem dinheiro, não compra.
	var broke := _world()
	broke.politics.player_party(broke).funds = 0.0
	_check(not broke.corruption.favor_allies(broke).ok, "sem fundo não há contrato")
	# O dinheiro do favor volta aos poucos.
	var fund2 := w.politics.party_fund(w)
	_month(w)
	_check(w.politics.party_fund(w) > fund2 - 1000.0 and w.corruption.kickbacks.size() > 0, "devolução dos contratos entra no fundo")

	# Compra de votos.
	var votes := _world()
	var norm := _norm(votes)
	var data: Dictionary = votes.politics.data_of("BRA")
	var other: Dictionary = {}
	for p: Dictionary in data.parties:
		if int(p.id) != int(data.player_party):
			other = p
	var cost := votes.corruption.quote(votes, norm, int(other.id))
	var f0 := votes.politics.party_fund(votes)
	var res := votes.corruption.offer(votes, int(other.id), norm, true)
	_check(res.ok and absf((f0 - votes.politics.party_fund(votes)) - cost) < 1e-6, "compra de voto cobra o preço cotado")
	_check(norm.get("deals", {}).has(str(other.id)) or not res.get("accepted", true), "acordo registrado quando o partido aceita")
	_check(not votes.corruption.offer(votes, int(other.id), norm, true, "favor").ok, "só dinheiro como contrapartida por enquanto")
	var done := _norm(votes)
	done.state = Legislation.STATE_IN_FORCE
	done.process = {}
	_check(not votes.corruption.bribe_votes(votes, done, int(other.id), true).ok, "sem votação pela frente não há o que comprar")

	# Detecção cai com as instituições fracas.
	var dem := _world("NOR")
	var aut := _world("PRK")
	_check(dem.corruption.integrity(dem, dem.player) > aut.corruption.integrity(aut, aut.player), "instituições mais fortes onde há mais democracia")
	dem.corruption.heat = 0.5
	aut.corruption.heat = 0.5
	_check(dem.corruption.scandal_chance(dem, dem.player) > aut.corruption.scandal_chance(aut, aut.player), "o escândalo é mais provável onde a justiça e a imprensa funcionam")
	_check(dem.corruption.bite(dem, dem.player) > aut.corruption.bite(aut, aut.player), "e pesa mais")

	# Escândalo: aprovação, estabilidade, percepção e investigação.
	var s := _world("NOR")
	s.corruption.heat = 1.0
	var p := s.player
	var approval := p.approval
	var stability := p.stability
	var seen := p.corr_seen
	var prompts := []
	s.prompt_requested.connect(func(pr): prompts.append(pr))
	for i in 40:
		_month(s)
		if s.corruption.scandals > 0:
			break
	_check(s.corruption.scandals > 0, "exposição máxima dá escândalo")
	_check(prompts.size() > 0 and prompts[0].options.size() == 3, "o aviso do escândalo chega ao jogador")
	_check(p.approval < approval and p.stability < stability and p.corr_seen > seen, "escândalo custa aprovação e estabilidade e sobe a percepção")
	_check(s.corruption.investigation > 0 or s.over, "escândalo abre investigação")

	# As opções do aviso funcionam, e processo pesado em país livre custa o cargo.
	prompts[0].options[0].fn.call()
	_check(s.corruption.heat == 0.0, "assumir zera a exposição")
	var j := _world("NOR")
	var ended := []
	j.game_ended.connect(func(res): ended.append(res))
	j.corruption.investigation = 1
	j.corruption.case_load = 1.0
	_month(j)
	_check(j.over and ended.size() == 1 and ended[0].reason == "impeachment", "condenação em país livre encerra o mandato")

	# A economia sente o desvio.
	var e := _world()
	e.player.corruption += 0.3
	_check(Corruption.risk_extra(e.player) > 0.0 and Corruption.invest_factor(e.player) < 1.0 and Corruption.collection_factor(e.player) < 1.0, "desvio positivo pesa em risco, investimento e arrecadação")
	_month(e)
	_check(e.player.risk >= risk_before - 0.5, "risco segue calculável")

	# Salvar e carregar.
	var saved := _world()
	saved.corruption.favor_allies(saved)
	saved.corruption.skim(saved)
	saved.corruption.heat = 0.4
	saved.corruption.investigation = 3
	var back := GameWorld.new()
	back.setup(7)
	back.load_dict(bytes_to_var(var_to_bytes(saved.to_dict())))
	_check(absf(back.corruption.heat - 0.4) < 1e-9 and back.corruption.investigation == 3 and back.corruption.stash > 0.0 and back.corruption.kickbacks.size() == 1, "estado da corrupção volta do save")
	_check(absf(back.player.corruption - saved.player.corruption) < 1e-9 and back.corruption.wait_left(back, "favor") > 0, "índice do país e esperas voltam do save")
	var old := saved.to_dict()
	old.erase("corruption")
	var legacy := GameWorld.new()
	legacy.setup(7)
	legacy.load_dict(bytes_to_var(var_to_bytes(old)))
	_check(legacy.corruption.heat == 0.0, "save antigo abre sem corrupção")

	# Janela: abre da cena, lista as ações e usa o fundo.
	var ui := _world()
	var window: CorruptionWindow = (load("res://scenes/ui/modals/corruption.tscn") as PackedScene).instantiate()
	root.add_child(window)
	await process_frame
	window.setup(ui)
	var buttons := window.find_children("act", "Button", true, false)
	_check(buttons.size() == CorruptionWindow.PLAIN.size(), "janela traz uma linha por ação")
	var fund_ui := ui.politics.party_fund(ui)
	(buttons[1] as Button).pressed.emit()
	_check(ui.politics.party_fund(ui) < fund_ui and (window.get_node("%feedback") as Label).text != "", "botão da janela gasta o fundo e responde")
	_check((buttons[1] as Button).disabled, "botão espera o intervalo")
	window.queue_free()

	print("RESULTADO: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
