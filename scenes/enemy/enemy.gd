extends CharacterBody2D
# Script d'un ennemi individuel qui utilise EnemyManager pour coordonner ses actions
# Gère la navigation, les attaques, la détection du joueur et les états

# === ÉNUMÉRATION DES ÉTATS ===
enum State {
	IDLE,    # Ennemi inactif (pause entre les patrouilles)
	PATROL,  # Ennemi en patrouille
	ENGAGE,  # Ennemi engagé avec le joueur (navigation vers position tactique)
	ATTACK,  # Ennemi en train d'attaquer
	DEAD     # Ennemi mort
}

# === PARAMÈTRES EXPORTÉS (modifiables dans l'éditeur) ===
@export var move_speed: float = 180.0           # Vitesse de déplacement (pixels/sec)
@export var attack_damage: int = 1              # Dégâts infligés par attaque
@export var attack_cooldown: float = 1.2        # Temps entre deux attaques (secondes)
@export var attack_windup: float = 0.4          # Temps de préparation avant l'attaque (secondes)
@export var health: int = 3                     # Points de vie
@export var separation_radius: float = 60.0    # Rayon de séparation avec les autres ennemis
@export var separation_force: float = 130.0    # Force de répulsion pour éviter les collisions

# === CONSTANTES ===
const HITBOX_ACTIVE_DURATION: float = 0.25  # Durée d'activation de la hitbox d'attaque
const ATTACK_DISTANCE: float = 55.0          # Distance minimale pour déclencher une attaque

# === RÉFÉRENCES AUX NŒUDS ENFANTS ===
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D  # Agent de navigation pour pathfinding
@onready var detection_area: Area2D = $DetectionArea            # Zone de détection du joueur
@onready var attack_area: Area2D = $AttackArea                  # Zone d'attaque (non utilisée actuellement)
@onready var attack_hitbox: Area2D = $AttackHitbox              # Hitbox qui inflige des dégâts
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D  # Forme de collision de la hitbox
@onready var hitbox_visual: Polygon2D = $AttackHitbox/Visual    # Visuel de la hitbox (debug)

# === VARIABLES D'ÉTAT ===
var state: State = State.IDLE                  # État actuel de l'ennemi
var player: Node2D = null                      # Référence au joueur détecté
var facing_direction: Vector2 = Vector2.RIGHT  # Direction vers laquelle l'ennemi regarde
var patrol_target: Vector2 = Vector2.ZERO      # Position cible de la patrouille
var patrol_timer: float = 0.0                  # Timer pour les pauses en IDLE
var patrol_wait: float = 2.5                   # Durée des pauses entre patrouilles
var attack_timer: float = 0.0                  # Timer du cooldown d'attaque
var windup_timer: float = 0.0                  # Timer de préparation de l'attaque
var wander_angle: float = 0.0                  # Angle de déplacement aléatoire (non utilisé)
var room_number: int = 1                       # Numéro de la salle où spawn l'ennemi
var room_min_x: float = 0.0                    # Limite gauche de la salle
var room_max_x: float = 2560.0                 # Limite droite de la salle

# === INITIALISATION ===

func _ready() -> void:
	add_to_group("enemy")  # Ajouter au groupe "enemy" pour la communication
	
	# Déterminer dans quelle salle l'ennemi spawn (map divisée en 2 salles)
	if global_position.x < 2560.0:
		room_number = 1
		room_min_x = 0.0
		room_max_x = 2560.0
	else:
		room_number = 2
		room_min_x = 2560.0
		room_max_x = 5120.0
	
	_update_health_bar()  # Initialiser la barre de vie
	
	# Configurer NavigationAgent2D pour le pathfinding et l'évitement
	nav_agent.path_desired_distance = 4.0         # Distance acceptable du chemin
	nav_agent.target_desired_distance = 20.0      # Distance acceptable de la cible
	nav_agent.radius = 25.0                       # Rayon de l'agent pour évitement
	nav_agent.neighbor_distance = 250.0           # Distance de détection des voisins
	nav_agent.max_neighbors = 8                   # Nombre max de voisins à considérer
	nav_agent.max_speed = move_speed              # Vitesse maximale
	nav_agent.avoidance_enabled = true            # Activer l'évitement automatique
	nav_agent.velocity_computed.connect(_on_velocity_computed)  # Connecter le signal de vélocité
	
	EnemyManager.register(self)  # S'enregistrer auprès du gestionnaire d'ennemis
	
	# Connecter les signaux
	detection_area.body_entered.connect(_on_player_detected)  # Détecter le joueur
	attack_hitbox.body_entered.connect(_on_hitbox_hit)        # Détecter les coups
	
	# Désactiver la hitbox d'attaque au démarrage
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	
	_pick_patrol_point()  # Choisir un premier point de patrouille

