# =============================================================================
# enemy.gd
# Script attaché au nœud Enemy (CharacterBody2D)
# =============================================================================

# L'ennemi hérite de CharacterBody2D pour avoir accès à la physique et collisions
extends CharacterBody2D

# Référence au NavigationAgent2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# -----------------------------------------------------------------------------
# CONSTANTES
# =============================================================================

# Vitesse de déplacement de l'ennemi en pixels par seconde
const SPEED = 400.0

# Dégâts infligés au joueur au contact
const DAMAGE_AMOUNT = 1

# Délai entre chaque coup au joueur (en secondes)
const DAMAGE_COOLDOWN = 1.0

# Portée de détection du joueur (distance en pixels)
const DETECTION_RANGE = 500.0

# =============================================================================
# VARIABLES D'ÉTAT
# =============================================================================

# Référence au joueur (trouvée automatiquement)
var player: Node2D = null



# Coodown pour les dégâts (évite que l'ennemi inflige des dégâts trop souvent)
var damage_cooldown_timer: float = 0.0

# =============================================================================
# _ready()
# Appelée quand l'ennemi entre dans la scène
# =============================================================================
func _ready() -> void:
	# On trouve le joueur dans le groupe "player"
	player = get_tree().get_first_node_in_group("player")
	
	# On connecte le signal de l'Area2D pour détecter les contacts
	$HitArea.body_entered.connect(_on_hit_area_body_entered)
	
	# On configure et connecte le NavigationAgent2D
	nav_agent.path_desired_distance = 15.0
	nav_agent.target_desired_distance = 15.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)

# =============================================================================
# _physics_process(delta)
# Appelée à chaque frame physique (60 fois/seconde par défaut)
# =============================================================================
func _physics_process(delta: float) -> void:
	# Si le joueur a été trouvé et est suffisamment proche
	if player and global_position.distance_to(player.global_position) <= DETECTION_RANGE:
		_follow_player_with_pathfinding()
	else:
		# Sinon, l'ennemi ne se déplace pas
		velocity = Vector2.ZERO
	
	# On diminue le coodown des dégâts
	if damage_cooldown_timer > 0.0:
		damage_cooldown_timer -= delta

# =============================================================================
# _follow_player_with_pathfinding()
# Utilise NavigationAgent2D pour contourner intelligemment les obstacles
# =============================================================================
func _follow_player_with_pathfinding() -> void:
	if not player:
		return
	
	# On met à jour la cible du NavigationAgent2D chaque frame pour suivre le joueur
	nav_agent.target_position = player.global_position
	
	# On récupère la prochaine position sur le chemin
	if not nav_agent.is_navigation_finished():
		var next_position = nav_agent.get_next_path_position()
		
		# Calcul de la direction vers ce point du chemin
		var direction = (next_position - global_position).normalized()
		
		# On assigne la vélocité et on laisse NavigationAgent2D gérer l'avoidance
		velocity = direction * SPEED
		nav_agent.set_velocity(velocity)
	else:
		# Si on a atteint la cible, on s'arrête
		velocity = Vector2.ZERO

# =============================================================================
# _on_velocity_computed(safe_velocity)
# Signal émis par NavigationAgent2D après calcul de l'avoidance
# =============================================================================
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

# =============================================================================
# _on_hit_area_body_entered(body)
# Signal appelé quand un corps entre en contact avec l'Area2D
# =============================================================================
func _on_hit_area_body_entered(body: Node2D) -> void:
	# Vérifier que c'est bien le joueur et que le cooldown est écoulé
	if body == player and damage_cooldown_timer <= 0.0:
		# On inflige des dégâts au joueur
		player.take_damage(DAMAGE_AMOUNT)
		
		# On réinitialise le cooldown
		damage_cooldown_timer = DAMAGE_COOLDOWN
