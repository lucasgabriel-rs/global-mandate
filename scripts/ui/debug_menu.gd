class_name DebugMenu
extends PanelContainer
## Test menu (F12): manually fires any game system, without waiting for the simulation to get there.
## The commands act on the player or on the target country, chosen from the list or by clicking on the map.
## The target may be the player's own country; only what requires another country is disabled in that case.

const ACTIONS := ["mission", "aid", "fta", "arms", "tariff", "denounce", "sanction", "embargo", "covert", "alliance", "peace", "war"]
# i18n-begin
const ACTION_NAMES := ["Missão diplomática", "Enviar ajuda", "Livre comércio", "Vender armas", "Tarifa de 20%", "Condenar", "Sanções", "Embargo total", "Operação secreta", "Pacto de defesa", "Propor paz", "Declarar guerra"]
# i18n-end

const DEBUG_HEADING := preload("res://scenes/ui/rows/debug_heading.tscn")
const DEBUG_GRID := preload("res://scenes/ui/rows/debug_grid.tscn")
const DEBUG_BUTTON := preload("res://scenes/ui/rows/debug_button.tscn")

var main: Node
## [{"section", "label", "fn", "target", "hide"}]: the list is public so the test can go through everything.
var commands: Array = []
var target: Country
var infinite_dp := false

var _rows: Array = []
var _buttons: Array = []

@onready var _options: OptionButton = %options
@onready var _status: Label = %status
@onready var _search: LineEdit = %search
@onready var _body: VBoxContainer = %body

var world: GameWorld:
	get:
		return main.world
var hud: Hud:
	get:
		return main.hud
var map: MapView:
	get:
		return main.map
var pl: Country:
	get:
		return main.world.player


func _ready() -> void:
	%Fechar.pressed.connect(toggle)
	_options.item_selected.connect(func(i: int):
		target = world.countries[_options.get_item_id(i)]
		_refresh_buttons())
	_search.text_changed.connect(_apply_filter)
	_define_commands()
	_build_rows()


func toggle() -> void:
	visible = not visible
	if visible:
		refresh_targets()
	else:
		get_viewport().gui_release_focus()


func refresh_targets() -> void:
	var list: Array = world.countries.filter(func(c): return c.alive and c != pl)
	list.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(b.name) < 0)
	list.push_front(pl)
	_options.clear()
	if target == null or not target.alive or world.by_iso.get(target.iso) != target:
		target = pl
	for i in list.size():
		_options.add_item(tr("%s (você)") % pl.name if list[i] == pl else list[i].name, list[i].idx)
		if list[i] == target:
			_options.select(i)
	_refresh_buttons()


func set_target(c: Country) -> void:
	if c == null or not c.alive:
		return
	target = c
	if visible:
		refresh_targets()


func _refresh_buttons() -> void:
	for i in commands.size():
		if commands[i].target:
			_buttons[i].disabled = target == pl
			_buttons[i].tooltip_text = tr("%s: escolha outro país como alvo.") % commands[i].label if target == pl else tr("%s (usa o país-alvo)") % commands[i].label


func _process(_delta: float) -> void:
	if infinite_dp and main and main.playing and world.player and not world.busy:
		var mine: Dictionary = world.politics.player_party(world)
		if not mine.is_empty():
			mine["funds"] = world.politics.fund_unit(world) * 50.0


# --- Command list -------------------------------------------------------------

func _add(section: String, label: String, fn: Callable, needs_target := false, hide_menu := false) -> void:
	commands.append({"section": section, "label": label, "fn": fn, "target": needs_target, "hide": hide_menu})


func _define_commands() -> void:
	_define_time()
	_define_player()
	_define_economy()
	_define_markets()
	_define_events()
	_define_diplomacy()
	_define_war()
	_define_borders()
	_define_units()
	_define_politics()
	_define_legislation()
	_define_interface()
	_define_endings()


