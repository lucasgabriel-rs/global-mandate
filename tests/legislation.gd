extends SceneTree
## Núcleo do sistema de legislação: compilador, motor, simulador, tramitação, Constituição e efeitos.
## Uso: godot --headless --path . --script tests/legislation.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FALHA: ", what)


func _has_error(result: Dictionary, part: String) -> bool:
	for e: Dictionary in result.errors:
		if String(e.text).contains(part):
			return true
	return false


func _program_with(event: String, build: Callable) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, event), Vector2.ZERO)
	build.call(program, stack.blocks)
	return program


func _add(program: Dictionary, list: Array, type: String, fields := {}) -> Dictionary:
	var block := LawProgram.new_block(program, type)
	for key: String in fields:
		block.fields[key] = fields[key]
	list.append(block)
	return block


func _advance(world: GameWorld, days: int) -> void:
	for i in days:
		world.player.next_election = 9999.0
		world.tick_day()


func _settle(world: GameWorld, norm: Dictionary, limit := 200) -> void:
	for i in limit:
		world.player.next_election = 9999.0
		if not norm.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING, Legislation.STATE_PUBLISHED]:
			return
		world.tick_day()


func _init() -> void:
	_catalog()
	_compiler()
	_engine()
	var world := GameWorld.new()
	world.setup()
	world.set_player(world.by_iso["BRA"], "normal")
	world.leader = Character.random(world.rng)
	_simulator(world)
	_tramitation(world)
	_constitution(world)
	_effects(world)
	_save(world)
	_taxes_and_funds()
	_houses()
	_new_articles()
	_negotiation()
	_central_bank()
	_party_ideas()
	_opposition(world)
	print("RESULTADO: %d falhas" % failures)
	quit()


func _catalog() -> void:
	var seen := {}
	for def: Dictionary in LawCatalog.BLOCKS:
		seen[def.id] = true
		_check(not LawCatalog.category(def.cat).is_empty(), "%s tem categoria" % def.id) if LawCatalog.category(def.cat).is_empty() else null
		for seg: Dictionary in LawCatalog.segments(def):
			if seg.has("field") and not def.get("fields", {}).has(seg.field):
				_check(false, "%s cita o campo %s" % [def.id, seg.field])
	_check(LawCatalog.BLOCKS.size() >= 80, "biblioteca com %d blocos" % LawCatalog.BLOCKS.size())
	for template: Dictionary in LawTemplates.all():
		var result := LawCompiler.compile(template.build.call(), {"rank": 60})
		_check(result.ok, "modelo %s compila: %s" % [template.id, str(result.errors)])


func _compiler() -> void:
	var r := LawCompiler.compile(LawProgram.empty())
	_check(not r.ok, "norma vazia é rejeitada")
	var program := LawProgram.empty()
	LawProgram.add_stack(program, LawProgram.new_block(program, "ec_charge"), Vector2.ZERO)
	r = LawCompiler.compile(program)
	_check(_has_error(r, "solto"), "bloco solto é erro de conexão")
	program = _program_with("ev_month", func(p, list): _add(p, list, "nao_existe"))
	r = LawCompiler.compile(program)
	_check(_has_error(r, "inexistente"), "bloco inexistente é rejeitado")
	program = _program_with("ev_month", func(p, list): _add(p, list, "ec_charge", {"amount": -5}))
	r = LawCompiler.compile(program)
	_check(_has_error(r, "negativo"), "valor negativo é operação impossível")
	program = _program_with("ev_month", func(p, list): _add(p, list, "ec_charge", {"name": ""}))
	r = LawCompiler.compile(program)
	_check(_has_error(r, "ausente"), "parâmetro vazio é ausente")
	program = _program_with("ev_month", func(p, list): _add(p, list, "fl_break"))
	r = LawCompiler.compile(program)
	_check(_has_error(r, "Interromper"), "interromper fora de repetição é fluxo inválido")
	program = _program_with("ev_month", func(p, list):
		var s := _add(p, list, "var_change", {"name": "x"}))
	r = LawCompiler.compile(program)
	_check(_has_error(r, "não inicializada"), "variável nunca definida")
	program = _program_with("ev_month", func(p, list):
		var i := _add(p, list, "fl_if")
		var both := LawProgram.new_block(p, "op_and")
		var a := LawProgram.new_block(p, "cd_owner")
		var no := LawProgram.new_block(p, "op_not")
		no.plugs.a = LawProgram.new_block(p, "cd_owner")
		both.plugs.a = a
		both.plugs.b = no
		i.plugs.cond = both
		_add(p, i.slots.do, "fl_end"))
	r = LawCompiler.compile(program)
	_check(_has_error(r, "contraditória"), "A e não A é condição contraditória")
	program = _program_with("ev_month", func(p, list):
		var v := _add(p, list, "var_set", {"name": "x", "value": 1})
		var div := LawProgram.new_block(p, "m_div")
		div.fields.a = 1
		div.fields.b = 0
		v.plugs.value = div)
	r = LawCompiler.compile(program)
	_check(_has_error(r, "divisão por zero"), "divisão por zero é operação impossível")
	program = _program_with("ev_month", func(p, list): _add(p, list, "ec_charge"))
	r = LawCompiler.compile(program, {"rank": 40})
	_check(_has_error(r, "não autorizada"), "decreto não cria tributo")
	r = LawCompiler.compile(program, {"rank": 60})
	_check(r.ok, "lei pode criar tributo")
	# Encaixe só aceita o tipo certo.
	var check := LawProgram.new_block(program, "fl_if")
	_check(not LawProgram.accepts(LawCatalog.get_def("fl_if").fields.cond, LawProgram.new_block(program, "sb_age")), "número não entra em condição")
	_check(LawProgram.accepts(LawCatalog.get_def("fl_if").fields.cond, LawProgram.new_block(program, "cd_owner")), "condição entra em condição")
	_check(not LawProgram.accepts(LawCatalog.get_def("ec_charge").fields.name, LawProgram.new_block(program, "sb_age")), "número não entra em texto")
	check.clear()


