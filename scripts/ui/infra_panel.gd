class_name InfraPanel
extends VBoxContainer
## Ports and airports of the country: use of each one, ongoing works and the decisions to expand, build and
## concede. The decision form is embedded in the panel (infra_build.tscn).

const ROW := preload("res://scenes/ui/rows/infra_row.tscn")
const PROJECT_ROW := preload("res://scenes/ui/rows/infra_project_row.tscn")
const EXPAND_LABELS := ["+25%", "+50%", "+100%"]

var world: GameWorld
## "expand", "new" or "concede" while the form is open.
var _mode := ""
var _target := -1
var _kind := ""
var _cities: Array = []

@onready var _port_sat: Label = %port_sat
@onready var _air_sat: Label = %air_sat
@onready var _logistics: Label = %logistics
@onready var _build_port: Button = %build_port
@onready var _build_air: Button = %build_air
@onready var _feedback: Label = %feedback
@onready var form: PanelContainer = %form
@onready var _no_projects: Label = %no_projects
@onready var _project_rows: VBoxContainer = %project_rows
@onready var _ports_title: Label = %PortsTitle
@onready var _port_rows: VBoxContainer = %port_rows
@onready var _air_rows: VBoxContainer = %air_rows
@onready var _form_title: Label = form.get_node("%form_title")
@onready var _form_body: Label = form.get_node("%form_body")
@onready var _city_line: Control = form.get_node("%CityLine")
@onready var _city_pick: OptionButton = form.get_node("%city_pick")
@onready var _size_line: Control = form.get_node("%SizeLine")
@onready var _size_pick: OptionButton = form.get_node("%size_pick")
@onready var _quote: Label = form.get_node("%quote")
@onready var _confirm: Button = form.get_node("%form_confirm")


func _ready() -> void:
	_build_port.pressed.connect(func(): open_new(Infrastructure.PORT))
	_build_air.pressed.connect(func(): open_new(Infrastructure.AIR))
	form.get_node("%form_cancel").pressed.connect(close_form)
	_confirm.pressed.connect(_on_confirm)
	_size_pick.item_selected.connect(func(_i): _update_quote())
	_city_pick.item_selected.connect(func(_i): _update_quote())


func bind(w: GameWorld) -> void:
	world = w
	close_form()
	_feedback.visible = false


func refresh() -> void:
	if world == null or world.player == null:
		return
	var c := world.player
	var inf := world.infra
	var office := world.in_office
	_saturation_label(_port_sat, inf.saturation(c, Infrastructure.PORT))
	_saturation_label(_air_sat, inf.saturation(c, Infrastructure.AIR))
	var l := c.logistics - 1.0
	_logistics.text = tr("neutra") if absf(l) < 0.005 else (tr("%s no comércio") % ("+" + UiKit.pct(l) if l > 0.0 else UiKit.pct(l)))
	_logistics.add_theme_color_override("font_color", UiKit.good_bad(l if absf(l) >= 0.005 else 0.0))
	var can_port := inf.can_build_port(c)
	_build_port.disabled = not office or not can_port
	_build_port.tooltip_text = "" if can_port else tr("%s não tem litoral.") % c.name
	_build_air.disabled = not office
	var facs := inf.facilities_of(c, world)
	var ports := facs.filter(func(f): return f.kind == Infrastructure.PORT)
	var airs := facs.filter(func(f): return f.kind == Infrastructure.AIR)
	_ports_title.text = tr("PORTOS") if not ports.is_empty() else tr("PORTOS: o país não tem porto marítimo")
	_fill(_port_rows, ports, c, office)
	_fill(_air_rows, airs, c, office)
	_fill_projects(c)
	if _mode != "":
		_update_quote()


func _saturation_label(label: Label, s: float) -> void:
	if s < 0.0:
		label.text = "—"
		label.add_theme_color_override("font_color", UiKit.DIM)
		return
	label.text = tr("%s da capacidade") % UiKit.pct(s, 0)
	label.add_theme_color_override("font_color", _use_color(s))


static func _use_color(u: float) -> Color:
	if u >= 0.95:
		return UiKit.RED
	if u >= 0.8:
		return UiKit.ACCENT
	return UiKit.GREEN


