# =============================================================================
# victory.gd
# Script de l'écran de victoire.
# Quand le joueur clique sur "Menu", on retourne au menu principal.
# =============================================================================
extends Control

func _ready() -> void:
	# On connecte le signal "pressed" du bouton "Menu".
	$CenterContainer/VBoxContainer/BoutonMenu.pressed.connect(_on_menu_pressed)

func _on_menu_pressed() -> void:
	# On charge le menu principal.
	get_tree().change_scene_to_file("res://scenes/menus/menu.tscn")
