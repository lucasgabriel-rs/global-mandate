class_name ProcessTrack
extends VBoxContainer
## Passo a passo da tramitação: comissão, plenário, outra casa, sanção, publicação e vigência, com a fase
## atual em destaque, os dias que faltam e a chance estimada de aprovação.

const CHIP := preload("res://scenes/ui/legislation/step_chip.tscn")
const STATE_COLORS := {"done": UiKit.GREEN, "current": UiKit.CYAN, "todo": UiKit.LINE, "failed": UiKit.RED}


func setup(world: GameWorld, norm: Dictionary) -> void:
	var leg := world.legislation
	var box: Control = %chips
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var track := leg.process_track(world, norm)
	var current := {}
	for i in track.size():
		var entry: Dictionary = track[i]
		var chip: Control = CHIP.instantiate()
		chip.name = "step_%d" % i
		box.add_child(chip)
		var color: Color = STATE_COLORS[entry.state]
		(chip.get_node("%bar") as ColorRect).color = color
		var label: Label = chip.get_node("%chip_name")
		label.text = ("✓ " if entry.state == "done" else ("✗ " if entry.state == "failed" else "")) + String(entry.label)
		label.add_theme_color_override("font_color", UiKit.TEXT if entry.state in ["current", "failed"] else UiKit.DIM)
		var days: Label = chip.get_node("%chip_days")
		days.text = "" if entry.state == "done" or int(entry.days) <= 0 else "%d dia%s" % [int(entry.days), "" if int(entry.days) == 1 else "s"]
		if entry.state in ["current", "failed"]:
			current = entry
	var now: Label = %now
	var chance_label: Label = %chance
	var total := leg.days_to_force(world, norm)
	if norm.state == Legislation.STATE_DRAFT:
		now.text = "Caminho até valer: cerca de %d dias depois de apresentada." % total
	elif norm.state in [Legislation.STATE_REJECTED, Legislation.STATE_INVALID]:
		now.text = "Parou em %s: %s." % [String(current.get("label", "")).to_lower(), String(norm.state).to_lower()]
	elif norm.state == Legislation.STATE_IN_FORCE:
		now.text = "Em vigor."
	elif not current.is_empty():
		now.text = "Agora: %s. Faltam cerca de %d dias para valer." % [String(current.detail if String(current.detail) != "" else current.label), total]
	else:
		now.text = ""
	var chance := leg.pass_chance(world, norm) if norm.state in [Legislation.STATE_DRAFT, Legislation.STATE_PROCESS, Legislation.STATE_APPROVED] else -1.0
	chance_label.visible = chance >= 0.0
	if chance >= 0.0:
		var rounded := clampi(roundi(chance * 20.0) * 5, 5, 95)
		chance_label.text = "Chance de aprovação: %s (cerca de %d%%). Estimativa grosseira; a pesquisa paga mostra a contagem por partido." % [Legislation.chance_word(chance), rounded]
		chance_label.add_theme_color_override("font_color", UiKit.GREEN if chance >= 0.6 else (UiKit.ACCENT if chance >= 0.4 else UiKit.RED))
	(%rule as Label).text = leg.type_rule_text(world, norm.type) if not norm.has("payload") else "Projeto pronto: passa pelo parlamento com o rito de lei ordinária."
