# =============================================================================
# settings_menu.gd
# Menu des paramètres (touches et plein écran)
# =============================================================================
extends Control

signal back_requested

# Référence au bouton actuellement en attente d'une nouvelle touche
var awaiting_input_button: Button = null

func _ready() -> void:
	# Connecter les boutons
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/FullscreenCheckbox.toggled.connect(_on_fullscreen_toggled)
	$Panel/VBoxContainer/CloseButton.pressed.connect(_on_close_pressed)
	
	# Connecter les boutons de changement de touches
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveUpButton.pressed.connect(_on_key_button_pressed.bind($Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveUpButton, "move_up"))
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveLeftButton.pressed.connect(_on_key_button_pressed.bind($Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveLeftButton, "move_left"))
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveDownButton.pressed.connect(_on_key_button_pressed.bind($Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveDownButton, "move_down"))
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveRightButton.pressed.connect(_on_key_button_pressed.bind($Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveRightButton, "move_right"))
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/InventoryButton.pressed.connect(_on_key_button_pressed.bind($Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/InventoryButton, "inventory"))
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/PickupButton.pressed.connect(_on_key_button_pressed.bind($Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/PickupButton, "pickup"))
	
	# Charger les paramètres actuels
	_load_settings()

func _load_settings() -> void:
	# Charger l'état du plein écran (sans déclencher le signal)
	var is_fullscreen: bool = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/FullscreenCheckbox.set_pressed_no_signal(is_fullscreen)
	
	# Désactiver la checkbox si on est dans l'éditeur
	if OS.has_feature("editor"):
		$Panel/VBoxContainer/ScrollContainer/VBoxContainer/FullscreenCheckbox.disabled = true
		$Panel/VBoxContainer/ScrollContainer/VBoxContainer/FullscreenCheckbox.tooltip_text = "Plein écran non disponible dans l'éditeur"
	
	# Charger les touches actuelles
	_update_key_labels()

func _update_key_labels() -> void:
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveUpButton.text = "Haut: %s" % _get_key_name(Settings.key_move_up)
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveLeftButton.text = "Gauche: %s" % _get_key_name(Settings.key_move_left)
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveDownButton.text = "Bas: %s" % _get_key_name(Settings.key_move_down)
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/MoveRightButton.text = "Droite: %s" % _get_key_name(Settings.key_move_right)
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/InventoryButton.text = "Inventaire: %s" % _get_key_name(Settings.key_inventory)
	$Panel/VBoxContainer/ScrollContainer/VBoxContainer/KeysSection/PickupButton.text = "Ramasser: %s" % _get_key_name(Settings.key_pickup)

func _get_key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode)

func _on_fullscreen_toggled(button_pressed: bool) -> void:
	Settings.set_fullscreen(button_pressed)
	# Attendre un court instant pour que le changement soit effectif
	await get_tree().process_frame

func _on_key_button_pressed(button: Button, _action: String) -> void:
	awaiting_input_button = button
	button.text = "Appuyez sur une touche..."

func _input(event: InputEvent) -> void:
	if awaiting_input_button and event is InputEventKey and event.pressed and not event.echo:
		var keycode: int = event.keycode
		
		# Mettre à jour la touche dans Settings
		match awaiting_input_button.name:
			"MoveUpButton":
				Settings.key_move_up = keycode
			"MoveLeftButton":
				Settings.key_move_left = keycode
			"MoveDownButton":
				Settings.key_move_down = keycode
			"MoveRightButton":
				Settings.key_move_right = keycode
			"InventoryButton":
				Settings.key_inventory = keycode
			"PickupButton":
				Settings.key_pickup = keycode
		
		Settings.save_settings()
		_update_key_labels()
		awaiting_input_button = null
		get_viewport().set_input_as_handled()

func show_menu() -> void:
	visible = true

func hide_menu() -> void:
	visible = false

func _on_close_pressed() -> void:
	hide_menu()
	back_requested.emit()
