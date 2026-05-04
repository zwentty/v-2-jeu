# =============================================================================
# inventory.gd
# Script de l'interface d'inventaire
# =============================================================================
extends Control

# Dictionnaire des objets dans l'inventaire {nom: quantité}
var items: Dictionary = {}

func _ready() -> void:
	# Connecter le bouton de fermeture
	$Panel/VBoxContainer/CloseButton.pressed.connect(_on_close_pressed)
	
	# Mettre à jour l'affichage
	update_display()

# Gérer les entrées clavier (fonctionne même en pause grâce à PROCESS_MODE_ALWAYS)
func _input(event: InputEvent) -> void:
	# Fermer l'inventaire avec la touche I quand il est ouvert
	if visible and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_I:
			toggle_visibility()
			get_viewport().set_input_as_handled()

# Ajoute un objet à l'inventaire
func add_item(item_name: String) -> void:
	# Si l'objet existe déjà, on incrémente le compteur
	if items.has(item_name):
		items[item_name] += 1
	else:
		items[item_name] = 1
	
	update_display()
	print("Objet ajouté : %s (total: %d)" % [item_name, items[item_name]])

# Met à jour l'affichage de la liste
func update_display() -> void:
	var item_list := $Panel/VBoxContainer/ItemList
	item_list.clear()
	
	# Afficher chaque type d'objet avec sa quantité
	for item_name in items.keys():
		var quantity: int = items[item_name]
		if quantity > 1:
			item_list.add_item("%s x%d" % [item_name, quantity])
		else:
			item_list.add_item(item_name)

# Affiche/cache l'inventaire
func toggle_visibility() -> void:
	visible = !visible
	
	# Pause le jeu quand l'inventaire est ouvert
	if visible:
		get_tree().paused = true
	else:
		get_tree().paused = false

func _on_close_pressed() -> void:
	toggle_visibility()
