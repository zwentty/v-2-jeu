extends CharacterBody2D
# Ennemi à distance qui lance des projectiles
# Reste à distance du joueur et tire périodiquement

# === ÉNUMÉRATION DES ÉTATS ===
enum State {
	IDLE,    # Ennemi inactif
	PATROL,  # Ennemi en patrouille
	ENGAGE,  # Ennemi engagé (maintient distance optimale)
	ATTACK,  # Ennemi en train de tirer
	DEAD     # Ennemi mort
}

# === PARAMÈTRES EXPORTÉS ===
@export var move_speed: float = 150.0           # Vitesse de déplacement (plus lent que l'ennemi mêlée)
@export var health: int = 2                     # Points de vie (plus fragile)
@export var shoot_cooldown: float = 2.0         # Temps entre deux tirs (secondes)
@export var shoot_windup: float = 0.5           # Temps de préparation avant le tir
@export var optimal_distance: float = 300.0     # Distance optimale par rapport au joueur
@export var min_distance: float = 200.0         # Distance minimale (recule si plus proche)
@export var max_distance: float = 400.0         # Distance maximale (avance si plus loin)
@export var separation_radius: float = 60.0    # Rayon de séparation avec les autres ennemis
@export var separation_force: float = 130.0    # Force de répulsion

# === SCÈNE DU PROJECTILE ===
@export var projectile_scene: PackedScene = preload("res://scenes/projectile/projectile.tscn")

# === RÉFÉRENCES AUX NŒUDS ENFANTS ===
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var detection_area: Area2D = $DetectionArea
@onready var visual: ColorRect = $Visual  # Visuel temporaire (à remplacer par un sprite)

# === VARIABLES D'ÉTAT ===
var state: State = State.IDLE
var player: Node2D = null
var facing_direction: Vector2 = Vector2.RIGHT
var patrol_target: Vector2 = Vector2.ZERO
var patrol_timer: float = 0.0
var shoot_timer: float = 0.0      # Cooldown entre les tirs
var windup_timer: float = 0.0     # Timer de préparation du tir

# === VARIABLES DE SALLE ===
var room_number: int = 1
var room_min_x: float = 0.0
var room_max_x: float = 2560.0

func _ready() -> void:
	# Déterminer la salle en fonction de la position de spawn
	if global_position.x < 2560.0:
		room_number = 1
		room_min_x = 0.0
		room_max_x = 2560.0
	else:
		room_number = 2
		room_min_x = 2560.0
		room_max_x = 5120.0
	
	# Configurer NavigationAgent2D
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 20.0
	nav_agent.radius = 25.0
	nav_agent.neighbor_distance = 250.0
	nav_agent.max_neighbors = 8
	nav_agent.max_speed = move_speed
	nav_agent.avoidance_enabled = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# Enregistrer auprès de l'EnemyManager
	EnemyManager.register(self)
	
	# Connecter les signaux
	detection_area.body_entered.connect(_on_player_detected)
	
	# Désactiver les ennemis de la salle 2 jusqu'à ce que le joueur y entre
	if room_number == 2:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		detection_area.monitoring = false
	
	# Commencer en patrouille
	state = State.PATROL
	_pick_patrol_point()

func _physics_process(delta: float) -> void:
	# Décrémenter les timers
	if shoot_timer > 0:
		shoot_timer -= delta
	if patrol_timer > 0:
		patrol_timer -= delta
	
	# Machine à états
	match state:
		State.IDLE:
			_state_idle(delta)
		State.PATROL:
			_state_patrol(delta)
		State.ENGAGE:
			_state_engage(delta)
		State.ATTACK:
			_state_attack(delta)
		State.DEAD:
			_state_dead()

# === ÉTATS ===

# IDLE : Attendre avant de reprendre la patrouille
func _state_idle(delta: float) -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	
	if patrol_timer <= 0:
		state = State.PATROL
		_pick_patrol_point()

# PATROL : Se déplacer vers un point de patrouille aléatoire
func _state_patrol(delta: float) -> void:
	_navigate_to(patrol_target)
	
	if global_position.distance_to(patrol_target) < 30.0:
		state = State.IDLE
		patrol_timer = randf_range(1.0, 3.0)

# ENGAGE : Maintenir distance optimale et tirer sur le joueur
func _state_engage(delta: float) -> void:
	# Si le joueur disparaît ou change de salle → retourner en patrouille
	if player == null or not _player_in_same_room():
		player = null
		state = State.PATROL
		_pick_patrol_point()
		return
	
	var dist = global_position.distance_to(player.global_position)
	
	# Récupérer la position cible assignée par EnemyManager (cercle d'encerclement)
	var target = EnemyManager.get_target_position(self)
	
	_navigate_to(target)
	_face_player()
	
	# Tirer si le cooldown est prêt et dans la plage de distance
	if shoot_timer <= 0 and dist >= min_distance and dist <= max_distance:
		state = State.ATTACK
		windup_timer = shoot_windup

