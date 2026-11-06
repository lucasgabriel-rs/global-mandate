class_name Character
extends RefCounted
## Dados do personagem do jogador: um dicionário simples, fácil de salvar. O retrato é uma countryball com a
## bandeira do país (Countryball); o gênero decide o laço e os nomes sorteados.
## "name" guarda o nome inteiro, sempre igual a prenome + sobrenome, para quem só lê o nome.

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


## Sorteia prenome e sobrenome do gênero do personagem. Os dois ficam marcados como sorteados até o jogador digitar.
static func reroll_name(c: Dictionary, group: String, rng: RandomNumberGenerator) -> void:
	var gender := String(c.get("gender", "m"))
	set_names(c, Names.first(group, gender, rng), Names.last(group, gender, rng))
	c["first_rolled"] = true
	c["last_rolled"] = true


## Trocar o gênero troca o prenome sorteado por um do gênero novo e passa o sobrenome sorteado para a forma
## do gênero (Ivanov, Ivanova). O que o jogador digitou fica como está.
static func set_gender(c: Dictionary, gender: String, group: String, rng: RandomNumberGenerator) -> void:
	c["gender"] = gender
	var first := String(c.get("first_name", ""))
	var last := String(c.get("last_name", ""))
	if c.get("first_rolled", false):
		first = Names.first(group, gender, rng)
	if c.get("last_rolled", false):
		last = Names.regender_last(last, gender)
	set_names(c, first, last)


## Saves antigos guardam só o nome inteiro: o prenome vai até o primeiro espaço, e o gênero sai do prenome.
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


## Político como personagem para o retrato: os de saves antigos não têm gênero, que sai do prenome.
static func for_politician(member: Dictionary) -> Dictionary:
	var gender := String(member.get("gender", ""))
	if gender == "":
		gender = Names.guess_gender(String(member.get("name", "")).get_slice(" ", 0))
	return {"name": member.get("name", ""), "gender": gender}


## Título de governo conforme o regime do país.
static func title_for(c: Country) -> String:
	return TranslationServer.translate("Chefe de governo") if c.dem >= 4.0 else TranslationServer.translate("Líder supremo")
