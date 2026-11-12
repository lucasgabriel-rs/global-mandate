class_name LawCodes
extends RefCounted
## Registry of the legal codes. The order here is the order in the editor palette and in the legislative center.

const SCRIPTS := [
	preload("res://scripts/sim/codes/code_tributario.gd"),
	preload("res://scripts/sim/codes/code_trabalhista.gd"),
	preload("res://scripts/sim/codes/code_penal.gd"),
	preload("res://scripts/sim/codes/code_civil.gd"),
	preload("res://scripts/sim/codes/code_eleitoral.gd"),
	preload("res://scripts/sim/codes/code_direitos.gd"),
	preload("res://scripts/sim/codes/code_cambial.gd"),
]

static var _codes: Array = []
static var _owner := {}
static var _mutex := Mutex.new()


## Builds the registry once. After that everything is read-only, safe between threads.
static func warm() -> void:
	_mutex.lock()
	if _codes.is_empty():
		var codes := []
		var owner := {}
		for script: GDScript in SCRIPTS:
			var code: LawCode = script.new()
			codes.append(code)
			for b: Dictionary in code.blocks():
				owner[b.id] = code
		_owner = owner
		_codes = codes
	_mutex.unlock()


static func all() -> Array:
	warm()
	return _codes


static func get_code(id: String) -> LawCode:
	for code: LawCode in all():
		if code.id == id:
			return code
	return null


## The code that owns a block type, or null for the advanced blocks.
static func owner_of(block_type: String) -> LawCode:
	warm()
	return _owner.get(block_type)
