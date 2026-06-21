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

# Bindings flexibles : peuvent être une touche clavier OU un bouton souris.
# Format : {"type": "key"|"mouse", "code": int}
var competence_binding: Dictionary = {"type": "key", "code": KEY_SPACE}
var attaque_binding: Dictionary = {"type": "mouse", "code": MOUSE_BUTTON_LEFT}

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
	competence_binding = config.get_value("keys", "competence", {"type": "key", "code": KEY_SPACE})
	attaque_binding = config.get_value("keys", "attaque", {"type": "mouse", "code": MOUSE_BUTTON_LEFT})
	
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
	config.set_value("keys", "competence", competence_binding)
	config.set_value("keys", "attaque", attaque_binding)
	
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

# =============================================================================
# Bindings flexibles (clavier OU souris)
# Un binding est un Dictionary : {"type": "key"|"mouse", "code": int}
# =============================================================================

# Nom lisible d'un binding, pour l'affichage dans les menus et sur les objets
func binding_display_name(binding: Dictionary) -> String:
	if binding.get("type", "key") == "mouse":
		match int(binding.get("code", 0)):
			MOUSE_BUTTON_LEFT: return "Clic gauche"
			MOUSE_BUTTON_RIGHT: return "Clic droit"
			MOUSE_BUTTON_MIDDLE: return "Clic milieu"
			_: return "Souris %d" % int(binding.get("code", 0))
	return OS.get_keycode_string(int(binding.get("code", 0)))

# Vrai si l'évènement correspond au binding (touche ou bouton souris)
func binding_matches_event(binding: Dictionary, event: InputEvent) -> bool:
	if binding.get("type", "key") == "mouse":
		return event is InputEventMouseButton and event.button_index == int(binding.get("code", 0))
	return event is InputEventKey and event.keycode == int(binding.get("code", 0))

# Construit un binding à partir d'un évènement clavier ou souris (rebind)
func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		return {"type": "mouse", "code": event.button_index}
	if event is InputEventKey:
		return {"type": "key", "code": event.keycode}
	return {}
