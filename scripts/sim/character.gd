class_name Character
extends RefCounted
## Data of the player's character: a plain dictionary, easy to save. The portrait is a countryball with the
## country's flag (Countryball); the gender decides the bow and the drawn names.
## "name" holds the full name, always equal to first name + surname, for whoever only reads the name.

const GENDERS := ["m", "f"]
# i18n-begin
const GENDER_LABELS := {"m": "Masculino", "f": "Feminino"}
# i18n-end


static func random(rng: RandomNumberGenerator, iso := "", region := "") -> Dictionary:
	var c := {
		"gender": GENDERS[rng.randi() % GENDERS.size()],
		"birth_year": GameWorld.START_YEAR - rng.randi_range(38, 62),
		"econ": rng.randf_range(-0.8, 0.8),
		"social": rng.randf_range(-0.8, 0.8),
	}
	reroll_name(c, Names.group_for(iso, region), rng)
	return c


static func full_name(c: Dictionary) -> String:
	if c.has("first_name"):
		return ("%s %s" % [c.first_name, c.get("last_name", "")]).strip_edges()
	return String(c.get("name", ""))


static func set_names(c: Dictionary, first: String, last: String) -> void:
	c["first_name"] = first
	c["last_name"] = last
	c["name"] = full_name(c)


## Draws first name and surname of the character's gender. Both stay marked as drawn until the player types.
static func reroll_name(c: Dictionary, group: String, rng: RandomNumberGenerator) -> void:
	var gender := String(c.get("gender", "m"))
	set_names(c, Names.first(group, gender, rng), Names.last(group, gender, rng))
	c["first_rolled"] = true
	c["last_rolled"] = true


## Changing the gender swaps the drawn first name for one of the new gender and turns the drawn surname into the
## gender's form (Ivanov, Ivanova). What the player typed stays as it is.
static func set_gender(c: Dictionary, gender: String, group: String, rng: RandomNumberGenerator) -> void:
	c["gender"] = gender
	var first := String(c.get("first_name", ""))
	var last := String(c.get("last_name", ""))
	if c.get("first_rolled", false):
		first = Names.first(group, gender, rng)
	if c.get("last_rolled", false):
		last = Names.regender_last(last, gender)
	set_names(c, first, last)


## Old saves keep only the full name: the first name goes up to the first space, and the gender comes from the first name.
static func migrated(old: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var c := old
	if not c.has("first_name"):
		var whole := String(c.get("name", "")).strip_edges()
		var cut := whole.find(" ")
		c["first_name"] = whole if cut < 0 else whole.substr(0, cut)
		c["last_name"] = "" if cut < 0 else whole.substr(cut + 1).strip_edges()
	if not c.has("gender"):
		c["gender"] = Names.guess_gender(c.first_name)
	if not c.has("econ"):
		c["econ"] = 0.0
		c["social"] = 0.0
	if not c.has("birth_year"):
		c["birth_year"] = GameWorld.START_YEAR - 50
	if full_name(c) == "":
		reroll_name(c, Names.DEFAULT_GROUP, rng)
	c["name"] = full_name(c)
	return c


## Politician as a character for the portrait: those from old saves have no gender, which comes from the first name.
static func for_politician(member: Dictionary) -> Dictionary:
	var gender := String(member.get("gender", ""))
	if gender == "":
		gender = Names.guess_gender(String(member.get("name", "")).get_slice(" ", 0))
	return {"name": member.get("name", ""), "gender": gender}


## Government title according to the country's regime.
static func title_for(c: Country) -> String:
	return TranslationServer.translate("Chefe de governo") if c.dem >= 4.0 else TranslationServer.translate("Líder supremo")
