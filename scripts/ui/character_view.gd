class_name CharacterView
extends Control
## Monta o stickman empilhando as peças desenhadas no VectorCraft e pintando cada uma com a cor escolhida.
## As imagens têm 200 x 300 unidades; o retrato mostra só cabeça e ombros.

const PORTRAIT_REGION := Rect2(30, 0, 140, 140)

static var _textures := {}

var character: Dictionary = {}:
	set(value):
		character = value
		queue_redraw()
## Só cabeça e ombros, para espaços pequenos.
@export var portrait := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _texture(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load("res://assets/character/" + file)
	return _textures[file]


func _tint(layer: Dictionary) -> Color:
	match layer.get("tint", ""):
		"skin":
			return Character.skin_color(character.skin)
		"hair":
			return character.hair_color
		"eyes":
			return character.eyes_color
		"clothes":
			return character.clothes_color
	return Color.WHITE


## Quantas camadas seriam desenhadas: serve aos testes, que comparam com o que o manifesto lista.
func layers() -> Array:
	var m := Character.manifest()
	var body := int(character.body)
	var out: Array = []
	out.append_array(m.hair[int(character.hair)].back)
	out.append_array(m.body[body].layers)
	out.append_array(m.outfit[int(character.outfit)].byBody[body])
	out.append_array(m.face[int(character.face)].layers)
	out.append_array(m.eyes[int(character.eyes)].layers)
	out.append_array(m.hair[int(character.hair)].front)
	return out


func _draw() -> void:
	if character.is_empty():
		return
	var area := PORTRAIT_REGION if portrait else Rect2(0, 0, 200, 300)
	var k := minf(size.x / area.size.x, size.y / area.size.y)
	var origin := (size - area.size * k) * 0.5 - area.position * k
	var rect := Rect2(origin, Vector2(200, 300) * k)
	for layer: Dictionary in layers():
		draw_texture_rect(_texture(layer.file), rect, false, _tint(layer))
