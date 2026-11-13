extends SceneTree
## Saves written by v0.1.2 (tests/fixtures, generated with the old code) must still load: same country, date,
## party fund, norms, parties and diplomacy; the simulation keeps running; and saving and loading again
## (round trip) keeps everything. Usage: godot --headless --path . -s tests/save_compat.gd

const DIR := "res://tests/fixtures/"
var failures := 0


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
	print("ok: " if cond else "FAIL: ", what)


static func summary(w: GameWorld) -> Dictionary:
	var p := w.politics.player_party(w)
	return {
		"iso": w.player.iso, "day_index": w.day_index, "date": w.date_string(), "in_office": w.in_office,
		"fund": snappedf(w.politics.party_fund(w), 0.0001), "party": String(p.name), "party_id": int(p.id),
		"norms": w.legislation.norms.size(), "leader": String(w.leader.name), "difficulty": w.difficulty,
		"gdp": snappedf(w.player.y_usd(), 0.001), "approval": snappedf(w.player.approval, 0.00001),
		"ruling": int(w.politics.data_of(w.player.iso).ruling), "parties": w.politics.data_of(w.player.iso).parties.size(),
		"relation_usa": snappedf(w.diplomacy.relation(w.player.idx, w.by_iso["USA"].idx), 0.0001),
		"chats": w.chats.size(), "wars": w.diplomacy.wars.size(), "sanctions": w.diplomacy.sanctions.size(),
	}


func _load(dict: Dictionary) -> GameWorld:
	var w := GameWorld.new()
	w.setup()
	w.load_dict(dict)
	return w


func _same(a: Dictionary, b: Dictionary) -> String:
	for k: String in b:
		if k == "treaties":
			continue
		var same: bool = is_equal_approx(float(a.get(k)), float(b[k])) if (b[k] is float or b[k] is int) and not b[k] is bool else a.get(k) == b[k]
		if not same:
			return "%s: %s != %s" % [k, a.get(k), b[k]]
	return ""


func _init() -> void:
	for tag in ["government", "opposition"]:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + tag + ".json"))
		var raw: Variant = FileAccess.open(DIR + tag + ".save", FileAccess.READ).get_var()
		_check(raw is Dictionary, "%s: the old save file reads" % tag)
		var w := _load(raw)
		var diff := _same(summary(w), expected)
		_check(diff == "", "%s: country, date, fund, norms, parties and diplomacy match the old game %s" % [tag, diff])
		_check(w.in_office == (tag == "government"), "%s: role kept" % tag)
		for i in 12:
			w.tick_day()
		_check(w.day_index == int(expected.day_index) + 12 and is_finite(w.player.y_usd()), "%s: the simulation keeps running" % tag)
		# Round trip: save with the current code and load again.
		var again := _load(bytes_to_var(var_to_bytes(w.to_dict())))
		diff = _same(summary(again), summary(w))
		_check(diff == "", "%s: save and load again keeps everything %s" % [tag, diff])
		for i in 5:
			again.tick_day()
		_check(again.day_index == w.day_index + 5, "%s: runs after the round trip" % tag)
	print("RESULT: %d failures" % failures)
	quit()
