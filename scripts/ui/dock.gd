class_name Dock
extends Control
## Dock no pé da tela, à moda do macOS: ícones agrupados que crescem quando o mouse passa,
## nome do item em um balão e um ponto embaixo das janelas abertas.

signal item_pressed(item: DockItem)

## Quanto o ícone sob o mouse cresce, e até que distância (px) os vizinhos crescem junto.
const MAGNIFY := 0.55
const REACH := 110.0
const BOTTOM_GAP := 8.0
const SHELF_PAD := 10.0

## Faixa à esquerda que o dock não pode cobrir (o noticiário mora ali).
@export var left_reserved := 0.0

var desk: WindowDesk
var _items: Array[DockItem] = []

@onready var _row: HBoxContainer = %items
@onready var _shelf: Panel = %shelf
@onready var _tip: PanelContainer = %tip
@onready var _tip_label: Label = %tip_label


func _ready() -> void:
	for child in _row.get_children():
		if child is DockItem:
			_items.append(child)
			child.pressed.connect(func(): item_pressed.emit(child))
			child.mouse_entered.connect(_show_tip.bind(child))
			child.mouse_exited.connect(func(): _tip.visible = false)
	_tip.visible = false


func items() -> Array[DockItem]:
	return _items


## Centro do ícone em coordenadas globais, de onde a janela sai ao abrir.
func item_center(item: DockItem) -> Vector2:
	return item.get_global_rect().get_center()


func item_for_window(i: int) -> DockItem:
	for it in _items:
		if it.window_index == i:
			return it
	return null


func _process(_delta: float) -> void:
	var mouse := get_local_mouse_position()
	var base_w := 0.0
	var gap := float(_row.get_theme_constant("separation"))
	for child in _row.get_children():
		if child is DockItem:
			base_w += child.base
		elif child is Control and child.visible:
			base_w += child.custom_minimum_size.x
		base_w += gap
	base_w -= gap
	var cx := maxf(size.x * 0.5, left_reserved + base_w * 0.5 + 24.0)
	# A ampliação usa as posições de repouso, para os ícones não fugirem do mouse.
	var near := mouse.y > size.y - 100.0 and mouse.y <= size.y and absf(mouse.x - cx) < base_w * 0.5 + REACH
	var x := cx - base_w * 0.5
	for child in _row.get_children():
		if child is DockItem:
			var it: DockItem = child
			var center := x + it.base * 0.5
			var k := clampf(1.0 - absf(mouse.x - center) / REACH, 0.0, 1.0) if near else 0.0
			var target := 1.0 + MAGNIFY * k * k
			it.magnify = lerpf(it.magnify, target, 0.35)
			if desk:
				it.set_running(it.window_index >= 0 and desk.is_open(it.window_index))
			x += it.base + gap
		elif child is Control and child.visible:
			x += child.custom_minimum_size.x + gap
	_row.reset_size()
	_row.position = Vector2(cx - _row.size.x * 0.5, size.y - BOTTOM_GAP - _row.size.y)
	var base_h: float = _items[0].base + 8.0 if not _items.is_empty() else 56.0
	_shelf.position = Vector2(_row.position.x - SHELF_PAD, size.y - BOTTOM_GAP - base_h - SHELF_PAD)
	_shelf.size = Vector2(_row.size.x + SHELF_PAD * 2.0, base_h + SHELF_PAD + 4.0)
	if _tip.visible:
		_place_tip()


func _show_tip(item: DockItem) -> void:
	_tip_label.text = tr(item.label)
	_tip.set_meta("item", item)
	_tip.reset_size()
	_tip.visible = true
	_place_tip()


func _place_tip() -> void:
	var item: DockItem = _tip.get_meta("item")
	var r := item.get_global_rect()
	_tip.global_position = Vector2(r.get_center().x - _tip.size.x * 0.5, r.position.y - _tip.size.y - 6.0)
