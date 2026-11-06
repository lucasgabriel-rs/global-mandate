class_name LanguagePicker
extends OptionButton
## Seletor de idioma da tela inicial e do menu de pausa. Os itens ficam na cena, na ordem de Lang.CODES,
## com o nome de cada idioma nele mesmo (por isso o nó não traduz o próprio texto).


func _ready() -> void:
	select(maxi(0, Lang.CODES.find(Lang.current())))
	item_selected.connect(func(i: int): Lang.apply(Lang.CODES[i]))
