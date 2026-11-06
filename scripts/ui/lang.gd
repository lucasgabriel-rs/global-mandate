class_name Lang
extends RefCounted
## Idioma do jogo. O português do Brasil é o original: os textos em português são os msgid dos
## catálogos em locale/*.po, então o que faltar traduzir aparece em português.
##
## A escolha fica em user://settings.cfg. Na primeira vez vale o idioma do sistema, se for inglês ou
## espanhol. Os testes rodam sempre em português, porque comparam os textos originais.

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT := "pt_BR"
## Códigos na ordem do seletor.
const CODES := ["pt_BR", "en", "es"]
## Nome de cada idioma nele mesmo, como aparece no seletor.
const NATIVE_NAMES := {"pt_BR": "Português", "en": "English", "es": "Español"}

## Números no estilo inglês (ponto decimal, vírgula nos milhares). Lido por UiKit, também na thread da
## simulação; só muda na thread principal, ao trocar o idioma.
static var english_numbers := false


## Idioma do começo do jogo: --lang=xx na linha de comando, o português nos testes de interface, o
## salvo em settings.cfg ou o do sistema.
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


## Troca o idioma. Os nós recebem NOTIFICATION_TRANSLATION_CHANGED; com save, a escolha fica para as
## próximas partidas.
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


## Traduz só quando pedido: para textos que às vezes são guardados (em português) e às vezes mostrados.
## O extrator reconhece tr_if("...") como texto traduzível.
static func tr_if(text: String, localized: bool) -> String:
	return TranslationServer.translate(text) if localized else text
