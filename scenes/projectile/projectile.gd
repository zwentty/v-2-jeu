extends Area2D
# Projectile lancé par un ennemi à distance
# Se déplace en ligne droite et inflige des dégâts au joueur

# === PARAMÈTRES EXPORTÉS ===
@export var speed: float = 400.0        # Vitesse du projectile (pixels/sec)
@export var damage: int = 1             # Dégâts infligés
@export var lifetime: float = 3.0       # Durée de vie avant destruction automatique (secondes)

# === VARIABLES ===
var direction: Vector2 = Vector2.RIGHT  # Direction du déplacement
var _lifetime_timer: float = 0.0        # Timer interne pour la durée de vie

func _ready() -> void:
	# Connecter le signal de collision
	body_entered.connect(_on_body_entered)
	
	# Orienter le sprite vers la direction
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	# Déplacer le projectile
	position += direction * speed * delta
	
	# Gérer la durée de vie
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()

# Initialise la direction du projectile (appelé par l'ennemi qui le lance)
func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()

# Collision avec un corps (joueur ou mur)
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Infliger des dégâts au joueur
		if body.has_method("take_damage"):
			body.take_damage(damage)
	
	# Détruire le projectile dans tous les cas (mur ou joueur)
	queue_free()
