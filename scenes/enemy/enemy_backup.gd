# =============================================================================
# enemy.gd
# Script attaché au nœud Enemy (CharacterBody2D)
# 
# SYSTÈME PRINCIPAL : State Machine (Machine à États)
# L'ennemi utilise une state machine avec 6 états différents :
# - IDLE (Au repos) : L'ennemi attend immobile avant de patrouiller
# - PATROL (Patrouille) : L'ennemi se déplace vers des points aléatoires
# - CHASE (Poursuite) : L'ennemi poursuit le joueur détecté
# - ORBIT (Orbite) : L'ennemi tourne autour du joueur (NOUVEAU - géré par EnemyManager)
# - ATTACK (Attaque) : L'ennemi se prépare et attaque le joueur proche
# - DEAD (Mort) : L'ennemi est mort et immobile
#
# COORDINATION : EnemyManager (Singleton)
# Le EnemyManager coordonne tous les ennemis pour créer un encerclement intelligent :
# - Assigne un angle d'orbite unique à chaque ennemi (réparti équitablement)
# - Redistribue les angles automatiquement quand un ennemi meurt
# - Limite le nombre d'attaquants simultanés (MAX_SIMULTANEOUS_ATTACKERS = 2)
# - Définit le rayon d'orbite (ORBIT_RADIUS = 110px) et la distance d'engagement (ENGAGE_DISTANCE = 300px)
#
# PATHFINDING : NavigationAgent2D
# Utilise le système de navigation de Godot pour éviter les obstacles
# et les autres ennemis (avoidance activé)
#
# STEERING BEHAVIORS :
# Les ennemis utilisent des comportements de steering (classe Steering) :
# - Seek : Se diriger vers une cible
# - Arrive : Comme Seek mais ralentit en approchant
# - Separate : Repousser les voisins pour éviter le regroupement
# - Wander : Déviation aléatoire pour un mouvement organique
#
# SYSTÈME DE SALLES :
# Le monde est divisé en 2 salles (X < 2560 = Salle 1, X >= 2560 = Salle 2)
# L'ennemi ne poursuit le joueur que s'ils sont dans la même salle
# =============================================================================

extends CharacterBody2D

# =============================================================================
# ÉNUMÉRATION DES ÉTATS
# Cette énumération définit tous les états possibles de l'ennemi
# =============================================================================
enum State {
	IDLE,    # Au repos, attend avant de patrouiller
	PATROL,  # Se déplace vers un point de patrouille aléatoire
	CHASE,   # Poursuit le joueur détecté
	ORBIT,   # Tourne autour du joueur à distance moyenne
	ATTACK,  # Attaque le joueur à portée
	DEAD     # Mort, immobile
}

# =============================================================================
# PARAMÈTRES EXPORTÉS (modifiables dans l'inspecteur Godot)
# Le symbole @export permet de modifier ces valeurs dans l'interface de Godot
# =============================================================================

## Vitesse de déplacement de l'ennemi (pixels par seconde)
## Plus la valeur est élevée, plus l'ennemi se déplace rapidement
@export var move_speed: float = 200.0

## Dégâts infligés au joueur lors d'une attaque réussie
## Le joueur perd ce nombre de points de vie quand touché
@export var attack_damage: int = 1

## Délai entre deux attaques consécutives (secondes)
## Après une attaque, l'ennemi doit attendre ce temps avant d'attaquer à nouveau
@export var attack_cooldown: float = 1.0

## Temps de préparation avant de lancer l'attaque (secondes)
## Donne au joueur le temps de voir l'attaque venir et de réagir
## L'ennemi s'arrête complètement pendant ce temps
@export var attack_windup: float = 0.5

## Distance d'arrêt près du joueur (pixels)
## L'ennemi s'arrête à cette distance du joueur pour ne pas le traverser
@export var stop_distance: float = 30.0

## Points de vie de l'ennemi
## Quand health atteint 0, l'ennemi meurt
@export var health: int = 3

## Rayon de séparation entre ennemis (pixels)
## Distance en dessous de laquelle les ennemis se repoussent
## AUGMENTÉ pour plus d'espacement entre ennemis
@export var separation_radius: float = 70.0

