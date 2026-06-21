# =============================================================================
# door.gd  (attaché à un Area2D : une porte de salle)
# Une porte relie la salle courante à une autre salle, dans N'IMPORTE QUELLE
# direction (la position/orientation de la porte est libre dans la scène).
#   - target_scene : la salle vers laquelle la porte mène.
#   - target_spawn : le nom du Marker2D d'arrivée dans la salle cible
#                    (là où le joueur apparaîtra).
# La porte est fermée (barrière bloquante) tant que la salle n'est pas nettoyée.
# room.gd appelle open() sur toutes les portes du groupe "door" à la fin de salle.
# Au contact du joueur (porte ouverte), on charge la salle cible.
# Si target_scene est vide, la porte ne s'ouvre jamais (= mur, ex. cul-de-sac).
# =============================================================================
extends Area2D

@export_file("*.tscn") var target_scene: String = ""
@export var target_spawn: String = ""

@onready var barriere: StaticBody2D = $Barriere
@onready var visual: Node2D = get_node_or_null("Visual")

var is_open: bool = false
var triggered: bool = false  # évite un double déclenchement

func _ready() -> void:
	add_to_group("door")
	body_entered.connect(_on_body_entered)
	_fermer()

# Ouvre la porte (sauf si elle ne mène nulle part).
func open() -> void:
	if target_scene == "":
		return
	is_open = true
	if barriere != null:
		barriere.collision_layer = 0
	if visual != null:
		visual.visible = false

func _fermer() -> void:
	is_open = false
	if barriere != null:
		barriere.collision_layer = 2
	if visual != null:
		visual.visible = true

func _on_body_entered(body: Node) -> void:
	if triggered or not is_open:
		return
	if not body.is_in_group("player"):
		return
	triggered = true
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.next_spawn_point = target_spawn
		var inventory := get_tree().get_first_node_in_group("inventory")
		gs.save_player(body, inventory)
	get_tree().change_scene_to_file(target_scene)
