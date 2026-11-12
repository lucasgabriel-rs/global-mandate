class_name DebtChart
extends Control
## Gráfico da janela Fiscal: curva de juros por prazo (linha) ou vencimentos por ano (barras).

@export var title := ""
@export_enum("curve", "bars") var mode := "curve"
@export var color := Color("4fb3d9")
var values := PackedFloat32Array()
var labels: Array[String] = []
var value_texts: Array[String] = []


func set_data(v: PackedFloat32Array, l: Array[String], texts: Array[String]) -> void:
	values = v
	labels = l
	value_texts = texts
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.025))
	draw_string(font, Vector2(6, 13), tr(title), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.DIM)
	if values.is_empty():
		return
	var lo := 0.0 if mode == "bars" else INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 0.0001:
		hi += 0.002
		if mode == "curve":
			lo -= 0.002
	if mode == "curve":
		var pad := (hi - lo) * 0.25
		lo -= pad
		hi += pad
	var top := 32.0
	var bottom := h - 18.0
	var n := values.size()
	var step := (w - 16.0) / n
	var pts := PackedVector2Array()
	for i in n:
		var x := 8.0 + step * (i + 0.5)
		var y := lerpf(bottom, top, (values[i] - lo) / (hi - lo))
		if mode == "bars":
			draw_rect(Rect2(x - step * 0.3, y, step * 0.6, bottom - y), color)
		else:
			pts.append(Vector2(x, y))
			draw_circle(Vector2(x, y), 2.5, color)
		if i < value_texts.size():
			draw_string(font, Vector2(x - step * 0.5, y - 4.0), value_texts[i], HORIZONTAL_ALIGNMENT_CENTER, step, 10, UiKit.TEXT)
		if i < labels.size():
			draw_string(font, Vector2(x - step * 0.5, h - 5.0), labels[i], HORIZONTAL_ALIGNMENT_CENTER, step, 10, UiKit.DIM)
	if pts.size() > 1:
		draw_polyline(pts, color, 1.5, true)