## Force de la séparation
## Plus cette valeur est élevée, plus les ennemis se repoussent fort
## AUGMENTÉE pour maintenir de meilleures distances
@export var separation_force: float = 150.0

## Rayon de ralentissement pour l'orbite (pixels)
## L'ennemi ralentit progressivement en approchant de sa position d'orbite
## AUGMENTÉ pour un ralentissement plus progressif
@export var orbit_slow_radius: float = 80.0

## Durée pendant laquelle la hitbox d'attaque reste active (secondes)
## Constante : ne peut pas être modifiée dans l'inspecteur
const HITBOX_ACTIVE_DURATION: float = 0.25

## Tolérance pour considérer qu'on est arrivé à la position d'orbite
## AUGMENTÉE avec le rayon d'orbite plus grand
const ORBIT_ARRIVAL_TOLERANCE: float = 20.0

## Durée minimale et maximale de l'orbite (secondes)
const ORBIT_DURATION_MIN: float = 2.0
const ORBIT_DURATION_MAX: float = 4.0

# =============================================================================
# RÉFÉRENCES AUX NŒUDS ENFANTS
# @onready signifie que ces variables seront initialisées quand _ready() est appelé
# $ est un raccourci pour get_node() - exemple : $NavigationAgent2D == get_node("NavigationAgent2D")
# =============================================================================

## Agent de navigation pour le pathfinding (évitement des obstacles et ennemis)
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

## Zone de détection du joueur (rayon 400px)
## Quand le joueur entre dedans, l'ennemi passe en mode CHASE
@onready var detection_area: Area2D = $DetectionArea

## Zone de portée d'attaque (rayon 50px)
## Quand le joueur entre dedans, l'ennemi passe en mode ATTACK
@onready var attack_area: Area2D = $AttackArea

## Zone de dégâts de l'attaque (se déplace devant l'ennemi)
## C'est cette zone qui inflige réellement les dégâts au joueur
@onready var attack_hitbox: Area2D = $AttackHitbox

## Forme de collision de la hitbox d'attaque
## Désactivée par défaut, s'active uniquement pendant l'attaque
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

## Visuel de la hitbox (carré jaune semi-transparent)
## Visible uniquement pendant l'attaque pour montrer la zone de danger
@onready var hitbox_visual: Polygon2D = $AttackHitbox/Visual

# =============================================================================
# VARIABLES D'ÉTAT
# Ces variables changent pendant le jeu pour suivre l'état de l'ennemi
# =============================================================================

## État actuel de l'ennemi dans la state machine
## Commence en IDLE (au repos)
var state: State = State.IDLE

## Référence au joueur (null si pas de joueur détecté)
## Stockée quand le joueur entre dans la DetectionArea
var player: Node2D = null

## Direction dans laquelle l'ennemi regarde (vecteur normalisé)
## Utilisée pour orienter la hitbox d'attaque
var facing_direction: Vector2 = Vector2.RIGHT

# --- Variables de patrouille ---

## Position cible de la patrouille
## Choisie aléatoirement dans les limites de la salle
var patrol_target: Vector2 = Vector2.ZERO

## Temps avant de recommencer à patrouiller après être arrivé à destination
var patrol_timer: float = 0.0

## Durée d'attente au repos entre deux patrouilles (secondes)
var patrol_wait: float = 2.5

# --- Variables d'attaque ---

## Timer du cooldown entre deux attaques
## Décompté chaque frame, l'attaque ne peut se déclencher que quand <= 0
var attack_timer: float = 0.0

## Timer de préparation avant l'attaque (windup)
## L'ennemi reste immobile pendant ce temps avant de frapper
var windup_timer: float = 0.0

# --- Variables d'orbite ---

## Timer de durée de l'orbite
## Quand ce timer atteint 0, l'ennemi décide de continuer à orbiter ou de tenter d'attaquer
var orbit_timer: float = 0.0

## Indique si l'ennemi est arrivé à sa position d'orbite
## Utilisé pour stabiliser le comportement une fois en position
var orbit_reached: bool = false

