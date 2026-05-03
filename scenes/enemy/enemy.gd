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

# =============================================================================
# _ready()
# Appelée une fois au démarrage, configure le NavigationAgent2D
# =============================================================================
func _ready() -> void:
	# Ajouter l'ennemi au groupe "enemy" pour que le joueur puisse le détecter
	add_to_group("enemy")
	
	# Initialiser la barre de vie
	_update_health_bar()
	
	# path_desired_distance : distance à laquelle un point intermédiaire
	# du chemin est considéré comme "atteint" (en pixels).
	nav_agent.path_desired_distance = 4.0
	
	# target_desired_distance : distance à laquelle la cible finale est
	# considérée comme "atteinte". On met stop_distance ici pour que
	# l'ennemi s'arrête naturellement à bonne distance du joueur.
	nav_agent.target_desired_distance = stop_distance

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
	
	# Met à jour la cible du NavigationAgent à chaque frame
	# pour suivre le joueur en temps réel
	nav_agent.target_position = player.global_position

	# Calcule la distance actuelle entre l'ennemi et le joueur
	var dist := global_position.distance_to(player.global_position)
	
	# Si on est à distance d'arrêt OU que la navigation est terminée,
	# on arrête le déplacement
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
	else:
		# Sinon, on avance vers le prochain point du chemin
		var next_pos := nav_agent.get_next_path_position()
		var direction := (next_pos - global_position).normalized()
		velocity = direction * speed

	move_and_slide()

	# Système de dégâts par distance : si l'ennemi est assez proche,
	# il tente d'infliger des dégâts
	if dist <= stop_distance:
		_try_damage(player)

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
# Charge l'écran de victoire
# =============================================================================
func _die() -> void:
	print("Ennemi éliminé !")
	get_tree().change_scene_to_file("res://scenes/menus/victory.tscn")

# =============================================================================
# _update_health_bar()
# Met à jour la barre de vie en fonction des PV actuels de l'ennemi
# =============================================================================
func _update_health_bar() -> void:
	$HealthBar.max_value = 3  # health max = 3 (constant)
	$HealthBar.value = health