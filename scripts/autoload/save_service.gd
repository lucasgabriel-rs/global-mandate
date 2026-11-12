extends Node
## Autoload. Where the save file lives and how it is written and read. Interface tests (--ui-*) use their own
## file, so they never touch the player's real save.
##
## The write is safe: a temporary file is written and checked before it replaces the save, and the previous save
## stays as a backup copy. A damaged save falls back to the backup.

const DEFAULT_PATH := "user://mandato.save"
const TEST_PATH := "user://mandato_test.save"

## Main save file. The backup sits next to it with the extension .bak.
var path := DEFAULT_PATH
var backup_path: String:
	get:
		return path.get_basename() + ".bak"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-"):
			path = TEST_PATH


func has_save() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(backup_path)


## Writes the world. Returns "" on success or the problem, as text for the player (a translatable msgid).
func write(world: GameWorld) -> String:
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return TranslationServer.translate("Não foi possível salvar: erro %d.") % FileAccess.get_open_error()
	f.store_var(world.to_dict())
	f.close()
	var check := FileAccess.open(temp, FileAccess.READ)
	var readable: bool = check != null and check.get_var() is Dictionary
	if check:
		check.close()
	if not readable:
		return TranslationServer.translate("Não foi possível salvar: o arquivo não pôde ser conferido.")
	var folder := DirAccess.open(path.get_base_dir())
	if FileAccess.file_exists(path):
		folder.rename(path.get_file(), backup_path.get_file())
	folder.rename(temp.get_file(), path.get_file())
	return ""


## Reads the save, or the backup if the main file is damaged, and builds the world. Null if there is none.
## Safe to call from a worker thread.
func read() -> GameWorld:
	var raw: Variant = _read_dictionary(path)
	if not raw is Dictionary:
		raw = _read_dictionary(backup_path)
	if not raw is Dictionary:
		return null
	var fresh := GameWorld.new()
	fresh.setup()
	fresh.load_dict(raw)
	return fresh


## Removes the save and its backup (tests).
func delete_files() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))


func _read_dictionary(file_path: String) -> Variant:
	var f := FileAccess.open(file_path, FileAccess.READ)
	return f.get_var() if f else null
