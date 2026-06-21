# =============================================================================
# menu.gd
# Script du menu principal.
# Quand le joueur clique sur "Démarrer", on charge la scène du monde.
# =============================================================================
extends Control

func _ready() -> void:
	# On connecte le signal "pressed" du bouton à notre fonction.
	# "$CenterContainer/VBoxContainer/BoutonStart" = chemin vers le nœud Button
	# dans l'arbre de la scène.
	$CenterContainer/VBoxContainer/BoutonStart.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	# Nouvelle partie : on réinitialise l'état sauvegardé (vie + inventaire).
	# Accès par chemin de nœud pour rester robuste si l'autoload n'est pas
	# encore enregistré (projet non rechargé dans l'éditeur).
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.reset()
	# change_scene_to_file() charge la première salle.
	get_tree().change_scene_to_file("res://scenes/world/salle_1.tscn")
