extends SceneTree
## Limits the subnational units to whatever contains them: states by the country's outline on the map and
## municipalities by the state. Runs after build_admin1.mjs and build_municipalities.mjs and rewrites
## data/admin1.json and data/municipalities.json. Running it again does not change the result.
## Uso: godot --headless --path . -s tools/clip_units.gd -- [--dry]
## To generate everything from scratch: build_map.mjs, build_admin1.mjs, build_municipalities.mjs and this script.
##
## A unit that falls entirely outside the outline, like an island that the map omits, becomes a small
## marker on the nearest edge: it keeps existing and can be selected, without leaving the limit.

const MIN_EXTRA_PIECE := 0.01
const MARKER_RADIUS := 0.12
const ADMIN1 := "res://data/admin1.json"
const MUNICIPALITIES := "res://data/municipalities.json"
const CAPITALS := "res://data/capitals.json"
const CITY_RADIUS := 0.35
## A unit with the capital's name and up to this area is the city itself (Paris, Berlin), with no extra unit.
const CITY_UNIT_MAX_AREA := 5.0


func _init() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var admin1: Dictionary = _read(ADMIN1)
	var mun: Dictionary = _read(MUNICIPALITIES)
	var rings_by_iso := GameData.native_rings()
	var enclaves := {}
	for iso: String in rings_by_iso:
		enclaves[iso] = GameData.native_enclaves(iso).map(func(e): return e.ring)

	var markers := []
	var state_pieces := {}
	var cut_units := 0
	var lost := 0.0
	var total := 0.0
	for u: Dictionary in admin1.units:
		var rings: Array = rings_by_iso.get(u.o, [])
		var before := _to_pieces(u.s)
		var after := _clip(before, rings, enclaves.get(u.o, []))
		var stats := _apply(u, before, after, rings, markers)
		cut_units += int(stats.x > 0.001)
		lost += stats.x
		total += stats.y
		if u.o == "BRA":
			state_pieces[u.n] = _to_pieces(u.s)
	print("states: %d clipped, %.2f%% of the area was outside the country" % [cut_units, 100.0 * lost / maxf(total, 0.001)])

	var cut_mun := 0
	var lost_mun := 0.0
	var total_mun := 0.0
	var mun_markers := []
	for u: Dictionary in mun.units:
		var container: Array = state_pieces[u.uf]
		var before := _to_pieces(u.s)
		var stats := _apply(u, before, _clip(before, container, []), container, mun_markers)
		cut_mun += int(stats.x > 0.001)
		lost_mun += stats.x
		total_mun += stats.y
	print("municipalities: %d clipped, %.2f%% of the area was outside the state" % [cut_mun, 100.0 * lost_mun / maxf(total_mun, 0.001)])
	print("markers: %d states/provinces: %s" % [markers.size(), ", ".join(markers.slice(0, 80))])
	print("markers: %d municipalities: %s" % [mun_markers.size(), ", ".join(mun_markers)])

	var arcs_before: int = admin1.arcs.size() + mun.arcs.size()
	admin1.arcs = _clip_arcs(admin1.arcs, func(arc): return [rings_by_iso.get(admin1.units[arc[0]].o, []), enclaves.get(admin1.units[arc[0]].o, [])])
	mun.arcs = _clip_arcs(mun.arcs, func(arc): return [state_pieces[mun.units[arc[0]].uf], []])
	print("borders: %d segments before, %d after" % [arcs_before, admin1.arcs.size() + mun.arcs.size()])

	var capitais: Dictionary = _read(CAPITALS)
	_place_capitals(capitais.capitals, admin1.units)

	if dry:
		print("--dry: nothing was written")
	else:
		_write(ADMIN1, admin1)
		_write(MUNICIPALITIES, mun)
		_write(CAPITALS, capitais)
		print("written")
	quit()


## Links each capital to the unit that contains it. If that unit is already the city, it is the capital itself;
## otherwise, the capital becomes a small unit inside it. Everything stays inside the country's limit.
func _place_capitals(capitals: Array, units: Array) -> void:
	var by_owner := {}
	for i in units.size():
		if not by_owner.has(units[i].o):
			by_owner[units[i].o] = []
		by_owner[units[i].o].append(i)
	var is_unit := 0
	var moved := []
	for cap: Dictionary in capitals:
		var pos := Vector2(cap.x, cap.y)
		var parent := -1
		var nearest := INF
		var nearest_point := pos
		var nearest_unit := -1
		for i: int in by_owner.get(cap.iso, []):
			for piece: PackedVector2Array in _to_pieces(units[i].s):
				# Only the outer outline is kept, so the province around an enclave also contains the point.
				if Geometry2D.is_point_in_polygon(pos, piece) and (parent < 0 or float(units[i].a) < float(units[parent].a)):
					parent = i
				for k in piece.size():
					var q := Geometry2D.get_closest_point_to_segment(pos, piece[k], piece[(k + 1) % piece.size()])
					if q.distance_squared_to(pos) < nearest:
						nearest = q.distance_squared_to(pos)
						nearest_point = q
						nearest_unit = i
		if parent < 0:
			parent = nearest_unit
			pos = nearest_point
			moved.append("%s (%s, %.1f)" % [cap.n, cap.iso, sqrt(nearest)])
		if parent < 0:
			print("capital without a unit: ", cap.n)
			continue
		cap.erase("s")
		cap.erase("a")
		cap.erase("b")
		cap.erase("c")
		cap.parent = parent
		var unit: Dictionary = units[parent]
		if _same_name(unit.n, cap.q) and float(unit.a) <= CITY_UNIT_MAX_AREA:
			cap.unit = parent
			is_unit += 1
			continue
		cap.erase("unit")
		var pieces := _to_pieces(unit.s)
		var r := minf(CITY_RADIUS, sqrt(float(unit.a)) * 0.2)
		var shape := PackedVector2Array()
		for i in 8:
			shape.append(pos + Vector2.from_angle(TAU * i / 8.0) * r)
		var inside := _usable(Subdivisions.intersect_all(shape, pieces))
		if inside.is_empty():
			inside = [_marker(pos, pieces)]
		_apply(cap, [shape], inside, pieces, [])
	print("capitals: %d are the unit itself, %d became a new unit" % [is_unit, capitals.size() - is_unit])
	print("capitals outside the outline, moved to the edge: ", ", ".join(moved))


