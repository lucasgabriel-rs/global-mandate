class_name Competences
extends RefCounted
## Who decides what in a country: the subnational unit ("state"), the union ("union") or both ("shared").
## The table comes from data/competences.json: federal countries use their own row or the default one,
## the others are unitary and use the row where almost everything belongs to the union.

const AREAS := ["health", "education", "public_security", "infrastructure", "taxes"]
const SHARED_WEIGHT := 0.5

static var _data := {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/competences.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data


static func is_unitary(iso: String) -> bool:
	return not iso in _load().federal


## Area to "state", "union" or "shared".
static func for_country(iso: String) -> Dictionary:
	var d := _load()
	if d.countries.has(iso):
		return d.countries[iso]
	return d.default if not is_unitary(iso) else d.unitary_default


## True when the unit has a say in the area (its own or shared).
static func decides(iso: String, area: String) -> bool:
	return for_country(iso).get(area, "union") != "union"


## Share of the areas the unit decides, with shared ones counting half.
static func state_weight(iso: String) -> float:
	var table := for_country(iso)
	var total := 0.0
	for area: String in AREAS:
		match String(table.get(area, "union")):
			"state":
				total += 1.0
			"shared":
				total += SHARED_WEIGHT
	return total / float(AREAS.size())
