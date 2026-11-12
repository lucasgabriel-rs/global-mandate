class_name UiKit
extends RefCounted
## Interface colors, style of the highlights applied during the game and number formatting.
## The theme itself lives in scenes/ui/theme.tres.

const BG := Color(0.043, 0.075, 0.102, 0.95)
const BG_SOFT := Color(1, 1, 1, 0.04)
const LINE := Color("27404f")
const TEXT := Color("dbe6ec")
const DIM := Color("8ba2af")
const ACCENT := Color("f2b33d")
const RED := Color("ec5a43")
const GREEN := Color("4cc794")
const CYAN := Color("4fb3d9")


static func panel_style(bg: Color = BG, border: Color = LINE, radius := 3, margin := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


# --- Number formatting ----------------------------------------------------------
# In Portuguese and Spanish, decimal comma and dot for thousands; in English, the opposite (Lang.english_numbers).
# The units (tri, bi, mi) go through translation; these functions also run on the simulation thread.

static func pct(v: float, digits := 1) -> String:
	if absf(v) >= 10.0:
		return "%s%%" % _comma("%.0f" % (v * 100.0))
	return "%s%%" % _comma(("%." + str(digits) + "f") % (v * 100.0))


static func money(b: float) -> String:
	var a := absf(b)
	var sign_txt := "-" if b < 0.0 else ""
	if a >= 1000.0:
		return sign_txt + TranslationServer.translate("US$ %s tri") % _comma("%.2f" % (a / 1000.0))
	if a >= 10.0:
		return sign_txt + TranslationServer.translate("US$ %s bi") % _comma("%.0f" % a)
	return sign_txt + TranslationServer.translate("US$ %s bi") % _comma("%.1f" % a)


## Value of a party's fund, in US$ millions.
static func millions(v: float) -> String:
	if absf(v) >= 1000.0:
		return TranslationServer.translate("US$ %s bi") % _comma("%.2f" % (v / 1000.0))
	return TranslationServer.translate("US$ %s mi") % _comma("%.1f" % v if absf(v) < 100.0 else "%.0f" % v)


static func thousand(v: float) -> String:
	var s := str(int(roundf(v)))
	var sep := "," if Lang.english_numbers else "."
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0 and s[i - 1] != "-":
			out = sep + out
	return out


static func num(v: float, digits := 1) -> String:
	return _comma(("%." + str(digits) + "f") % v)


## Swaps the printf decimal point for a comma, except in English.
static func _comma(s: String) -> String:
	return s if Lang.english_numbers else s.replace(".", ",")


static func good_bad(v: float, good_high := true) -> Color:
	if absf(v) < 0.0001:
		return TEXT
	return GREEN if (v > 0.0) == good_high else RED