# --- Variables de wander (errance) ---

## Angle de déviation pour le comportement wander
## Évolue progressivement pour créer un mouvement naturel
var wander_angle: float = 0.0

# --- Variables du système de salles ---

## Numéro de la salle d'appartenance de l'ennemi (1 ou 2)
## Déterminé au démarrage en fonction de la position X
var room_number: int = 1

## Limite minimale X de la salle (en pixels)
var room_min_x: float = 0.0

## Limite maximale X de la salle (en pixels)
var room_max_x: float = 2560.0

# =============================================================================
# _ready()
# Fonction appelée UNE SEULE FOIS quand l'ennemi est ajouté à la scène
# Initialise tous les paramètres et connexions nécessaires
# =============================================================================
func _ready() -> void:
	# --- 1. AJOUTER AU GROUPE "enemy" ---
	# Les groupes permettent de retrouver facilement tous les ennemis
	# Le joueur utilise get_tree().get_nodes_in_group("enemy") pour les trouver
	add_to_group("enemy")
	
	# --- 2. DÉTERMINER LA SALLE D'APPARTENANCE ---
	# Le monde est divisé en 2 salles séparées par X = 2560
	# Salle 1 : X entre 0 et 2560
	# Salle 2 : X entre 2560 et 5120
	if global_position.x < 2560.0:
		room_number = 1
		room_min_x = 0.0
		room_max_x = 2560.0
	else:
		room_number = 2
		room_min_x = 2560.0
		room_max_x = 5120.0
	
	print("Ennemi appartient à la salle %d (X: %.0f - %.0f)" % [room_number, room_min_x, room_max_x])
	
	# --- 3. INITIALISER LA BARRE DE VIE ---
	_update_health_bar()
	
	# --- 4. CONFIGURER LE NAVIGATIONAGENT2D ---
	# Le NavigationAgent2D gère le pathfinding (trouver un chemin vers la cible)
	
	# Distance minimale au chemin calculé pour considérer qu'on est "sur" le chemin
	nav_agent.path_desired_distance = 4.0
	
	# Distance à la cible finale pour considérer qu'on est arrivé
	nav_agent.target_desired_distance = stop_distance
	
	# --- Configuration de l'évitement (avoidance) ---
	# Permet aux ennemis de ne pas se superposer
	
	# Rayon de l'agent pour l'évitement (taille de sa "bulle personnelle")
	# Les autres agents essaieront de maintenir au moins cette distance
	nav_agent.radius = 30.0
	
	# Distance à laquelle l'agent détecte les voisins pour les éviter
	nav_agent.neighbor_distance = 300.0
	
	# Nombre maximum de voisins à considérer pour l'évitement
	nav_agent.max_neighbors = 10
	
	# Vitesse maximum pour les calculs d'évitement
	nav_agent.max_speed = move_speed
	
	# Activer le système d'évitement
	nav_agent.avoidance_enabled = true
	
	# Connecter le signal qui reçoit la vélocité calculée par le NavigationAgent
	# Quand nav_agent.set_velocity() est appelé, il calcule une vélocité sûre
	# (évitant les obstacles et autres agents) et appelle _on_velocity_computed()
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# --- 5. S'ENREGISTRER AUPRÈS DU ENEMYMANAGER ---
	# Le manager assigne un angle unique et gère la coordination
	# IMPORTANT : Ceci doit être fait avant de commencer à orbiter
	EnemyManager.register(self)
	
	# --- 6. CONNECTER LES SIGNAUX DE DÉTECTION ---
	# Ces signaux sont émis quand le joueur entre/sort des zones
	
	# DetectionArea : Grande zone (400px) pour détecter le joueur au loin
	detection_area.body_entered.connect(_on_player_detected)
	detection_area.body_exited.connect(_on_player_lost)
	
	# AttackArea : Zone moyenne (50px) pour passer en mode attaque
	attack_area.body_entered.connect(_on_attack_range_entered)
	attack_area.body_exited.connect(_on_attack_range_exited)
	
	# AttackHitbox : Zone de dégâts qui se déplace devant l'ennemi
	attack_hitbox.body_entered.connect(_on_hitbox_hit)
	
	# --- 7. INITIALISER LA HITBOX D'ATTAQUE ---
	# Par défaut, la hitbox est désactivée et invisible
	# Elle ne s'active que pendant l'attaque (0.25 secondes)
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	
	# --- 8. CHOISIR UN PREMIER POINT DE PATROUILLE ---
	# L'ennemi commence en mode IDLE mais prépare déjà son premier point de patrouille
	_pick_patrol_point()

