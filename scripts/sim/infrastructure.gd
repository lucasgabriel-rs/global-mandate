class_name Infrastructure
extends RefCounted
## Portos e aeroportos de cada país.
## Contrato com o resto do jogo: escreve `Country.logistics` (1 = neutro) e soma em
## `Country.sector_boost[Sectors.TRANSPORT]`, `[Sectors.TOURISM]` etc. Nunca toca em nós nem emite sinais:
## roda na thread da simulação (notícias só por `world.emit_news`).
##
## A demanda de um porto segue o comércio exterior do país; a de um aeroporto, o PIB e o turismo. A carga
## procura primeiro a instalação de costume e transborda para as que têm folga. A saturação do país
## (demanda / capacidade) define a logística: o efeito é medido contra a saturação do início do jogo, que já
## está embutida no PIB de partida. Guerra danifica, ocupação fecha, obras ampliam.

const PORT := "port"
const AIR := "air"
const KINDS := [PORT, AIR]
## Um TEU carrega, em média, umas 12 toneladas: é assim que portos de contêiner e de granel se somam.
const TEU_TONS := 12.0
## Custo de reposição em US$ bi por unidade de capacidade anual (milhão de TEU, de toneladas ou de
## passageiros), nos preços de um país rico. Países mais pobres constroem mais barato (ver cost_factor).
const UNIT_COST := {"TEU": 0.9, "t": 0.07, "pax": 0.2}
const EXPAND_OPTIONS := [0.25, 0.5, 1.0]
# i18n-begin
const NEW_SIZES := [["Pequeno", 0.08], ["Médio", 0.15], ["Grande", 0.3]]
# i18n-end
# i18n-begin
const OWNER_NAMES := {"public": "Público", "private": "Privado", "concession": "Concessão"}
# i18n-end
## Uma concessão roda um pouco mais que o mesmo ativo nas mãos do Estado.
const CONCESSION_EFFICIENCY := 1.05
## Quanto o país recebe ao conceder um ativo: fração do custo de reposição.
const CONCESSION_SHARE := 0.5
const MAX_PER_KIND := 16
## Países sem saída para o mar: não têm porto marítimo.
const LANDLOCKED := [
	"AFG", "ARM", "AUT", "AZE", "BDI", "BFA", "BLR", "BOL", "BTN", "BWA", "CAF", "CHE", "CZE", "ETH", "HUN",
	"KAZ", "KGZ", "LAO", "LSO", "LUX", "MDA", "MKD", "MLI", "MNG", "MWI", "NER", "NPL", "PRY", "RWA", "SRB",
	"SSD", "SVK", "SWZ", "TCD", "TJK", "TKM", "UGA", "UZB", "XKX", "ZMB", "ZWE", "BIH",
]

var facilities: Array = []
var projects: Array = []
var next_id := 1
## Muda sempre que uma instalação ou obra muda de estado: a interface e o mapa refazem suas listas.
var revision := 0
var rng := RandomNumberGenerator.new()
## Por país (índice): comércio, PIB e turismo reais do início, para medir a demanda.
var base_trade := PackedFloat32Array()
var base_gdp := PackedFloat32Array()
var base_tour := PackedFloat32Array()
## Por país e tipo (índice * 2 + 0 porto, + 1 aeroporto): saturação do início e a atual (-1 = não tem).
var sat0 := PackedFloat32Array()
var sat := PackedFloat32Array()
## Impulsos setoriais que este sistema já somou em cada país, para trocar pelo novo sem tocar nos dos outros.
var applied: Array = []
var _by_owner := {}
## Por país e tipo (mesmo índice de `sat`): as instalações que o país controla hoje.
var _lists: Array = []
var _by_id := {}
var _index_key := -1
## Países com instalação fechada ou danificada: só eles precisam da etapa de reparo fora da guerra.
var _hurt := {}
## Somas de demanda-base e capacidade efetiva por país e tipo, da última repartição completa. Nos meses sem
## repartição completa, a saturação sai delas; `_dirty` marca os países em que algo mudou desde então.
var _sum_base := PackedFloat32Array()
var _sum_eff := PackedFloat32Array()
var _dirty := {}
var _dirty_all := true


