class_name ChatLog
extends RefCounted
## Histórico das conversas do jogador, uma linha do tempo por contato ("pais:ARG", "partido:3"),
## no formato de mensagens de celular: {me, text, date, ok}. Fica no save junto do mundo.

const MAX_MESSAGES := 200


static func country_key(iso: String) -> String:
	return "pais:" + iso


static func party_key(id: int) -> String:
	return "partido:%d" % id


static func thread(world: GameWorld, key: String) -> Array:
	return world.chats.get(key, [])


## ok: true/false pinta a resposta (aceitou ou recusou); null deixa neutra.
static func add(world: GameWorld, key: String, me: bool, text: String, ok: Variant = null) -> void:
	var list: Array = world.chats.get_or_add(key, [])
	list.append({"me": me, "text": text, "date": world.date_string(), "ok": ok})
	if list.size() > MAX_MESSAGES:
		world.chats[key] = list.slice(list.size() - MAX_MESSAGES)


static func last_text(world: GameWorld, key: String) -> String:
	var list := thread(world, key)
	return String(list[-1].text) if not list.is_empty() else ""
