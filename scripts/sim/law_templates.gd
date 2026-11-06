class_name LawTemplates
extends RefCounted
## Modelos prontos: aparecem no editor e são os projetos que os partidos da IA apresentam.


static func all() -> Array:
	return [
		{"id": "iptu", "title": TranslationServer.translate("Imposto sobre a propriedade"), "ementa": TranslationServer.translate("Institui imposto anual de 5% sobre o valor das propriedades."), "build": property_tax},
		{"id": "salario", "title": TranslationServer.translate("Salário mínimo nacional"), "ementa": TranslationServer.translate("Estabelece um salário mínimo ligado à renda do país."), "build": minimum_wage},
		{"id": "renda", "title": TranslationServer.translate("Renda básica para quem tem pouco"), "ementa": TranslationServer.translate("Concede benefício anual a quem tem pouco dinheiro guardado."), "build": basic_income},
		{"id": "industria", "title": TranslationServer.translate("Socorro à indústria"), "ementa": TranslationServer.translate("Cria subsídio à indústria enquanto o desemprego estiver alto."), "build": industry_aid},
		{"id": "greve", "title": TranslationServer.translate("Direito de greve"), "ementa": TranslationServer.translate("Garante o direito de greve."), "build": strike_right},
		{"id": "desonera", "title": TranslationServer.translate("Isenção para pequenos negócios"), "ementa": TranslationServer.translate("Limita a cobrança da taxa de abertura e registra novas empresas."), "build": small_business},
		{"id": "piso_edu", "title": TranslationServer.translate("Piso da educação"), "ementa": TranslationServer.translate("Obriga o orçamento de educação em 6% do PIB."), "build": budget_law.bind("sp_education", 6.0)},
		{"id": "piso_saude", "title": TranslationServer.translate("Piso da saúde"), "ementa": TranslationServer.translate("Obriga o orçamento de saúde em 8% do PIB."), "build": budget_law.bind("sp_health", 8.0)},
		{"id": "teto_def", "title": TranslationServer.translate("Limite aos gastos militares"), "ementa": TranslationServer.translate("Obriga o orçamento de defesa em 1,5% do PIB."), "build": budget_law.bind("sp_defense", 1.5)},
		{"id": "ordem", "title": TranslationServer.translate("Lei de ordem pública"), "ementa": TranslationServer.translate("Define toque de recolher e reforça a polícia."), "build": public_order},
		{"id": "liberdade", "title": TranslationServer.translate("Lei de liberdade de associação"), "ementa": TranslationServer.translate("Garante a livre associação."), "build": civil_rights},
	]


static func _plug(program: Dictionary, owner: Dictionary, field: String, type: String, fields := {}) -> Dictionary:
	var block := LawProgram.new_block(program, type)
	for key: String in fields:
		block.fields[key] = fields[key]
	owner.plugs[field] = block
	return block


static func _add(program: Dictionary, list: Array, type: String, fields := {}) -> Dictionary:
	var block := LawProgram.new_block(program, type)
	for key: String in fields:
		block.fields[key] = fields[key]
	list.append(block)
	return block


## O exemplo do documento: identifica a propriedade, confere o dono e cobra 5% do valor tributável.
static func property_tax() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_fiscal"), Vector2(30, 30))
	var each := _add(program, stack.blocks, "fl_foreach", {"set": "properties"})
	var check := _add(program, each.slots.do, "fl_if")
	_plug(program, check, "cond", "cd_owner")
	var charge := _add(program, check.slots.do, "ac_obligation", {"days": 30})
	var tax := _plug(program, charge, "amount", "ec_calc", {"rate": 5})
	_plug(program, tax, "base", "sb_value")
	return program


static func minimum_wage() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	_add(program, stack.blocks, "ec_minwage", {"amount": 300})
	return program


static func basic_income() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_fiscal"), Vector2(30, 30))
	var check := _add(program, stack.blocks, "fl_ifelse")
	var has := _plug(program, check, "cond", "cd_money", {"amount": 5000})
	has.fields.amount = 5000
	_add(program, check.slots["else"], "ac_benefit", {"amount": 200})
	_add(program, check.slots.do, "fl_end")
	return program


static func industry_aid() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_fiscal"), Vector2(30, 30))
	var check := _add(program, stack.blocks, "fl_if")
	var high := _plug(program, check, "cond", "op_gt", {"b": 8})
	_plug(program, high, "a", "gm_value", {"field": "unemployment"})
	_add(program, check.slots.do, "ec_subsidy", {"amount": 2, "sector": "industria"})
	return program


static func strike_right() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	_add(program, stack.blocks, "rg_grant", {"right": "greve"})
	return program


static func small_business() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	_add(program, stack.blocks, "ec_cap", {"name": TranslationServer.translate("Taxa de abertura"), "max": 50})
	var second := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_company"), Vector2(30, 180))
	_add(program, second.blocks, "ec_fee", {"name": TranslationServer.translate("Taxa de abertura"), "amount": 200})
	_add(program, second.blocks, "ac_register")
	return program


static func budget_law(field: String, value: float) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	_add(program, stack.blocks, "ec_budget", {"field": field, "value": value})
	return program


static func public_order() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	_add(program, stack.blocks, "rg_restrict", {"name": TranslationServer.translate("Toque de recolher")})
	_add(program, stack.blocks, "ac_post", {"name": TranslationServer.translate("Guarda nacional"), "posts": 20000, "salary": 15000})
	return program


static func civil_rights() -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	_add(program, stack.blocks, "rg_grant", {"right": "associacao"})
	return program