func setup(world: GameWorld) -> void:
	rng.seed = hash([world.rng.seed, "infra"])
	facilities = []
	projects = []
	_hurt = {}
	next_id = 1
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/infra.json"))
	for c: Country in world.countries:
		if data.has(c.iso):
			for row: Array in data[c.iso]:
				_add_from_row(c.iso, row)
		else:
			_generate(c, world)
	var n := world.countries.size()
	base_trade.resize(n)
	base_gdp.resize(n)
	base_tour.resize(n)
	sat0.resize(n * 2)
	sat.resize(n * 2)
	_sum_base.resize(n * 2)
	_sum_eff.resize(n * 2)
	applied = []
	for c: Country in world.countries:
		base_trade[c.idx] = _trade_real(c, world)
		base_gdp[c.idx] = _gdp_real(c, world)
		base_tour[c.idx] = _tour_real(c, world)
		var zero := PackedFloat32Array()
		zero.resize(Sectors.COUNT)
		applied.append(zero)
	_rebuild_index(world)
	for c: Country in world.countries:
		for k in 2:
			_allocate(c, 1.0, k)
			sat0[c.idx * 2 + k] = sat[c.idx * 2 + k]
	revision += 1


func _add_from_row(iso: String, row: Array) -> void:
	var f := _facility(iso, String(row[0]), String(row[1]), String(row[2]), float(row[5]), String(row[6]), String(row[7]))
	f.lat = float(row[3])
	f.lon = float(row[4])
	var u0 := float(row[8]) if row.size() > 8 else (0.8 if f.kind == PORT else 0.82)
	f.base = cap_eq(f) * u0
	f.attract = f.base
	facilities.append(f)


func _facility(iso: String, kind: String, fname: String, city: String, cap: float, unit: String, owner: String) -> Dictionary:
	var f := {
		"id": next_id, "iso": iso, "kind": kind, "name": fname, "city": city, "lat": 0.0, "lon": 0.0,
		"cap": cap, "unit": unit, "owner": owner, "cond": 1.0, "closed": false, "exposure": rng.randf_range(0.05, 1.0),
		"base": 0.0, "attract": 0.0, "use": 0.0, "util": 0.0, "since": 0.0,
	}
	next_id += 1
	return f


## Países fora do arquivo de dados: um aeroporto na capital e, se houver litoral, um porto, do tamanho que a
## economia e a abertura comercial pedem.
func _generate(c: Country, world: GameWorld) -> void:
	var subs := world.subdivisions
	var city := c.name
	var pos := c.center
	if subs.capitals.has(c.iso) and subs.units.has(subs.capitals[c.iso]):
		var unit: Dictionary = subs.units[subs.capitals[c.iso]]
		city = String(unit.name)
		pos = unit.center
	var air := _facility(c.iso, AIR, tr("Aeroporto Internacional de %s") % city, city, snappedf(maxf(generated_capacity(c, AIR), 0.2), 0.1), "pax", "public")
	air.pos = pos
	air.base = cap_eq(air) * 0.8
	air.attract = air.base
	facilities.append(air)
	if not c.iso in LANDLOCKED:
		var port := _facility(c.iso, PORT, tr("Porto de %s") % c.name, city, snappedf(maxf(generated_capacity(c, PORT), 0.5), 0.5), "t", "public")
		port.pos = pos + Vector2(4.0, 3.0)
		port.base = cap_eq(port) * 0.8
		port.attract = port.base
		facilities.append(port)


## Capacidade "natural" para o tamanho do país: toneladas por comércio exterior, passageiros por renda e população.
static func generated_capacity(c: Country, kind: String) -> float:
	if kind == PORT:
		var trade := c.y_usd() * clampf(c.x_share + c.m_share, 0.05, 2.0)
		return trade * 0.6 / 0.8
	var trips := clampf(0.02 + c.gdp_pc() / 12000.0, 0.02, 6.0)
	return c.pop * trips / 0.82


# --- Medidas ---------------------------------------------------------------------