func _view() -> Dictionary:
	return {"subject": {"age": 30.0, "money": 1000.0, "income": 12000.0, "value": 100000.0, "tx": 500.0}, "count": 10.0, "game": {"inflation": 12.0}, "owner_share": 0.5, "inequality": 0.4, "date": "2025-06-01", "professions": {"agro": 0.25}, "unit_shares": {7: 0.5, 8: 0.5}, "licenses": {}, "institutions": {}, "norms_in_force": {}, "exemptions": {}, "caps": {}}


func _run_code(program: Dictionary, individual := false) -> Dictionary:
	var compiled := LawCompiler.compile(program, {"rank": 100})
	_check(compiled.ok, "programa de teste compila: %s" % str(compiled.errors)) if not compiled.ok else null
	var engine := LawEngine.new()
	engine.view = _view()
	engine.individual = individual
	return engine.run(compiled.code[compiled.code.keys()[0]].code)


func _engine() -> void:
	# Peso em agregado: 25% do grupo trabalha na agropecuária.
	var program := _program_with("ev_month", func(p, list):
		var i := _add(p, list, "fl_ifelse")
		i.plugs.cond = LawProgram.new_block(p, "cd_profession")
		i.plugs.cond.fields.profession = "agro"
		_add(p, i.slots.do, "ec_charge", {"name": "A", "amount": 100})
		_add(p, i.slots["else"], "ec_charge", {"name": "B", "amount": 10}))
	var r := _run_code(program)
	_check(r.ok and r.effects.size() == 2, "os dois ramos rodam em agregado")
	_check(is_equal_approx(r.effects[0].weight, 0.25) and is_equal_approx(r.effects[1].weight, 0.75), "cada ramo tem o peso da fração")
	# Comparação sobre o cidadão vale a fração, e não a média.
	var old := _program_with("ev_month", func(p, list):
		var i := _add(p, list, "fl_if")
		var cmp := LawProgram.new_block(p, "op_ge")
		cmp.plugs.a = LawProgram.new_block(p, "sb_age")
		cmp.fields.b = 60
		i.plugs.cond = cmp
		_add(p, i.slots.do, "ac_benefit", {"amount": 50}))
	r = _run_code(old)
	_check(r.effects.size() == 1 and r.effects[0].weight > 0.0 and r.effects[0].weight < 0.5, "idosos são parte do grupo: %s" % str(r.effects[0].weight if r.effects.size() else -1))
	r = _run_code(old, true)
	_check(r.effects.is_empty(), "um cidadão de 30 anos não é idoso")
	# Limite de passos em laço sem fim.
	var endless := _program_with("ev_month", func(p, list):
		var w := _add(p, list, "fl_while")
		var c := LawProgram.new_block(p, "op_eq")
		c.fields.a = 1
		c.fields.b = 1
		w.plugs.cond = c
		_add(p, w.slots.do, "ac_register"))
	r = _run_code(endless)
	_check(not r.ok and r.effects.is_empty(), "laço infinito para e não aplica nada")
	# Interromper sai da repetição e restaura o peso.
	var breaking := _program_with("ev_month", func(p, list):
		var rep := _add(p, list, "fl_repeat", {"times": 5})
		var i := _add(p, rep.slots.do, "fl_if")
		i.plugs.cond = LawProgram.new_block(p, "cd_owner")
		_add(p, i.slots.do, "fl_break")
		_add(p, list, "ac_register"))
	r = _run_code(breaking)
	_check(r.ok and r.effects.size() == 1 and is_equal_approx(r.effects[0].weight, 1.0), "interromper dentro de um se restaura o peso")
	# Mesma entrada, mesmo resultado.
	var a := _run_code(program)
	var b := _run_code(program)
	_check(var_to_str(a.effects) == var_to_str(b.effects), "execução determinística")
	# Isenção e limite.
	var taxed := _program_with("ev_month", func(p, list): _add(p, list, "ec_charge", {"name": "X", "amount": 1000}))
	var compiled := LawCompiler.compile(taxed, {"rank": 100})
	var engine := LawEngine.new()
	engine.view = _view()
	engine.view.exemptions = {"X": 0.5}
	engine.view.caps = {"X": 400.0}
	var capped := engine.run(compiled.code[compiled.code.keys()[0]].code)
	_check(is_equal_approx(capped.effects[0].values.amount, 200.0), "limite e isenção valem na cobrança")
	# Aguardar devolve uma continuação.
	var waits := _program_with("ev_month", func(p, list):
		_add(p, list, "fl_wait", {"days": 10})
		_add(p, list, "ac_register"))
	r = _run_code(waits)
	_check(r.waiting.get("days", 0) == 10 and r.effects.is_empty(), "aguardar para a execução")


