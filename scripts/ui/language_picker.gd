class_name LanguagePicker
extends OptionButton
## Seletor de idioma da tela inicial e do menu de pausa. Os itens ficam na cena, na ordem de Lang.CODES,
## com o nome de cada idioma nele mesmo (por isso o nó não traduz o próprio texto).


func _ready() -> void:
	_sync()
	item_selected.connect(func(i: int): Lang.apply(Lang.CODES[i]))


## O idioma pode mudar por fora (o outro seletor, --lang, os testes): o item marcado acompanha.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_sync()


func _sync() -> void:
	var i := maxi(0, Lang.CODES.find(Lang.current()))
	if selected != i:
		select(i)