static func eq_factor(unit: String) -> float:
	return TEU_TONS if unit == "TEU" else 1.0


## Capacidade nominal em unidades comparáveis entre portos (toneladas) e entre aeroportos (passageiros).
static func cap_eq(f: Dictionary) -> float:
	return float(f.cap) * eq_factor(f.unit)


## Capacidade que de fato opera: some com o fechamento, cai com o dano.
static func effective(f: Dictionary) -> float:
	if f.closed:
		return 0.0
	return cap_eq(f) * float(f.cond) * (CONCESSION_EFFICIENCY if f.owner == "concession" else 1.0)


## Obras ficam mais baratas onde a mão de obra é barata.
static func cost_factor(c: Country) -> float:
	return clampf(pow(c.gdp_pc() / 40000.0, 0.35), 0.45, 1.3)


static func replacement_cost(f: Dictionary, c: Country) -> float:
	return float(f.cap) * float(UNIT_COST[f.unit]) * cost_factor(c)


## Perda de produtividade por saturação: nada até 80%, depois cresce rápido; folga ajuda um pouco.
static func penalty(s: float) -> float:
	if s < 0.0:
		return 0.0
	if s < 0.6:
		return -(0.6 - s) * 0.1
	if s < 0.8:
		return 0.0
	if s < 1.0:
		return (s - 0.8) * (s - 0.8) * 2.5
	return minf(0.1 + (s - 1.0) * 0.8, 0.6)


func _trade_real(c: Country, world: GameWorld) -> float:
	return maxf((c.exports + c.imports) / maxf(world.global_price_index(), 0.01), 0.001)


func _gdp_real(c: Country, world: GameWorld) -> float:
	return maxf(c.y_usd() / maxf(world.global_price_index(), 0.01), 0.001)


func _tour_real(c: Country, world: GameWorld) -> float:
	var share: float = c.sector_share[Sectors.TOURISM] if c.sector_share.size() == Sectors.COUNT else 0.03
	return maxf(_gdp_real(c, world) * share, 0.0001)


## Quanto a demanda do país cresceu desde o início do jogo, por tipo.
func driver_ratio(c: Country, world: GameWorld, k: int) -> float:
	var gpi := maxf(world.global_price_index(), 0.01)
	if k == 0:
		return clampf((c.exports + c.imports) / gpi / maxf(base_trade[c.idx], 0.001), 0.05, 20.0)
	var gdp := c.y_usd() / gpi
	var share: float = c.sector_share[Sectors.TOURISM] if c.sector_share.size() == Sectors.COUNT else 0.03
	var g := gdp / maxf(base_gdp[c.idx], 0.001)
	var t := gdp * share / maxf(base_tour[c.idx], 0.0001)
	return clampf(0.6 * pow(g, 1.2) + 0.4 * t, 0.05, 20.0)


func saturation(c: Country, kind: String) -> float:
	return sat[c.idx * 2 + KINDS.find(kind)] if c.idx * 2 + 1 < sat.size() else -1.0


# --- Consultas da interface ------------------------------------------------------

## Quem controla cada instalação só muda quando um país é anexado ou uma obra nova fica pronta.
func _index_key_now(world: GameWorld) -> int:
	var dead := 0
	for c: Country in world.countries:
		if not c.alive:
			dead += 1
	return facilities.size() * 1000 + dead


func _rebuild_index(world: GameWorld) -> void:
	_by_owner = {}
	_by_id = {}
	_lists = []
	_lists.resize(world.countries.size() * 2)
	for i in _lists.size():
		_lists[i] = []
	for f: Dictionary in facilities:
		_by_id[int(f.id)] = f
		var owner := world.resolve_owner(f.iso)
		if owner == null or not owner.alive:
			continue
		if not _by_owner.has(owner.idx):
			_by_owner[owner.idx] = []
		_by_owner[owner.idx].append(f)
		_lists[owner.idx * 2 + (0 if f.kind == PORT else 1)].append(f)
		if f.closed or float(f.cond) < 1.0:
			_hurt[owner.idx] = true
	_index_key = _index_key_now(world)
	_dirty_all = true