# === BOUCLE PRINCIPALE ===

func _physics_process(delta: float) -> void:
	attack_timer -= delta  # Décrémenter le cooldown d'attaque
	wander_angle += randf_range(-0.2, 0.2)  # Varier l'angle de déplacement (non utilisé actuellement)
	
	# Exécuter la logique correspondant à l'état actuel
	match state:
		State.IDLE:    _state_idle(delta)
		State.PATROL:  _state_patrol(delta)
		State.ENGAGE:  _state_engage(delta)
		State.ATTACK:  _state_attack(delta)
		State.DEAD:    _state_dead()

# === LOGIQUE DES ÉTATS ===

# IDLE : Attendre avant de reprendre la patrouille
func _state_idle(delta: float) -> void:
	velocity = Vector2.ZERO  # Arrêter le mouvement
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	
	patrol_timer -= delta  # Décrémenter le timer d'attente
	if patrol_timer <= 0:
		_pick_patrol_point()  # Choisir un nouveau point
		state = State.PATROL  # Reprendre la patrouille

# PATROL : Se déplacer vers le point de patrouille
func _state_patrol(delta: float) -> void:
	# Arrivé à destination → passer en IDLE
	if global_position.distance_to(patrol_target) < 12.0:
		patrol_timer = patrol_wait
		state = State.IDLE
		return
	
	_navigate_to(patrol_target)  # Se diriger vers le point

# ENGAGE : Poursuivre le joueur selon la position assignée par EnemyManager
func _state_engage(delta: float) -> void:
	# Si le joueur disparaît ou change de salle → retourner en patrouille
	if player == null or not _player_in_same_room():
		state = State.PATROL
		_pick_patrol_point()
		return
	
	var dist = global_position.distance_to(player.global_position)
	
	# Si à portée d'attaque ET timer prêt ET autorisé par le manager → attaquer
	if dist < ATTACK_DISTANCE and attack_timer <= 0 and EnemyManager.can_attack(self):
		state = State.ATTACK
		windup_timer = attack_windup  # Commencer la préparation de l'attaque
		return
	
	# Récupérer la position cible assignée par EnemyManager (tactique : flanc, interception, etc.)
	var target = EnemyManager.get_target_position(self)
	_navigate_to(target)  # Se diriger vers cette position
	_face_player()  # Regarder vers le joueur

# ATTACK : Exécuter l'attaque après un temps de préparation
func _state_attack(delta: float) -> void:
	velocity = Vector2.ZERO  # S'arrêter pendant l'attaque
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	
	# Continuer de regarder le joueur pendant l'attaque
	if player:
		facing_direction = (player.global_position - global_position).normalized()
	
	# Phase de préparation (windup)
	if windup_timer > 0:
		windup_timer -= delta
		return  # Attendre la fin du windup
	
	# Déclencher l'attaque quand le timer est prêt
	if attack_timer <= 0:
		_trigger_attack()  # Activer la hitbox
		attack_timer = attack_cooldown  # Réinitialiser le cooldown
		
		# Retourner en ENGAGE après la durée d'attaque
		await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
		if state == State.ATTACK and player:
			state = State.ENGAGE

# DEAD : Ne rien faire (l'ennemi sera supprimé)
func _state_dead() -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()

# === SYSTÈMES D'ATTAQUE ET DÉTECTION ===