# =============================================================================
# _physics_process(delta)
# Fonction appelée À CHAQUE FRAME PHYSIQUE (60 fois par seconde par défaut)
# C'est la boucle principale de la state machine
# 
# delta : temps écoulé depuis la dernière frame (environ 0.016 secondes à 60 FPS)
# =============================================================================
func _physics_process(delta: float) -> void:
	# Décrémenter le timer d'attaque (cooldown)
	# Quand il atteint 0, une nouvelle attaque peut être lancée
	attack_timer -= delta
	
	# Faire évoluer l'angle de wander pour un mouvement naturel
	wander_angle += randf_range(-0.2, 0.2)
	
	# STATE MACHINE : exécuter le code correspondant à l'état actuel
	# match est l'équivalent d'un switch/case dans d'autres langages
	match state:
		State.IDLE:   _state_idle(delta)    # Au repos
		State.PATROL: _state_patrol(delta)  # En patrouille
		State.CHASE:  _state_chase(delta)   # Poursuite du joueur
		State.ORBIT:  _state_orbit(delta)   # Orbite autour du joueur
		State.ATTACK: _state_attack(delta)  # Attaque du joueur
		State.DEAD:   _state_dead()         # Mort

# =============================================================================
# ÉTATS DE LA STATE MACHINE
# Chaque fonction gère le comportement d'un état spécifique
# =============================================================================

# --- ÉTAT : IDLE (Au repos) ---
# L'ennemi attend immobile avant de recommencer à patrouiller
func _state_idle(delta: float) -> void:
	# Arrêter complètement le mouvement
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)  # Important : dire au NavigationAgent de ne pas bouger
	move_and_slide()
	
	# Décrémenter le timer d'attente
	patrol_timer -= delta
	
	# Quand le timer atteint 0, choisir un nouveau point et passer en PATROL
	if patrol_timer <= 0:
		_pick_patrol_point()
		state = State.PATROL

# --- ÉTAT : PATROL (Patrouille) ---
# L'ennemi se déplace vers un point aléatoire dans sa salle
# UTILISE STEERING : Arrive (ralentit en approchant) + Separation + Wander
func _state_patrol(delta: float) -> void:
	var dist_to_target = global_position.distance_to(patrol_target)
	
	# Si on est arrivé au point de patrouille (distance < 12 pixels)
	if dist_to_target < 12.0:
		# Attendre avant de choisir un nouveau point
		patrol_timer = patrol_wait
		state = State.IDLE
		return
	
	# FORCES DE STEERING COMBINÉES :
	# 1. Arrive : ralentit en approchant du point de patrouille
	var f_arrive = Steering.arrive(global_position, patrol_target, 60.0, move_speed)
	# 2. Separate : évite les autres ennemis
	var f_sep = Steering.separate(global_position, _get_neighbors(), separation_radius, separation_force)
	# 3. Wander : déviation légère pour un mouvement naturel (15% de la vitesse)
	var f_wander = Steering.wander(velocity, wander_angle, 0.2) * move_speed * 0.15
	
	# Combiner toutes les forces
	var final_velocity = f_arrive + f_sep + f_wander
	_apply_steering(final_velocity)