func _ensure_index(world: GameWorld) -> void:
	if _index_key != _index_key_now(world):
		_rebuild_index(world)


func facilities_of(c: Country, world: GameWorld) -> Array:
	_ensure_index(world)
	return _by_owner.get(c.idx, [])


func facility(id: int) -> Dictionary:
	return _by_id.get(id, {})


func projects_of(c: Country) -> Array:
	return projects.filter(func(p): return int(p.payer) == c.idx)


func project_on(id: int) -> Dictionary:
	for p: Dictionary in projects:
		if int(p.fac) == id:
			return p
	return {}


func has_project(c: Country, kind: String) -> bool:
	for p: Dictionary in projects:
		if int(p.payer) == c.idx and p.kind == kind and p.public:
			return true
	return false


func can_build_port(c: Country) -> bool:
	if not c.iso in LANDLOCKED:
		return true
	for f: Dictionary in facilities:
		if f.iso == c.iso and f.kind == PORT:
			return true
	return false


## Capacidade total do país, nas unidades comparáveis do tipo, para dimensionar obras novas.
func total_capacity(c: Country, world: GameWorld, kind: String) -> float:
	var t := 0.0
	for f: Dictionary in facilities_of(c, world):
		if f.kind == kind:
			t += cap_eq(f)
	return t


## Custo e prazo de ampliar uma instalação em `pct` (0.5 = +50%).
func expansion_quote(f: Dictionary, c: Country, pct: float) -> Dictionary:
	var add := float(f.cap) * pct
	var months := int(round((30.0 if f.kind == PORT else 36.0) * (0.8 + 0.4 * pct)))
	return {"add": add, "cost": add * float(UNIT_COST[f.unit]) * cost_factor(c), "months": months}


## Custo e prazo de um porto ou aeroporto novo de tamanho `size` (índice em NEW_SIZES).
func new_quote(c: Country, world: GameWorld, kind: String, size: int) -> Dictionary:
	var frac: float = NEW_SIZES[size][1]
	var total := maxf(total_capacity(c, world, kind), generated_capacity(c, kind))
	var unit := "TEU" if kind == PORT else "pax"
	var cap := maxf(snappedf(total * frac / eq_factor(unit), 0.1), 0.2 if kind == PORT else 1.0)
	var months := int(round((48.0 if kind == PORT else 54.0) * (0.85 + 0.6 * frac)))
	return {"add": cap, "unit": unit, "cost": cap * float(UNIT_COST[unit]) * cost_factor(c) * 1.35, "months": months}


func concession_value(f: Dictionary, c: Country) -> float:
	return replacement_cost(f, c) * CONCESSION_SHARE * float(f.cond) * clampf(float(f.util) / 0.8, 0.5, 1.2)


## Cidades onde o país já tem instalações (para escolher onde construir), sem repetir.
func cities_of(c: Country, world: GameWorld) -> Array:
	var out := []
	var seen := {}
	for f: Dictionary in facilities_of(c, world):
		if not seen.has(f.city):
			seen[f.city] = true
			out.append(f)
	return out


# --- Ações -----------------------------------------------------------------------

func start_expansion(world: GameWorld, c: Country, id: int, pct: float, public := true) -> Dictionary:
	var f := facility(id)
	if f.is_empty() or world.resolve_owner(f.iso) != c:
		return {"ok": false, "msg": tr("Instalação não encontrada.")}
	if public and f.owner != "public":
		return {"ok": false, "msg": tr("%s é operado pela iniciativa privada: quem amplia é a concessionária.") % f.name}
	if not project_on(id).is_empty():
		return {"ok": false, "msg": tr("Já há uma obra em %s.") % f.name}
	if f.closed:
		return {"ok": false, "msg": tr("%s está fechado.") % f.name}
	var q := expansion_quote(f, c, pct)
	projects.append({
		"id": next_id, "payer": c.idx, "fac": id, "kind": f.kind, "public": public, "add": q.add,
		"cost": q.cost if public else 0.0, "months": q.months, "left": q.months, "label": tr("Ampliação de %s") % f.name,
	})
	next_id += 1
	revision += 1
	if c == world.player:
		var who := tr("O governo") if public else tr("A operadora")
		world.emit_news(tr("%s começa a ampliar %s: +%d%% de capacidade em %s.") % [who, f.name, int(round(pct * 100.0)), years_text(q.months)], "economia", c)
	return {"ok": true, "msg": tr("Obra iniciada: %s, %s.") % [_money(q.cost), years_text(q.months)] if public else tr("A operadora amplia %s.") % f.name}


