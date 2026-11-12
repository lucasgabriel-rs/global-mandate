class_name LawCode
extends RefCounted
## A legal code (Tax, Criminal, Labor, Civil, Electoral, Rights and duties): its concrete blocks,
## the text the country starts the match with and each block's effect in the game.
##
## Each code lives in its own file in `scripts/sim/codes/` and is registered in `LawCodes`.
## Blocks follow the format of `LawCatalog.BLOCKS`, with `cat` equal to `category.id`. Prefer choice
## fields and numbers to free text: the player should not have to type names.
##
## Runs on the simulation thread: no nodes or signals; news only through `world.emit_news`.

## Short identifier ("tributario") and norm name ("Código Tributário").
var id := ""
var title := ""
var ementa := ""
## Editor palette category: {"id", "label", "color"}.
var category := {}
## Norm type of the code: complementary laws, except for the Constitution.
var norm_type := "complementar"


## Blocks of the code.
func blocks() -> Array:
	return []


## Extra choice lists for the fields {"t": "choice", "of": ...}.
func choices() -> Dictionary:
	return {}


## Block program the player's country starts with. Empty: the code is not created at the start.
func seed_program(_world: GameWorld, _c: Country) -> Dictionary:
	return {}


## Effect of a block of this code when the norm executes. `weight` is the fraction of the group reached;
## `norm_id` and `prio` go to `leg.stand`, which keeps the effect while the norm applies.
## Returns a short note for the history, or "".
func apply(_world: GameWorld, _leg: Legislation, _op: String, _values: Dictionary, _weight: float, _norm_id: int, _prio: float) -> String:
	return ""


## Once a month, for the player's country: what the code in force does to the country.
## Returns contributions that legislation adds up and passes on to the economy and politics:
## approval, stability, invest, unemp (fractions), inequality (Gini change, 0-1), labor (labor
## supply, fraction), tfp (annual productivity growth), evasion (share of revenue lost).
## Own indicators go in `c.code_stats[key]`.
func monthly(_world: GameWorld, _c: Country, _leg: Legislation) -> Dictionary:
	return {}
