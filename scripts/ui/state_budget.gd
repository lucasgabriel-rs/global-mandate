class_name StateBudget
extends VBoxContainer
## "Orçamento da unidade" window: the tax rate and the spending the unit sets itself. Areas that the union
## decides (see Competences) are shown but locked.

var world: GameWorld
var _syncing := false

@onready var _balance: Label = %balance_label
@onready var _note: Label = %budget_note
@onready var _tax: HSlider = %tax_slider
@onready var _tax_value: Label = %v_tax_slider
@onready var _areas := {
	"health": [%sp_health, %v_sp_health], "education": [%sp_education, %v_sp_education],
	"public_security": [%sp_public_security, %v_sp_public_security], "infrastructure": [%sp_infrastructure, %v_sp_infrastructure],
}


func _ready() -> void:
	_tax.value_changed.connect(func(v: float):
		if not _syncing and world and world.governor:
			world.governor.set_tax(v / 100.0)
			refresh())
	for area: String in _areas:
		(_areas[area][0] as HSlider).value_changed.connect(func(v: float):
			if not _syncing and world and world.governor:
				world.governor.set_spend(area, v / 100.0)
				refresh())


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.governor == null:
		return
	var gov := world.governor
	_syncing = true
	_tax.value = gov.tax_rate * 100.0
	_tax.editable = Competences.decides(gov.union_iso, "taxes")
	_tax_value.text = UiKit.pct(gov.tax_rate)
	for area: String in _areas:
		var slider: HSlider = _areas[area][0]
		slider.value = float(gov.spend.get(area, 0.0)) * 100.0
		slider.editable = Competences.decides(gov.union_iso, area)
		(_areas[area][1] as Label).text = UiKit.pct(float(gov.spend.get(area, 0.0)))
	_syncing = false
	var gdp := maxf(gov.gdp(world), 0.001)
	var balance := (gov.revenue(world) - gov.spending(world)) / gdp
	_balance.text = tr("Resultado: %s%.1f%% do PIB") % ["+" if balance > 0.0 else "", balance * 100.0]
	_balance.add_theme_color_override("font_color", UiKit.RED if balance < -0.02 else (UiKit.GREEN if balance >= 0.0 else UiKit.TEXT))
	_note.text = tr("As áreas travadas são decididas pela União.")