## Constrói uma instalação nova perto de `near` (outra instalação do país, cuja cidade empresta o local).
func start_new(world: GameWorld, c: Country, kind: String, near_id: int, size: int) -> Dictionary:
	var near := facility(near_id)
	if near.is_empty() or world.resolve_owner(near.iso) != c:
		return {"ok": false, "msg": tr("Escolha uma cidade do país.")}
	if kind == PORT and not can_build_port(c):
		return {"ok": false, "msg": tr("%s não tem litoral.") % c.name}
	var count := 0
	for f: Dictionary in facilities_of(c, world):
		if f.kind == kind:
			count += 1
	for p: Dictionary in projects:
		if int(p.payer) == c.idx and int(p.fac) < 0 and p.kind == kind:
			count += 1
	if count >= MAX_PER_KIND:
		return {"ok": false, "msg": tr("O país já tem instalações demais desse tipo.")}
	var q := new_quote(c, world, kind, size)
	var label := (tr("Novo porto de %s") if kind == PORT else tr("Novo aeroporto de %s")) % near.city
	var spec := {"city": near.city, "lat": float(near.lat) + 0.12, "lon": float(near.lon) + 0.12, "unit": q.unit, "iso": c.iso}
	if near.has("pos"):
		spec.pos = (near.pos as Vector2) + Vector2(3.0, -3.0)
	projects.append({
		"id": next_id, "payer": c.idx, "fac": -1, "kind": kind, "public": true, "add": q.add, "cost": q.cost,
		"months": q.months, "left": q.months, "label": label, "spec": spec,
	})
	next_id += 1
	revision += 1
	if c == world.player:
		world.emit_news(tr("Começa a construção do %s: %s em %s.") % [_lower_first(label), _money(q.cost), years_text(q.months)], "economia", c)
	return {"ok": true, "msg": tr("Obra iniciada: %s, %s.") % [_money(q.cost), years_text(q.months)]}


func concede(world: GameWorld, c: Country, id: int) -> Dictionary:
	var f := facility(id)
	if f.is_empty() or world.resolve_owner(f.iso) != c:
		return {"ok": false, "msg": tr("Instalação não encontrada.")}
	if f.owner != "public":
		return {"ok": false, "msg": tr("%s já é operado pela iniciativa privada.") % f.name}
	if not project_on(id).is_empty():
		return {"ok": false, "msg": tr("Espere a obra em %s terminar.") % f.name}
	if f.closed:
		return {"ok": false, "msg": tr("Ninguém compra a concessão de um ativo fechado.")}
	var value := concession_value(f, c)
	f.owner = "concession"
	_dirty[c.idx] = true
	c.extra_rev_bucket += value
	revision += 1
	if c == world.player:
		world.emit_news(tr("%s é concedido à iniciativa privada por %s.") % [f.name, _money(value)], "economia", c)
	return {"ok": true, "msg": tr("Concessão assinada: %s entram no Tesouro.") % _money(value), "value": value}


static func _money(b: float) -> String:
	return TranslationServer.translate("US$ %s bi") % (UiKit.num(b, 1) if b < 10.0 else str(int(round(b))))


static func _lower_first(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1)


static func years_text(months: int) -> String:
	if months % 12 == 0:
		return TranslationServer.translate("%d anos") % int(months / 12.0) if months >= 24 else TranslationServer.translate("1 ano")
	return TranslationServer.translate("%s anos") % UiKit.num(months / 12.0, 1)


# --- Etapa mensal ----------------------------------------------------------------

