class_name CompassView
extends Control
## Bússola política: esquerda e direita no eixo horizontal, autoritário no alto e libertário embaixo.
## points: [{econ, social, color, big?, label?}]. Com interactive, um clique escolhe a posição.

signal picked(econ: float, social: float)

const COLORS := [Color("c0504d"), Color("4f81bd"), Color("76a85b"), Color("c9a93f")]

var points: Array = []:
	set(value):
		points = value
		queue_redraw()
@export var interactive := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


func _square() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func to_screen(econ: float, social: float) -> Vector2:
	var r := _square()
	return r.get_center() + Vector2(clampf(econ, -1.0, 1.0), clampf(social, -1.0, 1.0)) * r.size.x * 0.5


func from_screen(at: Vector2) -> Vector2:
	var r := _square()
	return ((at - r.get_center()) / (r.size.x * 0.5)).clampf(-1.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var pressing: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var dragging: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if pressing or dragging:
		var value := from_screen(event.position)
		picked.emit(value.x, value.y)
		accept_event()


func _draw() -> void:
	var r := _square()
	var half := r.size * 0.5
	draw_rect(Rect2(r.position, half), Color(COLORS[0], 0.55))
	draw_rect(Rect2(r.position + Vector2(half.x, 0), half), Color(COLORS[1], 0.55))
	draw_rect(Rect2(r.position + Vector2(0, half.y), half), Color(COLORS[2], 0.55))
	draw_rect(Rect2(r.get_center(), half), Color(COLORS[3], 0.55))
	draw_rect(r, UiKit.LINE, false, 1.0)
	var c := r.get_center()
	draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), Color(0, 0, 0, 0.5), 1.0)
	draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), Color(0, 0, 0, 0.5), 1.0)
	var unit: float = r.size.x / 40.0
	for p: Dictionary in points:
		var at := to_screen(float(p.econ), float(p.social))
		var radius: float = clampf(unit * (1.6 if p.get("big", false) else 0.9), 2.0, 8.0)
		draw_circle(at, radius + 1.2, Color(0.02, 0.05, 0.07, 0.9))
		draw_circle(at, radius, p.get("color", Color.WHITE))
