# =============================================================================
# settings.gd
# Autoload pour gérer les paramètres du jeu
# =============================================================================
extends Node

# Touches configurables
var key_move_up: int = KEY_Z
var key_move_left: int = KEY_Q
var key_move_down: int = KEY_S
var key_move_right: int = KEY_D
var key_inventory: int = KEY_I
var key_pickup: int = KEY_E

# Fichier de sauvegarde
const SETTINGS_FILE: String = "user://settings.cfg"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE)
	
	if err != OK:
		# Fichier n'existe pas, utiliser les valeurs par défaut
		return
	
	# Charger les touches
	key_move_up = config.get_value("keys", "move_up", KEY_Z)
	key_move_left = config.get_value("keys", "move_left", KEY_Q)
	key_move_down = config.get_value("keys", "move_down", KEY_S)
	key_move_right = config.get_value("keys", "move_right", KEY_D)
	key_inventory = config.get_value("keys", "inventory", KEY_I)
	key_pickup = config.get_value("keys", "pickup", KEY_E)
	
	# Charger le plein écran
	var fullscreen: bool = config.get_value("display", "fullscreen", false)
	set_fullscreen(fullscreen)

func save_settings() -> void:
	var config := ConfigFile.new()
	
	# Sauvegarder les touches
	config.set_value("keys", "move_up", key_move_up)
	config.set_value("keys", "move_left", key_move_left)
	config.set_value("keys", "move_down", key_move_down)
	config.set_value("keys", "move_right", key_move_right)
	config.set_value("keys", "inventory", key_inventory)
	config.set_value("keys", "pickup", key_pickup)
	
	# Sauvegarder le plein écran
	config.set_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	config.save(SETTINGS_FILE)

func set_fullscreen(enabled: bool) -> void:
	# Vérifier si on est dans l'éditeur (embedded window)
	if OS.has_feature("editor"):
		print("Le plein écran n'est pas disponible dans l'éditeur Godot")
		return
	
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Sauvegarder immédiatement le changement
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value("display", "fullscreen", enabled)
	config.save(SETTINGS_FILE)
