class_name LawCatalog
extends RefCounted
## Biblioteca de blocos: todo bloco que pode entrar em uma norma. Nada aqui executa código; o compilador
## só aceita tipos desta lista, e o motor só conhece as ações listadas.
##
## kind: event (inicia um artigo), statement (instrução), cblock (instrução com blocos dentro),
## value (número ou texto) e bool (condição). rank é a menor hierarquia de norma que pode usar o bloco.
## Campos: t = num, money, pct, days, bool, text, date, any, var, choice, unit, ministry, company ou ref; d = valor inicial.
## ref: nome de algo que já existe (of = tax, license, institution ou duty), escolhido numa lista no editor;
## texto livre só para dar nome a algo novo.
##
## Os blocos concretos de cada código legal (Tributário, Penal...) vêm de `LawCodes`; os daqui são os
## avançados, para quem quer escrever regras próprias. `categories()`, `get_def()`, `in_category()`
## e `choice_list()` juntam as duas fontes.

## Categorias avançadas: ficam depois das dos códigos, sob o título "Avançado".
const CATEGORIES := [
	{"id": "events", "label": "Eventos", "color": Color("b5532c")},
	{"id": "conditions", "label": "Condições", "color": Color("2f7f7a")},
	{"id": "logic", "label": "Operadores lógicos", "color": Color("3f8f4f")},
	{"id": "data", "label": "Consultas", "color": Color("3a6ea5")},
	{"id": "variables", "label": "Variáveis", "color": Color("8a5a9e")},
	{"id": "admin", "label": "Ações administrativas", "color": Color("a5742a")},
	{"id": "economy", "label": "Economia e tributação", "color": Color("6f7f2a")},
	{"id": "rights", "label": "Direitos e obrigações", "color": Color("a53f5e")},
	{"id": "flow", "label": "Controle de fluxo", "color": Color("56606e")},
]

const RANK_ANY := 20
const RANK_DECREE := 40
const RANK_LAW := 60
const RANK_COMPLEMENTARY := 70

const CHOICES := {
	"profession": {"agro": "Agropecuária", "industria": "Indústria", "servicos": "Serviços", "publico": "Servidor público"},
	"tax_field": {"tax_income": "Renda e folha", "tax_consumption": "Consumo", "tax_corporate": "Empresas e capital", "tariff": "Tarifa de importação"},
	"budget_field": {"sp_social": "Previdência e assistência", "sp_health": "Saúde", "sp_education": "Educação e ciência", "sp_infra": "Infraestrutura", "sp_defense": "Defesa", "sp_admin": "Administração"},
	"param_field": {"mon_fin": "Emissão monetária (% do déficit)", "mobilization": "Mobilização militar"},
	"right": {"expressao": "Liberdade de expressão", "voto": "Voto universal", "greve": "Greve", "associacao": "Livre associação", "propriedade": "Propriedade privada", "saude": "Saúde pública", "educacao": "Educação pública", "moradia": "Moradia"},
	"sector": {"agro": "Agropecuária", "industria": "Indústria", "servicos": "Serviços", "energia": "Energia"},
	"game_value": {"gdp": "PIB (US$ bi)", "gdp_pc": "PIB per capita (US$)", "growth": "Crescimento (%)", "inflation": "Inflação (%)", "unemployment": "Desemprego (%)", "debt": "Dívida/PIB (%)", "approval": "Aprovação (%)", "stability": "Estabilidade (%)", "population": "População (mi)", "reserves": "Reservas (US$ bi)", "tension": "Tensão global (%)"},
	"each_set": {"citizens": "cidadão", "properties": "propriedade", "companies": "empresa", "units": "unidade do território"},
	"ministry_area": {"finance": "Economia e banco central", "foreign": "Relações exteriores", "defense": "Forças armadas", "health": "Saúde", "education": "Educação", "infrastructure": "Infraestrutura", "justice": "Justiça e ordem", "science": "Ciência e tecnologia", "culture": "Cultura", "environment": "Meio ambiente", "agriculture": "Agricultura"},
	"var_type": {"num": "Numérica", "money": "Monetária", "bool": "Booleana", "text": "Textual", "date": "Temporal", "id": "Identificador"},
}

