class_name CompaniesPanel
extends VBoxContainer
## Empresas do país, de capital aberto e fechado.

var world: GameWorld


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.player == null:
		return
