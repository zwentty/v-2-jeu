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
	# change_scene_to_file() remplace la scène actuelle par world.tscn.
	# C'est l'équivalent d'un "chargement de niveau".
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
