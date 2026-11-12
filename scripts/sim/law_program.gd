class_name LawProgram
extends RefCounted
## The visual program of a norm as plain data, easy to save and to version.
## Program: {"next_id": n, "stacks": [{"pos": [x, y], "repealed": bool, "blocks": [block...]}]}
## Block: {"id": n, "type": "ec_charge", "fields": {name: value}, "plugs": {name: block}, "slots": {name: [block...]}}
## Each stack that starts with an event is an article of the norm.


static func empty() -> Dictionary:
	return {"next_id": 1, "stacks": []}


static func new_block(program: Dictionary, type: String) -> Dictionary:
	var def := LawCatalog.get_def(type)
	var block := {"id": int(program.next_id), "type": type, "fields": {}, "plugs": {}, "slots": {}}
	program.next_id = int(program.next_id) + 1
	var fields: Dictionary = def.get("fields", {})
	for key: String in fields:
		if fields[key].has("d"):
			block.fields[key] = fields[key].d
	for slot: String in def.get("slots", []):
		block.slots[slot] = []
	return block


## Copies with new identifiers: used when dragging a ready-made template into another program.
static func clone(program: Dictionary, block: Dictionary) -> Dictionary:
	var copy: Dictionary = block.duplicate(true)
	_renumber(program, copy)
	return copy


static func _renumber(program: Dictionary, block: Dictionary) -> void:
	block.id = int(program.next_id)
	program.next_id = int(program.next_id) + 1
	for key: String in block.plugs:
		_renumber(program, block.plugs[key])
	for slot: String in block.slots:
		for inner: Dictionary in block.slots[slot]:
			_renumber(program, inner)


static func add_stack(program: Dictionary, block: Dictionary, pos: Vector2) -> Dictionary:
	var stack := {"pos": [pos.x, pos.y], "repealed": false, "blocks": [block]}
	program.stacks.append(stack)
	return stack


## Location of a block: {"list": list it is in, "index": i} or {"owner": block, "plug": field}.
static func locate(program: Dictionary, id: int) -> Dictionary:
	for stack: Dictionary in program.stacks:
		var found := _locate_in(stack.blocks, id)
		if not found.is_empty():
			found["stack"] = stack
			return found
	return {}


static func _locate_in(list: Array, id: int) -> Dictionary:
	for i in list.size():
		var block: Dictionary = list[i]
		if int(block.id) == id:
			return {"list": list, "index": i, "block": block}
		var found := _locate_inner(block, id)
		if not found.is_empty():
			return found
	return {}


static func _locate_inner(block: Dictionary, id: int) -> Dictionary:
	for key: String in block.plugs:
		var plug: Dictionary = block.plugs[key]
		if int(plug.id) == id:
			return {"owner": block, "plug": key, "block": plug}
		var deep := _locate_inner(plug, id)
		if not deep.is_empty():
			return deep
	for slot: String in block.slots:
		var deep := _locate_in(block.slots[slot], id)
		if not deep.is_empty():
			return deep
	return {}


## Takes out the block and everything below it in the same stack, as in Scratch. Returns the removed list.
static func detach(program: Dictionary, id: int) -> Array:
	var where := locate(program, id)
	if where.is_empty():
		return []
	if where.has("plug"):
		var plugged: Dictionary = where.owner.plugs[where.plug]
		where.owner.plugs.erase(where.plug)
		return [plugged]
	var list: Array = where.list
	var taken := list.slice(int(where.index))
	list.resize(int(where.index))
	_drop_empty(program)
	return taken


## Deletes only one block, keeping the ones below in place.
static func remove_one(program: Dictionary, id: int) -> void:
	var where := locate(program, id)
	if where.is_empty():
		return
	if where.has("plug"):
		where.owner.plugs.erase(where.plug)
	else:
		(where.list as Array).remove_at(int(where.index))
	_drop_empty(program)


static func _drop_empty(program: Dictionary) -> void:
	program.stacks = program.stacks.filter(func(s): return not s.blocks.is_empty())


## A list of blocks goes in right after (or before) the target block.
static func insert_near(program: Dictionary, target_id: int, blocks: Array, before: bool) -> bool:
	var where := locate(program, target_id)
	if where.is_empty() or where.has("plug"):
		return false
	var at := int(where.index) + (0 if before else 1)
	for b: Dictionary in blocks:
		(where.list as Array).insert(at, b)
		at += 1
	return true


