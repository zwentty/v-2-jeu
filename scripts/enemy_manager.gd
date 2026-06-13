extends Node
# Autoload singleton qui coordonne tous les ennemis du jeu
# Assigne des rôles tactiques (intercepter, flanquer, poursuivre) pour créer un comportement d'encerclement

# === ÉNUMÉRATION DES RÔLES ===
enum Role {
	INTERCEPT,      # Ennemi qui intercepte devant le joueur
	FLANK_LEFT,     # Ennemi qui flanque à gauche
	FLANK_RIGHT,    # Ennemi qui flanque à droite
	CHASE,          # Ennemi qui poursuit derrière
	SURROUND_LEFT,  # Triangulation : position gauche
	SURROUND_RIGHT, # Triangulation : position droite
	SURROUND_BACK   # Triangulation : position arrière
}

# === CONSTANTES DE CONFIGURATION ===
const MAX_ATTACKERS := 2           # Nombre maximum d'ennemis pouvant attaquer simultanément
const UPDATE_RATE := 0.2           # Fréquence de réassignation des rôles (en secondes)
const PREDICT_TIME := 0.8          # Temps de prédiction du mouvement du joueur (en secondes)
const INTERCEPT_DISTANCE := 330.0  # Distance de la position d'interception devant le joueur
const FLANK_DISTANCE := 270.0      # Distance des positions de flanc (gauche/droite)
const CHASE_DISTANCE := 230.0      # Distance de la position de poursuite derrière le joueur
const RUSH_DURATION := 2.0         # Durée du mode rush après déclenchement (en secondes)

# === VARIABLES D'ÉTAT ===
var _enemies: Array[Node] = []           # Liste de tous les ennemis enregistrés
var _roles: Dictionary = {}              # Dictionnaire : instance_id → Role assigné
var _target_positions: Dictionary = {}   # Dictionnaire : instance_id → Vector2 position cible
var _player: Node2D = null               # Référence au joueur
var _timer: float = 0.0                  # Timer pour la réassignation périodique des rôles
var _rush_mode: bool = false             # Mode rush actif (tous les ennemis attaquent)
var _rush_cooldown: float = 0.0          # Temps restant avant désactivation du mode rush

# === FONCTIONS PUBLIQUES (API pour les ennemis) ===

# Enregistre un ennemi dans le système de coordination
func register(enemy: Node) -> void:
	if enemy in _enemies:  # Empêcher les doublons
		return
	_enemies.append(enemy)
	enemy.set_meta("assigned", false)  # Métadonnée pour tracking de l'assignation

# Désenregistre un ennemi (appelé quand il meurt)
func unregister(enemy: Node) -> void:
	_enemies.erase(enemy)
	_roles.erase(enemy.get_instance_id())          # Nettoyer le rôle assigné
	_target_positions.erase(enemy.get_instance_id())  # Nettoyer la position cible

# Retourne le rôle actuellement assigné à un ennemi
func get_role(enemy: Node) -> Role:
	return _roles.get(enemy.get_instance_id(), Role.CHASE)  # CHASE par défaut

# Retourne la position cible vers laquelle un ennemi doit se diriger
func get_target_position(enemy: Node) -> Vector2:
	return _target_positions.get(enemy.get_instance_id(), _player.global_position if _player else Vector2.ZERO)

# Vérifie si un ennemi peut attaquer (limite le nombre d'attaquants simultanés)
func can_attack(_enemy: Node) -> bool:
	var count := 0
	for e in _enemies:
		if is_instance_valid(e) and e.state == e.State.ATTACK:  # Compter les ennemis en état ATTACK
			count += 1
	return count < MAX_ATTACKERS  # Autoriser si en dessous de la limite

# === BOUCLE PRINCIPALE ===

func _process(delta: float) -> void:
	_find_player()  # S'assurer qu'on a une référence au joueur
	if _player == null:
		return
	_cleanup()  # Nettoyer les ennemis morts/invalides
	
	# Décrémenter le cooldown du mode rush
	if _rush_cooldown > 0.0:
		_rush_cooldown -= delta
	
	# Réassigner les rôles périodiquement (tous les UPDATE_RATE secondes)
	_timer += delta
	if _timer >= UPDATE_RATE:
		_timer = 0.0
		_reassign_roles()