func _simulator(world: GameWorld) -> void:
	var before := world.player.law_rev_bucket
	var obligations: int = world.legislation.obligations.size()
	var citizen := {"age": 40.0, "money": 5000.0, "income": 20000.0, "value": 100000.0, "tx": 100.0, "owner": true, "profession": "servicos", "licenses": []}
	var result: Dictionary = world.legislation.simulate(world, LawTemplates.property_tax(), "ordinaria", "", citizen)
	var text := "\n".join(result.trace)
	print(text)
	_check(result.ok, "simulador roda o exemplo do documento")
	_check(text.contains("100.000,00") or text.contains("100000,00"), "mostra o valor tributável")
	_check(text.contains("5%") or text.contains("5,00%"), "mostra a alíquota")
	_check(text.contains("5000,00"), "mostra o imposto calculado")
	_check(text.contains("Obrigação tributária criada"), "mostra a obrigação criada")
	_check(world.player.law_rev_bucket == before and world.legislation.obligations.size() == obligations, "teste não cobra nada de verdade")


func _tramitation(world: GameWorld) -> void:
	var leg: Legislation = world.legislation
	var norm: Dictionary = leg.new_norm(world, "ordinaria")
	norm.program = LawTemplates.minimum_wage()
	var r: Dictionary = leg.present(world, norm)
	_check(not r.ok, "sem título não apresenta")
	norm.title = "Salário mínimo"
	norm.ementa = "Teste"
	r = leg.present(world, norm)
	_check(r.ok and norm.state == Legislation.STATE_PROCESS, "lei entra em tramitação")
	_check(not leg.standing.minwage.has("valor"), "antes da vigência a norma não vale")
	_settle(world, norm)
	print("  estado: ", norm.state, " votos: ", norm.votes.map(func(v): return "%d/%d" % [v.yes, v.needed]))
	_check(norm.process.log.size() >= 4, "cada etapa ficou registrada: %d" % norm.process.log.size())
	if norm.state == Legislation.STATE_IN_FORCE:
		_check(leg.standing.minwage.has("valor"), "em vigor, o salário mínimo vale")
		_check(not norm.versions.is_empty() and norm.versions[0].hash == hash(var_to_str(norm.versions[0].program)), "versão publicada guardada")
		# Vacância: publicada não é em vigor.
	var delayed: Dictionary = leg.new_norm(world, "decreto")
	delayed.title = "Decreto"
	delayed.ementa = "Teste de vacância"
	delayed.vacatio = 30
	delayed.program = _program_with("ev_enact", func(p, list): _add(p, list, "ac_expense", {"amount": 1}))
	r = leg.present(world, delayed)
	_check(r.ok, "decreto apresentado")
	_advance(world, 3)
	_check(delayed.state == Legislation.STATE_PUBLISHED, "publicada e ainda não em vigor: %s" % delayed.state)
	_advance(world, 30)
	_check(delayed.state == Legislation.STATE_IN_FORCE, "vigor depois da vacância")
	# Alteração gera nova versão e preserva a antiga.
	var changed: Dictionary = leg.start_change(world, delayed)
	changed.program.stacks[0].blocks[1].fields.amount = 2
	r = leg.present(world, changed)
	_check(r.ok, "alteração apresentada")
	_advance(world, 5)
	_check(delayed.versions.size() == 2 and delayed.current_v == 1, "alteração criou a versão 2")
	_check(float(delayed.versions[0].program.stacks[0].blocks[1].fields.amount) == 1.0, "a versão antiga não mudou")
	# Revogação parcial e integral.
	var multi: Dictionary = leg.new_norm(world, "decreto")
	multi.title = "Dois artigos"
	multi.ementa = "Teste"
	multi.program = _program_with("ev_enact", func(p, list): _add(p, list, "rg_require", {"name": "Registro"}))
	LawProgram.add_stack(multi.program, LawProgram.new_block(multi.program, "ev_enact"), Vector2(0, 100))
	multi.program.stacks[1].blocks.append(LawProgram.new_block(multi.program, "rg_require"))
	multi.program.stacks[1].blocks[1].fields.name = "Outro"
	leg.present(world, multi)
	_advance(world, 3)
	_check(leg.standing.requirements.has("Registro"), "requisito em vigor")
	_force_majority(world)
	var partial: Dictionary = leg.start_revocation(world, multi, [1])
	partial.type = "decreto"
	leg.present(world, partial)
	_settle(world, partial)
	_check(multi.state == Legislation.STATE_IN_FORCE and multi.versions.size() == 2 and multi.versions[1].program.stacks[0].repealed, "revogação parcial marca o artigo")
	var full: Dictionary = leg.start_revocation(world, multi, [])
	leg.present(world, full)
	_settle(world, full)
	_check(multi.state == Legislation.STATE_REVOKED, "revogação integral")
	_check(leg.standing.requirements.is_empty(), "norma revogada para de produzir efeitos")
	# Decreto não pode conter tributo nem revogar lei.
	var bad: Dictionary = leg.new_norm(world, "decreto")
	bad.title = "Inválido"
	bad.ementa = "Teste"
	bad.program = _program_with("ev_month", func(p, list): _add(p, list, "ec_charge"))
	r = leg.present(world, bad)
	_check(not r.ok, "compilador impede publicar além da competência")
	# Conflito só avisa.
	var first: Dictionary = leg.new_norm(world, "decreto")
	first.title = "Parâmetro"
	first.ementa = "A"
	first.program = _program_with("ev_enact", func(p, list): _add(p, list, "ac_param", {"field": "mobilization", "value": 0}))
	leg.present(world, first)
	_advance(world, 3)
	var second: Dictionary = leg.new_norm(world, "decreto")
	second.program = _program_with("ev_enact", func(p, list): _add(p, list, "ac_param", {"field": "mobilization", "value": 0}))
	var compiled: Dictionary = leg.compile_norm(second)
	_check(compiled.ok and not compiled.warnings.is_empty(), "conflito vira aviso, não erro")
	# Norma que falha é suspensa sem quebrar o jogo.
	var fragile: Dictionary = leg.new_norm(world, "decreto")
	fragile.title = "Frágil"
	fragile.ementa = "Divide por zero em execução"
	fragile.program = _program_with("ev_month", func(p, list):
		var v := _add(p, list, "var_set", {"name": "x", "value": 0})
		var s := _add(p, list, "var_set", {"name": "y", "value": 0})
		var div := LawProgram.new_block(p, "m_div")
		div.fields.a = 1
		div.plugs.b = LawProgram.new_block(p, "var_get")
		div.plugs.b.fields.name = "x"
		s.plugs.value = div
		v.fields.value = 0)
	r = leg.present(world, fragile)
	_check(r.ok, "norma frágil apresentada")
	_advance(world, 110)
	_check(fragile.state == Legislation.STATE_SUSPENDED, "falhas repetidas suspendem a norma: %s" % fragile.state)
	# IA apresenta projeto, e o chefe de governo sanciona ou veta.
	var ai: Dictionary = leg.new_norm(world, "ordinaria", "Deputado Teste")
	ai.by_player = false
	ai.title = "Projeto da IA"
	ai.ementa = "Teste"
	ai.program = LawTemplates.strike_right()
	leg.present(world, ai)
	var data: Dictionary = world.politics.data_of("BRA")
	for p: Dictionary in data.parties:
		p.econ = 0.0
		p.social = 0.5
	for i in 120:
		world.player.next_election = 9999.0
		world.tick_day()
		if ai.process.get("waiting_player", false) or ai.state != Legislation.STATE_PROCESS:
			break
	print("  IA: ", ai.state, " ", ai.process.log.back().result if not ai.process.log.is_empty() else "")
	if ai.process.get("waiting_player", false):
		r = leg.sanction(world, ai, false)
		_check(r.ok and not ai.process.get("waiting_player", false), "veto registrado")
		_check("override" in ai.process.steps, "veto vai a análise do parlamento")
		_settle(world, ai)
		_check(ai.votes.size() >= 2, "parlamento votou o veto")
	else:
		_check(ai.state != Legislation.STATE_PROCESS, "projeto da IA seguiu o rito: %s" % ai.state)
	_check(leg.audit.size() > 10, "auditoria registra as operações: %d" % leg.audit.size())