const BLOCKS := [
	# --- Eventos -----------------------------------------------------------------------
	{"id": "ev_citizen_enter", "cat": "events", "kind": "event", "text": "Quando um cidadão ingressar no território", "rank": RANK_ANY},
	{"id": "ev_transaction", "cat": "events", "kind": "event", "text": "Quando um cidadão realizar uma transação", "rank": RANK_ANY},
	{"id": "ev_property", "cat": "events", "kind": "event", "text": "Quando uma propriedade for adquirida", "rank": RANK_ANY},
	{"id": "ev_death", "cat": "events", "kind": "event", "text": "Quando um cidadão morrer", "rank": RANK_ANY},
	{"id": "ev_age", "cat": "events", "kind": "event", "text": "Quando um cidadão completar {age} anos", "fields": {"age": {"t": "num", "d": 18}}, "rank": RANK_ANY},
	{"id": "ev_company", "cat": "events", "kind": "event", "text": "Quando uma empresa for registrada", "rank": RANK_ANY},
	{"id": "ev_due", "cat": "events", "kind": "event", "text": "Quando uma obrigação vencer", "rank": RANK_ANY},
	{"id": "ev_election", "cat": "events", "kind": "event", "text": "Quando uma eleição for iniciada", "rank": RANK_ANY},
	{"id": "ev_fiscal", "cat": "events", "kind": "event", "text": "Quando um exercício financeiro começar", "rank": RANK_ANY},
	{"id": "ev_date", "cat": "events", "kind": "event", "text": "Em {date}", "fields": {"date": {"t": "date", "d": "2026-01-01"}}, "rank": RANK_ANY},
	{"id": "ev_month", "cat": "events", "kind": "event", "text": "Todo mês", "rank": RANK_ANY},
	{"id": "ev_enact", "cat": "events", "kind": "event", "text": "Quando esta norma entrar em vigor", "rank": RANK_ANY},
	{"id": "ev_war", "cat": "events", "kind": "event", "text": "Quando o país entrar em guerra", "rank": RANK_ANY},
	# --- Condições ---------------------------------------------------------------------
	{"id": "cd_profession", "cat": "conditions", "kind": "bool", "text": "cidadão trabalha em {profession}", "fields": {"profession": {"t": "choice", "of": "profession", "d": "servicos"}}, "rank": RANK_ANY},
	{"id": "cd_territory", "cat": "conditions", "kind": "bool", "text": "cidadão vive em {unit}", "fields": {"unit": {"t": "unit", "d": -1}}, "rank": RANK_ANY},
	{"id": "cd_money", "cat": "conditions", "kind": "bool", "text": "cidadão tem pelo menos {amount} em dinheiro", "fields": {"amount": {"t": "money", "d": 10000}}, "rank": RANK_ANY},
	{"id": "cd_owner", "cat": "conditions", "kind": "bool", "text": "a propriedade pertence ao cidadão", "rank": RANK_ANY},
	{"id": "cd_license", "cat": "conditions", "kind": "bool", "text": "cidadão tem a licença {license}", "fields": {"license": {"t": "ref", "of": "license", "d": "Comércio"}}, "rank": RANK_ANY},
	{"id": "cd_period", "cat": "conditions", "kind": "bool", "text": "a data está entre {from} e {to}", "fields": {"from": {"t": "date", "d": "2025-01-01"}, "to": {"t": "date", "d": "2030-12-31"}}, "rank": RANK_ANY},
	{"id": "cd_institution", "cat": "conditions", "kind": "bool", "text": "a instituição {institution} está ativa", "fields": {"institution": {"t": "ref", "of": "institution", "d": "Receita Federal"}}, "rank": RANK_ANY},
	{"id": "cd_norm", "cat": "conditions", "kind": "bool", "text": "a norma nº {norm} está em vigor", "fields": {"norm": {"t": "num", "d": 1}}, "rank": RANK_ANY},
	# --- Operadores lógicos --------------------------------------------------------------
	{"id": "op_and", "cat": "logic", "kind": "bool", "text": "{a} E {b}", "fields": {"a": {"t": "bool"}, "b": {"t": "bool"}}, "rank": RANK_ANY},
	{"id": "op_or", "cat": "logic", "kind": "bool", "text": "{a} OU {b}", "fields": {"a": {"t": "bool"}, "b": {"t": "bool"}}, "rank": RANK_ANY},
	{"id": "op_not", "cat": "logic", "kind": "bool", "text": "NÃO {a}", "fields": {"a": {"t": "bool"}}, "rank": RANK_ANY},
	{"id": "op_eq", "cat": "logic", "kind": "bool", "text": "{a} igual a {b}", "fields": {"a": {"t": "any", "d": 0}, "b": {"t": "any", "d": 0}}, "rank": RANK_ANY},
	{"id": "op_ne", "cat": "logic", "kind": "bool", "text": "{a} diferente de {b}", "fields": {"a": {"t": "any", "d": 0}, "b": {"t": "any", "d": 0}}, "rank": RANK_ANY},
	{"id": "op_gt", "cat": "logic", "kind": "bool", "text": "{a} maior que {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	{"id": "op_lt", "cat": "logic", "kind": "bool", "text": "{a} menor que {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	{"id": "op_ge", "cat": "logic", "kind": "bool", "text": "{a} maior ou igual a {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	{"id": "op_le", "cat": "logic", "kind": "bool", "text": "{a} menor ou igual a {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	{"id": "op_between", "cat": "logic", "kind": "bool", "text": "{a} está entre {lo} e {hi}", "fields": {"a": {"t": "num", "d": 0}, "lo": {"t": "num", "d": 0}, "hi": {"t": "num", "d": 10}}, "rank": RANK_ANY},
	# --- Consultas -----------------------------------------------------------------------
	{"id": "sb_age", "cat": "data", "kind": "value", "out": "num", "text": "idade do cidadão", "rank": RANK_ANY},
	{"id": "sb_money", "cat": "data", "kind": "value", "out": "money", "text": "dinheiro do cidadão", "rank": RANK_ANY},
	{"id": "sb_income", "cat": "data", "kind": "value", "out": "money", "text": "renda anual do cidadão", "rank": RANK_ANY},
	{"id": "sb_value", "cat": "data", "kind": "value", "out": "money", "text": "valor tributável da propriedade", "rank": RANK_ANY},
	{"id": "sb_tx", "cat": "data", "kind": "value", "out": "money", "text": "valor da transação", "rank": RANK_ANY},
	{"id": "gm_value", "cat": "data", "kind": "value", "out": "num", "text": "{field} do país", "fields": {"field": {"t": "choice", "of": "game_value", "d": "inflation"}}, "rank": RANK_ANY},
	# --- Variáveis ---------------------------------------------------------------------
	{"id": "var_set", "cat": "variables", "kind": "statement", "text": "Definir {name} ({vtype}) como {value}", "fields": {"name": {"t": "var", "d": "valor"}, "vtype": {"t": "choice", "of": "var_type", "d": "num"}, "value": {"t": "any", "d": 0}}, "rank": RANK_ANY},
	{"id": "var_get", "cat": "variables", "kind": "value", "out": "any", "text": "variável {name}", "fields": {"name": {"t": "var", "d": "valor"}}, "rank": RANK_ANY},
	{"id": "var_change", "cat": "variables", "kind": "statement", "text": "Alterar {name} para {value}", "fields": {"name": {"t": "var", "d": "valor"}, "value": {"t": "any", "d": 0}}, "rank": RANK_ANY},
	{"id": "m_add", "cat": "variables", "kind": "value", "out": "num", "text": "{a} + {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	{"id": "m_sub", "cat": "variables", "kind": "value", "out": "num", "text": "{a} − {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	{"id": "m_mul", "cat": "variables", "kind": "value", "out": "num", "text": "{a} × {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 1}}, "rank": RANK_ANY},
	{"id": "m_div", "cat": "variables", "kind": "value", "out": "num", "text": "{a} ÷ {b}", "fields": {"a": {"t": "num", "d": 0}, "b": {"t": "num", "d": 1}}, "rank": RANK_ANY},
	{"id": "m_pct", "cat": "variables", "kind": "value", "out": "money", "text": "{rate}% de {base}", "fields": {"rate": {"t": "pct", "d": 5}, "base": {"t": "num", "d": 0}}, "rank": RANK_ANY},
	# --- Ações administrativas -----------------------------------------------------------
	{"id": "ac_obligation", "cat": "admin", "kind": "statement", "text": "Criar obrigação tributária de {amount} com prazo de {days} dias", "fields": {"amount": {"t": "money", "d": 100}, "days": {"t": "days", "d": 30}}, "rank": RANK_LAW, "econ": 0.3, "social": -0.05},
	{"id": "ac_fine", "cat": "admin", "kind": "statement", "text": "Aplicar multa de {amount}", "fields": {"amount": {"t": "money", "d": 100}}, "rank": RANK_DECREE, "econ": 0.05, "social": -0.2},
	{"id": "ac_benefit", "cat": "admin", "kind": "statement", "text": "Conceder benefício de {amount}", "fields": {"amount": {"t": "money", "d": 100}}, "rank": RANK_LAW, "econ": -0.4, "social": 0.1},
	{"id": "ac_revoke_license", "cat": "admin", "kind": "statement", "text": "Revogar a licença {license}", "fields": {"license": {"t": "ref", "of": "license", "d": "Comércio"}}, "rank": RANK_DECREE, "social": -0.2},
	{"id": "ac_issue_license", "cat": "admin", "kind": "statement", "text": "Emitir autorização: licença {license}", "fields": {"license": {"t": "ref", "of": "license", "d": "Comércio"}}, "rank": RANK_ANY, "social": 0.05},
	{"id": "ac_register", "cat": "admin", "kind": "statement", "text": "Registrar o cidadão no cadastro", "rank": RANK_ANY, "social": -0.05},
	{"id": "ac_status", "cat": "admin", "kind": "statement", "text": "Alterar situação cadastral para {status}", "fields": {"status": {"t": "text", "d": "Regular"}}, "rank": RANK_ANY},
	{"id": "ac_post", "cat": "admin", "kind": "statement", "text": "Criar o cargo público {name} com {posts} vagas e salário anual de {salary}", "fields": {"name": {"t": "text", "d": "Fiscal"}, "posts": {"t": "num", "d": 1000}, "salary": {"t": "money", "d": 20000}}, "rank": RANK_LAW, "econ": -0.15},
	{"id": "ac_expense", "cat": "admin", "kind": "statement", "text": "Registrar despesa pública de {amount} bilhões para {purpose}", "fields": {"amount": {"t": "num", "d": 1}, "purpose": {"t": "text", "d": "Obras"}}, "rank": RANK_DECREE, "econ": -0.15},
	{"id": "ac_institution", "cat": "admin", "kind": "statement", "text": "Criar a instituição {name} com custo anual de {cost} bilhões", "fields": {"name": {"t": "text", "d": "Receita Federal"}, "cost": {"t": "num", "d": 1}}, "rank": RANK_LAW, "econ": -0.2},
	{"id": "ac_param", "cat": "admin", "kind": "statement", "text": "Alterar {field} para {value}%", "fields": {"field": {"t": "choice", "of": "param_field", "d": "mon_fin"}, "value": {"t": "pct", "d": 0}}, "rank": RANK_DECREE},
	{"id": "ad_min_create", "cat": "admin", "kind": "statement", "text": "Criar o ministério {name}, responsável por {area}", "fields": {"name": {"t": "text", "d": "Ciência"}, "area": {"t": "choice", "of": "ministry_area", "d": "science"}}, "rank": RANK_LAW, "econ": -0.1},
	{"id": "ad_min_merge", "cat": "admin", "kind": "statement", "text": "Fundir os ministérios {a} e {b} em {name}", "fields": {"a": {"t": "ministry", "d": ""}, "b": {"t": "ministry", "d": ""}, "name": {"t": "text", "d": "Novo ministério"}}, "rank": RANK_LAW, "econ": 0.15},
	{"id": "ad_min_abolish", "cat": "admin", "kind": "statement", "text": "Extinguir o ministério {a}", "fields": {"a": {"t": "ministry", "d": ""}}, "rank": RANK_LAW, "econ": 0.2},
	# --- Economia e tributação ---------------------------------------------------------
	{"id": "ec_rate", "cat": "economy", "kind": "statement", "text": "Definir alíquota de {field} em {value}% do PIB", "fields": {"field": {"t": "choice", "of": "tax_field", "d": "tax_income"}, "value": {"t": "pct", "d": 10}}, "rank": RANK_LAW, "econ": -0.3},
	{"id": "ec_calc", "cat": "economy", "kind": "value", "out": "money", "text": "imposto de {rate}% sobre {base}", "fields": {"rate": {"t": "pct", "d": 5}, "base": {"t": "money", "d": 0}}, "rank": RANK_ANY},
	{"id": "ec_charge", "cat": "economy", "kind": "statement", "text": "Cobrar o tributo {name} no valor de {amount}", "fields": {"name": {"t": "ref", "of": "tax", "d": "Imposto"}, "amount": {"t": "money", "d": 100}}, "rank": RANK_LAW, "econ": -0.35},
	{"id": "ec_fee", "cat": "economy", "kind": "statement", "text": "Criar a taxa {name} de {amount}", "fields": {"name": {"t": "text", "d": "Taxa"}, "amount": {"t": "money", "d": 10}}, "rank": RANK_LAW, "econ": -0.15},
	{"id": "ec_contribution", "cat": "economy", "kind": "statement", "text": "Criar a contribuição {name} de {rate}% da renda mensal", "fields": {"name": {"t": "text", "d": "Contribuição"}, "rate": {"t": "pct", "d": 2}}, "rank": RANK_COMPLEMENTARY, "econ": -0.35},
	{"id": "ec_exempt", "cat": "economy", "kind": "statement", "text": "Definir isenção de {share}% no tributo {name}", "fields": {"name": {"t": "ref", "of": "tax", "d": "Imposto"}, "share": {"t": "pct", "d": 100}}, "rank": RANK_LAW, "econ": 0.2},
	{"id": "ec_cap", "cat": "economy", "kind": "statement", "text": "Limitar a cobrança de {name} a {max} por pessoa", "fields": {"name": {"t": "ref", "of": "tax", "d": "Imposto"}, "max": {"t": "money", "d": 1000}}, "rank": RANK_LAW, "econ": 0.2},
	{"id": "ec_treasury", "cat": "economy", "kind": "statement", "text": "Transferir {amount} bilhões das reservas ao Tesouro", "fields": {"amount": {"t": "num", "d": 1}}, "rank": RANK_DECREE},
	{"id": "ec_subsidy", "cat": "economy", "kind": "statement", "text": "Criar subsídio de {amount} bilhões por ano para {sector}", "fields": {"amount": {"t": "num", "d": 1}, "sector": {"t": "choice", "of": "sector", "d": "industria"}}, "rank": RANK_LAW, "econ": -0.3, "social": -0.05},
	{"id": "ec_minwage", "cat": "economy", "kind": "statement", "text": "Estabelecer salário mínimo de {amount} por mês", "fields": {"amount": {"t": "money", "d": 300}}, "rank": RANK_LAW, "econ": -0.45, "social": 0.05},
	{"id": "ec_spend", "cat": "economy", "kind": "statement", "text": "Criar despesa permanente de {amount} bilhões por ano para {purpose}", "fields": {"amount": {"t": "num", "d": 1}, "purpose": {"t": "text", "d": "Programa social"}}, "rank": RANK_LAW, "econ": -0.35},
	{"id": "ec_privatize", "cat": "economy", "kind": "statement", "text": "Privatizar {stake}% da participação do Estado em {company}", "fields": {"stake": {"t": "pct", "d": 50}, "company": {"t": "company", "d": ""}}, "rank": RANK_LAW, "econ": 0.45},
	{"id": "ec_nationalize", "cat": "economy", "kind": "statement", "text": "Estatizar {company}, levando a participação do Estado a {stake}% do capital", "fields": {"company": {"t": "company", "d": ""}, "stake": {"t": "pct", "d": 100}}, "rank": RANK_LAW, "econ": -0.5, "social": -0.05},
	{"id": "ec_budget", "cat": "economy", "kind": "statement", "text": "Obrigar o orçamento de {field} a {value}% do PIB", "fields": {"field": {"t": "choice", "of": "budget_field", "d": "sp_health"}, "value": {"t": "pct", "d": 5}}, "rank": RANK_LAW, "econ": -0.15},
	# --- Direitos e obrigações -----------------------------------------------------------
	{"id": "rg_grant", "cat": "rights", "kind": "statement", "text": "Conceder o direito: {right}", "fields": {"right": {"t": "choice", "of": "right", "d": "greve"}}, "rank": RANK_LAW, "econ": -0.05, "social": 0.5},
	{"id": "rg_remove", "cat": "rights", "kind": "statement", "text": "Remover o direito: {right}", "fields": {"right": {"t": "choice", "of": "right", "d": "greve"}}, "rank": RANK_COMPLEMENTARY, "social": -0.7},
	{"id": "rg_duty", "cat": "rights", "kind": "statement", "text": "Criar a obrigação: {name}", "fields": {"name": {"t": "text", "d": "Serviço cívico"}}, "rank": RANK_LAW, "social": -0.35},
	{"id": "rg_deadline", "cat": "rights", "kind": "statement", "text": "Estabelecer prazo de {days} dias para {name}", "fields": {"days": {"t": "days", "d": 90}, "name": {"t": "ref", "of": "duty", "d": "Serviço cívico"}}, "rank": RANK_DECREE},
	{"id": "rg_restrict", "cat": "rights", "kind": "statement", "text": "Definir a restrição: {name}", "fields": {"name": {"t": "text", "d": "Toque de recolher"}}, "rank": RANK_LAW, "social": -0.6},
	{"id": "rg_require", "cat": "rights", "kind": "statement", "text": "Estabelecer o requisito: {name}", "fields": {"name": {"t": "text", "d": "Registro profissional"}}, "rank": RANK_DECREE, "social": -0.1},
	{"id": "rg_exception", "cat": "rights", "kind": "statement", "text": "Criar exceção à obrigação {name}", "fields": {"name": {"t": "ref", "of": "duty", "d": "Serviço cívico"}}, "rank": RANK_DECREE, "social": 0.15},
	{"id": "rg_penalty", "cat": "rights", "kind": "statement", "text": "Definir penalidade de {amount} para {name}", "fields": {"amount": {"t": "money", "d": 500}, "name": {"t": "ref", "of": "duty", "d": "Serviço cívico"}}, "rank": RANK_LAW, "social": -0.2},
	# --- Controle de fluxo ---------------------------------------------------------------
	{"id": "fl_if", "cat": "flow", "kind": "cblock", "text": "Se {cond}", "fields": {"cond": {"t": "bool"}}, "slots": ["do"], "rank": RANK_ANY},
	{"id": "fl_ifelse", "cat": "flow", "kind": "cblock", "text": "Se {cond}", "fields": {"cond": {"t": "bool"}}, "slots": ["do", "else"], "rank": RANK_ANY},
	{"id": "fl_while", "cat": "flow", "kind": "cblock", "text": "Enquanto {cond}", "fields": {"cond": {"t": "bool"}}, "slots": ["do"], "rank": RANK_ANY},
	{"id": "fl_repeat", "cat": "flow", "kind": "cblock", "text": "Repetir {times} vezes", "fields": {"times": {"t": "num", "d": 3}}, "slots": ["do"], "rank": RANK_ANY},
	{"id": "fl_foreach", "cat": "flow", "kind": "cblock", "text": "Para cada {set}", "fields": {"set": {"t": "choice", "of": "each_set", "d": "citizens"}}, "slots": ["do"], "rank": RANK_ANY},
	{"id": "fl_wait", "cat": "flow", "kind": "statement", "text": "Aguardar {days} dias", "fields": {"days": {"t": "days", "d": 30}}, "rank": RANK_ANY},
	{"id": "fl_break", "cat": "flow", "kind": "statement", "text": "Interromper a repetição", "rank": RANK_ANY},
	{"id": "fl_end", "cat": "flow", "kind": "statement", "text": "Encerrar a execução", "rank": RANK_ANY},
]

static var _by_id := {}
static var _categories: Array = []
static var _choices := {}
static var _all_blocks: Array = []
static var _mutex := Mutex.new()


## Junta os blocos avançados aos dos códigos, uma vez só; depois é só leitura, seguro entre threads.
static func _warm() -> void:
	if not _by_id.is_empty():
		return
	_mutex.lock()
	if _by_id.is_empty():
		var cats := []
		var choices := CHOICES.duplicate()
		var blocks := []
		for code: LawCode in LawCodes.all():
			var cat: Dictionary = code.category.duplicate()
			cat["code"] = code.id
			cats.append(cat)
			choices.merge(code.choices())
			blocks.append_array(code.blocks())
		for cat: Dictionary in CATEGORIES:
			var advanced := cat.duplicate()
			advanced["advanced"] = true
			cats.append(advanced)
		blocks.append_array(BLOCKS)
		var by_id := {}
		for b: Dictionary in blocks:
			by_id[b.id] = b
		_categories = cats
		_choices = choices
		_all_blocks = blocks
		_by_id = by_id
	_mutex.unlock()


static func get_def(id: String) -> Dictionary:
	_warm()
	return _by_id.get(id, {})


## Categorias da paleta: primeiro as dos códigos (com "code"), depois as avançadas (com "advanced").
static func categories() -> Array:
	_warm()
	return _categories


static func category(id: String) -> Dictionary:
	for c: Dictionary in categories():
		if c.id == id:
			return c
	return {}


static func in_category(id: String) -> Array:
	_warm()
	return _all_blocks.filter(func(b): return b.cat == id)


## Lista de escolha de um campo {"t": "choice", "of": nome}, dos avançados ou de um código.
static func choice_list(of: String) -> Dictionary:
	_warm()
	return _choices.get(of, {})


## Pedaços do texto de um bloco: [{"text": "Cobrar"}, {"field": "amount"}, ...], para a tela e para a lei.
## Com localized, o molde é traduzido antes de ser cortado: a ordem dos campos pode mudar no outro idioma.
static func segments(def: Dictionary, localized := false) -> Array:
	var out := []
	var text: String = TranslationServer.translate(def.text) if localized else def.text
	var at := 0
	while at < text.length():
		var open := text.find("{", at)
		if open < 0:
			out.append({"text": text.substr(at)})
			break
		if open > at:
			out.append({"text": text.substr(at, open - at)})
		var close := text.find("}", open)
		out.append({"field": text.substr(open + 1, close - open - 1)})
		at = close + 1
	return out


## Pode encaixar um bloco de saída "from" em um campo do tipo "to"?
static func compatible(from: String, to: String) -> bool:
	if from == "any" or to == "any":
		return to != "bool" or from == "bool" or from == "any"
	if to == "bool" or from == "bool":
		return to == from
	if to == "text" or to == "date" or to == "var" or to == "choice" or to == "unit" or to == "ministry" or to == "company" or to == "ref":
		return false
	return from in ["num", "money", "pct", "days"]
