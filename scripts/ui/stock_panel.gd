class_name StockPanel
extends VBoxContainer
## A bolsa de valores do país.

var world: GameWorld


func bind(w: GameWorld) -> void:
	world = w


func refresh() -> void:
	if world == null or world.player == null:
		return
