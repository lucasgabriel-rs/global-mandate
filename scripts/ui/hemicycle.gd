class_name Hemicycle
extends Control
## Plenário em semicírculo: um ponto por assento, da esquerda à direita do espectro político.
## Partidos do governo têm o ponto cheio; os da oposição, um contorno em volta.

const MAX_ROWS := 9

var _seats: Array = []


func set_parties(parties: Array, coalition: Array) -> void:
	var ordered := parties.filter(func(p): return int(p.seats) > 0)
	ordered.sort_custom(func(a, b): return float(a.econ) < float(b.econ))
	_seats = []
	for p: Dictionary in ordered:
		for i in int(p.seats):
			_seats.append({"color": p.color, "government": p.id in coalition})
	queue_redraw()


## Posições dos assentos: fileiras concêntricas, com mais lugares nas de fora.
func seat_positions(count: int) -> PackedVector2Array:
	var center := Vector2(size.x * 0.5, size.y - 4.0)
	var outer := minf(size.x * 0.5 - 6.0, size.y - 10.0)
	var inner := outer * 0.34
	var rows := clampi(int(sqrt(count * 0.45)), 2, MAX_ROWS)
	var total_radius := 0.0
	var radii := []
	for r in rows:
		var radius := lerpf(inner, outer, float(r) / maxf(rows - 1, 1))
		radii.append(radius)
		total_radius += radius
	var places := []
	var used := 0
	for r in rows:
		var n := roundi(count * radii[r] / total_radius) if r < rows - 1 else count - used
		used += n
		for i in n:
			var a := PI - PI * (float(i) + 0.5) / maxf(n, 1)
			places.append([a, center + Vector2(cos(a), -sin(a)) * float(radii[r])])
	places.sort_custom(func(x, y): return x[0] > y[0])
	var out := PackedVector2Array()
	for place: Array in places:
		out.append(place[1])
	return out


func _draw() -> void:
	if _seats.is_empty():
		return
	var points := seat_positions(_seats.size())
	var outer := minf(size.x * 0.5 - 6.0, size.y - 10.0)
	var r := clampf(outer * 1.4 / sqrt(_seats.size() + 1.0) * 0.42, 1.3, 5.5)
	for i in points.size():
		var seat: Dictionary = _seats[i]
		draw_circle(points[i], r, seat.color)
		if not seat.government:
			draw_arc(points[i], r, 0.0, TAU, 10, Color(0.02, 0.05, 0.07, 0.85), 1.0, true)