func _constitution(world: GameWorld) -> void:
	var leg: Legislation = world.legislation
	var mandate := {}
	for a: Dictionary in leg.constitution.articles:
		if a.param == "mandate":
			mandate = a
	var old_text: String = mandate.text
	_check(old_text.contains("4 anos"), "texto original: %s" % old_text)
	var emenda: Dictionary = leg.new_norm(world, "emenda")
	emenda.title = "Mandato de cinco anos"
	emenda.ementa = "Altera o Art. 4º"
	emenda.ops = [{"op": "alter", "article": mandate.id, "value": 5}]
	var diff := Legislation.word_diff(old_text, leg.preview_op(emenda.ops[0]).after)
	_check(diff.contains("[s]4[/s]") and diff.contains("5"), "comparação mostra a troca: %s" % diff)
	# Cláusula pétrea é barrada.
	var petrea := {}
	for a: Dictionary in leg.constitution.articles:
		if a.petrea:
			petrea = a
	var blocked: Dictionary = leg.new_norm(world, "emenda")
	blocked.ops = [{"op": "suppress", "article": petrea.id}]
	_check(not leg.check_amendment(world, blocked).ok, "cláusula pétrea não pode mudar")
	leg.delete_draft(blocked.id)
	# Tudo a favor, para testar o rito sem depender da composição do parlamento.
	var data: Dictionary = world.politics.data_of("BRA")
	var saved_coalition: Array = data.coalition.duplicate()
	data.coalition = data.parties.map(func(p): return p.id)
	for p: Dictionary in data.parties:
		p.econ = 0.0
		p.social = 0.0
	var r: Dictionary = leg.present(world, emenda)
	_check(r.ok, "emenda apresentada: %s" % r.msg)
	var version: int = leg.constitution.version
	for i in 120:
		world.player.next_election = 9999.0
		world.tick_day()
		if emenda.state == Legislation.STATE_AWAITING:
			_check(leg.constitution.version == version, "aguardando publicação, a Constituição ainda não mudou") if not has_meta("seen") else null
			set_meta("seen", true)
		if not emenda.state in [Legislation.STATE_PROCESS, Legislation.STATE_APPROVED, Legislation.STATE_AWAITING]:
			break
	data.coalition = saved_coalition
	print("  emenda: ", emenda.state, " votos: ", emenda.votes.size())
	_check(emenda.state == Legislation.STATE_IN_FORCE, "emenda promulgada: %s" % emenda.state)
	_check(emenda.votes.size() == 2, "duas votações no rito do Brasil")
	_check(leg.constitution.version == version + 1, "nova versão da Constituição")
	_check(leg.mandate_years() == 5.0, "o mandato passou a ser de cinco anos")
	var original: Dictionary = leg.constitution_version(0)
	var kept := ""
	for a: Dictionary in original.articles:
		if a.param == "mandate":
			kept = a.text
	_check(kept == old_text, "a versão original continua consultável")
	_check(leg.constitution_version(leg.constitution.version).changes[0].before == old_text, "guarda texto anterior e posterior")


