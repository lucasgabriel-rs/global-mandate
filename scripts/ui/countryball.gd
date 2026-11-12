class_name Countryball
extends Control
## Character portrait: a countryball with the country's flag, white eyes and no mouth.
## Female characters get a pink bow on top of the ball. The flag comes from data/flags.json;
## a country with no flag there becomes stripes with colors taken from the ISO code.

const FLAGS := "res://data/flags.json"
const OUTLINE := Color("141414")
const SHADOW := Color(0, 0, 0, 0.14)
const BOW := Color("ff6fb0")
const BOW_DARK := Color("e04891")
const SEGMENTS := 72
## Height of the bow above the ball, in diameters.
const BOW_ROOM := 0.14

static var _flags := {}

var character: Dictionary = {}:
	set(value):
		character = value
		queue_redraw()
## ISO code of the country whose flag the ball wears.
var iso := "":
	set(value):
		iso = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_person(person: Dictionary, country_iso: String) -> void:
	character = person
	iso = country_iso


func is_female() -> bool:
	return String(character.get("gender", "")) == "f"


static func flag(country_iso: String) -> Dictionary:
	if _flags.is_empty():
		_flags = JSON.parse_string(FileAccess.get_file_as_string(FLAGS))
	if _flags.has(country_iso):
		return _flags[country_iso]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(country_iso)
	var colors := []
	for i in 3:
		colors.append("#" + Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf_range(0.45, 0.95)).to_html(false))
	return {("h" if rng.randi() % 2 == 0 else "v"): colors}


## Where the ball sits: the bow needs space above it.
func ball_rect() -> Rect2:
	var room := BOW_ROOM if is_female() else 0.0
	var d := minf(size.x, size.y / (1.0 + room)) * 0.92
	var center := Vector2(size.x * 0.5, size.y * 0.5 + d * room * 0.5)
	return Rect2(center - Vector2(d, d) * 0.5, Vector2(d, d))


func _draw() -> void:
	if character.is_empty() and iso == "":
		return
	var box := ball_rect()
	var r := box.size.x * 0.5
	var center := box.get_center()
	var circle := _ellipse(center, Vector2(r, r))
	_draw_flag(flag(iso), box, circle)
	for part: PackedVector2Array in Geometry2D.clip_polygons(circle, _ellipse(center + Vector2(-r, -r) * 0.16, Vector2(r, r))):
		draw_colored_polygon(part, SHADOW)
	draw_arc(center, r, 0.0, TAU, SEGMENTS, OUTLINE, maxf(1.5, r * 0.06), true)
	_draw_eyes(center, r)
	if is_female():
		_draw_bow(center, r)


func _draw_flag(f: Dictionary, box: Rect2, circle: PackedVector2Array) -> void:
	var horizontal := f.has("h")
	var colors: Array = f.get("h", f.get("v", []))
	var weights: Array = f.get("w", [])
	var total := 0.0
	for i in colors.size():
		total += float(weights[i]) if i < weights.size() else 1.0
	var at := 0.0
	for i in colors.size():
		var share := (float(weights[i]) if i < weights.size() else 1.0) / total
		var stripe := Rect2(0, at, 1, share) if horizontal else Rect2(at, 0, share, 1)
		_fill(_rect_poly(stripe, box), Color(colors[i]), circle)
		at += share
	for shape: Dictionary in f.get("e", []):
		_fill(_shape_poly(shape, box), Color(shape.c), circle)


func _fill(poly: PackedVector2Array, color: Color, circle: PackedVector2Array) -> void:
	for part: PackedVector2Array in Geometry2D.intersect_polygons(poly, circle):
		draw_colored_polygon(part, color)


func _shape_poly(shape: Dictionary, box: Rect2) -> PackedVector2Array:
	var at := func(x: float, y: float) -> Vector2: return box.position + Vector2(x, y) * box.size
	if shape.has("rect"):
		var q: Array = shape.rect
		return _rect_poly(Rect2(q[0], q[1], q[2], q[3]), box)
	if shape.has("disc"):
		var q: Array = shape.disc
		var ry: float = q[3] if q.size() > 3 else q[2]
		return _ellipse(at.call(q[0], q[1]), Vector2(q[2], ry) * box.size)
	if shape.has("star"):
		var q: Array = shape.star
		var points := int(shape.get("n", 5))
		var inner := float(shape.get("in", 0.38))
		var c: Vector2 = at.call(q[0], q[1])
		var tips := PackedVector2Array()
		for i in points * 2:
			var a := -PI * 0.5 + PI * i / points
			tips.append(c + Vector2(cos(a), sin(a)) * float(q[2]) * box.size.x * (1.0 if i % 2 == 0 else inner))
		return tips
	var flat: Array = shape.get("poly", [])
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(at.call(flat[i], flat[i + 1]))
	return out


static func _rect_poly(unit: Rect2, box: Rect2) -> PackedVector2Array:
	var a := box.position + unit.position * box.size
	var b := a + unit.size * box.size
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


static func _ellipse(c: Vector2, radius: Vector2, steps := SEGMENTS) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		out.append(c + Vector2(cos(a), sin(a)) * radius)
	return out


## Countryball eyes: white, outlined, looking slightly sideways. They have eyelashes.
func _draw_eyes(center: Vector2, r: float) -> void:
	var width := maxf(1.0, r * 0.045)
	for side: float in [-1.0, 1.0]:
		var c := center + Vector2(r * (0.06 + side * 0.3), -r * 0.08)
		var eye := _ellipse(c, Vector2(r * 0.17, r * 0.22), 32)
		draw_colored_polygon(eye, Color.WHITE)
		eye.append(eye[0])
		draw_polyline(eye, OUTLINE, width, true)
		if is_female():
			for k: float in [0.0, 1.0]:
				var a := -PI * 0.5 + side * (0.55 + k * 0.4)
				var from := c + Vector2(cos(a) * r * 0.17, sin(a) * r * 0.22)
				draw_line(from, from + Vector2(cos(a), sin(a)) * r * 0.12, OUTLINE, width, true)


## Pink bow on top, slightly to the side, tilted following the curve of the ball.
func _draw_bow(center: Vector2, r: float) -> void:
	var angle := deg_to_rad(-62.0)
	var knot := center + Vector2(cos(angle), sin(angle)) * r * 0.97
	var turn := Transform2D(angle + PI * 0.5, knot)
	var s := r * 0.36
	var width := maxf(1.0, r * 0.04)
	for side: float in [-1.0, 1.0]:
		var loop := PackedVector2Array()
		for p: Vector2 in [Vector2(0, 0), Vector2(side * 0.75, -0.55), Vector2(side * 1.0, -0.2), Vector2(side * 0.95, 0.3), Vector2(side * 0.7, 0.5)]:
			loop.append(turn * (p * s))
		draw_colored_polygon(loop, BOW)
		loop.append(loop[0])
		draw_polyline(loop, OUTLINE, width, true)
	draw_circle(knot, s * 0.24, BOW_DARK, true, -1.0, true)
	draw_arc(knot, s * 0.24, 0.0, TAU, 24, OUTLINE, width, true)