# --- ÉTAT : CHASE (Poursuite) ---
# L'ennemi poursuit le joueur détecté
# UTILISE STEERING : Seek (fort) + Separation + Wander
func _state_chase(delta: float) -> void:
	# Si le joueur a disparu, retourner en patrouille
	if player == null:
		state = State.PATROL
		_pick_patrol_point()
		return
	
	# Vérifier que le joueur est dans la même salle
	# L'ennemi ne peut pas poursuivre le joueur dans une autre salle
	var player_in_same_room := (room_number == 1 and player.global_position.x < 2560.0) or \
	                           (room_number == 2 and player.global_position.x >= 2560.0)
	
	if not player_in_same_room:
		# Le joueur est dans l'autre salle, arrêter la poursuite
		state = State.PATROL
		_pick_patrol_point()
		return
	
	# Calculer la distance au joueur
	var dist = global_position.distance_to(player.global_position)
	
	# Si assez proche, passer en mode ORBIT pour encercler le joueur
	# La distance d'engagement est définie par le EnemyManager (ENGAGE_DISTANCE = 300px)
	# À ce moment, l'ennemi reçoit une position d'orbite unique calculée par le manager
	# Cela permet aux ennemis de se répartir équitablement autour du joueur
	if dist < EnemyManager.ENGAGE_DISTANCE:
		orbit_timer = randf_range(ORBIT_DURATION_MIN, ORBIT_DURATION_MAX)
		orbit_reached = false  # Réinitialiser le flag
		state = State.ORBIT
		return
	
	# FORCES DE STEERING COMBINÉES :
	# 1. Seek : fonce vers le joueur (force principale)
	var f_seek = Steering.seek(global_position, player.global_position) * move_speed
	# 2. Separate : évite les autres ennemis (×1.3 pour bien s'espacer en approche)
	var f_sep = Steering.separate(global_position, _get_neighbors(), separation_radius, separation_force * 1.3)
	# 3. Wander : déviation pour ne pas foncer bêtement (20% de la vitesse)
	var f_wander = Steering.wander(velocity, wander_angle, 0.3) * move_speed * 0.2
	
	# Combiner toutes les forces
	var final_velocity = f_seek + f_sep + f_wander
	_apply_steering(final_velocity)

# --- ÉTAT : ORBIT (Orbite) ---
# L'ennemi tourne autour du joueur à distance moyenne
# Permet l'encerclement naturel du joueur par plusieurs ennemis
# UTILISE STEERING : Arrive vers position assignée + Separation renforcée
func _state_orbit(delta: float) -> void:
	# Si le joueur a disparu, retourner en patrouille
	if player == null:
		state = State.PATROL
		orbit_reached = false
		_pick_patrol_point()
		return
	
	# Décrémenter le timer d'orbite
	orbit_timer -= delta
	
	# Obtenir la position cible sur l'orbite depuis le EnemyManager
	# Le manager calcule un point sur le cercle selon l'angle assigné
	var target_orbit_pos = EnemyManager.get_orbit_position(self, player.global_position)
	
	# Calculer la distance à la position d'orbite cible
	var dist_to_orbit_pos = global_position.distance_to(target_orbit_pos)
	
	# Vérifier si on est arrivé à la position d'orbite
	if dist_to_orbit_pos < ORBIT_ARRIVAL_TOLERANCE:
		orbit_reached = true
	
	# Calculer la distance au joueur
	var dist_to_player = global_position.distance_to(player.global_position)
	
	# Vérifier si on peut attaquer
	# Conditions : proche du joueur, cooldown écoulé, quota d'attaquants non atteint
	if dist_to_player < 50.0 and attack_timer <= 0 and EnemyManager.can_attack(self):
		state = State.ATTACK
		orbit_reached = false
		windup_timer = attack_windup
		return
	
	# Quand le timer atteint 0 et qu'on est en position, décider de la suite
	if orbit_timer <= 0 and orbit_reached:
		_decide_after_orbit()
		return
	
	# FORCES DE STEERING COMBINÉES :
	# 1. Arrive : Se déplace vers la position d'orbite en ralentissant progressivement
	var f_arrive = Steering.arrive(global_position, target_orbit_pos, orbit_slow_radius, move_speed)
	
	# 2. Separate : RENFORCÉE (×2.0) pour bien espacer les ennemis autour du joueur
	#    Plus forte qu'en patrouille/chase pour maintenir la formation circulaire
	var f_sep = Steering.separate(global_position, _get_neighbors(), separation_radius, separation_force * 2.0)
	
	# 3. Wander : FAIBLE (5%) pour donner un mouvement légèrement organique
	#    Seulement quand on est arrivé en position pour éviter de perturber l'approche
	var f_wander = Vector2.ZERO
	if orbit_reached:
		f_wander = Steering.wander(velocity, wander_angle, 0.2) * move_speed * 0.05
	
	# Combiner les forces
	var final_velocity = f_arrive + f_sep + f_wander
	_apply_steering(final_velocity)
	
	# Toujours regarder vers le joueur pendant l'orbite
	_face_player()

