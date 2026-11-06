extends SceneTree
## Gera locale/messages.pot com todos os textos traduzíveis do jogo e, com --merge, atualiza os .po com
## msgmerge. O msgid é sempre o texto original em português.
##
## Uso:
##   godot --headless --path . --script tools/extract_pot.gd              só o .pot
##   godot --headless --path . --script tools/extract_pot.gd -- --merge   .pot e msgmerge nos .po
##
## De onde vêm os textos:
## - cenas (.tscn): text, tooltip_text, placeholder_text, title, label (dock), itens de OptionButton e o nome dos filhos
##   de TabContainer (é o título da aba). Nós com auto_translate_mode desligado ficam de fora.
## - scripts (.gd): o primeiro argumento literal de tr(), tr_n(), atr(), Lang.tr_if() e TranslationServer.translate();
##   e todos os textos de uma linha que termina em "# i18n" ou de um trecho entre "# i18n-begin" e
##   "# i18n-end", menos as chaves de dicionário (texto seguido de ":") e o que parece id (minúsculas sem
##   espaço, siglas de até 4 letras; "# i18n-all" no fim da linha pega também esses). As marcas servem para constantes e dados guardados em português,
##   que só são traduzidos na hora de mostrar.
## - dados: blocos de lei, categorias e listas de escolha (LawCatalog e LawCodes), títulos e ementas dos
##   códigos, nomes dos setores e nomes dos países (data/countries.csv).

const POT_PATH := "res://locale/messages.pot"
const LANGS := ["en", "es"]
## "label" é o nome dos ícones do dock (DockItem).
const TSCN_KEYS := ["text", "tooltip_text", "placeholder_text", "title", "label"]

## msgid -> lista de referências "arquivo:linha", na ordem em que apareceram.
var _entries := {}
var _order: Array[String] = []


func _init() -> void:
	var scenes: Array[String] = []
	_walk("res://scenes", ".tscn", scenes)
	for path in scenes:
		_scan_scene(path)
	var scripts: Array[String] = []
	_walk("res://scripts", ".gd", scripts)
	for path in scripts:
		_scan_script(path)
	_scan_data()
	_write_pot()
	print("messages.pot: %d entradas" % _order.size())
	if OS.get_cmdline_user_args().has("--merge"):
		_merge()
	quit()


func _walk(dir: String, ext: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), ext, out)


func _add(msgid: String, ref: String) -> void:
	if msgid.strip_edges().is_empty() or not _has_letters(msgid):
		return
	if not _entries.has(msgid):
		_entries[msgid] = []
		_order.append(msgid)
	if _entries[msgid].size() < 4:
		_entries[msgid].append(ref)


