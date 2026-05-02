# =============================================================================
# game_over.gd
# Script de l'écran de défaite.
# Quand le joueur clique sur "Rejouer", on recharge la scène du monde.
# =============================================================================
extends Control

func _ready() -> void:
	# On connecte le signal "pressed" du bouton "Rejouer".
	$CenterContainer/VBoxContainer/BoutonRejouer.pressed.connect(_on_rejouer_pressed)

func _on_rejouer_pressed() -> void:
	# On recharge world.tscn pour recommencer une nouvelle partie.
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