# --- ÉTAT : ATTACK (Attaque) ---
# L'ennemi se prépare et attaque le joueur
func _state_attack(delta: float) -> void:
	# IMPORTANT : Arrêter complètement le mouvement pendant l'attaque
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)  # Dire au NavigationAgent de ne pas bouger
	move_and_slide()
	
	# Continuer à regarder vers le joueur pendant l'attaque
	if player:
		facing_direction = (player.global_position - global_position).normalized()
	
	# PHASE 1 : Préparation (windup)
	# L'ennemi reste immobile pendant windup_timer secondes
	if windup_timer > 0:
		windup_timer -= delta
		return  # Ne pas continuer tant que la préparation n'est pas terminée
	
	# PHASE 2 : Lancement de l'attaque
	# Une fois la préparation terminée, attaquer si le cooldown est écoulé
	if attack_timer <= 0:
		_trigger_attack()  # Lancer l'attaque
		attack_timer = attack_cooldown  # Réinitialiser le cooldown
		windup_timer = attack_windup  # Réinitialiser le windup pour la prochaine attaque
		
		# VÉRIFICATION : Le joueur est-il toujours dans la portée d'attaque ?
		# Si le joueur s'est éloigné pendant l'attaque, retourner en CHASE après
		if player:
			var dist := global_position.distance_to(player.global_position)
			if dist > 50.0:  # Rayon de l'AttackArea
				# Attendre la fin de l'animation d'attaque
				await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
				# Vérifier qu'on est toujours en ATTACK (pas mort entre temps)
				if state == State.ATTACK:
					state = State.CHASE

# --- ÉTAT : DEAD (Mort) ---
# L'ennemi est mort et reste immobile
func _state_dead() -> void:
	# S'assurer que l'ennemi est complètement immobile
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()

# =============================================================================
# SYSTÈME D'ATTAQUE AVEC HITBOX
# L'attaque utilise une hitbox qui se déplace devant l'ennemi
# Cette hitbox est visible pendant un court instant (0.25 secondes)
# =============================================================================

# --- Déclencher une attaque ---
# Positionne, active et anime la hitbox d'attaque
func _trigger_attack() -> void:
	# ÉTAPE 1 : Positionner la hitbox devant l'ennemi
	# facing_direction indique où l'ennemi regarde
	# On multiplie par 40 pixels pour placer la hitbox à 40px devant l'ennemi
	attack_hitbox.position = facing_direction * 40.0
	
	# ÉTAPE 2 : Activer la hitbox
	# Activer la collision pour qu'elle puisse toucher le joueur
	hitbox_shape.disabled = false
	# Rendre visible le carré jaune pour montrer la zone d'attaque
	hitbox_visual.visible = true
	
	# ÉTAPE 3 : Désactiver après HITBOX_ACTIVE_DURATION secondes
	# await = attend que le timer soit terminé avant de continuer
	await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
	
	# IMPORTANT : Vérifier que l'ennemi n'est pas mort pendant l'attente
	if hitbox_shape:  # Si hitbox_shape existe encore (pas queue_free())
		hitbox_shape.disabled = true  # Désactiver la collision
		hitbox_visual.visible = false  # Cacher le visuel