func _define_time() -> void:
	var s := tr("Tempo")
	_add(s, tr("Pausar"), func(): main._set_speed(0))
	_add(s, tr("Velocidade 4x"), func(): main._set_speed(3))
	_add(s, tr("Botão +7 dias"), func(): main.start_skip(7))
	_add(s, tr("Botão +30 dias"), func(): main.start_skip(30))
	_add(s, tr("Avançar 1 dia"), _advance.bind(1))
	_add(s, tr("Avançar 1 mês"), _advance.bind(30))
	_add(s, tr("Avançar 1 ano"), _advance.bind(365))
	_add(s, tr("Avançar 5 anos"), _advance.bind(365 * 5))


func _define_player() -> void:
	var s := tr("Jogador")
	_add(s, tr("Fundo do partido +20 unidades"), func():
		var mine: Dictionary = world.politics.player_party(world)
		mine["funds"] = float(mine.get("funds", 0.0)) + world.politics.fund_unit(world) * 20.0)
	_add(s, tr("Fundo infinito: ligar/desligar"), func():
		infinite_dp = not infinite_dp
		return tr("Fundo infinito %s.") % (tr("ligado") if infinite_dp else tr("desligado")))
	_add(s, tr("Aprovação 90%"), func(): pl.approval = 0.9)
	_add(s, tr("Aprovação 5%"), func(): pl.approval = 0.05)
	_add(s, tr("Estabilidade 90%"), func(): pl.stability = 0.9)
	_add(s, tr("Estabilidade 5%"), func(): pl.stability = 0.05)
	_add(s, tr("Reservas +US$ 500 bi"), func(): pl.reserves += 500.0)
	_add(s, tr("Dívida +50% do PIB"), func(): pl.debt_loc += pl.y_nominal() * 0.5)
	_add(s, tr("Tropas e equipamento x2"), func():
		pl.troops *= 2.0
		pl.mil_stock *= 2.0)
	_add(s, tr("Dar 1.000 ogivas"), func(): pl.nukes += 1000)
	_add(s, tr("Virar democracia"), func(): pl.dem = 8.0)
	_add(s, tr("Virar regime autoritário"), func(): pl.dem = 2.0)
	_add(s, tr("Assumir o país-alvo"), func():
		var speed: int = main.speed
		var next := target
		world.set_player(next, world.difficulty)
		world.diplomacy.update_prod_factors(world)
		main._enter_game()
		main._set_speed(speed)
		target = next
		refresh_targets()
		return tr("Agora você governa %s.") % next.name, true)
	_add(s, tr("Editar personagem"), func(): hud.character_requested.emit())


func _define_economy() -> void:
	var s := tr("Economia")
	for who: String in [tr("Jogador"), tr("Alvo")]:
		var use_target := who == "Alvo"
		var c := func() -> Country: return target if use_target else pl
		_add(s, tr("Crise bancária: ") + who, func(): Economy.banking_crisis(c.call(), world))
		_add(s, tr("Moratória: ") + who, func(): Economy.apply_default(c.call(), world))
		_add(s, tr("Programa do FMI: ") + who, func(): Economy.apply_imf(c.call(), world))
		_add(s, tr("Recessão: ") + who, func(): c.call().demand_shock -= 0.12)
		_add(s, tr("Boom: ") + who, func(): c.call().demand_shock += 0.12)
		_add(s, tr("Inflação +15 p.p.: ") + who, func():
			c.call().pi_core += 0.15
			c.call().pi_e += 0.15)
		_add(s, tr("Bolha de crédito: ") + who, func(): c.call().credit_gap = 0.2)
		_add(s, tr("Troca de governo: ") + who, func(): world.diplomacy.on_government_change(c.call(), world))


func _define_markets() -> void:
	var s := tr("Mercados")
	for i in Markets.NAMES.size():
		_add(s, tr("%s: corte de oferta") % tr(Markets.NAMES[i]), func(): world.markets.shock[i] = 0.3)
		_add(s, tr("%s: excesso de oferta") % tr(Markets.NAMES[i]), func(): world.markets.shock[i] = -0.2)
	_add(s, tr("Fechar/abrir Ormuz"), func():
		world.markets.chokepoint = 0.0 if world.markets.chokepoint > 0.0 else 0.15
		return tr("Ormuz %s.") % (tr("fechado") if world.markets.chokepoint > 0.0 else tr("aberto")))
	_add(s, tr("Aversão a risco 100%"), func(): world.global_risk = 1.0)
	_add(s, tr("Aversão a risco 0%"), func(): world.global_risk = 0.0)
	_add(s, tr("Tensão global 100%"), func(): world.global_tension = 1.0)