# Trouve et stocke la référence au joueur
func _find_player() -> void:
	if _player != null and is_instance_valid(_player):  # Garder la référence si valide
		return
	var players = get_tree().get_nodes_in_group("player")
	_player = players[0] if players.size() > 0 else null

# Nettoie la liste des ennemis en retirant ceux qui sont morts ou invalides
func _cleanup() -> void:
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and e.state != e.State.DEAD)

# === LOGIQUE DE RÉASSIGNATION DES RÔLES ===

func _reassign_roles() -> void:
	if _enemies.size() == 0 or _player == null:
		return
	
	# Prédire la position future du joueur
	var player_velocity = _player.velocity
	var future_pos = _player.global_position + player_velocity * PREDICT_TIME
	
	# Calculer la direction de référence depuis la position CHASE vers le joueur
	# Utilise la vélocité pour estimer où serait le CHASE, sinon une position par défaut
	var chase_reference_pos: Vector2
	if player_velocity.length() > 10:
		var vel_dir = player_velocity.normalized()
		chase_reference_pos = future_pos - vel_dir * CHASE_DISTANCE
	else:
		# Si le joueur est immobile, utiliser une position de référence derrière lui
		chase_reference_pos = future_pos - Vector2.RIGHT * CHASE_DISTANCE
	
	# Direction de référence : depuis la position CHASE théorique vers le joueur
	var player_dir = chase_reference_pos.direction_to(future_pos)
	
	# Obtenir la liste des ennemis activement engagés
	var engaged = _get_engaged_enemies()
	
	# Gérer le mode rush (encerclement détecté)
	_update_rush_mode()
	if _rush_mode:
		_apply_rush_strategy(engaged, future_pos)
		return
	
	# Appliquer la stratégie tactique selon le nombre d'ennemis
	_reset_assignments()
	match engaged.size():
		0, 1, 2:
			_apply_direct_pursuit(engaged, future_pos)
		3:
			_apply_triangle_formation(engaged, future_pos, player_dir)
		_:
			_apply_advanced_tactics(engaged, future_pos, player_dir)

# Retourne les ennemis qui poursuivent activement le joueur
func _get_engaged_enemies() -> Array[Node]:
	var engaged: Array[Node] = []
	for enemy in _enemies:
		if enemy.state == enemy.State.ENGAGE or enemy.state == enemy.State.ATTACK:
			engaged.append(enemy)
	return engaged

# Met à jour le mode rush selon la détection d'encerclement
func _update_rush_mode() -> void:
	if _is_player_encircled():
		_rush_mode = true
		_rush_cooldown = RUSH_DURATION
	elif _rush_cooldown <= 0.0:
		_rush_mode = false

# Réinitialise les métadonnées d'assignation
func _reset_assignments() -> void:
	for enemy in _enemies:
		enemy.set_meta("assigned", false)

# STRATÉGIE RUSH : Tous les ennemis attaquent directement
func _apply_rush_strategy(engaged: Array[Node], target_pos: Vector2) -> void:
	for enemy in engaged:
		_roles[enemy.get_instance_id()] = Role.INTERCEPT
		_target_positions[enemy.get_instance_id()] = target_pos
		enemy.set_meta("assigned", true)
	print("RUSH MODE ACTIVE - Cooldown: %.1fs" % _rush_cooldown)

# STRATÉGIE 1-2 ENNEMIS : Poursuite directe simple
func _apply_direct_pursuit(engaged: Array[Node], target_pos: Vector2) -> void:
	for enemy in engaged:
		_roles[enemy.get_instance_id()] = Role.INTERCEPT
		_target_positions[enemy.get_instance_id()] = target_pos
		enemy.set_meta("assigned", true)