# --- Callback quand la hitbox touche quelque chose ---
# Cette fonction est appelée automatiquement par le signal body_entered de AttackHitbox
func _on_hitbox_hit(body: Node2D) -> void:
	# Vérifier que c'est bien le joueur (et pas un mur ou autre chose)
	# ET que le joueur a une méthode take_damage (pour infliger des dégâts)
	if body.is_in_group("player") and body.has_method("take_damage"):
		# Infliger les dégâts au joueur
		body.take_damage(attack_damage)

# =============================================================================
# SIGNAUX DE DÉTECTION
# Ces fonctions sont appelées automatiquement quand le joueur entre/sort des zones
# Elles gèrent les transitions d'états de la state machine
# =============================================================================

# --- Joueur détecté dans la DetectionArea (rayon 400px) ---
# Déclenche la poursuite du joueur
func _on_player_detected(body: Node2D) -> void:
	# Vérifier que c'est bien le joueur ET que l'ennemi n'est pas mort
	if body.is_in_group("player") and state != State.DEAD:
		player = body  # Stocker la référence au joueur
		state = State.CHASE  # Passer en mode poursuite

# --- Joueur sorti de la DetectionArea ---
# Note : actuellement ne fait rien, mais pourrait être utilisé pour arrêter la poursuite
func _on_player_lost(body: Node2D) -> void:
	pass  # Vide pour l'instant

# --- Joueur entré dans la AttackArea (rayon 50px) ---
# Déclenche l'attaque SEULEMENT si l'ennemi n'est pas déjà en ORBIT
# Si en ORBIT, l'ennemi décide lui-même quand attaquer
func _on_attack_range_entered(body: Node2D) -> void:
	# Vérifier que c'est bien le joueur ET que l'ennemi n'est pas mort
	if body.is_in_group("player") and state != State.DEAD:
		# NE PAS interrompre l'orbite - laisser l'ennemi décider quand attaquer
		if state == State.ORBIT:
			return
		
		state = State.ATTACK  # Passer en mode attaque
		windup_timer = attack_windup  # Initialiser le temps de préparation

# --- Joueur sorti de la AttackArea ---
# L'ennemi retourne en orbite, SAUF si une attaque est en cours
func _on_attack_range_exited(body: Node2D) -> void:
	if body.is_in_group("player") and player != null and state != State.DEAD:
		# PROTECTION : Ne pas annuler l'attaque si elle est déjà en préparation ou en cours
		# Cela empêche le joueur d'annuler l'attaque en passant rapidement à côté de l'ennemi
		if state == State.ATTACK and (windup_timer > 0 or attack_timer > (attack_cooldown - HITBOX_ACTIVE_DURATION)):
			return  # L'attaque continue même si le joueur sort de la zone
		
		# Sinon, retourner en ORBIT pour continuer à tourner autour du joueur
		# (sauf si déjà en ORBIT, dans ce cas on reste en ORBIT)
		if state != State.ORBIT:
			state = State.ORBIT
			orbit_timer = randf_range(ORBIT_DURATION_MIN, ORBIT_DURATION_MAX)

# =============================================================================
# STEERING - APPLICATION DES FORCES DE MOUVEMENT
# Ces fonctions appliquent les forces de steering calculées
# =============================================================================

# --- Appliquer une force de steering ---
# Prend la vélocité désirée (combinaison de forces), la limite à move_speed,
# puis demande au NavigationAgent de calculer une vélocité sûre
func _apply_steering(desired: Vector2) -> void:
	# Limiter la vitesse maximale
	var clamped = desired.limit_length(move_speed)
	# Mettre à jour facing_direction pour l'orientation
	if clamped.length() > 0.1:
		facing_direction = clamped.normalized()
	# Définir la cible du NavigationAgent légèrement devant l'ennemi
	# Cela permet au NavigationAgent d'éviter les obstacles sur le trajet
	nav_agent.set_target_position(global_position + clamped)
	# Demander au NavigationAgent de calculer une vélocité sûre
	nav_agent.set_velocity(clamped)

# --- Callback de vélocité calculée ---
# Cette fonction est appelée automatiquement par le NavigationAgent2D
# après avoir appelé nav_agent.set_velocity()
# 
# Le NavigationAgent calcule une "vélocité sûre" qui évite les obstacles
# On l'applique directement à l'ennemi
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity  # Appliquer la vélocité calculée
	move_and_slide()  # Déplacer l'ennemi en tenant compte des collisions