func _define_events() -> void:
	var s := tr("Eventos")
	_add(s, tr("Seca"), func(): WorldEvents._drought(world))
	_add(s, tr("Pandemia"), func(): WorldEvents._pandemic(world))
	_add(s, tr("Choque de oferta"), func(): WorldEvents._supply_shock(world))
	_add(s, tr("Onda tecnológica"), func(): WorldEvents._tech_wave(world))
	_add(s, tr("Desastre regional"), func(): WorldEvents._regional_disaster(world))
	_add(s, tr("Protestos em massa"), func(): WorldEvents._mass_protests(world))
	_add(s, tr("Dilema sorteado"), func(): WorldEvents._player_dilemma(world))
	_add(s, tr("Dilema: greve"), func(): WorldEvents._dilemma_strike(world, pl))
	_add(s, tr("Dilema: corrupção"), func(): WorldEvents._dilemma_corruption(world, pl))
	_add(s, tr("Dilema: desastre"), func(): WorldEvents._dilemma_disaster(world, pl))
	_add(s, tr("Dilema: bancos"), func(): WorldEvents._dilemma_bank(world, pl))
	_add(s, tr("Dilema: combustível"), func(): WorldEvents._dilemma_fuel(world, pl))
	_add(s, tr("Dilema: alimentos"), func(): WorldEvents._dilemma_food(world, pl))
	_add(s, tr("Dilema: migrantes"), func(): WorldEvents._dilemma_migrants(world, pl))
	_add(s, tr("Dilema: indústria"), func(): WorldEvents._dilemma_industry(world, pl))
	_add(s, tr("Oferta do FMI"), func(): world.offer_imf(pl))
	_add(s, tr("Oferta de livre comércio"), func(): world.offer_fta(target), true)
	_add(s, tr("Oferta de aliança"), func(): world.offer_alliance(target), true)
	_add(s, tr("Ameaça recebida"), func(): world.receive_threat(target), true)


func _define_diplomacy() -> void:
	var s := tr("Diplomacia")
	for i in ACTIONS.size():
		var act: String = ACTIONS[i]
		_add(s, tr(ACTION_NAMES[i]), func():
			world.action_used.clear()
			var r: Dictionary = world.do_action(act, target)
			return String(r.msg) if String(r.msg) != "" else tr("%s executada.") % tr(ACTION_NAMES[i]), true)
	_add(s, tr("Relação +100"), func(): world.diplomacy.set_relation(pl.idx, target.idx, 100.0), true)
	_add(s, tr("Relação -100"), func(): world.diplomacy.set_relation(pl.idx, target.idx, -100.0), true)
	_add(s, tr("Assinar aliança direto"), func(): world.diplomacy.sign_alliance(pl, target, world), true)
	_add(s, tr("Assinar livre comércio direto"), func(): world.diplomacy.sign_fta(pl, target, world), true)
	_add(s, tr("Tornar Estado-cliente"), func(): world.diplomacy.make_client(pl, target, world), true)
	_add(s, tr("Anexar o alvo"), func(): world.diplomacy.annex(pl, target, world), true)
	_add(s, tr("Alvo: IA escolhe gastos e guerra"), func(): NationAI.step_month(target, world), true)


## Current war with the target. Without a war, the player declares one.
func _war() -> Dictionary:
	var w: Dictionary = world.diplomacy.war_between(pl.idx, target.idx)
	if w.is_empty():
		world.diplomacy.declare_war(pl, target, world)
		w = world.diplomacy.war_between(pl.idx, target.idx)
	return w


func _player_front(w: Dictionary, value: float) -> void:
	w.front = value if pl.idx in w.a else -value


