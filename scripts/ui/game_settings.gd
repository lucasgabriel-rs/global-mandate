class_name GameSettings
extends RefCounted
## Opções de vídeo e interface do jogador. Ficam em user://settings.cfg (o idioma, em [game], é de Lang).
## Os testes de interface rodam sempre com os valores padrão, para as capturas não dependerem da máquina.

## Os testes trocam o caminho para não mexer nas opções reais do jogador.
static var path := Lang.SETTINGS_PATH
const SCALE_MIN := 0.75
const SCALE_MAX := 1.25
const SCALE_STEP := 0.05

static var fullscreen := false
static var vsync := true
static var ui_scale := 1.0


## Lê o arquivo e aplica. Chamado na abertura do jogo.
static func startup() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-"):
			return
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
		vsync = bool(cfg.get_value("video", "vsync", true))
		ui_scale = clampf(float(cfg.get_value("interface", "scale", 1.0)), SCALE_MIN, SCALE_MAX)
	apply()


static func apply() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.content_scale_factor = ui_scale


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("interface", "scale", ui_scale)
	cfg.save(path)


static func reset() -> void:
	fullscreen = false
	vsync = true
	ui_scale = 1.0
	apply()
	save()