# =============================================================================
# UTILITAIRES
# Fonctions d'aide diverses
# =============================================================================

# --- Obtenir la liste des ennemis voisins ---
# Retourne un Array de tous les autres ennemis vivants
# Utilisé pour le comportement Separate (éviter les autres ennemis)
func _get_neighbors() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(
		func(e): return e != self and is_instance_valid(e) and e.state != State.DEAD
	)

# --- Regarder vers le joueur ---
# Met à jour facing_direction pour pointer vers le joueur
func _face_player() -> void:
	if player:
		facing_direction = (player.global_position - global_position).normalized()

# --- Décider de l'action après l'orbite ---
# Appelée quand orbit_timer atteint 0 ET que l'ennemi est en position
# 60% de chance de foncer attaquer, 40% de continuer à orbiter
func _decide_after_orbit() -> void:
	# Vérifier si on peut attaquer (quota non atteint)
	if randf() < 0.6 and EnemyManager.can_attack(self):
		# Foncer vers le joueur pour tenter une attaque
		state = State.CHASE
		orbit_reached = false
	else:
		# Continuer à orbiter, réinitialiser le timer
		orbit_timer = randf_range(ORBIT_DURATION_MIN, ORBIT_DURATION_MAX)

# --- Choisir un nouveau point de patrouille aléatoire ---
func _pick_patrol_point() -> void:
	# Générer un décalage aléatoire entre -150 et +150 pixels en X et Y
	var offset := Vector2(randf_range(-150, 150), randf_range(-150, 150))
	patrol_target = global_position + offset
	
	# IMPORTANT : S'assurer que le point reste dans les limites de la salle
	# On laisse une marge de 100 pixels des bords
	patrol_target.x = clamp(patrol_target.x, room_min_x + 100, room_max_x - 100)

# =============================================================================
# SYSTÈME DE DÉGÂTS ET MORT
# =============================================================================

# --- Recevoir des dégâts ---
# Fonction publique appelée par le joueur quand il attaque l'ennemi
func take_damage(amount: int) -> void:
	# Si l'ennemi est déjà mort, ignorer les dégâts
	if state == State.DEAD:
		return
	
	# Soustraire les dégâts des points de vie
	health -= amount
	print("Ennemi PV : %d" % health)
	
	# Mettre à jour la barre de vie visuelle
	_update_health_bar()
	
	# Si les PV atteignent 0 ou moins, l'ennemi meurt
	if health <= 0:
		die()

# --- Mourir ---
# Gère la mort de l'ennemi
func die() -> void:
	# Passer en état DEAD
	state = State.DEAD
	
	# Désactiver complètement la hitbox d'attaque et son visuel
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	
	print("Ennemi éliminé !")
	
	# SE DÉSENREGISTRER DU ENEMYMANAGER
	# Important : permet au manager de redistribuer les angles
	EnemyManager.unregister(self)
	
	# DROP D'ITEM : Créer un objet ramassable à la position de l'ennemi
	
	# Charger la scène de l'item
	var item_scene: PackedScene = load("res://scenes/items/item.tscn")
	# Instancier (créer une copie) de l'item
	var item: Node2D = item_scene.instantiate()
	# Placer l'item à la position de l'ennemi
	item.global_position = global_position
	# Définir le nom de l'item
	item.item_name = "Butin d'ennemi"
	
	# Ajouter l'item à la scène (au même niveau que l'ennemi dans l'arbre de nœuds)
	get_parent().add_child(item)
	
	# Supprimer l'ennemi de la scène
	# queue_free() supprime le nœud à la fin de la frame
	queue_free()

# --- Mettre à jour la barre de vie ---
# Fonction interne pour synchroniser la ProgressBar avec les PV actuels
func _update_health_bar() -> void:
	$HealthBar.max_value = 3  # Maximum = 3 PV (constante)
	$HealthBar.value = health  # Valeur actuelle = PV restants