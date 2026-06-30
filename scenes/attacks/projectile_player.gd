extends Area2D
# =============================================================================
# Projectile — VERSION PLAYER (slime)
#
# Copie du projectile tiré par l'ennemi à distance
# (scenes/projectile/projectile.gd, utilisé par ranged_enemy.gd).
# Différence volontaire : ce projectile vise les ENNEMIS (groupe "enemy"),
# pas le joueur. Le paramètre "source" de la version ennemi n'existe plus ici :
# cette version cible TOUJOURS les ennemis.
#
# Fichier SÉPARÉ du projectile-ennemi : modifiable indépendamment sans toucher
# à projectile.gd. Voir aussi l'attaque mêlée version player : melee_attack_player.gd.
# =============================================================================

# === PARAMÈTRES EXPORTÉS ===
@export var speed: float = 500.0        # Vitesse du projectile (pixels/sec)
@export var damage: int = 3             # Dégâts infligés aux ennemis
@export var lifetime: float = 3.0       # Durée de vie avant destruction automatique

# === VARIABLES ===
var direction: Vector2 = Vector2.RIGHT  # Direction du déplacement
var _lifetime_timer: float = 0.0        # Timer interne pour la durée de vie

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()

# Initialise la direction du projectile (appelé par le joueur qui le lance)
func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()

func _on_body_entered(body: Node2D) -> void:
	# Vise uniquement les ennemis ; ignore le joueur ; se détruit sur les murs
	if body.is_in_group("enemy"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif not body.is_in_group("player"):
		# Mur ou obstacle
		queue_free()
