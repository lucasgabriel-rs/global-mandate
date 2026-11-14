class_name CompareChart
extends Control
## Line chart that compares the same series of several countries, with axis, grid and legend.

const COLORS := [Color("f2b33d"), Color("4fb3d9"), Color("4cc794"), Color("ec5a43"), Color("b48ade")]

## How values appear on the axis: percentage or number with 0, 1 or 2 decimals.
@export_enum("pct", "num0", "num1", "num2") var format := "pct"
## How many months from the end of the series the chart shows.
@export var window := 120
## Year of the last point, to label the time axis.
var end_year := 2026.0
var _series: Array[PackedFloat32Array] = []
var _names: PackedStringArray = []


func set_data(series: Array[PackedFloat32Array], names: PackedStringArray) -> void:
	_series = series
	_names = names
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.025))
	var left := 52.0
	var top := 22.0
	var bottom := h - 20.0
	var right := w - 8.0
	# Legend at the top.
	var lx := left
	for i in _names.size():
		var col: Color = COLORS[i % COLORS.size()]
		draw_rect(Rect2(lx, 8, 10, 3), col)
		draw_string(font, Vector2(lx + 14, 13), _names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.TEXT)
		lx += 22.0 + font.get_string_size(_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var count := 0
	var lo := INF
	var hi := -INF
	for s in _series:
		var n := mini(s.size(), window)
		count = maxi(count, n)
		for i in range(s.size() - n, s.size()):
			lo = minf(lo, s[i])
			hi = maxf(hi, s[i])
	if count < 2:
		draw_string(font, Vector2(left, h * 0.5), tr("Ainda sem histórico suficiente."), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.DIM)
		return
	if hi - lo < 0.0001:
		hi += 0.0005
		lo -= 0.0005
	var pad := (hi - lo) * 0.08
	lo -= pad
	hi += pad
	var to_y := func(v: float) -> float: return lerpf(bottom, top, (v - lo) / (hi - lo))
	var to_x := func(i: int) -> float: return lerpf(left, right, float(i) / float(count - 1))
	# Horizontal grid with labels.
	for k in 5:
		var v := lerpf(lo, hi, float(k) / 4.0)
		var gy: float = to_y.call(v)
		draw_line(Vector2(left, gy), Vector2(right, gy), Color(1, 1, 1, 0.06), 1.0)
		draw_string(font, Vector2(0, gy + 4), _value_text(v), HORIZONTAL_ALIGNMENT_RIGHT, left - 6.0, 10, UiKit.DIM)
	if lo < 0.0 and hi > 0.0:
		var zy: float = to_y.call(0.0)
		draw_line(Vector2(left, zy), Vector2(right, zy), Color(1, 1, 1, 0.2), 1.0)
	# Years on the time axis.
	var years := float(count - 1) / 12.0
	var step := 1 if years <= 6.0 else (5 if years <= 30.0 else 10)
	var first_year := ceili(end_year - years)
	for yr in range(first_year, int(floor(end_year)) + 1):
		if yr % step != 0 and step > 1:
			continue
		var i := int(roundf(float(count - 1) - (end_year - float(yr)) * 12.0))
		if i < 0 or i >= count:
			continue
		var gx: float = to_x.call(i)
		draw_line(Vector2(gx, top), Vector2(gx, bottom), Color(1, 1, 1, 0.05), 1.0)
		draw_string(font, Vector2(gx - 30, h - 5), str(yr), HORIZONTAL_ALIGNMENT_CENTER, 60, 10, UiKit.DIM)
	for si in _series.size():
		var s := _series[si]
		var n := mini(s.size(), window)
		if n < 2:
			continue
		var pts := PackedVector2Array()
		for j in n:
			pts.append(Vector2(to_x.call(count - n + j), to_y.call(s[s.size() - n + j])))
		draw_polyline(pts, COLORS[si % COLORS.size()], 2.0 if si == 0 else 1.5, true)


func _value_text(v: float) -> String:
	match format:
		"num0": return UiKit.num(v, 0)
		"num1": return UiKit.num(v, 1)
		"num2": return UiKit.num(v, 2)
	return UiKit.pct(v)