func _effects(world: GameWorld) -> void:
	var leg: Legislation = world.legislation
	var c := world.player
	var norm: Dictionary = leg.new_norm(world, "decreto")
	norm.title = "Despesa"
	norm.ementa = "Teste"
	norm.program = _program_with("ev_month", func(p, list): _add(p, list, "ac_expense", {"amount": 12}))
	leg.present(world, norm)
	_advance(world, 3)
	var debt_before: float = c.debt_loc
	var spending_before: float = c.spending
	c.law_spend_bucket = 0.0
	leg.fire(world, "ev_month")
	_check(is_equal_approx(c.law_spend_bucket, 12.0), "despesa entra nas contas do mês: %s" % c.law_spend_bucket)
	Economy.step_month(c, world)
	_check(c.spending > spending_before, "a despesa aumenta o gasto do país")
	_check(c.law_spend_bucket == 0.0, "o mês fecha as contas")
	_check(debt_before != c.debt_loc, "a dívida responde")
	leg.fire(world, "ev_month")
	leg.fire(world, "ev_month")
	_check(c.law_spend_bucket <= 12.0 + 0.001, "o mesmo evento não roda duas vezes no mesmo dia")


func _save(world: GameWorld) -> void:
	var leg: Legislation = world.legislation
	var dict := world.to_dict()
	var bytes := var_to_bytes(dict)
	var back: Dictionary = bytes_to_var(bytes)
	var other := GameWorld.new()
	other.setup()
	other.load_dict(back)
	_check(other.legislation.norms.size() == leg.norms.size(), "normas voltam do save")
	_check(other.legislation.mandate_years() == leg.mandate_years(), "Constituição volta do save")
	_check(other.legislation.audit.size() == leg.audit.size(), "auditoria volta do save")
	# Versão adulterada é detectada.
	var victim := -1
	for id: int in back.legislation.norms:
		var n: Dictionary = back.legislation.norms[id]
		if n.state == Legislation.STATE_IN_FORCE and not n.versions.is_empty() and n.versions[0].hash != 0 and n.versions[0].program.stacks.size() > 0:
			victim = id
			n.versions[0].program.stacks[0].pos = [999.0, 999.0]
			break
	if victim >= 0:
		var third := GameWorld.new()
		third.setup()
		third.load_dict(back)
		_check(third.legislation.norms[victim].state == Legislation.STATE_SUSPENDED, "versão adulterada suspende a norma")
	# Exportar e importar.
	var src: Dictionary = leg.new_norm(world, "ordinaria")
	src.title = "Exportada"
	src.ementa = "Teste"
	src.program = LawTemplates.property_tax()
	var path: String = leg.export_norm(src)
	_check(path != "", "exportou: %s" % path)
	var imported: Dictionary = leg.import_norm(world, path.get_file())
	_check(imported.ok and leg.compile_norm(imported.norm).ok, "importa e compila: %s" % imported.msg)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _opposition(world: GameWorld) -> void:
	var leg: Legislation = world.legislation
	world.start_in_opposition()
	var decree: Dictionary = leg.new_norm(world, "decreto")
	decree.title = "X"
	decree.ementa = "Y"
	decree.program = _program_with("ev_enact", func(p, list): _add(p, list, "ac_register"))
	var r: Dictionary = leg.present(world, decree)
	_check(not r.ok, "oposição não edita decreto")
	_check(leg.can(world, "present", "ordinaria"), "oposição apresenta lei")
	_check(not leg.can(world, "veto"), "oposição não veta")


func _force_majority(world: GameWorld) -> void:
	var data: Dictionary = world.politics.data_of(world.player.iso)
	data.coalition = data.parties.map(func(p): return p.id)
	for p: Dictionary in data.parties:
		p.econ = 0.0
		p.social = 0.0


func _fresh(iso := "BRA") -> GameWorld:
	var world := GameWorld.new()
	world.setup()
	world.set_player(world.by_iso[iso], "normal")
	world.leader = Character.random(world.rng)
	return world


