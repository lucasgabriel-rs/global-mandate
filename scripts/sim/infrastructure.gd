class_name Infrastructure
extends RefCounted
## Portos e aeroportos de cada país.
## Contrato com o resto do jogo: escreve `Country.logistics` (1 = neutro) e soma em
## `Country.sector_boost[Sectors.TRANSPORT]`, `[Sectors.TOURISM]` etc. Nunca toca em nós nem emite sinais:
## roda na thread da simulação (notícias só por `world.emit_news`).


func setup(_world: GameWorld) -> void:
	pass


## Chamado uma vez por mês, depois da legislação.
func step_month(_world: GameWorld) -> void:
	pass


func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary, _world: GameWorld) -> void:
	pass