## Chamado uma vez por mês, depois da legislação.
func step_month(world: GameWorld) -> void:
	if base_gdp.size() != world.countries.size():
		setup(world)
	_ensure_index(world)
	_step_projects(world)
	var governed := world.governed()
	var at_war := {}
	for w: Dictionary in world.diplomacy.wars:
		for i: int in w.a + w.d:
			at_war[i] = true
	for c: Country in world.countries:
		if not c.alive:
			continue
		var facs: Array = _by_owner.get(c.idx, [])
		_hazards(c, world, facs, at_war.has(c.idx))
		# A repartição por instalação (o que a tela mostra e o que move as decisões de obra) roda a cada
		# trimestre, todo mês no país do jogador e sempre que algo mudou; no resto, basta a saturação.
		var quarter := (world.months_elapsed + c.idx) % 3 == 0
		var full := quarter or c == world.player or _dirty_all or _dirty.has(c.idx)
		for k in 2:
			if _lists[c.idx * 2 + k].is_empty():
				sat[c.idx * 2 + k] = -1.0
			elif full:
				_allocate(c, driver_ratio(c, world, k), k)
			else:
				_quick_saturation(c, driver_ratio(c, world, k), k)
		_apply_effects(c)
		if quarter:
			_private_investment(c, world, facs)
			if c != governed:
				_state_investment(c, world, facs)
	_dirty = {}
	_dirty_all = false


func _step_projects(world: GameWorld) -> void:
	var keep := []
	for p: Dictionary in projects:
		var c: Country = world.countries[p.payer]
		if not c.alive:
			revision += 1
			continue
		var f := facility(int(p.fac)) if int(p.fac) >= 0 else {}
		if int(p.fac) >= 0 and f.is_empty():
			continue
		# Obra em instalação fechada fica parada: nem avança, nem custa.
		if not f.is_empty() and f.closed:
			keep.append(p)
			continue
		if p.public:
			c.extra_spend_bucket += float(p.cost) / float(p.months)
		p.left = int(p.left) - 1
		if int(p.left) > 0:
			keep.append(p)
			continue
		revision += 1
		if f.is_empty():
			var spec: Dictionary = p.spec
			var fresh := _facility(spec.iso, p.kind, String(p.label), spec.city, float(p.add), spec.unit, "public")
			fresh.lat = spec.lat
			fresh.lon = spec.lon
			if spec.has("pos"):
				fresh.pos = spec.pos
			fresh.since = world.year_float()
			facilities.append(fresh)
			if c == world.player:
				world.emit_news(tr("Inaugurado o %s, com capacidade para %s por ano.") % [_lower_first(String(p.label)), capacity_text(fresh)], "economia", c)
		else:
			f.cap = float(f.cap) + float(p.add)
			var owner := world.resolve_owner(f.iso)
			if owner:
				_dirty[owner.idx] = true
			if c == world.player:
				world.emit_news(tr("Concluída a ampliação de %s: agora %s por ano.") % [f.name, capacity_text(f)], "economia", c)
	projects = keep
	_ensure_index(world)


static func capacity_text(f: Dictionary) -> String:
	var v := float(f.cap)
	var txt := UiKit.num(v, 1) if v < 10.0 else str(int(round(v)))
	match String(f.unit):
		"TEU": return TranslationServer.translate("%s mi TEU") % txt
		"t": return TranslationServer.translate("%s mi t") % txt
	return TranslationServer.translate("%s mi passageiros") % txt