func _define_war() -> void:
	var s := tr("Guerra")
	_add(s, tr("Declarar guerra ao alvo"), func(): _war(), true)
	_add(s, tr("Alvo declara guerra a você"), func():
		if world.diplomacy.war_between(pl.idx, target.idx).is_empty():
			world.diplomacy.declare_war(target, pl, world), true)
	_add(s, tr("Avançar a frente 25%"), func():
		var w := _war()
		w.front = clampf(float(w.front) + (25.0 if pl.idx in w.a else -25.0), -60.0, 96.0), true)
	_add(s, tr("Recuar a frente 25%"), func():
		var w := _war()
		w.front = clampf(float(w.front) - (25.0 if pl.idx in w.a else -25.0), -60.0, 96.0), true)
	_add(s, tr("Alternar postura ofensiva"), func(): pl.stance_offensive = not pl.stance_offensive)
	_add(s, tr("Vitória por capitulação"), func(): world.player_won_war(_war(), target), true)
	_add(s, tr("Vitória: expulsar invasor"), func():
		if world.diplomacy.war_between(pl.idx, target.idx).is_empty():
			world.diplomacy.declare_war(target, pl, world)
		world.player_repelled(world.diplomacy.war_between(pl.idx, target.idx), target), true)
	_add(s, tr("Paz com você vencendo"), func():
		target.war_exhaustion = 1.0
		var w := _war()
		_player_front(w, 40.0)
		return String(world._propose_peace(target).msg), true)
	_add(s, tr("Paz sem vencedor"), func():
		target.war_exhaustion = 1.0
		var w := _war()
		_player_front(w, 1.0)
		return String(world._propose_peace(target).msg), true)
	_add(s, tr("Paz com você perdendo"), func():
		var w := _war()
		_player_front(w, -40.0)
		world.diplomacy.end_war_by_player(w, target, pl, world, 0.15, tr("Paz assinada: %s cede {pct} do território a %s.") % [pl.name, target.name]), true)
	_add(s, tr("Guerra entre o alvo e um vizinho"), func():
		var other := _neighbor_of(target)
		if other == null:
			return tr("O alvo não tem vizinho disponível.")
		world.diplomacy.declare_war(target, other, world), true)
	_add(s, tr("Alvo ataca aliado seu"), func():
		var other := _neighbor_of(target)
		if other == null:
			return tr("O alvo não tem vizinho disponível.")
		world.diplomacy.sign_alliance(pl, other, world)
		world.diplomacy.declare_war(target, other, world), true)
	_add(s, tr("Tratado entre IAs: cede 20%"), func():
		var other := _neighbor_of(target)
		if other == null:
			return tr("O alvo não tem vizinho disponível.")
		var w := world.diplomacy.declare_war(other, target, world)
		world.diplomacy._end_war(w, world, tr("Tratado de paz: %s cede {pct} do território a %s.") % [target.name, other.name], other, target, 0.2), true)
	_add(s, tr("Capitulação entre IAs"), func():
		var other := _neighbor_of(target)
		if other == null:
			return tr("O alvo não tem vizinho disponível.")
		var w := world.diplomacy.declare_war(other, target, world)
		world.diplomacy._capitulation(w, other, target, world), true)


func _neighbor_of(c: Country) -> Country:
	var best: Country = null
	var dist := INF
	for o: Country in world.countries:
		if o == c or o == pl or not o.alive or world.diplomacy.in_war(o.idx):
			continue
		var d := c.center.distance_squared_to(o.center)
		if d < dist:
			dist = d
			best = o
	return best


func _define_borders() -> void:
	var s := tr("Fronteiras")
	_add(s, tr("Demarcar conquistas"), func():
		hud.begin_demarcation({"kind": "victory", "war": _war(), "rival": target, "budget": 0.9}), true, true)
	_add(s, tr("Negociar fronteiras"), func():
		hud.begin_demarcation({"kind": "negotiation", "war": _war(), "rival": target, "budget": 1.0}), true, true)
	_add(s, tr("Ganhar 10% do alvo"), func(): return _cede(target, pl), true)
	_add(s, tr("Perder 10% para o alvo"), func(): return _cede(pl, target), true)


