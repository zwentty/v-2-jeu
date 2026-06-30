# =============================================================================
# item.gd
# Script pour un objet ramassable au sol
# =============================================================================
extends Area2D

# Émis au ramassage, juste avant la destruction de l'objet, pour qu'un futur
# système d'inventaire récupère la forme transportée (peut être null).
signal forme_ramassee(forme: PlayableForm)

@export var item_name: String = "Objet"
# Couleur et forme du visuel — surchargées à l'instanciation pour les drops ennemis
@export var item_color: Color = Color(1, 0.8, 0, 1)
@export var item_polygon: PackedVector2Array
# Forme jouable transportée par cet objet (renseignée par l'ennemi à sa mort).
@export var carried_form: PlayableForm = null

var player_nearby: bool = false

func _ready() -> void:
	add_to_group("item")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Les âmes se ramassent avec la touche/clic « compétence », les autres objets avec la touche « ramasser »
	if est_ame():
		$Label.text = Settings.binding_display_name(Settings.competence_binding)
	else:
		$Label.text = OS.get_keycode_string(Settings.key_pickup)

	$Visual.color = item_color
	if item_polygon.size() > 0:
		$Visual.polygon = item_polygon

	_spread_from_nearby_items()

# Déplace l'item si un autre item est déjà trop proche
func _spread_from_nearby_items() -> void:
	const MIN_DIST := 24.0
	for _attempt in range(8):
		var overlapping := false
		for other in get_tree().get_nodes_in_group("item"):
			if other == self:
				continue
			if global_position.distance_to(other.global_position) < MIN_DIST:
				overlapping = true
				break
		if not overlapping:
			break
		global_position += Vector2.from_angle(randf() * TAU) * MIN_DIST

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		$Label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		$Label.visible = false

# Indique si cet objet est une âme (drop d'ennemi).
# Les âmes ont un nom commençant par « Âme » et se ramassent avec la touche espace.
func est_ame() -> bool:
	return item_name.begins_with("Âme")

# Retourne la forme jouable transportée (null si aucune).
# Permet à un futur inventaire de la récupérer sans passer par le signal.
func get_carried_form() -> PlayableForm:
	return carried_form

# Fonction appelée par le joueur pour ramasser l'objet
func pickup() -> String:
	# Expose la forme transportée avant destruction (inventaire futur).
	forme_ramassee.emit(carried_form)
	queue_free()
	return item_name