# STRATÉGIE 3 ENNEMIS : Triangulation autour du joueur
func _apply_triangle_formation(engaged: Array[Node], target_pos: Vector2, player_dir: Vector2) -> void:
	# 1. Assigner l'ennemi qui poursuit par derrière (CHASE)
	var chase_pos = target_pos - player_dir * CHASE_DISTANCE
	var chase_enemy = _find_nearest_unassigned(engaged, chase_pos)
	
	if chase_enemy:
		_roles[chase_enemy.get_instance_id()] = Role.SURROUND_BACK
		_target_positions[chase_enemy.get_instance_id()] = chase_pos
		chase_enemy.set_meta("assigned", true)
		
		# 2. Calculer la direction entre le joueur et l'ennemi CHASE
		var chase_to_player = chase_enemy.global_position.direction_to(target_pos)
		
		# 3. Positionner les deux autres ennemis à gauche et droite pour intercepter (120° au lieu de 90°)
		var positions = {
			Role.SURROUND_LEFT: target_pos + chase_to_player.rotated(-2.0 * PI / 3.0) * FLANK_DISTANCE,   # 120° à gauche
			Role.SURROUND_RIGHT: target_pos + chase_to_player.rotated(2.0 * PI / 3.0) * FLANK_DISTANCE,   # 120° à droite
		}
		
		for role in [Role.SURROUND_LEFT, Role.SURROUND_RIGHT]:
			_assign_best_enemy_from_list(role, positions[role], engaged)

# STRATÉGIE 4+ ENNEMIS : Tactiques avancées avec rôles fixes
func _apply_advanced_tactics(engaged: Array[Node], target_pos: Vector2, player_dir: Vector2) -> void:
	# Positions tactiques : devant, gauche, droite
	var positions = {
		Role.INTERCEPT: target_pos + player_dir * INTERCEPT_DISTANCE,
		Role.FLANK_LEFT: target_pos + player_dir.rotated(-PI / 2.0) * FLANK_DISTANCE,
		Role.FLANK_RIGHT: target_pos + player_dir.rotated(PI / 2.0) * FLANK_DISTANCE,
	}
	
	# Assigner les positions prioritaires
	for role in [Role.INTERCEPT, Role.FLANK_LEFT, Role.FLANK_RIGHT]:
		_assign_best_enemy_from_list(role, positions[role], engaged)
	
	# Les ennemis restants vont derrière
	for enemy in engaged:
		if not enemy.get_meta("assigned"):
			_roles[enemy.get_instance_id()] = Role.CHASE
			_target_positions[enemy.get_instance_id()] = target_pos - player_dir * CHASE_DISTANCE
			enemy.set_meta("assigned", true)

# Trouve l'ennemi non assigné le plus proche d'une position
func _find_nearest_unassigned(enemies: Array[Node], target: Vector2) -> Node:
	var best_enemy = null
	var best_dist = INF
	for enemy in enemies:
		if enemy.get_meta("assigned"):
			continue
		var dist = enemy.global_position.distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best_enemy = enemy
	return best_enemy

# === DÉTECTION D'ENCERCLEMENT PAR COUVERTURE ANGULAIRE ===

