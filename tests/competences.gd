extends SceneTree
## Tests of the competences table (who decides what: state, union or both), without the interface.
## Usage: godot --headless --path . -s tests/competences.gd

var failures := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok: ", what)
	else:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	_check(Competences.decides("BRA", "health") and not Competences.is_unitary("BRA"), "Brazil is federal and its states decide health")
	_check(Competences.decides("USA", "public_security"), "US states decide public security")
	_check(Competences.is_unitary("FRA"), "France is unitary")
	_check(Competences.state_weight("FRA") < Competences.state_weight("BRA"), "a unitary country gives its regions less weight")
	_check(Competences.state_weight("BRA") > 0.0 and Competences.state_weight("BRA") <= 1.0, "the weight is a share between 0 and 1")
	var table := Competences.for_country("XXX")
	_check(not table.is_empty(), "an unknown country gets the default table")
	var bad := 0
	for iso: String in ["BRA", "USA", "FRA", "XXX"]:
		var t := Competences.for_country(iso)
		for area: String in Competences.AREAS:
			if not t.get(area, "") in ["state", "union", "shared"]:
				bad += 1
	_check(bad == 0, "every table covers every area with a valid owner")
	print("RESULT: ", failures, " failures")
	quit(1 if failures > 0 else 0)
