# =============================================================================
# inventory.gd
# Script de l'interface d'inventaire
# =============================================================================
extends Control

# Dictionnaire des objets dans l'inventaire {nom: quantité}
var items: Dictionary = {}

# Nombre de slots dans l'inventaire
const MAX_SLOTS: int = 24

# Référence au GridContainer
var grid_container: GridContainer = null

func _ready() -> void:
	# Connecter le bouton de fermeture
	$Panel/VBoxContainer/CloseButton.pressed.connect(_on_close_pressed)
	
	# Récupérer le GridContainer
	grid_container = $Panel/VBoxContainer/ScrollContainer/GridContainer
	
	# Créer les slots d'inventaire
	_create_slots()
	
	# Mettre à jour l'affichage
	update_display()

# Crée les slots d'inventaire visuels
func _create_slots() -> void:
	for i in range(MAX_SLOTS):
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(100, 100)
		
		# Style du slot vide
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.2, 1)
		style.border_color = Color(0.3, 0.3, 0.35, 1)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 5
		style.corner_radius_top_right = 5
		style.corner_radius_bottom_right = 5
		style.corner_radius_bottom_left = 5
		slot.add_theme_stylebox_override("panel", style)
		
		# Container pour le contenu du slot
		var vbox := VBoxContainer.new()
		vbox.anchor_right = 1.0
		vbox.anchor_bottom = 1.0
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_child(vbox)
		
		# Label pour le nom de l'objet
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		name_label.custom_minimum_size = Vector2(90, 0)
		vbox.add_child(name_label)
		
		# Label pour la quantité
		var qty_label := Label.new()
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty_label.add_theme_font_size_override("font_size", 16)
		qty_label.add_theme_color_override("font_color", Color(1, 1, 0.5, 1))
		qty_label.visible = false
		vbox.add_child(qty_label)
		
		grid_container.add_child(slot)

# Gérer les entrées clavier (fonctionne même en pause grâce à PROCESS_MODE_ALWAYS)
func _input(event: InputEvent) -> void:
	# Ouvrir/fermer l'inventaire avec la touche configurée
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == Settings.key_inventory:
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
	if not grid_container:
		return
	
	# Réinitialiser tous les slots
	for i in range(grid_container.get_child_count()):
		var slot := grid_container.get_child(i) as Panel
		if slot:
			var vbox := slot.get_child(0) as VBoxContainer
			var name_label := vbox.get_child(0) as Label
			var qty_label := vbox.get_child(1) as Label
			
			name_label.text = ""
			qty_label.text = ""
			qty_label.visible = false
			
			# Style slot vide
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.15, 0.15, 0.2, 1)
			style.border_color = Color(0.3, 0.3, 0.35, 1)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.corner_radius_top_left = 5
			style.corner_radius_top_right = 5
			style.corner_radius_bottom_right = 5
			style.corner_radius_bottom_left = 5
			slot.add_theme_stylebox_override("panel", style)
	
	# Remplir les slots avec les items
	var slot_index: int = 0
	for item_name in items.keys():
		if slot_index >= MAX_SLOTS:
			break
		
		var quantity: int = items[item_name]
		var slot := grid_container.get_child(slot_index) as Panel
		if slot:
			var vbox := slot.get_child(0) as VBoxContainer
			var name_label := vbox.get_child(0) as Label
			var qty_label := vbox.get_child(1) as Label
			
			# Afficher le nom de l'item
			name_label.text = item_name
			
			# Afficher la quantité si > 1
			if quantity > 1:
				qty_label.text = "x%d" % quantity
				qty_label.visible = true
			
			# Style slot rempli
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.25, 0.35, 0.45, 1)
			style.border_color = Color(0.5, 0.7, 0.9, 1)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.corner_radius_top_left = 5
			style.corner_radius_top_right = 5
			style.corner_radius_bottom_right = 5
			style.corner_radius_bottom_left = 5
			slot.add_theme_stylebox_override("panel", style)
		
		slot_index += 1

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