func _is_player_encircled() -> bool:
	# Nécessite au moins 3 ennemis pour considérer un encerclement
	if _enemies.size() < 3 or _player == null:
		return false
	
	# Liste des angles de couverture (ennemis + murs)
	var angles: Array[float] = []
	
	# === 1. DÉTECTER LES MURS PROCHES DU JOUEUR ===
	var space_state = _player.get_world_2d().direct_space_state
	var wall_detection_distance = 60.0  # Le joueur doit être très proche du mur (collé)
	var check_directions = 4  # Vérifier 4 directions autour du joueur (tous les 90°)
	var wall_hits: Array[bool] = []  # Stocke si chaque direction touche un mur
	
	# Lancer des raycasts dans toutes les directions
	for i in range(check_directions):
		var angle = (TAU / check_directions) * i  # TAU = 2*PI = 360°
		var direction = Vector2.RIGHT.rotated(angle)
		
		# Créer un raycast depuis le joueur vers la direction
		var query = PhysicsRayQueryParameters2D.create(
			_player.global_position,
			_player.global_position + direction * wall_detection_distance
		)
		query.collision_mask = 2  # Layer 2 = Murs
		
		# Tester la collision
		var result = space_state.intersect_ray(query)
		wall_hits.append(result.size() > 0)  # true si un mur est touché
	
	# === 2. REGROUPER LES SECTIONS DE MUR CONTINUES ===
	# Un mur droit = plusieurs raycasts touchent → on ne veut qu'UN angle pour tout le mur
	var in_wall_section = false
	for i in range(check_directions):
		var has_wall = wall_hits[i]
		var prev_has_wall = wall_hits[(i - 1 + check_directions) % check_directions]
		
		# Début d'une nouvelle section de mur (transition non-mur → mur)
		if has_wall and not prev_has_wall:
			var angle = (TAU / check_directions) * i
			angles.append(angle)  # Ajouter l'angle de début de section
			in_wall_section = true
		elif not has_wall:
			in_wall_section = false  # Fin de la section de mur
	
	# === 3. AJOUTER LES ANGLES DES ENNEMIS ENGAGÉS ===
	# Ne compter QUE les ennemis qui poursuivent activement le joueur
	var engaged_enemies = 0
	for enemy in _enemies:
		# Ignorer les ennemis en IDLE ou PATROL (autre pièce ou non engagés)
		if enemy.state != enemy.State.ENGAGE and enemy.state != enemy.State.ATTACK:
			continue
		
		var dir = _player.global_position.direction_to(enemy.global_position)
		var angle = dir.angle()  # Angle entre -PI et +PI
		angles.append(angle)
		engaged_enemies += 1
	
	# Besoin d'au moins 3 ennemis ENGAGÉS + murs pour considérer un encerclement
	if engaged_enemies < 3:
		return false
	
	# === 4. CALCULER LE PLUS GRAND ÉCART ANGULAIRE ===
	angles.sort()  # Trier les angles de -PI à +PI
	
	var max_gap = 0.0
	for i in angles.size():
		var next_i = (i + 1) % angles.size()  # Index suivant (boucle au début)
		var gap = angles[next_i] - angles[i]
		
		# Cas spécial : écart entre le dernier angle et le premier (autour de 2*PI)
		if next_i == 0:
			gap += TAU  # Ajouter 360° pour gérer la boucle
		
		max_gap = max(max_gap, gap)  # Garder le plus grand écart
	
	# === 5. DÉTERMINER SI LE JOUEUR EST ENCERCLÉ ===
	# Seuil uniforme de 180° pour tous les cas (déclenche facilement le rush)
	var max_acceptable_gap = PI  # 180°
	
	# Debug : afficher les informations de détection
	print("Engaged enemies: ", engaged_enemies, " | Walls: ", (angles.size() - engaged_enemies), " | Max gap: ", rad_to_deg(max_gap), "° | Acceptable: ", rad_to_deg(max_acceptable_gap), "° | Encircled: ", max_gap < max_acceptable_gap)
	
	# Encerclé = le plus grand "trou" est plus petit que le seuil acceptable
	return max_gap < max_acceptable_gap

# Assigne le meilleur ennemi pour un rôle parmi une liste spécifique
func _assign_best_enemy_from_list(role: Role, target_pos: Vector2, enemy_list: Array[Node]) -> void:
	var best_enemy = null
	var best_score = INF  # Initialiser avec une valeur infinie
	
	# Parcourir seulement les ennemis de la liste fournie
	for enemy in enemy_list:
		if enemy.get_meta("assigned"):  # Ignorer les ennemis déjà assignés
			continue
		
		# Calculer la distance entre l'ennemi et la position cible du rôle
		var dist = enemy.global_position.distance_to(target_pos)
		
		# Bonus de stabilité : réduire la distance si l'ennemi garde son rôle actuel
		# Évite les réassignations constantes (churn)
		if _roles.get(enemy.get_instance_id(), -1) == role:
			dist -= 50.0  # Bonus de 50 pixels
		
		# Garder l'ennemi avec le meilleur score (distance la plus courte)
		if dist < best_score:
			best_score = dist
			best_enemy = enemy
	
	# Si aucun ennemi disponible, ne rien faire
	if best_enemy == null:
		return
	
	# Assigner le rôle et la position cible à l'ennemi sélectionné
	_roles[best_enemy.get_instance_id()] = role
	_target_positions[best_enemy.get_instance_id()] = target_pos
	best_enemy.set_meta("assigned", true)  # Marquer comme assigné
