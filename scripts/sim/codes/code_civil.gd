class_name CodeCivil
extends LawCode
## Código Civil: Família, casamento, propriedade, contratos, herança e empresas.
##
## O que vale fica em `standing.codes` como "civil:<item>". Todo mês o código mede a segurança
## jurídica (`c.code_stats["seguranca_juridica"]`, 0-1): propriedade, contratos, falência e o tempo
## para abrir uma empresa. Ela puxa o investimento; a burocracia puxa a produtividade.

## Nota de cada escolha na segurança jurídica, de 0 a 1.
const PROPERTY_SCORE := {"indenizacao_previa": 0.95, "titulos": 0.6, "sem_indenizacao": 0.15}
const CONTRACT_SCORE := {"ampla": 0.9, "dirigida": 0.7, "restrita": 0.3}
const BANKRUPTCY_SCORE := {"recuperacao": 0.85, "liquidacao": 0.7, "sem_protecao": 0.35}
## A segurança jurídica anda esta fração do caminho até o alvo a cada mês: confiança demora.
const TRUST_PACE := 0.08
## Procedimentos para abrir empresa que não pesam na produtividade.
const FREE_STEPS := 6.0


func _init() -> void:
	id = "civil"
	title = "Código Civil"
	ementa = "Família, casamento, propriedade, contratos, herança e empresas."
	category = {"id": "civil", "label": "Civil", "color": Color("8a6a2f")}