# ATTACK : Préparer et lancer le projectile
func _state_attack(delta: float) -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	
	# Continuer de regarder le joueur pendant la préparation
	if player:
		facing_direction = (player.global_position - global_position).normalized()
	
	# Phase de préparation (windup)
	if windup_timer > 0:
		windup_timer -= delta
		return
	
	# Tirer le projectile
	_shoot_projectile()
	shoot_timer = shoot_cooldown
	
	# Retourner en ENGAGE
	if player and _player_in_same_room():
		state = State.ENGAGE
	else:
		player = null
		state = State.PATROL
		_pick_patrol_point()

# DEAD : Ne rien faire
func _state_dead() -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)

# === MÉTHODES AUXILIAIRES ===

# Détection du joueur
func _on_player_detected(body: Node2D) -> void:
	if body.is_in_group("player") and state != State.DEAD:
		player = body
		
		# Vérifier que le joueur est dans la même salle avant d'engager
		if _player_in_same_room():
			state = State.ENGAGE

# Navigation vers une cible
func _navigate_to(target: Vector2) -> void:
	nav_agent.set_target_position(target)
	
	if nav_agent.is_navigation_finished():
		return
	
	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	
	# Ajouter séparation avec les autres ennemis
	var separation = _calculate_separation()
	
	# Ajouter évitement du joueur (importante pour ne pas le traverser)
	var player_avoidance = _calculate_player_avoidance()
	
	# Combiner toutes les forces
	direction = (direction + separation + player_avoidance).normalized()
	
	var desired_velocity = direction * move_speed
	nav_agent.set_velocity(desired_velocity)

# Callback de NavigationAgent2D
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

# Calcul de la force de séparation avec les autres ennemis
func _calculate_separation() -> Vector2:
	var separation = Vector2.ZERO
	var nearby_enemies = get_tree().get_nodes_in_group("enemy")
	
	for enemy in nearby_enemies:
		if enemy == self or not is_instance_valid(enemy):
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist < separation_radius and dist > 0:
			var away = (global_position - enemy.global_position).normalized()
			separation += away * (separation_radius - dist) / separation_radius
	
	return separation.normalized() * separation_force if separation.length() > 0 else Vector2.ZERO

# Calcul de la force d'évitement du joueur (pour contourner au lieu de traverser)
func _calculate_player_avoidance() -> Vector2:
	if player == null:
		return Vector2.ZERO
	
	var dist = global_position.distance_to(player.global_position)
	var avoidance_radius = min_distance * 0.8  # Commence à éviter à 80% de la distance minimale
	
	# Si trop proche du joueur, force de répulsion forte
	if dist < avoidance_radius and dist > 0:
		var away = (global_position - player.global_position).normalized()
		var strength = (avoidance_radius - dist) / avoidance_radius  # Force proportionnelle
		return away * separation_force * strength * 1.5  # 1.5x plus fort que séparation entre ennemis
	
	return Vector2.ZERO

# Oriente l'ennemi vers le joueur
func _face_player() -> void:
	if player:
		facing_direction = (player.global_position - global_position).normalized()

# Vérifie si le joueur est dans la même salle
func _player_in_same_room() -> bool:
	return (room_number == 1 and player.global_position.x < 2560.0) or \
	       (room_number == 2 and player.global_position.x >= 2560.0)

# Choisit un point de patrouille aléatoire
func _pick_patrol_point() -> void:
	var offset := Vector2(randf_range(-150, 150), randf_range(-150, 150))
	patrol_target = global_position + offset
	patrol_target.x = clamp(patrol_target.x, room_min_x + 100, room_max_x - 100)

# Tire un projectile vers le joueur
func _shoot_projectile() -> void:
	if projectile_scene == null or player == null:
		return
	
	# Instancier le projectile
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
	
	# Positionner le projectile devant l'ennemi
	projectile.global_position = global_position + facing_direction * 20.0
	
	# Définir la direction du projectile
	projectile.set_direction(facing_direction)

# === SYSTÈME DE SANTÉ ===

# Infliger des dégâts à l'ennemi
func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	
	health -= amount
	
	if health <= 0:
		die()

# Mort de l'ennemi
func die() -> void:
	state = State.DEAD
	EnemyManager.unregister(self)

	# Faire apparaître un objet à ramasser (même forme que l'ennemi mais en noir)
	var item_scene: PackedScene = load("res://scenes/items/item.tscn")
	var item: Node2D = item_scene.instantiate()
	item.global_position = global_position
	item.item_name = "Âme de Slime"
	item.item_color = Color.BLACK
	item.item_polygon = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	get_parent().add_child(item)

	# Animation de mort (fade out simple)
	var tween = create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
