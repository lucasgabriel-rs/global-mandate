class_name Corporate
extends RefCounted
## Empresas de cada país e a bolsa de valores (capital aberto e capital fechado).
## Contrato com o resto do jogo: lê `Country.sector_out`/`sector_share` (ver Sectors), pode somar em
## `Country.sector_boost`, e é dono de `Country.stock`, o índice da bolsa. Nunca toca em nós nem emite sinais:
## roda na thread da simulação (notícias só por `world.emit_news`).


func setup(_world: GameWorld) -> void:
	pass


## Chamado uma vez por mês, depois da legislação.
func step_month(_world: GameWorld) -> void:
	pass


## Índice da bolsa, chamado na etapa mensal de cada país.
static func update_index(c: Country, world: GameWorld, growth: float) -> void:
	c.stock *= exp(clampf(0.05 + 2.0 * (growth - c.g0) - 1.0 * c.rgap - 0.3 * (world.global_risk - 0.2) + c.pi_yoy * 0.8 + world.rng.randfn(0.0, 0.14), -0.8, 0.8) * Economy.DT)


func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary, _world: GameWorld) -> void:
	pass
