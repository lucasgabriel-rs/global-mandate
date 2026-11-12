extends SceneTree
## Toda cena de interface precisa abrir sem erro e sem dois nós de mesmo nome sob o mesmo pai: nomes
## repetidos fazem os containers deixarem nós fora da organização da tela.
## Uso: godot --headless --path . --script tests/scenes.gd

var failures := 0


func _walk(path: String, out: Array) -> void:
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".tscn"):
			out.append(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_walk(path.path_join(d), out)


func _init() -> void:
	var all := []
	_walk("res://scenes", all)
	for path: String in all:
		var seen := {}
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if not line.begins_with("[node ") or not line.contains(" parent=\""):
				continue
			var key := "%s/%s" % [line.get_slice("parent=\"", 1).get_slice("\"", 0), line.get_slice("name=\"", 1).get_slice("\"", 0)]
			if seen.has(key):
				failures += 1
				print("FAIL: nome repetido em %s: %s" % [path, key])
			seen[key] = true
		var scene: PackedScene = load(path)
		var node := scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) if scene else null
		if node == null:
			failures += 1
			print("FAIL: não abre: ", path)
		else:
			node.free()
	print("%d cenas conferidas" % all.size())
	print("RESULT: %d failures" % failures)
	quit()