## Guerra danifica, ocupação fecha, paz conserta (o Estado paga o reparo do que é dele).
func _hazards(c: Country, world: GameWorld, facs: Array, war: bool) -> void:
	if facs.is_empty():
		return
	var occ := maxf(c.occupied - c.occ0, 0.0)
	# Uma vez por semestre, todos passam pela checagem (pega dano vindo de fora deste sistema).
	if not war and occ <= 0.0 and not _hurt.has(c.idx) and world.months_elapsed % 6 != 0:
		return
	var hurt := false
	var shut := []
	var reopened := []
	for f: Dictionary in facs:
		var closed := occ > float(f.exposure)
		if closed != bool(f.closed):
			f.closed = closed
			revision += 1
			_dirty[c.idx] = true
			(shut if closed else reopened).append(String(f.name))
		if war and not closed and rng.randf() < 0.012 + 0.08 * occ:
			var hit := rng.randf_range(0.15, 0.45)
			f.cond = maxf(float(f.cond) - hit, 0.05)
			revision += 1
			_dirty[c.idx] = true
			if c == world.player:
				world.emit_news(tr("Ataque danifica %s: a capacidade cai para %d%%.") % [f.name, int(float(f.cond) * 100.0)], "guerra", c)
		elif float(f.cond) < 1.0 and not closed:
			var rate := 0.01 if war else 0.04
			f.cond = minf(float(f.cond) + rate, 1.0)
			_dirty[c.idx] = true
			if f.owner == "public":
				c.extra_spend_bucket += replacement_cost(f, c) * rate * 0.5
		if f.closed or float(f.cond) < 1.0:
			hurt = true
	if hurt:
		_hurt[c.idx] = true
	else:
		_hurt.erase(c.idx)
	if c == world.player:
		if not shut.is_empty():
			world.emit_news(tr("%s: a região está ocupada pelo inimigo.") % _closing_text(shut, tr("fecha"), tr("fecham")), "guerra", c)
		if not reopened.is_empty():
			world.emit_news("%s." % _closing_text(reopened, tr("volta a operar"), tr("voltam a operar")), "economia", c)


## "Porto de Santos fecha", "Santos e Galeão fecham", "Santos, Galeão e mais 3 fecham".
static func _closing_text(names: Array, one: String, many: String) -> String:
	if names.size() == 1:
		return "%s %s" % [names[0], one]
	if names.size() == 2:
		return TranslationServer.translate("%s e %s %s") % [names[0], names[1], many]
	return TranslationServer.translate("%s, %s e mais %d instalações %s") % [names[0], names[1], names.size() - 2, many]


## Reparte a demanda do país entre as instalações de um tipo e mede a saturação.
func _allocate(c: Country, ratio: float, k: int) -> void:
	var slot := c.idx * 2 + k
	var facs: Array = _lists[slot]
	var n := facs.size()
	if n == 0:
		sat[slot] = -1.0
		return
	var eff := PackedFloat32Array()
	eff.resize(n)
	var att := PackedFloat32Array()
	att.resize(n)
	var demand := 0.0
	var eff_total := 0.0
	var att_total := 0.0
	for i in n:
		var f: Dictionary = facs[i]
		demand += float(f.base)
		var e := 0.0
		if not f.closed:
			e = float(f.cap) * (TEU_TONS if f.unit == "TEU" else 1.0) * float(f.cond) * (CONCESSION_EFFICIENCY if f.owner == "concession" else 1.0)
		eff[i] = e
		# A clientela de cada instalação acompanha devagar a capacidade que ela oferece.
		var a := float(f.attract)
		a += (e * 0.8 - a) * 0.03
		f.attract = a
		if e > 0.0:
			att[i] = maxf(a, e * 0.05)
			att_total += att[i]
		eff_total += e
	_sum_base[slot] = demand
	_sum_eff[slot] = eff_total
	demand *= ratio
	if eff_total <= 0.0:
		for f: Dictionary in facs:
			f.use = 0.0
			f.util = 0.0
		sat[slot] = 2.0
		return
	# Primeiro, cada uma recebe sua clientela; o que passa da capacidade vai para quem tem folga.
	var use := PackedFloat32Array()
	use.resize(n)
	var excess := 0.0
	var spare := 0.0
	for i in n:
		var want := demand * att[i] / att_total
		use[i] = minf(want, eff[i])
		excess += want - use[i]
		spare += eff[i] - use[i]
	var moved := minf(excess, spare)
	for i in n:
		var e := eff[i]
		var u := use[i]
		if moved > 0.0:
			u += moved * (e - u) / spare
		if excess > spare:
			u += (excess - spare) * e / eff_total
		var f: Dictionary = facs[i]
		f.use = u
		f.util = u / e if e > 0.0 else 0.0
	sat[slot] = demand / eff_total


