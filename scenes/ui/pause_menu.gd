# =============================================================================
# pause_menu.gd
# Menu pause avec bouton paramètres
# =============================================================================
extends Control

signal settings_requested

func _ready() -> void:
	# Connecter les boutons
	$Panel/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$Panel/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$Panel/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	
	# Désactiver l'input par défaut
	set_process_input(false)

# Gérer les entrées clavier (fonctionne même en pause grâce à PROCESS_MODE_ALWAYS)
func _input(event: InputEvent) -> void:
	# Fermer le menu pause avec Echap seulement si le menu est visible
	if visible and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_on_resume_pressed()
			get_viewport().set_input_as_handled()

func show_menu() -> void:
	visible = true
	get_tree().paused = true
	set_process_input(true)

func hide_menu() -> void:
	visible = false
	get_tree().paused = false
	set_process_input(false)

func _on_resume_pressed() -> void:
	hide_menu()

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menus/menu.tscn")