func _cede(from: Country, to: Country) -> String:
	var share := world.territories.auto_cede(from, to, 0.1, world)
	if share <= 0.0:
		return tr("%s não tem unidade pequena o bastante para ceder 10%%.") % from.name
	world.diplomacy.transfer(from, to, share, world)
	return tr("%s cedeu %s do território a %s.") % [from.name, UiKit.pct(share), to.name]


func _define_units() -> void:
	var s := tr("Unidades")
	_add(s, tr("Abrir a aba Divisões"), func(): hud._desk.current_tab = hud._divisions_tab)
	_add(s, tr("Desenhar no país"), func():
		hud._divisions.select_unit(-1)
		hud.start_drawing())
	_add(s, tr("Desenhar dentro de uma unidade"), func():
		if not _select_first_unit():
			return tr("Seu país não tem unidades.")
		hud.start_drawing())
	_add(s, tr("Modo de fusão"), func():
		if not _select_first_unit():
			return tr("Seu país não tem unidades.")
		hud._divisions.start_merge())
	_add(s, tr("Modo de desmembramento"), func():
		if not _select_first_unit():
			return tr("Seu país não tem unidades.")
		hud._divisions.start_split())
	_add(s, tr("Fundir duas vizinhas agora"), _merge_neighbors)
	_add(s, tr("Primeira unidade vira capital do país"), func():
		var roots := world.subdivisions.roots_of(pl.iso)
		if roots.is_empty():
			return tr("Seu país não tem unidades.")
		world.subdivisions.set_capital(pl.iso, roots[0])
		return tr("%s agora é a capital de %s.") % [world.subdivisions.units[roots[0]].name, pl.name])
	_add(s, tr("Remover a capital do país"), func(): world.subdivisions.clear_capital(pl.iso))
	_add(s, tr("Apagar a primeira unidade"), func():
		var roots := world.subdivisions.roots_of(pl.iso)
		if roots.is_empty():
			return tr("Seu país não tem unidades.")
		world.subdivisions.delete_unit(roots[0])
		hud._divisions.select_unit(-1))


func _select_first_unit() -> bool:
	hud._desk.current_tab = hud._divisions_tab
	if map.drawing:
		map.cancel_draft()
	var roots := world.subdivisions.roots_of(pl.iso)
	if roots.is_empty():
		return false
	hud._divisions.select_unit(roots[0])
	return true


func _merge_neighbors() -> String:
	var subs := world.subdivisions
	var roots := subs.roots_of(pl.iso)
	for i in roots.size():
		for j in range(i + 1, roots.size()):
			if Subdivisions._touching(subs.units[roots[i]], subs.units[roots[j]]):
				var names := "%s e %s" % [subs.units[roots[i]].name, subs.units[roots[j]].name]
				var r := subs.merge_units([roots[i], roots[j]])
				hud._divisions.select_unit(r.get("id", -1))
				return tr("%s fundidas.") % names if r.ok else String(r.msg)
	return tr("Nenhuma dupla de unidades vizinhas.")


func _define_politics() -> void:
	var s := tr("Política")
	_add(s, tr("Abrir a aba Política"), func(): hud._desk.current_tab = hud._politics_tab)
	_add(s, tr("Escolher partido"), func(): hud.party_requested.emit())
	_add(s, tr("Entrar no menor partido"), func():
		var data := world.politics.data_of(pl.iso)
		var smallest: Dictionary = data.parties[0]
		for p: Dictionary in data.parties:
			if float(p.support) < float(smallest.support):
				smallest = p
		return String(world.politics.join_party(world, smallest.id).get("msg", "")))
	_add(s, tr("Fundar partido de teste"), func():
		return String(world.politics.found_party(world, tr("Partido Teste %d") % world.months_elapsed, "centro", Color.DEEP_PINK).get("msg", "")))
	for b: Dictionary in Politics.BILLS:
		_add(s, tr("Votar: ") + String(b.name), func():
			world.politics.data_of(pl.iso).bills_used.erase(b.id)
			return String(world.politics.vote(world, b.id).get("msg", "")))
	_add(s, tr("Propor +1 p.p. em renda"), func():
		world.politics.set_budget(world, "sp_social", minf(pl.sp_social + 0.01, 0.3)))
	_add(s, tr("Propor -1 p.p. em previdência"), func():
		world.politics.set_budget(world, "sp_social", maxf(pl.sp_social - 0.01, 0.0)))
	_add(s, tr("Oposição: criticar"), func():
		return String(world.politics.criticize(world).msg))
	_add(s, tr("Oposição: campanha"), func():
		return String(world.politics.campaign(world).msg))
	_add(s, tr("Oposição: moção de censura"), func():
		return String(world.politics.censure(world).msg))
	_add(s, tr("Refazer o gabinete"), func(): world.politics.auto_cabinet(world))
	_add(s, tr("Abrir a aba Ministros"), func(): hud._desk.current_tab = hud._cabinet_tab)
	_add(s, tr("Abrir o primeiro partido"), func(): main._open_party_detail(int(world.politics.data_of(pl.iso).parties[0].id)))
	_add(s, tr("Conversar com o alvo"), func():
		world.talks.erase(target.iso)
		main._open_talk(target), true)