## Tributos só mudam por lei, o parlamento leva tempo e o fundo paga as pesquisas.
func _taxes_and_funds() -> void:
	var world := _fresh()
	var c := world.player
	var leg: Legislation = world.legislation
	var code: Dictionary = {}
	for norm: Dictionary in leg.norms.values():
		if norm.get("base_code", false):
			code = norm
	code = leg.code_norm("tributario")
	_check(code.state == Legislation.STATE_IN_FORCE and code.versions[0].program.stacks[0].blocks.size() > 15, "o país começa com um Código Tributário em blocos")
	var income0 := c.tax_income
	var bill: Dictionary = leg.start_tax_bill(world)
	for block: Dictionary in bill.program.stacks[0].blocks:
		if block.type == "tr_prev":
			block.fields.aliquota = float(block.fields.aliquota) + 4.0
	var cut: Dictionary = leg.start_tax_bill(world)
	for block: Dictionary in cut.program.stacks[0].blocks:
		if block.type == "tr_prev":
			block.fields.aliquota = float(block.fields.aliquota) - 4.0
	_check(float(leg.position_for(world, bill).econ) < float(leg.position_for(world, cut).econ), "subir imposto fica mais à esquerda que cortar")
	_check(leg.popularity_of(world, bill) < leg.popularity_of(world, cut), "subir imposto é menos popular que cortar")
	leg.delete_draft(int(cut.id))
	# Fundo: cada gasto tem o próprio preço, e a pesquisa de popularidade é a mais cara.
	var politics := world.politics
	var fund0 := politics.party_fund(world)
	_check(fund0 > 0.0, "o partido começa com fundo: " + UiKit.millions(fund0))
	var cheap := politics.fund_price(world, "poll_support")
	var dear := politics.fund_price(world, "poll_popularity")
	_check(dear > cheap, "popularidade custa mais que apoios: %s e %s" % [UiKit.millions(dear), UiKit.millions(cheap)])
	for kind: String in Politics.FUND_PRICES:
		if kind != "poll_popularity":
			_check(politics.fund_price(world, kind) < dear, "%s custa menos que a pesquisa de popularidade" % kind)
	var support: Dictionary = leg.poll(world, "poll_support", bill)
	print(support.text)
	_check(support.ok and is_equal_approx(politics.party_fund(world), fund0 - cheap), "pesquisa de apoios desconta só o preço dela")
	_check(String(support.text).contains("Câmara") and String(support.text).contains("Senado"), "os apoios vêm por casa")
	var mood: Dictionary = leg.poll(world, "poll_popularity", bill)
	print(mood.text)
	_check(mood.ok and String(mood.text).contains("Favoráveis") and is_equal_approx(politics.party_fund(world), fund0 - cheap - dear), "pesquisa de popularidade desconta o próprio preço")
	politics.player_party(world).funds = 0.0
	_check(not leg.poll(world, "poll_popularity", bill).ok, "sem fundo não há pesquisa")
	var party_ids := {}
	for party: Dictionary in politics.data_of("BRA").parties:
		party_ids[party.id] = float(party.get("funds", -1.0))
		_check(float(party.get("funds", -1.0)) >= 0.0, "todo partido tem fundo: %s" % party.short) if float(party.get("funds", -1.0)) < 0.0 else null
	_check(party_ids.size() >= 2, "cada partido tem o próprio fundo")
	_advance(world, 40)
	_check(politics.party_fund(world) > 0.0, "o fundo recebe todo mês")
	# Sem deliberação instantânea, em lei, projeto ou orçamento.
	_force_majority(world)
	leg.present(world, bill)
	_check(is_equal_approx(c.tax_income, income0), "apresentar não muda o imposto")
	_advance(world, 10)
	_check(is_equal_approx(c.tax_income, income0) and bill.votes.is_empty(), "dez dias depois ainda não houve votação")
	_settle(world, bill)
	_check(bill.state == Legislation.STATE_IN_FORCE, "a lei tributária termina o rito: " + bill.state)
	_check(bill.votes.size() >= 2, "passou pelas duas casas: %d" % bill.votes.size())
	print("  imposto: ", income0, " -> ", c.tax_income)
	_check(c.tax_income > income0 + 0.015, "em vigor, o imposto muda por lei")


## Uma casa ou duas, conforme a Constituição.
func _houses() -> void:
	var world := _fresh()
	var houses: Array = world.politics.houses(world)
	_check(houses.size() == 2 and houses[0].name == "Câmara" and houses[1].name == "Senado", "o Brasil tem duas casas")
	_check(Politics._count_seats(houses[1].parties) == int(houses[1].total) and int(houses[1].total) < int(houses[0].total), "o senado tem bancada própria e menor")
	var small := _fresh("URY")
	_check(small.politics.houses(small).size() == 1, "país pequeno tem uma casa só")


