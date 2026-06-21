# =============================================================================
# victory.gd
# Script de l'écran de victoire.
# Quand le joueur clique sur "Rejouer", on recharge le monde pour recommencer.
# =============================================================================
extends Control

func _ready() -> void:
	# On connecte le signal "pressed" du bouton "Rejouer".
	$CenterContainer/VBoxContainer/BoutonRejouer.pressed.connect(_on_rejouer_pressed)

func _on_rejouer_pressed() -> void:
	# Nouvelle partie : on réinitialise l'état sauvegardé (vie + inventaire).
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.reset()
	# On recharge la première salle pour recommencer.
	get_tree().change_scene_to_file("res://scenes/world/salle_1.tscn")
