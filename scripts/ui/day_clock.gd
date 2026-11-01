class_name DayClock
extends Control
## Relógio analógico da barra superior. Os dígitos dos minutos trocam rápido demais para o olho em
## qualquer velocidade; o ponteiro dá uma volta a cada hora de jogo e mostra o ritmo de relance.
## O anel em volta enche ao longo do dia e recomeça à meia-noite.

const MINUTES_PER_DAY := 1440.0

var minute := 0:
	set(value):
		if value != minute:
			minute = value
			queue_redraw()


## Ângulo na tela de um ponteiro: 0 aponta para cima e cresce no sentido horário.
static func hand_angle(fraction: float) -> float:
	return fraction * TAU - PI * 0.5


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(c, r - 3.0, Color(1, 1, 1, 0.05))
	draw_arc(c, r, 0.0, TAU, 48, UiKit.LINE, 2.0, true)
	var day := minute / MINUTES_PER_DAY
	if day > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + day * TAU, maxi(int(48.0 * day), 2), UiKit.ACCENT, 2.0, true)
	var hour_hand := hand_angle(fmod(minute, 720.0) / 720.0)
	var minute_hand := hand_angle(fmod(minute, 60.0) / 60.0)
	draw_line(c, c + Vector2.from_angle(hour_hand) * (r - 9.0), UiKit.TEXT, 2.4, true)
	draw_line(c, c + Vector2.from_angle(minute_hand) * (r - 5.0), UiKit.ACCENT, 1.6, true)
	draw_circle(c, 2.0, UiKit.TEXT)
