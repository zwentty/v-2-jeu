extends Node2D
class_name TransformHandler
# =============================================================================
# TransformHandler
# Nœud à ajouter comme ENFANT du slime (player). Gère la transformation du
# slime en une PlayableForm lorsqu'il « mange » le drop d'un ennemi.
#
# apply(form) adopte une forme : visuel, attaque, compétence et statistiques,
# en conservant le pourcentage de PV au changement de forme.
#
# Le handler ne connaît JAMAIS le type concret de l'attaque/compétence montée :
# il appelle simplement une méthode de déclenchement commune (TRIGGER_METHOD)
# sur l'instance courante. Toutes les attaques-slime exposent cette méthode.
# =============================================================================

# Émis à la fin de apply(), une fois la nouvelle forme entièrement montée.
signal transformed(form: PlayableForm)

# Référence vers l'AnimatedSprite2D du slime (nœud "Visual").
@export var animated_sprite: AnimatedSprite2D
# Référence vers le nœud porteur des statistiques. Aujourd'hui c'est le slime
# lui-même (il possède max_health / health) ; peut être un nœud de stats dédié.
@export var stats_node: Node

# Animation jouée au repos juste après une transformation.
const IDLE_ANIM: StringName = &"idle"
# Méthode publique commune que TOUTES les attaques/compétences-slime exposent
# pour être déclenchées. Le handler ne connaît rien d'autre de leur type.
const TRIGGER_METHOD: StringName = &"trigger"

# Forme actuellement incarnée (null tant qu'aucune transformation n'a eu lieu).
var current_form: PlayableForm = null
# Instances montées de l'attaque et de la compétence de la forme courante.
var attack_instance: Node = null
var ability_instance: Node = null


# Adopte une nouvelle forme jouable.
func apply(form: PlayableForm) -> void:
	if form == null:
		return

	# 1. Retirer proprement les capacités de la forme précédente.
	if is_instance_valid(attack_instance):
		attack_instance.queue_free()
	if is_instance_valid(ability_instance):
		ability_instance.queue_free()
	attack_instance = null
	ability_instance = null

	# 2. Appliquer le SpriteFrames de la nouvelle forme et lancer l'idle.
	if animated_sprite and form.sprite_frames:
		animated_sprite.sprite_frames = form.sprite_frames
		if animated_sprite.sprite_frames.has_animation(IDLE_ANIM):
			animated_sprite.play(IDLE_ANIM)

	# 3. Instancier attaque et compétence comme enfants, garder les références.
	if form.attack_scene:
		attack_instance = form.attack_scene.instantiate()
		add_child(attack_instance)
	if form.ability_scene:
		ability_instance = form.ability_scene.instantiate()
		add_child(ability_instance)

	# 4. Appliquer les stats (en conservant le pourcentage de PV).
	_apply_stats(form.stats)

	# 5. Mémoriser la forme courante et signaler la transformation.
	current_form = form
	transformed.emit(form)


# === STATISTIQUES ===

# Applique un StatBlock au nœud de stats en conservant le pourcentage de PV.
func _apply_stats(stats: StatBlock) -> void:
	if stats == null or stats_node == null:
		return

	# PV : conserver le pourcentage de vie au changement de forme.
	# ratio = vie courante / ancien max_health (calculé AVANT d'écraser le max).
	# Au tout premier appel (aucune forme précédente), pas de ratio fiable :
	# on démarre la nouvelle forme à pleine vie (ratio = 1.0).
	var ratio: float = 1.0
	if current_form != null and "max_health" in stats_node and "health" in stats_node:
		var old_max: float = float(stats_node.max_health)
		if old_max > 0.0:
			ratio = float(stats_node.health) / old_max

	if "max_health" in stats_node:
		stats_node.max_health = stats.max_health
	if "health" in stats_node:
		stats_node.health = ratio * stats.max_health

	# Autres stats : appliquées seulement si le nœud les possède réellement.
	_set_if_present(stats_node, &"move_speed", stats.move_speed)
	_set_if_present(stats_node, &"damage", stats.damage)
	_set_if_present(stats_node, &"weight", stats.weight)

	# Rafraîchit l'affichage de vie du nœud de stats s'il en propose un, pour que
	# la barre reflète tout de suite le nouveau max et le ratio de PV conservé.
	if stats_node.has_method("_update_health_bar"):
		stats_node._update_health_bar()


func _set_if_present(node: Object, prop: StringName, value) -> void:
	if prop in node:
		node.set(prop, value)


# === DÉCLENCHEMENT DES CAPACITÉS ===
# Relais type-agnostiques : on appelle la méthode commune TRIGGER_METHOD sur
# l'instance montée, sans jamais connaître son type concret.

func use_attack() -> void:
	_trigger(attack_instance)

func use_ability() -> void:
	_trigger(ability_instance)

func _trigger(instance: Node) -> void:
	if is_instance_valid(instance) and instance.has_method(TRIGGER_METHOD):
		instance.call(TRIGGER_METHOD)