func blocks() -> Array:
	return [
		{"id": "cv_marriage_age", "cat": "civil", "kind": "statement", "text": "Fixar a idade mínima para casar em {age} anos", "fields": {"age": {"t": "num", "d": 18}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": 0.1},
		{"id": "cv_same_sex", "cat": "civil", "kind": "statement", "text": "União entre pessoas do mesmo sexo: {status}", "fields": {"status": {"t": "choice", "of": "same_sex", "d": "casamento"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": 0.3},
		{"id": "cv_divorce", "cat": "civil", "kind": "statement", "text": "Divórcio {mode}", "fields": {"mode": {"t": "choice", "of": "divorce", "d": "direto"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": 0.2},
		{"id": "cv_goods", "cat": "civil", "kind": "statement", "text": "Adotar a {regime} como regime de bens padrão do casamento", "fields": {"regime": {"t": "choice", "of": "goods_regime", "d": "comunhao_parcial"}}, "rank": LawCatalog.RANK_COMPLEMENTARY},
		{"id": "cv_property", "cat": "civil", "kind": "statement", "text": "Garantir a propriedade privada, com desapropriação {mode}", "fields": {"mode": {"t": "choice", "of": "expropriation", "d": "indenizacao_previa"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.4},
		{"id": "cv_adverse", "cat": "civil", "kind": "statement", "text": "Admitir usucapião após {years} anos de posse mansa e pacífica", "fields": {"years": {"t": "num", "d": 10}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": -0.15, "social": 0.05},
		{"id": "cv_inheritance", "cat": "civil", "kind": "statement", "text": "Reservar {share}% da herança aos herdeiros necessários", "fields": {"share": {"t": "pct", "d": 50}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "social": -0.05},
		{"id": "cv_contracts", "cat": "civil", "kind": "statement", "text": "Liberdade contratual {level}", "fields": {"level": {"t": "choice", "of": "contract_freedom", "d": "dirigida"}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.35},
		{"id": "cv_usury", "cat": "civil", "kind": "statement", "text": "Limitar os juros dos contratos privados a {rate}% ao ano", "fields": {"rate": {"t": "pct", "d": 24}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": -0.35},
		{"id": "cv_business", "cat": "civil", "kind": "statement", "text": "Abrir uma empresa em até {days} dias, com {steps} procedimentos", "fields": {"days": {"t": "days", "d": 15}, "steps": {"t": "num", "d": 6}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.3},
		{"id": "cv_bankruptcy", "cat": "civil", "kind": "statement", "text": "Tratar a insolvência com {mode}, com prazo de {days} dias para o plano", "fields": {"mode": {"t": "choice", "of": "bankruptcy", "d": "recuperacao"}, "days": {"t": "days", "d": 180}}, "rank": LawCatalog.RANK_COMPLEMENTARY, "econ": 0.15},
		{"id": "cv_prescription", "cat": "civil", "kind": "statement", "text": "Fixar a prescrição das dívidas civis em {years} anos", "fields": {"years": {"t": "num", "d": 5}}, "rank": LawCatalog.RANK_COMPLEMENTARY},
	]


func choices() -> Dictionary:
	return {
		"same_sex": {"casamento": "casamento civil permitido", "uniao_civil": "só união civil", "proibida": "proibida"},
		"divorce": {"direto": "direto, a pedido de qualquer cônjuge", "com_causa": "só consensual ou com causa provada", "proibido": "proibido"},
		"goods_regime": {"comunhao_parcial": "comunhão parcial", "comunhao_universal": "comunhão universal", "separacao_total": "separação total"},
		"expropriation": {"indenizacao_previa": "só com indenização prévia em dinheiro", "titulos": "paga em títulos públicos", "sem_indenizacao": "sem indenização, por interesse social"},
		"contract_freedom": {"ampla": "ampla", "dirigida": "com cláusulas protetivas obrigatórias", "restrita": "restrita a contratos-padrão do Estado"},
		"bankruptcy": {"recuperacao": "recuperação judicial antes da falência", "liquidacao": "liquidação rápida dos bens", "sem_protecao": "falência sem proteção ao devedor"},
	}


## O texto com que o país começa: países ricos abrem empresa rápido e protegem contratos; regimes
## fechados desapropriam sem pagar; sociedades progressistas casam e divorciam com menos amarras.
func seed_program(world: GameWorld, c: Country) -> Dictionary:
	var lean := CodePenal._lean(world, c)
	var social := float(lean.social)
	var right := float(lean.econ)
	var gdp_pc := c.gdp_pc()
	var free := c.dem >= 6.0
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	var list: Array = stack.blocks
	CodePenal._add(program, list, "cv_marriage_age", {"age": 18 if free or gdp_pc > 10000.0 else 16})
	var same_sex := "proibida"
	if free and social > 0.2:
		same_sex = "casamento"
	elif free:
		same_sex = "uniao_civil"
	CodePenal._add(program, list, "cv_same_sex", {"status": same_sex})
	CodePenal._add(program, list, "cv_divorce", {"mode": "direto" if free else "com_causa"})
	CodePenal._add(program, list, "cv_goods", {"regime": "separacao_total" if right > 0.4 else "comunhao_parcial"})
	var property := "indenizacao_previa"
	if c.dem < 4.0 and right < 0.0:
		property = "sem_indenizacao"
	elif c.dem < 6.0 or right < -0.4:
		property = "titulos"
	CodePenal._add(program, list, "cv_property", {"mode": property})
	CodePenal._add(program, list, "cv_adverse", {"years": 10 if gdp_pc > 15000.0 else 5})
	CodePenal._add(program, list, "cv_inheritance", {"share": 0 if right > 0.4 and gdp_pc > 30000.0 else 50})
	var contracts := "dirigida"
	if right > 0.3 and free:
		contracts = "ampla"
	elif c.dem < 4.0 and right < 0.0:
		contracts = "restrita"
	CodePenal._add(program, list, "cv_contracts", {"level": contracts})
	if right < 0.0 or gdp_pc < 8000.0:
		CodePenal._add(program, list, "cv_usury", {"rate": 12 if right < -0.3 else 24})
	# Mais rico, mais rápido: de uns 60 dias em países pobres a uma semana nos ricos.
	var days := roundi(clampf(70.0 - log(maxf(gdp_pc, 500.0) / 1000.0) * 15.0, 5.0, 90.0))
	var steps := roundi(clampf(days / 6.0, 3.0, 14.0))
	CodePenal._add(program, list, "cv_business", {"days": days, "steps": steps})
	CodePenal._add(program, list, "cv_bankruptcy", {"mode": "recuperacao" if gdp_pc > 6000.0 and c.dem >= 4.0 else "liquidacao", "days": 180})
	CodePenal._add(program, list, "cv_prescription", {"years": 5 if free else 10})
	return program


func apply(_world: GameWorld, leg: Legislation, op: String, values: Dictionary, _weight: float, norm_id: int, prio: float) -> String:
	match op:
		"cv_marriage_age":
			leg.stand("civil:idade_casamento", {"age": clampf(float(values.get("age", 18.0)), 12.0, 30.0)}, norm_id, prio)
		"cv_same_sex":
			leg.stand("civil:mesmo_sexo", {"status": String(values.get("status", "proibida"))}, norm_id, prio)
		"cv_divorce":
			leg.stand("civil:divorcio", {"mode": String(values.get("mode", "direto"))}, norm_id, prio)
		"cv_goods":
			leg.stand("civil:regime_bens", {"regime": String(values.get("regime", "comunhao_parcial"))}, norm_id, prio)
		"cv_property":
			leg.stand("civil:propriedade", {"mode": String(values.get("mode", "indenizacao_previa"))}, norm_id, prio)
		"cv_adverse":
			leg.stand("civil:usucapiao", {"years": clampf(float(values.get("years", 10.0)), 1.0, 50.0)}, norm_id, prio)
		"cv_inheritance":
			leg.stand("civil:legitima", {"share": clampf(float(values.get("share", 50.0)), 0.0, 100.0) / 100.0}, norm_id, prio)
		"cv_contracts":
			leg.stand("civil:contratos", {"level": String(values.get("level", "dirigida"))}, norm_id, prio)
		"cv_usury":
			var rate := clampf(float(values.get("rate", 24.0)), 0.0, 100.0)
			leg.stand("civil:juros_max", {"rate": rate / 100.0}, norm_id, prio)
			return tr("juros limitados a %s%% ao ano") % UiKit.num(rate)
		"cv_business":
			var days := clampf(float(values.get("days", 15.0)), 1.0, 365.0)
			leg.stand("civil:abertura_empresa", {"days": days, "steps": clampf(float(values.get("steps", 6.0)), 1.0, 40.0)}, norm_id, prio)
			return tr("empresa aberta em até %d dias") % roundi(days)
		"cv_bankruptcy":
			leg.stand("civil:falencia", {"mode": String(values.get("mode", "recuperacao")), "days": clampf(float(values.get("days", 180.0)), 30.0, 1000.0)}, norm_id, prio)
		"cv_prescription":
			leg.stand("civil:prescricao", {"years": clampf(float(values.get("years", 5.0)), 1.0, 50.0)}, norm_id, prio)
	return ""


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	_enact_seed(world, leg)
	var law := leg.code_standing(id)
	var property: float = PROPERTY_SCORE.get(String(law.get("propriedade", {}).get("mode", "")), 0.5)
	var contracts: float = CONTRACT_SCORE.get(String(law.get("contratos", {}).get("level", "")), 0.6)
	var bankruptcy: float = BANKRUPTCY_SCORE.get(String(law.get("falencia", {}).get("mode", "")), 0.4)
	var business: Dictionary = law.get("abertura_empresa", {"days": 60.0, "steps": 12.0})
	var days := float(business.days)
	var steps := float(business.steps)
	var opening := 1.0 - clampf((days - 5.0) / 115.0, 0.0, 1.0)
	# Juro tabelado baixo demais seca o crédito; usucapião rápido e prescrição curta inseguram o dono.
	var usury := 1.0
	if law.has("juros_max"):
		usury = clampf(float(law.juros_max.rate) / 0.2, 0.3, 1.0)
	var adverse := clampf(float(law.get("usucapiao", {}).get("years", 10.0)) / 10.0, 0.4, 1.0)
	var prescription := float(law.get("prescricao", {}).get("years", 5.0))
	var term := 1.0 - clampf(absf(prescription - 7.0) / 20.0, 0.0, 0.4)
	var courts := clampf(c.dem / 10.0, 0.2, 1.0)
	var target := property * 0.25 + contracts * 0.2 + bankruptcy * 0.12 + opening * 0.13 + usury * 0.08 + adverse * 0.05 + term * 0.05 + courts * 0.12
	var trust := float(c.code_stats.get("seguranca_juridica", target))
	trust = clampf(trust + (target - trust) * TRUST_PACE, 0.0, 1.0)
	c.code_stats["seguranca_juridica"] = trust
	c.code_stats["dias_abrir_empresa"] = days
	# Família: o eleitor gosta de leis próximas do que pensa; quem se afasta perde aprovação.
	var social := float(CodePenal._lean(world, c).social)
	var liberal := 0.0
	liberal += float({"casamento": 1.0, "uniao_civil": 0.4, "proibida": -0.6}.get(String(law.get("mesmo_sexo", {}).get("status", "")), 0.0))
	liberal += float({"direto": 0.6, "com_causa": 0.0, "proibido": -1.0}.get(String(law.get("divorcio", {}).get("mode", "")), 0.0))
	liberal += clampf((float(law.get("idade_casamento", {}).get("age", 18.0)) - 16.0) * 0.25, -1.0, 0.5)
	var approval := -absf(liberal / 3.0 - social) * 0.01 + 0.004
	var stability := 0.0
	var mode := String(law.get("propriedade", {}).get("mode", ""))
	if mode == "sem_indenizacao":
		stability -= 0.01 if c.dem >= 4.0 else 0.0
		approval += 0.004
	return {
		"approval": approval, "stability": stability,
		"invest": (trust - 0.65) * 0.25,
		"tfp": -maxf(steps - FREE_STEPS, 0.0) * 0.0004 - maxf(days - 30.0, 0.0) * 0.00003 + (bankruptcy - 0.6) * 0.002,
		"inequality": -0.004 if mode == "sem_indenizacao" else 0.0,
	}


func _enact_seed(world: GameWorld, leg: Legislation) -> void:
	var norm := leg.code_norm(id)
	if norm.is_empty() or norm.get("seed_run", false) or not leg.code_standing(id).is_empty():
		return
	norm["seed_run"] = true
	leg.fire(world, "ev_enact", {"only": int(norm.id)})