## A emenda cria e exclui artigos de verdade, inclusive programados com blocos.
func _new_articles() -> void:
	var world := _fresh()
	var leg: Legislation = world.legislation
	_force_majority(world)
	var count: int = leg.constitution.articles.size()
	var veto := {}
	for a: Dictionary in leg.constitution.articles:
		if a.param == "veto":
			veto = a
	var emenda: Dictionary = leg.new_norm(world, "emenda")
	emenda.title = "Reforma"
	emenda.ementa = "Cria e exclui artigos."
	emenda.ops = [{"op": "add", "kind": "artigo", "text": "O ensino básico é gratuito."}, {"op": "suppress", "article": veto.id}, {"op": "replace", "article": _param_article(leg, "mandate").id, "text": "O governo dura {v} anos, salvo guerra."}]
	emenda.program = _program_with("ev_enact", func(p, list): _add(p, list, "rg_grant", {"right": "moradia"}))
	var r: Dictionary = leg.present(world, emenda)
	_check(r.ok, "emenda com artigos novos apresentada: " + str(r.msg))
	_settle(world, emenda)
	_check(emenda.state == Legislation.STATE_IN_FORCE, "emenda promulgada: " + emenda.state)
	_check(leg.constitution.articles.size() == count + 2, "dois artigos a mais, um de texto e um de blocos")
	var added := false
	for a: Dictionary in leg.constitution.articles:
		added = added or String(a.text).contains("ensino básico")
	_check(added, "o artigo novo está no texto")
	_check(veto.get("suppressed", false) and leg.param("veto", true) == false, "excluir o veto acaba com o veto")
	_check(not "sanction" in leg._steps_for({"type": "ordinaria"}), "sem veto, a lei não passa pela sanção")
	_check(_param_article(leg, "mandate").text.contains("salvo guerra"), "substituição muda a redação: " + _param_article(leg, "mandate").text)
	_check(leg.mandate_years() == 4.0, "o valor do artigo continua")
	_check(leg.standing.rights.has("moradia"), "o artigo em blocos executa")
	# Excluir o artigo de blocos desliga o que ele mantinha.
	var block_article := {}
	for a: Dictionary in leg.constitution.articles:
		if a.has("program_norm"):
			block_article = a
	var second: Dictionary = leg.new_norm(world, "emenda")
	second.title = "Retira"
	second.ementa = "Exclui o artigo em blocos."
	second.ops = [{"op": "suppress", "article": block_article.id}]
	leg.present(world, second)
	_settle(world, second)
	_check(not leg.standing.rights.has("moradia"), "excluir o artigo desliga o efeito")


func _param_article(leg: Legislation, key: String) -> Dictionary:
	for a: Dictionary in leg.constitution.articles:
		if a.param == key:
			return a
	return {}


## Negociar vira votos de verdade, para aprovar ou para derrubar.
func _negotiation() -> void:
	var world := _fresh()
	var leg: Legislation = world.legislation
	var politics := world.politics
	var data: Dictionary = politics.data_of("BRA")
	politics.player_party(world).funds = 100000.0
	# Sem acordo, a proposta distante cai.
	var hostile := func() -> Dictionary:
		var norm: Dictionary = leg.new_norm(world, "ordinaria")
		norm.title = "Dura"
		norm.ementa = "Teste"
		norm.program = _program_with("ev_enact", func(p, list): _add(p, list, "rg_restrict", {"name": "X"}))
		for p: Dictionary in data.parties:
			p.econ = 0.0
			p.social = 1.0
		leg.present(world, norm)
		norm.position = {"econ": 0.9, "social": -1.0}
		return norm
	var data_mine: int = int(data.player_party)
	data.coalition = [data.ruling]
	var plain: Dictionary = hostile.call()
	_settle(world, plain)
	_check(plain.state == Legislation.STATE_REJECTED, "sem negociar, a proposta distante cai: " + plain.state)
	# Comprando todas as bancadas, passa.
	var bought: Dictionary = hostile.call()
	_check(leg.can_negotiate(bought), "em tramitação dá para negociar")
	var fund0 := politics.party_fund(world)
	var accepted := 0
	var refused := 0
	for p: Dictionary in data.parties:
		var r: Dictionary = leg.negotiate(world, bought, p.id, true, true)
		_check(r.ok, "negociação responde: " + str(r.msg)) if not r.ok else null
		if r.get("accepted", false):
			accepted += 1
		else:
			refused += 1
	print("  acordos: ", accepted, " recusas: ", refused)
	_check(politics.party_fund(world) <= fund0, "acordo sai do fundo")
	var again: Dictionary = {}
	for p: Dictionary in data.parties:
		if p.id != data_mine:
			again = leg.negotiate(world, bought, p.id, true)
			break
	_check(not again.ok, "o mesmo partido não negocia duas vezes a mesma proposta")
	# Acordo força o voto, a favor e contra.
	var forced: Dictionary = hostile.call()
	forced["deals"] = {}
	for p: Dictionary in data.parties:
		forced.deals[str(p.id)] = true
	_settle(world, forced)
	_check(forced.state == Legislation.STATE_IN_FORCE, "com todas as bancadas no acordo, a proposta passa: " + forced.state)
	var blocked: Dictionary = leg.new_norm(world, "ordinaria", "Deputado")
	blocked.by_player = false
	blocked.title = "Da IA"
	blocked.ementa = "Teste"
	blocked.program = LawTemplates.strike_right()
	for p: Dictionary in data.parties:
		p.econ = 0.0
		p.social = 0.5
	leg.present(world, blocked)
	blocked["deals"] = {}
	for p: Dictionary in data.parties:
		blocked.deals[str(p.id)] = false
	_settle(world, blocked)
	_check(blocked.state == Legislation.STATE_REJECTED, "fechando contra, a proposta da IA cai: " + blocked.state)
	_check(not leg.can_negotiate(blocked), "depois da votação não há o que negociar")
	# Própria bancada segue de graça; cargo põe o partido no governo.
	var free: Dictionary = hostile.call()
	var before := politics.party_fund(world)
	_check(leg.negotiate(world, free, data_mine, false).accepted and is_equal_approx(politics.party_fund(world), before), "a própria bancada segue a orientação de graça")
	var cheap := leg.deal_price(world, data.parties[0], false)
	_check(leg.deal_price(world, data.parties[0], true) > cheap, "oferta generosa custa mais")
	politics.player_party(world).funds = 0.0
	var outside: Dictionary = {}
	for p: Dictionary in data.parties:
		if not p.id in data.coalition and int(p.seats) > 0:
			outside = p
			break
	if not outside.is_empty():
		var broke: Dictionary = hostile.call()
		_check(not leg.negotiate(world, broke, outside.id, true).ok, "sem fundo não há acordo")
		for p: Dictionary in data.parties:
			p.econ = 0.0
			p.social = 0.0
		var r: Dictionary = leg.offer_post(world, broke, outside.id)
		_check(r.ok and (r.accepted == (outside.id in data.coalition)), "oferecer governo: " + str(r.msg))


