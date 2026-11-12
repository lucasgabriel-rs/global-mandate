class_name Lang
extends RefCounted
## Game language. Brazilian Portuguese is the original: the Portuguese texts are the msgids of the
## catalogs in locale/*.po, so whatever is missing a translation shows up in Portuguese.
##
## The choice is kept in user://settings.cfg. The first time, the system language applies, if it is English or
## Spanish. Tests always run in Portuguese, because they compare the original texts.

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT := "pt_BR"
## Codes in the order of the selector.
const CODES := ["pt_BR", "en", "es"]
## Name of each language in itself, as it appears in the selector.
const NATIVE_NAMES := {"pt_BR": "Português", "en": "English", "es": "Español"}

## English-style numbers (decimal point, comma for thousands). Read by UiKit, also on the simulation
## thread; it only changes on the main thread, when the language is switched.
static var english_numbers := false


## Language at the start of the game: --lang=xx on the command line, Portuguese in interface tests, the one
## saved in settings.cfg or the system's.
static func startup() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			apply(arg.trim_prefix("--lang="), false)
			return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-"):
			apply(DEFAULT, false)
			return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		apply(String(cfg.get_value("game", "language", DEFAULT)), false)
	else:
		apply(system_language(), false)


static func system_language() -> String:
	var lang := OS.get_locale_language()
	return lang if lang in ["en", "es"] else DEFAULT


static func current() -> String:
	var lang := TranslationServer.get_locale().get_slice("_", 0)
	return lang if lang in ["en", "es"] else DEFAULT


## Switches the language. Nodes receive NOTIFICATION_TRANSLATION_CHANGED; with save, the choice is kept for
## the next matches.
static func apply(code: String, save := true) -> void:
	if not code in CODES:
		code = DEFAULT
	english_numbers = code == "en"
	TranslationServer.set_locale(code)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("game", "language", code)
		cfg.save(SETTINGS_PATH)


## Translates only when asked: for texts that are sometimes stored (in Portuguese) and sometimes shown.
## The extractor recognizes tr_if("...") as translatable text.
static func tr_if(text: String, localized: bool) -> String:
	return TranslationServer.translate(text) if localized else text
