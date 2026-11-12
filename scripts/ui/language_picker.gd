class_name LanguagePicker
extends OptionButton
## Language selector of the start screen and the pause menu. The items live in the scene, in the order of Lang.CODES,
## with each language's name in itself (so the node does not translate its own text).


func _ready() -> void:
	_sync()
	item_selected.connect(func(i: int): Lang.apply(Lang.CODES[i]))


## The language may change from outside (the other selector, --lang, the tests): the checked item follows.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_sync()


func _sync() -> void:
	var i := maxi(0, Lang.CODES.find(Lang.current()))
	if selected != i:
		select(i)
