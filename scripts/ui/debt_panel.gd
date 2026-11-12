class_name DebtPanel
extends VBoxContainer
## Seção de dívida da janela Fiscal: curva de juros, composição dos títulos, vencimentos e a dinâmica
## da razão dívida/PIB.

const TENOR_LABELS: Array[String] = ["3m", "1a", "2a", "5a", "10a", "30a"]

@onready var _curve: DebtChart = %debt_curve
@onready var _mats: DebtChart = %debt_maturities
@onready var _maturity: Label = %debt_maturity_value
@onready var _mix: Label = %debt_mix_value
@onready var _rollover: Label = %debt_rollover_value
@onready var _real: Label = %debt_real_value
@onready var _snow: Label = %debt_snowball_value
@onready var _primary: Label = %debt_primary_value
@onready var _adjust: Label = %debt_adjust_value


func refresh(c: Country) -> void:
	var texts: Array[String] = []
	for v in c.curve:
		texts.append("%.1f" % (v * 100.0))
	var labels: Array[String] = []
	for l in TENOR_LABELS:
		labels.append(tr(l))
	_curve.set_data(c.curve, labels, texts)

	var mats := Economy.maturities(c, 5)
	var usd := PackedFloat32Array()
	var mtexts: Array[String] = []
	var years: Array[String] = []
	for i in mats.size():
		usd.append(mats[i] / c.e)
		mtexts.append(UiKit.money(mats[i] / c.e))
		years.append("+%d" % (i + 1))
	_mats.set_data(usd, years, mtexts)

	var yn := maxf(c.y_nominal(), 0.001)
	_maturity.text = tr("%.1f anos") % c.debt_maturity
	var total := maxf(c.debt_loc + c.debt_fx * c.e, 0.001)
	var il := c.debt_loc * c.debt_il_share / total
	var fx := c.debt_fx * c.e / total
	_mix.text = "%s / %s / %s" % [UiKit.pct(1.0 - il - fx, 0), UiKit.pct(il, 0), UiKit.pct(fx, 0)]
	_rollover.text = "%s  (%s)" % [UiKit.money(c.rollover / c.e), UiKit.pct(c.rollover / yn)]
	_real.text = UiKit.pct(Economy.real_yield_at(c, 10.0), 2)
	var d: Dictionary = c.debt_dyn
	_snow.text = UiKit.pct(d.snowball, 1)
	_snow.add_theme_color_override("font_color", UiKit.RED if d.snowball > 0.005 else UiKit.TEXT)
	_primary.text = UiKit.pct(d.primary, 1)
	_primary.add_theme_color_override("font_color", UiKit.GREEN if d.primary > 0.0 else UiKit.RED)
	_adjust.text = UiKit.pct(d.adjust, 1)
