class_name LawReview
extends PanelContainer
## Before sending to parliament: the predicted effect on approval, the budget and social groups, the
## parties' reaction and the path the norm will follow. Nothing here changes the match.

var editor: LawEditor


func setup(owner_editor: LawEditor) -> void:
	editor = owner_editor
	%rv_back.pressed.connect(func(): visible = false)
	%rv_send.pressed.connect(func(): editor.send())


func open() -> void:
	var world := editor.world
	var leg := world.legislation
	var norm := editor.norm
	var fx := leg.expected_effects(world, norm)
	var what := ""
	if int(norm.get("amends", -1)) >= 0:
		what = tr("Muda %d bloco(s) e tira %d em relação ao texto em vigor.") % [int(fx.added), int(fx.removed)]
	else:
		what = tr("Norma nova com %d bloco(s).") % int(fx.added)
	(%rv_norm as Label).text = "%s  ·  %s. %s" % [tr(Legislation.NORM_TYPES[norm.type].label), tr(norm.title), what]
	var approval: float = fx.approval
	var big: Label = %rv_approval
	big.text = tr("%+.1f p.p. ao entrar em vigor") % (approval * 100.0)
	big.add_theme_color_override("font_color", UiKit.GREEN if approval > 0.0005 else (UiKit.RED if approval < -0.0005 else UiKit.TEXT))
	var popularity: float = fx.popularity
	(%rv_popularity as Label).text = tr("Cerca de %d%% do eleitorado aprova a proposta.") % roundi(popularity * 100.0)
	var budget: float = fx.budget
	var money: Label = %rv_budget
	money.text = tr("Sem efeito direto") if is_zero_approx(budget) else tr("%s%s (%s do PIB)") % ["+" if budget > 0.0 else "", UiKit.money(budget), UiKit.pct(float(fx.budget_share), 2)]
	money.add_theme_color_override("font_color", UiKit.GREEN if budget > 0.0 else (UiKit.RED if budget < 0.0 else UiKit.TEXT))
	var note := tr("Receita a mais conta como ganho; despesa nova, como custo.") if not is_zero_approx(budget) else tr("Nenhum bloco desta norma cobra ou gasta diretamente.")
	if int(fx.unknown_budget) > 0:
		note += tr(" Os blocos dos códigos agem pela economia ao longo dos meses (investimento, emprego, arrecadação).")
	(%rv_budget_note as Label).text = note
	var groups := []
	for g: Dictionary in fx.groups:
		var color := "#4cc794" if g.mood == "a favor" else ("#ec5a43" if g.mood == "contra" else "#f2b33d")
		groups.append("%s: [color=%s]%s[/color]" % [g.label, color, g.mood])
	(%rv_groups as RichTextLabel).text = "\n".join(groups)
	var parties := []
	for p: Dictionary in fx.parties:
		var c: Color = p.color
		parties.append("[color=#%s]■[/color] %s (%d): %s" % [c.to_html(false), p.short, int(p.seats), tr("[color=#4cc794]tende a apoiar[/color]") if p.favor else tr("[color=#ec5a43]tende a rejeitar[/color]")])
	(%rv_parties as RichTextLabel).text = "\n".join(parties)
	(%rv_track as ProcessTrack).setup(world, norm)
	(%rv_feedback as Label).text = ""
	visible = true


func show_error(text: String) -> void:
	(%rv_feedback as Label).text = text