# Active la hitbox d'attaque pendant un court instant
func _trigger_attack() -> void:
	attack_hitbox.position = facing_direction * 40.0  # Placer la hitbox devant l'ennemi
	hitbox_shape.disabled = false  # Activer la collision
	hitbox_visual.visible = true   # Afficher le visuel
	
	# Désactiver après la durée d'activation
	await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
	if hitbox_shape:
		hitbox_shape.disabled = true
		hitbox_visual.visible = false

# Appelé quand la hitbox touche quelque chose
func _on_hitbox_hit(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(attack_damage)  # Infliger des dégâts au joueur

# Appelé quand un corps entre dans la zone de détection
func _on_player_detected(body: Node2D) -> void:
	if body.is_in_group("player") and state != State.DEAD:
		player = body  # Mémoriser la référence au joueur
		state = State.ENGAGE  # Passer en mode engagement

# === NAVIGATION ET MOUVEMENT ===

# Se déplacer vers une cible en utilisant NavigationAgent2D + séparation
func _navigate_to(target: Vector2) -> void:
	nav_agent.set_target_position(target)  # Définir la destination
	
	if nav_agent.is_navigation_finished():  # Arrivé à destination
		return
	
	# Obtenir le prochain point du chemin calculé
	var next_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_pos)
	var desired = direction * move_speed  # Vélocité désirée vers le chemin
	
	# Ajouter une force de séparation pour éviter les collisions entre ennemis
	var f_sep = Steering.separate(global_position, _get_neighbors(), separation_radius, separation_force)
	
	# Combiner les forces et limiter à la vitesse max
	var final_vel = (desired + f_sep).limit_length(move_speed)
	
	# Mettre à jour la direction vers laquelle l'ennemi regarde
	if final_vel.length() > 0.1:
		facing_direction = final_vel.normalized()
	
	# Envoyer la vélocité au NavigationAgent pour calcul d'évitement
	nav_agent.set_velocity(final_vel)

# Appelé par NavigationAgent2D après calcul de la vélocité sécurisée
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity  # Utiliser la vélocité corrigée
	move_and_slide()  # Appliquer le mouvement

# Retourne les ennemis voisins vivants (pour la séparation)
func _get_neighbors() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(
		func(e): return e != self and is_instance_valid(e) and e.state != State.DEAD
	)

# Oriente l'ennemi vers le joueur
func _face_player() -> void:
	if player:
		facing_direction = (player.global_position - global_position).normalized()

# Vérifie si le joueur est dans la même salle que l'ennemi
func _player_in_same_room() -> bool:
	return (room_number == 1 and player.global_position.x < 2560.0) or \
	       (room_number == 2 and player.global_position.x >= 2560.0)

# Choisit un point de patrouille aléatoire dans la salle
func _pick_patrol_point() -> void:
	var offset := Vector2(randf_range(-150, 150), randf_range(-150, 150))
	patrol_target = global_position + offset
	# Contraindre la position dans les limites de la salle
	patrol_target.x = clamp(patrol_target.x, room_min_x + 100, room_max_x - 100)

# === SYSTÈME DE SANTÉ ET MORT ===

# Inflige des dégâts à l'ennemi
func take_damage(amount: int) -> void:
	if state == State.DEAD:  # Ne pas infliger de dégâts si déjà mort
		return
	
	health -= amount  # Réduire la santé
	_update_health_bar()  # Mettre à jour l'affichage
	
	if health <= 0:
		die()  # Déclencher la mort

# Gère la mort de l'ennemi
func die() -> void:
	state = State.DEAD  # Passer à l'état mort
	hitbox_shape.disabled = true  # Désactiver la hitbox d'attaque
	hitbox_visual.visible = false
	
	EnemyManager.unregister(self)  # Se désenregistrer du manager
	
	# Faire apparaître un objet à ramasser
	var item_scene: PackedScene = load("res://scenes/items/item.tscn")
	var item: Node2D = item_scene.instantiate()
	item.global_position = global_position
	item.item_name = "Butin d'ennemi"
	get_parent().add_child(item)
	
	queue_free()  # Supprimer l'ennemi de la scène

# Met à jour l'affichage de la barre de vie
func _update_health_bar() -> void:
	$HealthBar.max_value = 3
	$HealthBar.value = health