## Rows are reused: only those that are missing or left over are created or removed.
func _fill(box: VBoxContainer, list: Array, c: Country, office: bool) -> void:
	list.sort_custom(func(a, b): return Infrastructure.cap_eq(a) > Infrastructure.cap_eq(b))
	while box.get_child_count() < list.size():
		var row: Control = ROW.instantiate()
		box.add_child(row)
		var fill: StyleBoxFlat = (row.get_node("%fac_bar") as ProgressBar).get_theme_stylebox("fill").duplicate()
		(row.get_node("%fac_bar") as ProgressBar).add_theme_stylebox_override("fill", fill)
		row.get_node("%expand").pressed.connect(func(): open_expand(int(row.get_meta("id"))))
		row.get_node("%concede").pressed.connect(func(): open_concede(int(row.get_meta("id"))))
	while box.get_child_count() > list.size():
		var extra := box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.queue_free()
	var inf := world.infra
	for i in list.size():
		var f: Dictionary = list[i]
		var row: Control = box.get_child(i)
		row.set_meta("id", int(f.id))
		var util := float(f.util)
		(row.get_node("%fac_name") as Label).text = String(f.name)
		(row.get_node("%fac_owner") as Label).text = String(Infrastructure.OWNER_NAMES.get(f.owner, ""))
		var use: Label = row.get_node("%fac_use")
		use.text = tr("fechado") if f.closed else UiKit.pct(util, 0)
		use.add_theme_color_override("font_color", UiKit.RED if f.closed else _use_color(util))
		var bar: ProgressBar = row.get_node("%fac_bar")
		bar.value = minf(util, 1.0)
		(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = _use_color(util)
		var parts := [tr("%s · %s por ano") % [f.city, Infrastructure.capacity_text(f)]]
		if f.closed:
			parts.append(tr("fechado: região ocupada"))
		elif float(f.cond) < 0.999:
			parts.append(tr("danificado, opera a %d%%") % int(float(f.cond) * 100.0))
		var p := inf.project_on(int(f.id))
		if not p.is_empty():
			parts.append(tr("em obra: +%s") % Infrastructure.capacity_text({"cap": p.add, "unit": f.unit}))
		(row.get_node("%fac_detail") as Label).text = " · ".join(parts)
		var public: bool = f.owner == "public"
		var blocked: bool = not office or f.closed or not p.is_empty()
		for key in ["%expand", "%concede"]:
			var b: Button = row.get_node(key)
			b.visible = public
			b.disabled = blocked


func _fill_projects(c: Country) -> void:
	var list := world.infra.projects_of(c)
	_no_projects.visible = list.is_empty()
	while _project_rows.get_child_count() < list.size():
		_project_rows.add_child(PROJECT_ROW.instantiate())
	while _project_rows.get_child_count() > list.size():
		var extra := _project_rows.get_child(_project_rows.get_child_count() - 1)
		_project_rows.remove_child(extra)
		extra.queue_free()
	for i in list.size():
		var p: Dictionary = list[i]
		var row: Control = _project_rows.get_child(i)
		(row.get_node("%proj_name") as Label).text = String(p.label)
		var left := int(p.left)
		(row.get_node("%proj_left") as Label).text = tr("falta 1 mês") if left == 1 else tr("faltam %d meses") % left
		var unit: String = p.spec.unit if p.has("spec") else String(world.infra.facility(int(p.fac)).get("unit", "t"))
		var added := tr("+%s por ano") % Infrastructure.capacity_text({"cap": p.add, "unit": unit})
		var paid := tr("%s, pagos mês a mês pelo Tesouro") % UiKit.money(float(p.cost)) if p.public else tr("paga pela operadora")
		(row.get_node("%proj_detail") as Label).text = "%s · %s" % [added, paid]
		(row.get_node("%proj_bar") as ProgressBar).value = 1.0 - float(left) / maxf(float(p.months), 1.0)


# --- Form --------------------------------------------------------------------

func open_expand(id: int) -> void:
	var f := world.infra.facility(id)
	if f.is_empty():
		return
	_mode = "expand"
	_target = id
	_form_title.text = tr("Ampliar %s") % f.name
	_form_body.text = tr("Hoje: %s por ano, %s em uso. A obra é paga mês a mês pelo Tesouro e só aumenta a capacidade quando termina.") % [Infrastructure.capacity_text(f), UiKit.pct(float(f.util), 0)]
	_city_line.visible = false
	_size_line.visible = true
	_size_pick.clear()
	for label: String in EXPAND_LABELS:
		_size_pick.add_item(label)
	_size_pick.select(1)
	_confirm.text = tr("Iniciar obra")
	_show_form()


func open_new(kind: String) -> void:
	var c := world.player
	_mode = "new"
	_kind = kind
	_target = -1
	var port := kind == Infrastructure.PORT
	_form_title.text = tr("Construir porto") if port else tr("Construir aeroporto")
	_form_body.text = (tr("Um porto novo divide a carga com os outros e alivia os que estão lotados.") if port else tr("Um aeroporto novo alivia os que estão lotados e ajuda o turismo.")) + tr(" Leva anos, e o custo sai mês a mês pelo Tesouro.")
	# A new port only where there is already a port (coast); an airport in any city with a facility.
	_cities = world.infra.cities_of(c, world).filter(func(f): return not port or f.kind == Infrastructure.PORT)
	if _cities.is_empty():
		_cities = world.infra.cities_of(c, world)
	_city_pick.clear()
	for f: Dictionary in _cities:
		_city_pick.add_item(String(f.city))
	_city_line.visible = true
	_size_line.visible = true
	_size_pick.clear()
	for item: Array in Infrastructure.NEW_SIZES:
		_size_pick.add_item(String(item[0]))
	_size_pick.select(1)
	_confirm.text = tr("Iniciar obra")
	_show_form()


func open_concede(id: int) -> void:
	var f := world.infra.facility(id)
	if f.is_empty():
		return
	_mode = "concede"
	_target = id
	_form_title.text = tr("Conceder %s") % f.name
	_form_body.text = tr("Uma operadora privada assume o ativo e paga uma outorga única ao Tesouro. Ela opera um pouco melhor e amplia por conta própria quando lotar, mas o governo deixa de decidir sobre ele.")
	_city_line.visible = false
	_size_line.visible = false
	_confirm.text = tr("Assinar concessão")
	_show_form()


func _show_form() -> void:
	_feedback.visible = false
	form.visible = true
	_update_quote()


func close_form() -> void:
	_mode = ""
	_target = -1
	if form:
		form.visible = false


func _update_quote() -> void:
	var c := world.player
	var inf := world.infra
	match _mode:
		"expand":
			var f := inf.facility(_target)
			if f.is_empty():
				close_form()
				return
			var q := inf.expansion_quote(f, c, Infrastructure.EXPAND_OPTIONS[maxi(_size_pick.selected, 0)])
			_quote.text = _quote_text(q.add, f.unit, q.cost, q.months)
		"new":
			if _cities.is_empty():
				_quote.text = tr("O país não tem onde construir.")
				_confirm.disabled = true
				return
			var q := inf.new_quote(c, world, _kind, maxi(_size_pick.selected, 0))
			_quote.text = _quote_text(q.add, q.unit, q.cost, q.months)
		"concede":
			var f := inf.facility(_target)
			if f.is_empty():
				close_form()
				return
			_quote.text = tr("Outorga estimada: %s, de uma vez.") % UiKit.money(inf.concession_value(f, c))
	_confirm.disabled = not world.in_office


func _quote_text(add: float, unit: String, cost: float, months: int) -> String:
	return tr("+%s por ano · %s em %s (%s por mês)") % [Infrastructure.capacity_text({"cap": add, "unit": unit}), UiKit.money(cost), Infrastructure.years_text(months), UiKit.money(cost / months)]


func _on_confirm() -> void:
	var c := world.player
	var inf := world.infra
	var r := {}
	match _mode:
		"expand":
			r = inf.start_expansion(world, c, _target, Infrastructure.EXPAND_OPTIONS[maxi(_size_pick.selected, 0)])
		"new":
			var near: Dictionary = _cities[maxi(_city_pick.selected, 0)]
			r = inf.start_new(world, c, _kind, int(near.id), maxi(_size_pick.selected, 0))
		"concede":
			r = inf.concede(world, c, _target)
	if r.is_empty():
		return
	close_form()
	_feedback.text = r.msg
	_feedback.add_theme_color_override("font_color", UiKit.GREEN if r.ok else UiKit.RED)
	_feedback.visible = true
	world.refresh_map = true
	refresh()
