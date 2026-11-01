class_name MiniChart
extends Control
## Gráfico de linha compacto com título, valor atual e referência zero.

@export var title := ""
var series := PackedFloat32Array()
@export var color := Color("4fb3d9")
## Como o valor atual aparece: porcentagem ou número com 0, 1 ou 2 casas.
@export_enum("pct", "num0", "num1", "num2") var format := "pct"
## Série do histórico do país que este gráfico mostra (growth, infl, debt...).
@export var series_key := ""
var window := 60
var zero_line := true


func set_data(s: PackedFloat32Array) -> void:
	series = s
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.025))
	draw_string(font, Vector2(6, 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.DIM)
	if series.is_empty():
		return
	var start := maxi(series.size() - window, 0)
	var lo := INF
	var hi := -INF
	for i in range(start, series.size()):
		lo = minf(lo, series[i])
		hi = maxf(hi, series[i])
	if hi - lo < 0.0001:
		hi += 0.0005
		lo -= 0.0005
	var pad := (hi - lo) * 0.1
	lo -= pad
	hi += pad
	var top := 18.0
	var bottom := h - 4.0
	var count := series.size() - start
	var to_y := func(v: float) -> float: return lerpf(bottom, top, (v - lo) / (hi - lo))
	if zero_line and lo < 0.0 and hi > 0.0:
		var zy: float = to_y.call(0.0)
		draw_line(Vector2(0, zy), Vector2(w, zy), Color(1, 1, 1, 0.14), 1.0)
	var pts := PackedVector2Array()
	for i in count:
		var x := float(i) / maxf(count - 1, 1) * (w - 4.0) + 2.0
		pts.append(Vector2(x, to_y.call(series[start + i])))
	if pts.size() >= 2:
		var fill := pts.duplicate()
		fill.append(Vector2(pts[pts.size() - 1].x, bottom))
		fill.append(Vector2(pts[0].x, bottom))
		var fc := color
		fc.a = 0.12
		if Geometry2D.triangulate_polygon(fill).size() > 0:
			draw_colored_polygon(fill, fc)
		draw_polyline(pts, color, 1.5, true)
	var last: float = series[series.size() - 1]
	var txt := _value_text(last)
	draw_string(font, Vector2(0, 13), txt, HORIZONTAL_ALIGNMENT_RIGHT, w - 6.0, 12, UiKit.TEXT)


func _value_text(v: float) -> String:
	match format:
		"num0": return UiKit.num(v, 0)
		"num1": return UiKit.num(v, 1)
		"num2": return UiKit.num(v, 2)
	return UiKit.pct(v)