func _define_legislation() -> void:
	var life := tr("Vida")
	_add(life, tr("Fazer o jogador adoecer"), func(): People._player_falls_ill(world, world.leader))
	_add(life, tr("Avançar a idade em 20 anos"), func(): world.leader["birth_year"] = int(world.leader.get("birth_year", world.year - 50)) - 20)
	_add(life, tr("Renunciar"), func(): world.resign())
	_add(life, tr("Assassinato do jogador"), func(): world._finish("assassinato", tr("Um atentado encerrou seu governo.")))
	_add(life, tr("Líder do alvo morre"), func():
		var data: Dictionary = world.politics.data_of(target.iso)
		var party: Dictionary = world.politics.ruling_party(target.iso)
		People.remove_member(world, target, data, party, party.members[0], tr("Teste: morre o líder")), true)
	_add(life, tr("Eleição no alvo"), func(): Economy._ai_election(target, world), true)
	_add(life, tr("Líder do alvo pede conversa"), func():
		world.next_talk_month = 0
		world.request_talk(target), true)
	var s := tr("Legislação")
	_add(s, tr("Abrir o centro legislativo"), func(): main.open_legislation())
	_add(s, tr("Colocar um modelo em vigor por decreto"), func():
		var leg: Legislation = world.legislation
		var norm: Dictionary = leg.new_norm(world, "decreto")
		norm.title = tr("Decreto de teste")
		norm.ementa = tr("Teste do menu debug.")
		var program := LawProgram.empty()
		var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_month"), Vector2(30, 30))
		stack.blocks.append(LawProgram.new_block(program, "ac_expense"))
		norm.program = program
		return String(leg.present(world, norm).msg))
	_add(s, tr("Disparar o evento mensal das normas"), func(): world.legislation.fire(world, "ev_month"))
	_add(s, tr("Projeto da IA agora"), func():
		var leg: Legislation = world.legislation
		var norm: Dictionary = leg.new_norm(world, "ordinaria", tr("Deputado de teste"))
		norm.by_player = false
		norm.title = tr("Projeto de teste")
		norm.ementa = tr("Teste do menu debug.")
		norm.program = LawTemplates.strike_right()
		return String(leg.present(world, norm).msg))


func _define_interface() -> void:
	var s := tr("Interface")
	for key: String in MapView.MODES:
		_add(s, tr("Mapa: %s") % tr(MapView.MODES[key][0]), func(): hud._on_mode(key))
	for i in 9:
		_add(s, tr("Aba %d do painel") % (i + 1), func(): hud._desk.current_tab = i)
	_add(s, tr("Centralizar no alvo"), func():
		map.focus_on(target)
		map.select(target)
		hud.show_country(target))
	_add(s, tr("Salvar partida"), func(): main._save_game())
	_add(s, tr("Carregar partida"), func():
		if not FileAccess.file_exists(main.SAVE_PATH):
			return tr("Ainda não há partida salva.")
		main._load_game())
	_add(s, tr("Abrir o menu de pausa"), func(): main._open_menu())
	_add(s, tr("Abrir a ajuda"), func(): main._show_help())
	_add(s, tr("Abrir o criador de personagem"), func(): main._open_creator(Character.random(world.rng, world.player.iso, world.player.region), func(ch):
		world.leader = ch
		hud.refresh_leader()))


