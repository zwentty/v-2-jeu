# =============================================================================
# enemy.gd
# Script attaché au nœud Enemy (CharacterBody2D)
# Pathfinding avec NavigationAgent2D + système de dégâts par distance.
# =============================================================================

extends CharacterBody2D

# =============================================================================
# PARAMÈTRES EXPORTÉS (modifiables dans l'inspecteur)
# =============================================================================

## Vitesse de déplacement vers le joueur (pixels/seconde)
@export var speed: float = 200.0

## Dégâts infligés au joueur par contact
@export var damage: int = 1

## Délai entre deux dégâts consécutifs (secondes)
@export var damage_cooldown: float = 1.0

## Distance d'arrêt : l'ennemi s'arrête à cette distance du joueur
## (somme des rayons joueur + ennemi + marge de sécurité)
@export var stop_distance: float = 30.0

## Points de vie de l'ennemi
@export var health: int = 3

# =============================================================================
# RÉFÉRENCES
# =============================================================================

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# =============================================================================
# VARIABLES D'ÉTAT
# =============================================================================

# Timer interne pour le cooldown de dégâts
var _cooldown_timer: float = 0.0

# Déterminer la salle d'appartenance (1 ou 2) et les limites de pathfinding
# Salle 1: X < 2560, Salle 2: X >= 2560
var room_number: int = 1
var room_min_x: float = 0.0
var room_max_x: float = 2560.0

# =============================================================================
# _ready()
# Appelée une fois au démarrage, configure le NavigationAgent2D
# =============================================================================
func _ready() -> void:
	# Ajouter l'ennemi au groupe "enemy" pour que le joueur puisse le détecter
	add_to_group("enemy")
	
	# Déterminer la salle d'appartenance basée sur la position X
	if global_position.x < 2560.0:
		room_number = 1
		room_min_x = 0.0
		room_max_x = 2560.0
	else:
		room_number = 2
		room_min_x = 2560.0
		room_max_x = 5120.0
	
	print("Ennemi appartient à la salle %d (X: %.0f - %.0f)" % [room_number, room_min_x, room_max_x])
	
	# Initialiser la barre de vie
	_update_health_bar()
	
	# Configuration du NavigationAgent2D
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = stop_distance
	
	# Configuration de l'avoidance (pour éviter les autres ennemis)
	nav_agent.radius = 30.0  # Taille de la "bulle personnelle" (distance maintenue)
	nav_agent.neighbor_distance = 300.0  # Distance de détection des voisins
	nav_agent.max_neighbors = 10  # Nombre max d'agents à éviter
	nav_agent.max_speed = speed  # Vitesse max pour les calculs d'évitement
	nav_agent.avoidance_enabled = true  # Activer l'évitement
	
	# Connecter le signal velocity_computed pour utiliser la vélocité corrigée
	nav_agent.velocity_computed.connect(_on_velocity_computed)

# =============================================================================
# _physics_process(delta)
# Appelée à chaque frame physique (60 fois/seconde par défaut)
# =============================================================================
func _physics_process(delta: float) -> void:
	# Décompte du cooldown de dégâts
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	# Trouve le joueur dans le groupe "player"
	# (on le cherche chaque frame au lieu de stocker une référence,
	# ça évite les problèmes si le joueur est supprimé/recréé)
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var player := players[0] as CharacterBody2D
	
	# Vérifier que le joueur est dans la même salle que l'ennemi
	# Sinon, arrêter le pathfinding
	var player_in_same_room := (room_number == 1 and player.global_position.x < 2560.0) or \
	                           (room_number == 2 and player.global_position.x >= 2560.0)
	
	if not player_in_same_room:
		# Joueur dans une autre salle : arrêter le mouvement
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	# Met à jour la cible du NavigationAgent à chaque frame
	# pour suivre le joueur en temps réel
	nav_agent.target_position = player.global_position

	# Calcule la distance actuelle entre l'ennemi et le joueur
	var dist := global_position.distance_to(player.global_position)
	
	# Si on est à distance d'arrêt OU que la navigation est terminée,
	# on arrête le déplacement
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
	else:
		# Sinon, on calcule la direction vers le prochain point du chemin
		var next_pos := nav_agent.get_next_path_position()
		var direction := (next_pos - global_position).normalized()
		var desired_velocity := direction * speed
		
		# On envoie la vélocité désirée au NavigationAgent2D
		# Il va calculer une vélocité corrigée pour éviter les autres agents
		# et appeler _on_velocity_computed() avec le résultat
		nav_agent.set_velocity(desired_velocity)

	# Système de dégâts par distance : si l'ennemi est assez proche,
	# il tente d'infliger des dégâts
	if dist <= stop_distance:
		_try_damage(player)

# =============================================================================
# _on_velocity_computed(safe_velocity)
# Callback appelé par NavigationAgent2D avec la vélocité corrigée pour éviter
# les autres agents. C'est ici qu'on applique le mouvement final.
# =============================================================================
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

# =============================================================================
# _try_damage(player)
# Tente d'infliger des dégâts au joueur si le cooldown est écoulé
# =============================================================================
func _try_damage(player: Node) -> void:
	# Si le cooldown n'est pas écoulé, on ne fait rien
	if _cooldown_timer > 0.0:
		return
	
	# Vérifie que le joueur a bien une méthode take_damage()
	if player.has_method("take_damage"):
		player.take_damage(damage)
		_cooldown_timer = damage_cooldown

# =============================================================================
# take_damage(amount)
# Appelée quand l'ennemi reçoit des dégâts (par l'attaque du joueur)
# =============================================================================
func take_damage(amount: int) -> void:
	health -= amount
	print("Ennemi PV : %d" % health)
	
	# Mettre à jour la barre de vie
	_update_health_bar()
	
	# Si les PV tombent à 0 ou moins, l'ennemi meurt
	if health <= 0:
		_die()

# =============================================================================
# _die()
# Appelée quand l'ennemi meurt
# Drop un objet à sa position avant de disparaître
# =============================================================================
func _die() -> void:
	print("Ennemi éliminé !")
	
	# Créer un objet à la position de l'ennemi
	var item_scene: PackedScene = load("res://scenes/items/item.tscn")
	var item: Node2D = item_scene.instantiate()
	item.global_position = global_position
	item.item_name = "Butin d'ennemi"
	
	# Ajouter l'objet à la scène (au même niveau que l'ennemi)
	get_parent().add_child(item)
	
	# Supprimer l'ennemi
	queue_free()

# =============================================================================
# _update_health_bar()
# Met à jour la barre de vie en fonction des PV actuels de l'ennemi
# =============================================================================
func _update_health_bar() -> void:
	$HealthBar.max_value = 3  # health max = 3 (constant)
	$HealthBar.value = health