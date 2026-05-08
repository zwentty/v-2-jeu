# =============================================================================
# pause.gd
# Script du menu pause.
# Quand le joueur clique sur "Reprendre", on reprend le jeu.
# =============================================================================
extends Control

var settings_menu: Control = null

func _ready() -> void:
	# Mettre ce nœud en mode "continue même en pause" pour que les boutons fonctionnent
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# On met le jeu en pause (ralentit tous les process sauf ui_focus_changed)
	get_tree().paused = true
	
	# On connecte le signal "pressed" des boutons
	$CenterContainer/VBoxContainer/BoutonReprendre.pressed.connect(_on_reprendre_pressed)
	$CenterContainer/VBoxContainer/BoutonParametres.pressed.connect(_on_parametres_pressed)

func _on_reprendre_pressed() -> void:
	# On reprend le jeu
	get_tree().paused = false
	# On supprime le menu pause
	queue_free()

func _on_parametres_pressed() -> void:
	# Cacher le menu pause
	visible = false
	
	# Charger et afficher le menu paramètres
	var settings_scene: PackedScene = load("res://scenes/ui/settings_menu.tscn")
	settings_menu = settings_scene.instantiate()
	settings_menu.back_requested.connect(_on_settings_back)
	get_parent().add_child(settings_menu)
	settings_menu.show_menu()

func _on_settings_back() -> void:
	# Réafficher le menu pause
	visible = true
	# Supprimer le menu paramètres
	if settings_menu:
		settings_menu.queue_free()
		settings_menu = null

# =============================================================================
# _input(event)
# Appelée pour chaque input
# =============================================================================
func _input(event: InputEvent) -> void:
	# Si on appuie sur ESC, on reprend le jeu (sauf si settings est ouvert)
	if event.is_action_pressed("ui_cancel"):
		if settings_menu and settings_menu.visible:
			_on_settings_back()
		else:
			_on_reprendre_pressed()
		get_tree().root.set_input_as_handled()  # Empêcher la propagation