func _define_endings() -> void:
	var s := tr("Fim de jogo")
	_add(s, tr("Eleição agora"), func():
		pl.dem = maxf(pl.dem, 6.0)
		world._player_election(pl))
	_add(s, tr("Perder a eleição"), func():
		world.enter_opposition(tr("%s assume. Oposição forçada pelo menu debug.") % world.politics.hand_over(pl).name, tr("Derrotado nas urnas")))
	_add(s, tr("Voltar ao governo"), func():
		var data := world.politics.data_of(pl.iso)
		data.ruling = data.player_party
		world.politics.form_coalition(data)
		world.in_office = true
		world.politics.auto_cabinet(world))
	_add(s, tr("Golpe de Estado"), func():
		world._finish("golpe", tr("Generais e a elite política perderam a paciência. Um golpe encerrou seu governo.")))
	_add(s, tr("Revolução"), func():
		world._finish("golpe", tr("Multidões tomaram o palácio. Seu regime caiu.")))
	_add(s, tr("Ataque nuclear"), func():
		var w := _war()
		target.nukes = maxi(target.nukes, 100)
		_player_front(w, 75.0)
		var att: Country = world.countries[w.main_a]
		var def: Country = world.countries[w.main_d]
		if target == att:
			w.front = -40.0
		world.nuclear_check(w, att, def, true), true)
	_add(s, tr("Derrota militar"), func():
		world.player_lost_war(target), true)
	_add(s, tr("Voltar à tela inicial"), func(): main._restart())


# --- Execution ----------------------------------------------------------------------

func _advance(days: int) -> String:
	var done := 0
	for i in days:
		if world.over or not main.prompts.is_empty():
			break
		world.tick_day()
		done += 1
	if done < days and not world.over:
		return tr("Avançou %d de %d dias: há uma decisão esperando.") % [done, days]
	return tr("Avançou %d dias.") % done


## Executes a command by index and shows the result. Public so the test can call it.
func run(index: int) -> void:
	var cmd: Dictionary = commands[index]
	if target == null or not target.alive or world.by_iso.get(target.iso) != target:
		refresh_targets()
	if cmd.target and target == pl:
		_status.text = tr("%s precisa de outro país: escolha um alvo.") % cmd.label
		_status.add_theme_color_override("font_color", UiKit.RED)
		return
	var result: Variant = cmd.fn.call()
	var text: String = str(result) if result is String and result != "" else tr("%s: feito.") % cmd.label
	_status.text = text
	_status.add_theme_color_override("font_color", UiKit.GREEN)
	print("debug: ", cmd.label, " -> ", text)
	if cmd.hide:
		visible = false
	if main.playing:
		if visible:
			refresh_targets()
		hud.refresh(true)
		map.refresh_colors()
		map.refresh_units()


func _build_rows() -> void:
	var grid: GridContainer = null
	var section := ""
	for i in commands.size():
		var cmd: Dictionary = commands[i]
		if cmd.section != section:
			section = cmd.section
			var title: Label = DEBUG_HEADING.instantiate()
			title.text = section.to_upper()
			_body.add_child(title)
			grid = DEBUG_GRID.instantiate()
			_body.add_child(grid)
			_rows.append({"title": title, "grid": grid, "buttons": []})
		var b: Button = DEBUG_BUTTON.instantiate()
		b.text = cmd.label
		b.tooltip_text = cmd.label + (tr(" (usa o país-alvo)") if cmd.target else "")
		b.pressed.connect(run.bind(i))
		if cmd.section == "Fim de jogo":
			b.add_theme_color_override("font_color", UiKit.RED)
		grid.add_child(b)
		_rows[-1].buttons.append(b)
		_buttons.append(b)


func _apply_filter(text: String) -> void:
	var query := text.strip_edges().to_lower()
	for row: Dictionary in _rows:
		var any := false
		for b: Button in row.buttons:
			b.visible = query == "" or b.text.to_lower().contains(query)
			any = any or b.visible
		row.title.visible = any
		row.grid.visible = any
