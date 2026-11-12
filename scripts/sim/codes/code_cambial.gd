class_name CodeCambial
extends LawCode
## Lei Cambial e do Fundo Soberano: intervenção do banco central, controle de capitais e o fundo.
##
## O que vale fica em `standing.codes` como "cambial:<item>". Todo mês o código copia o que está em
## vigor para o país (`fx_lean`, `cap_controls`, `swf_*`), que a economia usa. Sem fundo na lei, o
## fundo para de receber aportes e de pagar saques, mas o saldo continua aplicado.

## Quanto o banco central segura do movimento do câmbio em cada escolha.
const LEAN := {"livre": 0.0, "suave": 0.3, "forte": 0.7}
const CONTROLS := {"nenhum": 0.0, "imposto": 0.35, "cotas": 0.75}


func _init() -> void:
	id = "cambial"
	title = "Lei Cambial e do Fundo Soberano"
	ementa = "Intervenção no câmbio, controle de capitais e fundo soberano."
	category = {"id": "cambial", "label": "Câmbio", "color": Color("2f7a8a")}
	norm_type = "ordinaria"


func blocks() -> Array:
	var law := LawCatalog.RANK_LAW
	return [
		{"id": "cb_intervencao", "cat": "cambial", "kind": "statement", "text": "O banco central intervém no câmbio de forma {modo}, vendendo e comprando reservas", "fields": {"modo": {"t": "choice", "of": "cb_modo", "d": "suave"}}, "rank": law},
		{"id": "cb_controle", "cat": "cambial", "kind": "statement", "text": "Controle de capitais: {nivel}", "fields": {"nivel": {"t": "choice", "of": "cb_controle", "d": "nenhum"}}, "rank": law, "econ": -0.3},
		{"id": "fs_fundo", "cat": "cambial", "kind": "statement", "text": "Fundo soberano: recebe {renda}% da renda pública de commodities e {superavit}% dos superávits", "fields": {"renda": {"t": "pct", "d": 50}, "superavit": {"t": "pct", "d": 30}}, "rank": law, "econ": 0.1},
		{"id": "fs_saque", "cat": "cambial", "kind": "statement", "text": "Saque anual do fundo soberano limitado a {limite}% do saldo", "fields": {"limite": {"t": "pct", "d": 3}}, "rank": law},
	]


func choices() -> Dictionary:
	return {
		"cb_modo": {"livre": "livre (sem intervenção)", "suave": "suave", "forte": "forte"},
		"cb_controle": {"nenhum": "nenhum", "imposto": "imposto sobre a saída de capitais", "cotas": "cotas e autorização prévia"},
	}


## O texto inicial repete o que o país já faz; o fundo só aparece onde ele existe.
func seed_program(_world: GameWorld, c: Country) -> Dictionary:
	var program := LawProgram.empty()
	var stack := LawProgram.add_stack(program, LawProgram.new_block(program, "ev_enact"), Vector2(30, 30))
	var list: Array = stack.blocks
	CodePenal._add(program, list, "cb_intervencao", {"modo": _closest(LEAN, c.fx_lean)})
	CodePenal._add(program, list, "cb_controle", {"nivel": _closest(CONTROLS, c.cap_controls)})
	if c.swf_active:
		CodePenal._add(program, list, "fs_fundo", {"renda": snappedf(c.swf_rent_share * 100.0, 1.0), "superavit": snappedf(c.swf_surplus_share * 100.0, 1.0)})
		CodePenal._add(program, list, "fs_saque", {"limite": snappedf(c.swf_limit * 100.0, 0.5)})
	return program


static func _closest(table: Dictionary, x: float) -> String:
	var best := ""
	var gap := INF
	for k: String in table:
		if absf(float(table[k]) - x) < gap:
			gap = absf(float(table[k]) - x)
			best = k
	return best


func apply(_world: GameWorld, leg: Legislation, op: String, values: Dictionary, _weight: float, norm_id: int, prio: float) -> String:
	match op:
		"cb_intervencao":
			leg.stand("cambial:intervencao", {"lean": float(LEAN.get(String(values.get("modo", "suave")), 0.3))}, norm_id, prio)
		"cb_controle":
			leg.stand("cambial:controle", {"level": float(CONTROLS.get(String(values.get("nivel", "nenhum")), 0.0))}, norm_id, prio)
		"fs_fundo":
			var rent := clampf(float(values.get("renda", 50.0)), 0.0, 100.0)
			var surplus := clampf(float(values.get("superavit", 30.0)), 0.0, 100.0)
			leg.stand("cambial:fundo", {"rent": rent / 100.0, "surplus": surplus / 100.0}, norm_id, prio)
			return tr("fundo soberano recebe %s%% da renda de commodities") % UiKit.num(rent)
		"fs_saque":
			var limit := clampf(float(values.get("limite", 3.0)), 0.0, 100.0)
			leg.stand("cambial:saque", {"limit": limit / 100.0}, norm_id, prio)
			return tr("saque do fundo limitado a %s%% ao ano") % UiKit.num(limit, 1)
	return ""


func monthly(world: GameWorld, c: Country, leg: Legislation) -> Dictionary:
	_enact_seed(world, leg)
	var law := leg.code_standing(id)
	if law.is_empty():
		return {}
	c.fx_lean = float(law.get("intervencao", {}).get("lean", c.fx_lean))
	c.cap_controls = float(law.get("controle", {}).get("level", 0.0))
	c.swf_active = law.has("fundo")
	if c.swf_active:
		c.swf_rent_share = float(law.fundo.rent)
		c.swf_surplus_share = float(law.fundo.surplus)
		# Sem regra de saque na lei, o fundo só acumula.
		c.swf_limit = float(law.get("saque", {}).get("limit", 0.0))
	c.code_stats["fundo_soberano"] = c.swf
	# Controle de capitais afasta investimento estrangeiro.
	return {"invest": -0.04 * c.cap_controls}


func _enact_seed(world: GameWorld, leg: Legislation) -> void:
	var norm := leg.code_norm(id)
	if norm.is_empty() or norm.get("seed_run", false) or not leg.code_standing(id).is_empty():
		return
	norm["seed_run"] = true
	leg.fire(world, "ev_enact", {"only": int(norm.id)})