static func _has_letters(s: String) -> bool:
	for i in s.length():
		var ch := s.unicode_at(i)
		if (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch >= 192:
			return true
	return false


# --- Cenas ----------------------------------------------------------------------------

func _scan_scene(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var types := {}  # caminho do nó -> tipo
	var node_props := []  # [[msgid, linha]] do nó atual
	var node_skip := false
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		if line.begins_with("["):
			_flush_node(path, node_props, node_skip)
			node_props = []
			node_skip = false
			if line.begins_with("[node "):
				var name := _attr(line, "name")
				var parent := _attr(line, "parent")
				var type := _attr(line, "type")
				var node_path := name if parent == "" else (name if parent == "." else parent + "/" + name)
				if parent == "":
					node_path = "."
				types[node_path] = type
				if parent != "" and types.get(parent, "") == "TabContainer":
					node_props.append([name, i + 1])
			i += 1
			continue
		if line.begins_with("auto_translate_mode = 2"):
			node_skip = true
		var eq := line.find(" = \"")
		if eq > 0:
			var key := line.substr(0, eq)
			if key in TSCN_KEYS or (key.begins_with("popup/item_") and key.ends_with("/text")):
				# O valor pode ocupar várias linhas: vai até a aspa final não escapada.
				var start_line := i
				var value := line.substr(eq + 4)
				while not _closes(value) and i + 1 < lines.size():
					i += 1
					value += "\n" + lines[i]
				value = value.substr(0, value.length() - 1)
				node_props.append([_unescape_tscn(value), start_line + 1])
		i += 1
	_flush_node(path, node_props, node_skip)


func _flush_node(path: String, props: Array, skip: bool) -> void:
	if not skip:
		for p: Array in props:
			_add(p[0], "%s:%d" % [path.trim_prefix("res://"), p[1]])


static func _attr(line: String, key: String) -> String:
	var at := line.find(key + "=\"")
	if at < 0:
		return ""
	at += key.length() + 2
	return line.substr(at, line.find("\"", at) - at)


## O texto termina em aspa que não está escapada?
static func _closes(value: String) -> bool:
	if not value.ends_with("\""):
		return false
	var slashes := 0
	var k := value.length() - 2
	while k >= 0 and value[k] == "\\":
		slashes += 1
		k -= 1
	return slashes % 2 == 0


static func _unescape_tscn(s: String) -> String:
	return s.replace("\\\"", "\"").replace("\\\\", "\\")


# --- Scripts --------------------------------------------------------------------------

func _scan_script(path: String) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var call_re := RegEx.create_from_string("(?<!\\w)(?:tr|tr_n|atr|tr_if|TranslationServer\\.translate)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var str_re := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"(\\s*:)?")
	# Nos trechos marcados, ids (minúsculas sem espaço) e siglas curtas não são texto.
	var id_re := RegEx.create_from_string("^(?:[a-z0-9_.]*|[A-Z]{1,4})$")
	var in_block := false
	var ref_path := path.trim_prefix("res://")
	for n in lines.size():
		var line: String = lines[n]
		var bare := line.strip_edges()
		if bare.begins_with("# i18n-begin"):
			in_block = true
			continue
		if bare.begins_with("# i18n-end"):
			in_block = false
			continue
		if bare.begins_with("#"):
			continue
		var ref := "%s:%d" % [ref_path, n + 1]
		for m in call_re.search_all(line):
			_add(_unescape_gd(m.get_string(1)), ref)
		var every := line.ends_with("# i18n-all")
		if in_block or line.ends_with("# i18n") or every:
			var code := line.substr(0, line.rfind("# i18n")) if line.ends_with("# i18n") or every else line
			for m in str_re.search_all(code):
				if m.get_string(2).is_empty() and (every or not id_re.search(m.get_string(1))):
					_add(_unescape_gd(m.get_string(1)), ref)


static func _unescape_gd(s: String) -> String:
	return s.c_unescape()


# --- Dados ----------------------------------------------------------------------------

func _scan_data() -> void:
	for cat: Dictionary in LawCatalog.categories():
		_add(String(cat.label), "scripts/sim/law_catalog.gd (categorias)")
	for cat: Dictionary in LawCatalog.categories():
		for b: Dictionary in LawCatalog.in_category(cat.id):
			_add(String(b.text), "scripts/sim/law_catalog.gd (bloco %s)" % b.id)
	var lists := LawCatalog.CHOICES.duplicate()
	for code: LawCode in LawCodes.all():
		_add(code.title, "scripts/sim/codes (%s)" % code.id)
		_add(code.ementa, "scripts/sim/codes (%s)" % code.id)
		lists.merge(code.choices())
	for of: String in lists:
		var list: Dictionary = lists[of]
		for key in list:
			_add(str(list[key]), "scripts/sim/law_catalog.gd (escolha %s)" % of)
	for s: String in Sectors.NAMES:
		_add(s, "scripts/sim/sectors.gd (NAMES)")
	for row: Dictionary in GameData.load_countries():
		_add(String(row.name), "data/countries.csv (%s)" % row.iso)


# --- Saída ----------------------------------------------------------------------------

func _write_pot() -> void:
	DirAccess.make_dir_recursive_absolute("res://locale")
	var out := PackedStringArray()
	out.append("# Textos do Global Mandate. Gerado por tools/extract_pot.gd: não edite à mão.")
	out.append("msgid \"\"")
	out.append("msgstr \"\"")
	out.append("\"Project-Id-Version: Global Mandate\\n\"")
	out.append("\"MIME-Version: 1.0\\n\"")
	out.append("\"Content-Type: text/plain; charset=UTF-8\\n\"")
	out.append("\"Content-Transfer-Encoding: 8-bit\\n\"")
	out.append("\"X-Source-Language: pt_BR\\n\"")
	out.append("")
	for msgid in _order:
		out.append("#: " + " ".join(PackedStringArray(_entries[msgid].map(func(r): return r.replace(" ", "_")))))
		if "%" in msgid and _has_format(msgid):
			out.append("#, c-format")
		out.append_array(_po_string("msgid", msgid))
		out.append("msgstr \"\"")
		out.append("")
	var f := FileAccess.open(POT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(out))


static func _has_format(s: String) -> bool:
	return RegEx.create_from_string("%[-+0#]*\\d*(?:\\.\\d+)?[sdif]").search(s) != null


static func po_escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\t", "\\t").replace("\n", "\\n")


static func _po_string(key: String, s: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not "\n" in s:
		out.append("%s \"%s\"" % [key, po_escape(s)])
		return out
	out.append("%s \"\"" % key)
	var parts := s.split("\n")
	for k in parts.size():
		var piece: String = parts[k] + ("\n" if k < parts.size() - 1 else "")
		if not piece.is_empty():
			out.append("\"%s\"" % po_escape(piece))
	return out


func _merge() -> void:
	var pot := ProjectSettings.globalize_path(POT_PATH)
	for lang: String in LANGS:
		var po := ProjectSettings.globalize_path("res://locale/%s.po" % lang)
		if not FileAccess.file_exists("res://locale/%s.po" % lang):
			var f := FileAccess.open("res://locale/%s.po" % lang, FileAccess.WRITE)
			f.store_string(FileAccess.get_file_as_string(POT_PATH).replace("Gerado por tools/extract_pot.gd: não edite à mão.", "Tradução: edite os msgstr; tools/extract_pot.gd -- --merge acrescenta os textos novos.").replace("\"X-Source-Language: pt_BR\\n\"", "\"Language: %s\\n\"\n\"X-Source-Language: pt_BR\\n\"" % lang))
			f.close()
		var output := []
		var code := OS.execute("msgmerge", ["--quiet", "--update", "--backup=none", "--no-wrap", po, pot], output, true)
		if code != 0:
			push_error("msgmerge falhou em %s: %s" % [lang, "".join(output)])
			continue
		var missing := _untranslated(po)
		print("%s.po: %d sem tradução%s" % [lang, missing.size(), "" if missing.is_empty() else " (primeira: %s)" % missing[0]])


## Entradas do .po com msgstr vazio ou marcadas como fuzzy (o Godot ignora as fuzzy).
static func _untranslated(po_path: String) -> Array:
	var out := []
	var text := FileAccess.get_file_as_string(po_path)
	for block: String in text.split("\n\n"):
		if not "msgid" in block or block.contains("msgid \"\"\nmsgstr \"\"\n\"Project"):
			continue
		if block.strip_edges().begins_with("#~"):
			continue
		var fuzzy := block.contains("#, fuzzy")
		var id_at := block.find("msgid ")
		var str_at := block.find("\nmsgstr ")
		if id_at < 0 or str_at < 0:
			continue
		var msgstr := block.substr(str_at + 8).strip_edges()
		if fuzzy or msgstr == "\"\"":
			out.append(block.substr(id_at + 6, str_at - id_at - 6).strip_edges().left(60))
	return out
