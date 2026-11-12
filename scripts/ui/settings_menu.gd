class_name SettingsMenu
extends Control
## Janela de configurações: idioma, modo de janela, sincronia vertical e escala da interface.
## Cada mudança vale na hora e fica guardada em GameSettings. Quem abre a janela ouve `closed`.

signal closed

@onready var _window_mode: OptionButton = %window_mode
@onready var _vsync: CheckButton = %vsync
@onready var _scale: HSlider = %ui_scale
@onready var _scale_value: Label = %ui_scale_value


func _ready() -> void:
	_scale.min_value = GameSettings.SCALE_MIN
	_scale.max_value = GameSettings.SCALE_MAX
	_scale.step = GameSettings.SCALE_STEP
	_show_current()
	_window_mode.item_selected.connect(func(i: int):
		GameSettings.fullscreen = i == 1
		_changed())
	_vsync.toggled.connect(func(on: bool):
		GameSettings.vsync = on
		_changed())
	# O valor só vale ao soltar o controle: mudar a escala a cada pixel arrastado refaz a tela inteira.
	_scale.value_changed.connect(func(v: float): _scale_value.text = "%d%%" % roundi(v * 100.0))
	_scale.drag_ended.connect(func(changed: bool):
		if changed:
			GameSettings.ui_scale = _scale.value
			_changed())
	%restaurar.pressed.connect(func():
		GameSettings.reset()
		_show_current())
	%voltar.pressed.connect(func(): closed.emit())


func _show_current() -> void:
	_window_mode.select(1 if GameSettings.fullscreen else 0)
	_vsync.set_pressed_no_signal(GameSettings.vsync)
	_scale.set_value_no_signal(GameSettings.ui_scale)
	_scale_value.text = "%d%%" % roundi(GameSettings.ui_scale * 100.0)


func _changed() -> void:
	GameSettings.apply()
	GameSettings.save()
