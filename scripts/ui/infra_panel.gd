class_name InfraPanel
extends VBoxContainer
## Portos e aeroportos do país.

var world: GameWorld


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.player == null:
		return
