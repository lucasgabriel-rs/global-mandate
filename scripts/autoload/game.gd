extends Node
## Autoload. The match in progress: the current world, shared by the interface instead of being handed from window
## to window. Main sets it when a match starts, loads or restarts.
##
## The simulation (scripts/sim) never reads this: autoloads do not exist for headless test scripts, and the world
## runs on worker threads. The world always reaches the simulation as an argument.

## Emitted after the world was replaced (new match, load or restart). Whoever cached the old world must drop it.
signal world_changed(world: GameWorld)

var world: GameWorld:
	set(value):
		world = value
		world_changed.emit(value)