static func insert_in_slot(program: Dictionary, owner_id: int, slot: String, blocks: Array) -> bool:
	var where := locate(program, owner_id)
	if where.is_empty() or not where.block.slots.has(slot):
		return false
	(where.block.slots[slot] as Array).append_array(blocks)
	return true


static func plug(program: Dictionary, owner_id: int, field: String, block: Dictionary) -> bool:
	var where := locate(program, owner_id)
	if where.is_empty():
		return false
	var def := LawCatalog.get_def(where.block.type)
	var spec: Dictionary = def.get("fields", {}).get(field, {})
	if spec.is_empty() or not accepts(spec, block):
		return false
	where.block.plugs[field] = block
	return true


static func accepts(spec: Dictionary, block: Dictionary) -> bool:
	var def := LawCatalog.get_def(block.type)
	if def.kind == "bool":
		return spec.t == "bool" or spec.t == "any"
	if def.kind == "value":
		return LawCatalog.compatible(String(def.get("out", "num")), String(spec.t))
	return false


static func contains(root: Dictionary, id: int) -> bool:
	return int(root.id) == id or not _locate_inner(root, id).is_empty()


static func walk(blocks: Array, fn: Callable) -> void:
	for block: Dictionary in blocks:
		fn.call(block)
		for key: String in block.plugs:
			walk([block.plugs[key]], fn)
		for slot: String in block.slots:
			walk(block.slots[slot], fn)


static func all_blocks(program: Dictionary) -> Array:
	var out := []
	for stack: Dictionary in program.stacks:
		walk(stack.blocks, func(b): out.append(b))
	return out


# --- Legal text ----------------------------------------------------------------------
# The text stored in the norm (LawCompiler) is always in Portuguese, the original language, so it does not change
# with the player's language. With localized, it comes out translated, to show on the screen.

static func block_text(block: Dictionary, localized := false) -> String:
	var def := LawCatalog.get_def(block.type)
	if def.is_empty():
		return Lang.tr_if("[bloco desconhecido]", localized)
	var out := ""
	for seg: Dictionary in LawCatalog.segments(def, localized):
		if seg.has("text"):
			out += seg.text
		else:
			out += field_text(block, seg.field, localized)
	return out


static func field_text(block: Dictionary, field: String, localized := false) -> String:
	if block.plugs.has(field):
		return block_text(block.plugs[field], localized)
	var spec: Dictionary = LawCatalog.get_def(block.type).get("fields", {}).get(field, {})
	if not block.fields.has(field):
		return "(...)"
	var value: Variant = block.fields[field]
	match spec.get("t", ""):
		"choice":
			return Lang.tr_if(String(LawCatalog.choice_list(spec.of).get(value, value)), localized)
		"money":
			return Lang.tr_if("%s moedas", localized) % UiKit.thousand(float(value))
		"unit":
			return Lang.tr_if("o território escolhido", localized) if int(value) >= 0 else Lang.tr_if("qualquer parte do país", localized)
		"bool":
			return Lang.tr_if("verdadeiro", localized) if value else Lang.tr_if("falso", localized)
	if value is float or value is int:
		return UiKit.num(float(value), 0) if is_equal_approx(float(value), roundf(float(value))) else UiKit.num(float(value), 2)
	return str(value)


## Text of the norm: each stack becomes an article, with the inner blocks as sub-items.
static func legal_text(program: Dictionary, localized := false) -> String:
	var lines := []
	var number := 0
	for stack: Dictionary in program.stacks:
		number += 1
		var head := Lang.tr_if("Art. %dº", localized) % number
		if stack.get("repealed", false):
			lines.append(Lang.tr_if("%s (Revogado.)", localized) % head)
			continue
		var blocks: Array = stack.blocks
		var first: Dictionary = blocks[0]
		lines.append("%s %s:" % [head, block_text(first, localized)])
		_legal_list(blocks.slice(1), 1, lines, localized)
	return "\n".join(lines)


static func _legal_list(blocks: Array, depth: int, lines: Array, localized: bool) -> void:
	var pad := "    ".repeat(depth)
	for block: Dictionary in blocks:
		lines.append("%s%s;" % [pad, block_text(block, localized)])
		for slot: String in block.slots:
			if slot == "else":
				lines.append(Lang.tr_if("%sCaso contrário:", localized) % pad)
			_legal_list(block.slots[slot], depth + 1, lines, localized)