func _quick_saturation(c: Country, ratio: float, k: int) -> void:
	var slot := c.idx * 2 + k
	if sat[slot] < 0.0:
		return
	var eff := _sum_eff[slot]
	sat[slot] = _sum_base[slot] * ratio / eff if eff > 0.0 else 2.0


## Logística e setores, medidos contra a saturação de partida.
func _apply_effects(c: Country) -> void:
	var sp := sat[c.idx * 2]
	var sa := sat[c.idx * 2 + 1]
	var qp := penalty(sat0[c.idx * 2]) - penalty(sp) if sp >= 0.0 else 0.0
	var qa := penalty(sat0[c.idx * 2 + 1]) - penalty(sa) if sa >= 0.0 else 0.0
	var wp := 0.7 if sp >= 0.0 else 0.0
	c.logistics = clampf(1.0 + wp * qp + (1.0 - wp) * qa, 0.4, 1.2)
	if c.sector_boost.size() != Sectors.COUNT:
		return
	var done: PackedFloat32Array = applied[c.idx]
	_boost(c, done, Sectors.TRANSPORT, 0.3 * (wp * qp + (1.0 - wp) * qa))
	_boost(c, done, Sectors.TOURISM, 0.3 * qa)
	_boost(c, done, Sectors.TRADE, 0.06 * qp)
	_boost(c, done, Sectors.INDUSTRY, 0.05 * qp)
	applied[c.idx] = done


static func _boost(c: Country, done: PackedFloat32Array, i: int, target: float) -> void:
	var v := clampf(target, -0.15, 0.06)
	if v != done[i]:
		c.sector_boost[i] += v - done[i]
		done[i] = v


## Concessionárias e operadores privados ampliam sozinhos o que lota, sem dinheiro público.
func _private_investment(c: Country, world: GameWorld, facs: Array) -> void:
	for f: Dictionary in facs:
		if float(f.util) < 0.95 or f.owner == "public" or f.closed or rng.randf() > 0.15:
			continue
		if project_on(int(f.id)).is_empty():
			start_expansion(world, c, int(f.id), 0.4, false)


## Governos da IA ampliam ou constroem quando o país satura e as contas permitem.
func _state_investment(c: Country, world: GameWorld, facs: Array) -> void:
	if (world.months_elapsed + c.idx) % 3 != 0:
		return
	if c.debt_ratio > c.debt_tol * 1.4 or world.year_float() < c.default_until:
		return
	for k in 2:
		var kind: String = KINDS[k]
		var s := sat[c.idx * 2 + k]
		if s < 0.92 or has_project(c, kind) or rng.randf() > 0.35:
			continue
		var best: Dictionary = {}
		for f: Dictionary in facs:
			if f.kind == kind and f.owner == "public" and not f.closed and project_on(int(f.id)).is_empty():
				if best.is_empty() or float(f.util) > float(best.util):
					best = f
		if best.is_empty():
			continue
		if s > 1.1 and rng.randf() < 0.3:
			start_new(world, c, kind, int(best.id), 1)
		else:
			start_expansion(world, c, int(best.id), 0.5)


# --- Salvar e carregar -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"facilities": facilities.duplicate(true), "projects": projects.duplicate(true), "next_id": next_id,
		"base_trade": base_trade, "base_gdp": base_gdp, "base_tour": base_tour, "sat0": sat0, "sat": sat,
		"applied": applied.duplicate(true), "rng_seed": rng.seed, "rng_state": rng.state,
	}


func from_dict(d: Dictionary, world: GameWorld) -> void:
	if not d.has("facilities"):
		setup(world)
		return
	facilities = d.facilities.duplicate(true)
	projects = d.projects.duplicate(true)
	next_id = int(d.next_id)
	base_trade = d.base_trade
	base_gdp = d.base_gdp
	base_tour = d.base_tour
	sat0 = d.sat0
	sat = d.sat
	applied = d.applied.duplicate(true)
	rng.seed = d.rng_seed
	rng.state = d.rng_state
	_rebuild_index(world)
	revision += 1
	_sum_base.resize(sat.size())
	_sum_eff.resize(sat.size())