## Banco central independente decide o juro sozinho, para o jogador e para os outros países.
func _central_bank() -> void:
	var world := _fresh()
	var leg: Legislation = world.legislation
	var c := world.player
	_check(c.cb_independent and leg.param("cb_independent", false) == true, "democracia consolidada tem banco central independente")
	var pure := c.rate
	c.rate_manual = true
	c.rate_set = 0.5
	Economy.step_month(c, world)
	_check(c.rate < 0.4, "mesmo forçado, o juro de banco independente não obedece: %.3f (antes %.3f)" % [c.rate, pure])
	c.rate_manual = false
	# Emenda muda a independência, e o juro manual passa a valer.
	_force_majority(world)
	var emenda: Dictionary = leg.new_norm(world, "emenda")
	emenda.title = "Subordina o banco central"
	emenda.ementa = "Teste"
	emenda.ops = [{"op": "alter", "article": _param_article(leg, "cb_independent").id, "value": false}]
	_check(leg.present(world, emenda).ok, "a emenda é apresentada")
	_settle(world, emenda)
	_check(emenda.state == Legislation.STATE_IN_FORCE and not c.cb_independent, "a Constituição tira a independência: " + emenda.state)
	c.rate_manual = true
	c.rate_set = 0.5
	var r0 := c.rate
	Economy.step_month(c, world)
	_check(c.rate > r0 + 0.1, "sem independência, o governo manda no juro: %.3f" % c.rate)
	# Outros países.
	var free: Country = world.by_iso["DEU"]
	var closed: Country = world.by_iso["CHN"]
	_check(free.cb_independent and not closed.cb_independent, "Alemanha independente, China subordinada")
	free.rate_manual = true
	var leader: Dictionary = world.politics.leader_of(free.iso)
	leader.econ = -1.0
	for i in 200:
		NationAI._central_bank(free, world, NationAI._mind(free, world))
	_check(not free.rate_manual, "líder de esquerda não mexe em banco independente")
	var left: Dictionary = world.politics.leader_of(closed.iso)
	left.econ = -1.0
	var pressed := false
	for i in 400:
		NationAI._central_bank(closed, world, NationAI._mind(closed, world))
		pressed = pressed or closed.rate_manual
	_check(pressed, "em banco subordinado, o líder interfere")
	# Saves antigos ganham o campo e o artigo.
	var old: Dictionary = free.to_dict()
	old.erase("cb_independent")
	old.dem = 2.0
	old.peg = 0
	_check(not Country.from_dict(old).cb_independent, "save antigo calcula a independência")


## Só quem cria partido escolhe bússola; quem entra em outro adota as ideias dele.
func _party_ideas() -> void:
	var world := _fresh()
	var politics := world.politics
	var data: Dictionary = politics.data_of("BRA")
	world.leader.econ = 1.0
	world.leader.social = 1.0
	var other: Dictionary = {}
	for p: Dictionary in data.parties:
		if p.id != int(data.player_party):
			other = p
			break
	var party_econ := float(other.econ)
	_check(politics.join_party(world, other.id, true).ok, "entra em outro partido")
	_check(absf(float(world.leader.econ) - party_econ) < 0.001, "adota as ideias do partido: %.2f e %.2f" % [float(world.leader.econ), party_econ])
	_check(absf(float(other.econ) - party_econ) < 0.001, "entrar não desloca a bússola do partido")
	world.leader.econ = -0.9
	world.leader.social = 0.8
	var founded: Dictionary = politics.found_party(world, "Partido da Bússola", "centro", Color.RED, true)
	_check(founded.ok and float(world.leader.econ) == -0.9, "quem cria o partido mantém as ideias que escolheu")
	_check(float(politics.player_party(world).econ) < 0.0, "a bússola escolhida puxa a do partido novo")
