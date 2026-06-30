extends Area2D
# =============================================================================
# Attaque mêlée — VERSION PLAYER (slime)
#
# Copie du comportement de l'attaque mêlée de l'ennemi
# (scenes/enemy/enemy.gd : _trigger_attack / _on_hitbox_hit + nœud AttackHitbox).
# Différence volontaire : cette attaque vise les ENNEMIS (groupe "enemy"),
# pas le joueur.
#
# Fichier SÉPARÉ de l'attaque-ennemi : modifiable indépendamment sans toucher
# à enemy.gd. Voir aussi le projectile version player : projectile_player.gd.
# =============================================================================

# === PARAMÈTRES (équivalents de l'attaque-ennemi, ajustables côté player) ===
@export var attack_damage: int = 3
const HITBOX_ACTIVE_DURATION: float = 0.25  # durée pendant laquelle la hitbox frappe
const HITBOX_DISTANCE: float = 40.0         # distance de la hitbox devant le slime

# === NŒUDS ===
@onready var hitbox_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox_visual: Polygon2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_hitbox_hit)
	# Désactivée et invisible par défaut (comme la hitbox de l'ennemi)
	hitbox_shape.disabled = true
	hitbox_visual.visible = false

# Interface de déclenchement COMMUNE à toutes les attaques/compétences-slime.
# Appelée par le TransformHandler (use_attack()/use_ability()) sans connaître le
# type concret de l'attaque. Vise automatiquement le curseur depuis le slime.
func trigger() -> void:
	declencher(get_global_mouse_position() - global_position)

# Déclenche l'attaque dans la direction voulue.
# À appeler depuis le joueur (slime) en passant la direction de visée.
func declencher(direction: Vector2) -> void:
	position = direction.normalized() * HITBOX_DISTANCE
	hitbox_shape.disabled = false
	hitbox_visual.visible = true

	await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
	if is_instance_valid(self):
		hitbox_shape.disabled = true
		hitbox_visual.visible = false

func _on_hitbox_hit(body: Node2D) -> void:
	# Vise les ennemis (et non le joueur comme la version ennemi)
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(attack_damage)
