extends Node
## Autoload. The player's video and interface options, kept in user://settings.cfg (the language, in [game],
## belongs to Lang). Applies the saved options and the language when the game opens.
## Interface tests always run with the default values, so screenshots do not depend on the machine.

const SCALE_MIN := 0.75
const SCALE_MAX := 1.25
const SCALE_STEP := 0.05

## Tests swap the path so they do not touch the player's real options.
var path := Lang.SETTINGS_PATH
var fullscreen := false
var vsync := true
var ui_scale := 1.0


func _ready() -> void:
	Lang.startup()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-"):
			return
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
		vsync = bool(cfg.get_value("video", "vsync", true))
		ui_scale = clampf(float(cfg.get_value("interface", "scale", 1.0)), SCALE_MIN, SCALE_MAX)
	apply()


func apply() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	get_tree().root.content_scale_factor = ui_scale


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("interface", "scale", ui_scale)
	cfg.save(path)


func reset() -> void:
	fullscreen = false
	vsync = true
	ui_scale = 1.0
	apply()
	save()
