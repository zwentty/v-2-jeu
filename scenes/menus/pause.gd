# =============================================================================
# pause.gd
# Script du menu pause.
# Quand le joueur clique sur "Reprendre", on reprend le jeu.
# =============================================================================
extends Control

func _ready() -> void:
	# Mettre ce nœud en mode "continue même en pause" pour que les boutons fonctionnent
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# On met le jeu en pause (ralentit tous les process sauf ui_focus_changed)
	get_tree().paused = true
	
	# On connecte le signal "pressed" du bouton "Reprendre".
	$CenterContainer/VBoxContainer/BoutonReprendre.pressed.connect(_on_reprendre_pressed)

func _on_reprendre_pressed() -> void:
	# On reprend le jeu
	get_tree().paused = false
	# On supprime le menu pause
	queue_free()

# =============================================================================
# _input(event)
# Appelée pour chaque input
# =============================================================================
func _input(event: InputEvent) -> void:
	# Si on appuie sur ESC, on reprend le jeu
	if event.is_action_pressed("ui_cancel"):
		_on_reprendre_pressed()
		get_tree().root.set_input_as_handled()  # Empêcher la propagation