func _same_name(a: String, b: String) -> bool:
	var x := a.to_lower().replace("-", " ")
	var y := b.to_lower().replace("-", " ")
	return x == y or x.begins_with(y + " ") or x.ends_with(" " + y) or y.begins_with(x + " ")


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false))


func _to_pieces(flat_list: Array) -> Array:
	var out := []
	for flat: Array in flat_list:
		var pts := PackedVector2Array()
		pts.resize(flat.size() / 2)
		for i in pts.size():
			pts[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
		out.append(pts)
	return out


func _clip(pieces: Array, container: Array, holes: Array) -> Array:
	var out := Subdivisions._intersect_pieces(pieces, container)
	for hole: PackedVector2Array in holes:
		out = Subdivisions.subtract(out, hole)
	return out


## Writes the new geometry to the unit. Returns Vector2(lost area, original area).
func _apply(u: Dictionary, before: Array, clipped: Array, container: Array, markers: Array) -> Vector2:
	var original := Subdivisions.total_area(before)
	var pieces := _usable(clipped)
	if pieces.is_empty():
		pieces = [_marker(Subdivisions._label_point(before), container)]
		markers.append(u.n)
	var flat := []
	for p: PackedVector2Array in pieces:
		var line := []
		for q in p:
			line.append(snappedf(q.x, 0.001))
			line.append(snappedf(q.y, 0.001))
		flat.append(line)
	var area := Subdivisions.total_area(pieces)
	var box := Subdivisions._bounds_all(pieces)
	var center := Subdivisions._label_point(pieces)
	u.s = flat
	u.a = snappedf(area, 0.001)
	u.b = [snappedf(box.position.x, 0.001), snappedf(box.position.y, 0.001), snappedf(box.end.x, 0.001), snappedf(box.end.y, 0.001)]
	u.c = [snappedf(center.x, 0.01), snappedf(center.y, 0.01)]
	return Vector2(maxf(original - area, 0.0), original)


## Keeps the largest piece and discards crumbs from the clipping.
func _usable(pieces: Array) -> Array:
	var out := []
	var biggest: PackedVector2Array = PackedVector2Array()
	var best := 0.0
	for p: PackedVector2Array in pieces:
		if p.size() < 3:
			continue
		var a := Subdivisions.polygon_area(p)
		if a <= 0.0:
			continue
		if a > best:
			best = a
			biggest = p
		if a >= MIN_EXTRA_PIECE:
			out.append(p)
	if out.is_empty() and not biggest.is_empty():
		out.append(biggest)
	return out


func _marker(from: Vector2, container: Array) -> PackedVector2Array:
	var nearest := from
	var best := INF
	for ring: PackedVector2Array in container:
		for i in ring.size():
			var q := Geometry2D.get_closest_point_to_segment(from, ring[i], ring[(i + 1) % ring.size()])
			if q.distance_squared_to(from) < best:
				best = q.distance_squared_to(from)
				nearest = q
	var r := MARKER_RADIUS
	while r < 40.0:
		var diamond := PackedVector2Array([nearest + Vector2(0, -r), nearest + Vector2(r, 0), nearest + Vector2(0, r), nearest + Vector2(-r, 0)])
		var inside := _usable(Subdivisions.intersect_all(diamond, container))
		if not inside.is_empty():
			return inside[0]
		r *= 2.0
	return PackedVector2Array([nearest, nearest + Vector2(r, 0), nearest + Vector2(0, r)])


## limits.call(arc) returns [allowed rings, holes].
func _clip_arcs(arcs: Array, limits: Callable) -> Array:
	var out := []
	for arc: Array in arcs:
		var flat: Array = arc[2]
		var pts := PackedVector2Array()
		pts.resize(flat.size() / 2)
		for i in pts.size():
			pts[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
		var limit: Array = limits.call(arc)
		var box := Subdivisions._bounds(pts)
		var parts := []
		for ring: PackedVector2Array in limit[0]:
			if box.intersects(Subdivisions._bounds(ring)):
				parts.append_array(Geometry2D.intersect_polyline_with_polygon(pts, ring))
		for hole: PackedVector2Array in limit[1]:
			var kept := []
			for part: PackedVector2Array in parts:
				kept.append_array(Geometry2D.clip_polyline_with_polygon(part, hole))
			parts = kept
		for part: PackedVector2Array in parts:
			for run: PackedVector2Array in _inside_runs(part, limit[0]):
				var line := []
				for q in run:
					line.append(snappedf(q.x, 0.001))
					line.append(snappedf(q.y, 0.001))
				out.append([arc[0], arc[1], line])
	return out


## Line clipping may join two pieces with a stretch outside the limit: cuts the line at those stretches.
func _inside_runs(part: PackedVector2Array, rings: Array) -> Array:
	var runs := []
	var current := PackedVector2Array()
	for i in part.size() - 1:
		if Territories._inside_any((part[i] + part[i + 1]) * 0.5, rings):
			if current.is_empty():
				current.append(part[i])
			current.append(part[i + 1])
		elif current.size() >= 2:
			runs.append(current)
			current = PackedVector2Array()
	if current.size() >= 2:
		runs.append(current)
	return runs
