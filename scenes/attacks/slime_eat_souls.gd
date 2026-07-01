extends Node2D
class_name SlimeEatSouls
# =============================================================================
# Compétence du slime de base : manger les âmes.
#
# Extraite de player.gd : ramasse l'âme (drop d'ennemi) la plus proche dans un
# rayon donné. Le ramassage déclenche, via le signal forme_ramassee de l'item,
# la transformation du slime (cf. transform_inventory.gd → devour()).
#
# Expose trigger() : l'interface commune des attaques/compétences-slime, appelée
# par le TransformHandler (use_ability()).
#
# Le nœud étant enfant du TransformHandler, il n'existe QUE tant que la forme de
# base est active. Les formes-ennemis n'ont pas d'ability_scene : une fois
# transformé, on ne peut donc plus manger d'âme — la règle est structurelle.
# =============================================================================

# Portée de ramassage (px), identique à l'ancien _try_pickup_items du joueur.
@export var pickup_range: float = 50.0

var _player: CharacterBody2D = null


# Interface commune appelée par le TransformHandler (use_ability()).
func trigger() -> void:
	var player := _get_player()
	if player == null:
		return

	for item in get_tree().get_nodes_in_group("item"):
		if not item.has_method("pickup") or not item.has_method("est_ame"):
			continue
		if not item.est_ame():
			continue
		if player.global_position.distance_to(item.global_position) <= pickup_range:
			var item_name: String = item.pickup()
			var inv := get_tree().get_first_node_in_group("inventory")
			if inv and inv.has_method("add_item"):
				inv.add_item(item_name)
			return


# Résolution paresseuse du joueur (groupe "player" peuplé après le _ready).
func _get_player() -> CharacterBody2D:
	if not is_instance_valid(_player):
		var p := get_tree().get_first_node_in_group("player")
		if p is CharacterBody2D:
			_player = p
	return _player
