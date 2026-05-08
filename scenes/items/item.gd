# =============================================================================
# item.gd
# Script pour un objet ramassable au sol
# =============================================================================
extends Area2D

# Nom de l'objet
@export var item_name: String = "Objet"

# Est-ce que le joueur est à proximité ?
var player_nearby: bool = false

func _ready() -> void:
	# Ajouter au groupe "item" pour que le joueur puisse les détecter
	add_to_group("item")
	
	# Connecter les signaux de détection
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Afficher la touche de ramassage configurée
	$Label.text = OS.get_keycode_string(Settings.key_pickup)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		$Label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		$Label.visible = false

# Fonction appelée par le joueur pour ramasser l'objet
func pickup() -> String:
	queue_free()  # Supprime l'objet de la scène
	return item_name
