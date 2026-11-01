class_name Character
extends RefCounted
## Dados do personagem do jogador: um dicionário simples, fácil de salvar. As formas são índices das
## peças desenhadas no VectorCraft (assets/character/manifest.json); as cores são livres, exceto a pele.

const MANIFEST := "res://assets/character/manifest.json"
const SHAPES := ["hair", "eyes", "face", "body", "outfit"]
const SHAPE_LABELS := {"hair": "Cabelo", "eyes": "Olhos", "face": "Rosto", "body": "Corpo", "outfit": "Roupa"}
const COLOR_KEYS := ["eyes_color", "hair_color", "clothes_color"]
const COLOR_LABELS := {"eyes_color": "Olhos", "hair_color": "Cabelo", "clothes_color": "Roupa"}
## Escala Monk de tons de pele (10 tons), usada em estudos de representação da pele humana. O jogador
## escolhe uma posição ao longo dela, então não existe como sair das cores reais da espécie.
const SKIN_TONES := [
	Color("f6ede4"), Color("f3e7db"), Color("f7ead0"), Color("eadaba"), Color("d7bd96"),
	Color("a07e56"), Color("825c43"), Color("604134"), Color("3a312a"), Color("292420"),
]
const NATURAL_HAIR := [Color("1d1a18"), Color("3d2a1c"), Color("6a4525"), Color("b0793a"), Color("e0c070"), Color("a8431f"), Color("8c8c8a"), Color("e8e6e0")]
const NATURAL_EYES := [Color("2e1c10"), Color("5a3a1e"), Color("3f6b4a"), Color("3b6d9e"), Color("7b8a94")]
const FIRST_NAMES := ["Helena", "Marcos", "Sofia", "Rafael", "Beatriz", "Tiago", "Lúcia", "André", "Clara", "Otávio", "Marina", "Vicente"]
const LAST_NAMES := ["Almeida", "Duarte", "Moreira", "Vargas", "Teixeira", "Nunes", "Campos", "Rezende", "Prado", "Salles"]

static var _manifest := {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.open(MANIFEST, FileAccess.READ).get_as_text())
	return _manifest


static func option_count(key: String) -> int:
	return manifest()[key].size()


static func option_label(key: String, index: int) -> String:
	return manifest()[key][index].label


## t vai de 0 (pele mais clara) a 1 (mais escura), interpolando entre tons reais vizinhos.
static func skin_color(t: float) -> Color:
	var x := clampf(t, 0.0, 1.0) * (SKIN_TONES.size() - 1)
	var i := mini(int(x), SKIN_TONES.size() - 2)
	return (SKIN_TONES[i] as Color).lerp(SKIN_TONES[i + 1], x - i)


static func random(rng: RandomNumberGenerator) -> Dictionary:
	var c := {
		"name": "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]],
		"skin": rng.randf(),
		"birth_year": GameWorld.START_YEAR - rng.randi_range(38, 62),
		"econ": rng.randf_range(-0.8, 0.8),
		"social": rng.randf_range(-0.8, 0.8),
		"hair_color": NATURAL_HAIR[rng.randi() % NATURAL_HAIR.size()],
		"eyes_color": NATURAL_EYES[rng.randi() % NATURAL_EYES.size()],
		"clothes_color": Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.75), rng.randf_range(0.3, 0.8)),
	}
	for key: String in SHAPES:
		c[key] = rng.randi() % option_count(key)
	return c


## Personagens de saves antigos, com outro formato, viram um novo com o mesmo nome.
static func migrated(old: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if old.has("face") and old.has("clothes_color"):
		if not old.has("econ"):
			old["econ"] = 0.0
			old["social"] = 0.0
		if not old.has("birth_year"):
			old["birth_year"] = GameWorld.START_YEAR - 50
		return old
	var fresh := random(rng)
	if old.has("name"):
		fresh.name = old.name
	return fresh


## Aparência de um político, sempre a mesma: nasce da semente guardada nele.
static func for_politician(member: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(member.get("seed", 1))
	var look := random(rng)
	look.name = member.name
	return look


## Título de governo conforme o regime do país.
static func title_for(c: Country) -> String:
	return "Chefe de governo" if c.dem >= 4.0 else "Líder supremo"
