class_name LawCode
extends RefCounted
## Um código legal (Tributário, Penal, Trabalhista, Civil, Eleitoral, Direitos e deveres): seus blocos
## concretos, o texto com que o país começa a partida e o efeito de cada bloco no jogo.
##
## Cada código mora em um arquivo próprio em `scripts/sim/codes/` e é registrado em `LawCodes`.
## Blocos seguem o formato de `LawCatalog.BLOCKS`, com `cat` igual a `category.id`. Prefira campos
## de escolha e números a texto livre: o jogador não deve precisar digitar nomes.
##
## Roda na thread da simulação: nada de nós nem sinais; notícias só por `world.emit_news`.

## Identificador curto ("tributario") e nome da norma ("Código Tributário").
var id := ""
var title := ""
var ementa := ""
## Categoria da paleta do editor: {"id", "label", "color"}.
var category := {}
## Tipo de norma do código: leis complementares, salvo a Constituição.
var norm_type := "complementar"


## Blocos do código.
func blocks() -> Array:
	return []


## Listas de escolha extras para os campos {"t": "choice", "of": ...}.
func choices() -> Dictionary:
	return {}


## Programa de blocos com que o país do jogador começa. Vazio: o código não é criado no início.
func seed_program(_world: GameWorld, _c: Country) -> Dictionary:
	return {}


## Efeito de um bloco deste código quando a norma executa. `weight` é a fração do grupo atingido;
## `norm_id` e `prio` vão para `leg.stand`, que guarda o efeito enquanto a norma valer.
## Devolve uma nota curta para o histórico, ou "".
func apply(_world: GameWorld, _leg: Legislation, _op: String, _values: Dictionary, _weight: float, _norm_id: int, _prio: float) -> String:
	return ""


## Uma vez por mês, para o país do jogador: o que o código em vigor faz com o país.
## Devolve contribuições que a legislação soma e repassa à economia e à política:
## approval, stability, invest, unemp (frações), inequality (variação do Gini, 0-1), labor (oferta
## de trabalho, fração), tfp (crescimento anual da produtividade), evasion (fração da arrecadação perdida).
## Indicadores próprios vão em `c.code_stats[chave]`.
func monthly(_world: GameWorld, _c: Country, _leg: Legislation) -> Dictionary:
	return {}
