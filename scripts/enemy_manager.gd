extends Node
# Autoload singleton qui coordonne tous les ennemis du jeu
# Assigne des rôles tactiques (intercepter, flanquer, poursuivre) pour créer un comportement d'encerclement

# === ÉNUMÉRATION DES RÔLES ===
enum Role {
	INTERCEPT,    # Ennemi qui intercepte devant le joueur
	FLANK_LEFT,   # Ennemi qui flanque à gauche
	FLANK_RIGHT,  # Ennemi qui flanque à droite
	CHASE         # Ennemi qui poursuit derrière
}

# === CONSTANTES DE CONFIGURATION ===
const MAX_ATTACKERS := 2           # Nombre maximum d'ennemis pouvant attaquer simultanément
const UPDATE_RATE := 0.5           # Fréquence de réassignation des rôles (en secondes)
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
	
	# === 1. PRÉDICTION DU MOUVEMENT DU JOUEUR ===
	var player_velocity = _player.velocity
	var player_dir = Vector2.RIGHT  # Direction par défaut
	
	# Utiliser la direction du mouvement si le joueur bouge
	if player_velocity.length() > 10:
		player_dir = player_velocity.normalized()
	
	# Prédire où sera le joueur dans PREDICT_TIME secondes
	var future_pos = _player.global_position + player_velocity * PREDICT_TIME
	
	# === 2. DÉTECTION D'ENCERCLEMENT ===
	var is_encircled = _is_player_encircled()
	
	# Activer le mode rush si le joueur est encerclé
	if is_encircled:
		_rush_mode = true
		_rush_cooldown = RUSH_DURATION  # Réinitialiser le cooldown
	
	# Désactiver le mode rush quand le cooldown expire
	if _rush_cooldown <= 0.0:
		_rush_mode = false
	
	# === 3. MODE RUSH : TOUS LES ENNEMIS ATTAQUENT ===
	if _rush_mode:
		for enemy in _enemies:
			_roles[enemy.get_instance_id()] = Role.INTERCEPT  # Tous foncent sur le joueur
			_target_positions[enemy.get_instance_id()] = future_pos  # Cible = position prédite du joueur
			enemy.set_meta("assigned", true)
		print("RUSH MODE ACTIVE - Cooldown: ", "%.1f" % _rush_cooldown, "s")
		return  # Sortir de la fonction, pas besoin d'assigner d'autres rôles
	
	# === 4. MODE NORMAL : ASSIGNATION TACTIQUE DES RÔLES ===
	
	# Calculer les positions cibles pour chaque rôle autour du joueur
	var role_positions = {
		Role.INTERCEPT: future_pos + player_dir * INTERCEPT_DISTANCE,               # Devant le joueur
		Role.FLANK_LEFT: future_pos + player_dir.rotated(-PI / 2.0) * FLANK_DISTANCE,  # À gauche
		Role.FLANK_RIGHT: future_pos + player_dir.rotated(PI / 2.0) * FLANK_DISTANCE,  # À droite
	}
	
	# Réinitialiser les métadonnées d'assignation
	for enemy in _enemies:
		enemy.set_meta("assigned", false)
	
	# Assigner les 3 rôles prioritaires (1 ennemi pour chaque position)
	_assign_best_enemy(Role.INTERCEPT, role_positions[Role.INTERCEPT])
	_assign_best_enemy(Role.FLANK_LEFT, role_positions[Role.FLANK_LEFT])
	_assign_best_enemy(Role.FLANK_RIGHT, role_positions[Role.FLANK_RIGHT])
	
	# Tous les ennemis restants deviennent CHASE (poursuivre derrière)
	for enemy in _enemies:
		if enemy.get_meta("assigned"):  # Ignorer ceux déjà assignés
			continue
		
		_roles[enemy.get_instance_id()] = Role.CHASE
		_target_positions[enemy.get_instance_id()] = future_pos - player_dir * CHASE_DISTANCE  # Derrière le joueur
		enemy.set_meta("assigned", true)

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
	
	# === 3. AJOUTER LES ANGLES DES ENNEMIS ===
	for enemy in _enemies:
		var dir = _player.global_position.direction_to(enemy.global_position)
		var angle = dir.angle()  # Angle entre -PI et +PI
		angles.append(angle)
	
	# Besoin d'au moins 3 points de couverture (ennemis + murs combinés)
	if angles.size() < 3:
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
	# Plus il y a d'ennemis, plus on tolère un grand écart
	# 3 ennemis : max 140° | 4 ennemis : max 160° | 5+ ennemis : max 180°
	var max_acceptable_gap = lerp(PI * 0.78, PI, min((_enemies.size() - 3) / 2.0, 1.0))
	
	# Debug : afficher les informations de détection
	print("Enemies: ", _enemies.size(), " | Walls: ", (angles.size() - _enemies.size()), " | Max gap: ", rad_to_deg(max_gap), "° | Acceptable: ", rad_to_deg(max_acceptable_gap), "° | Encircled: ", max_gap < max_acceptable_gap)
	
	# Encerclé = le plus grand "trou" est plus petit que le seuil acceptable
	return max_gap < max_acceptable_gap

# === ASSIGNATION DU MEILLEUR ENNEMI POUR UN RÔLE ===

func _assign_best_enemy(role: Role, target_pos: Vector2) -> void:
	var best_enemy = null
	var best_score = INF  # Initialiser avec une valeur infinie
	
	# Parcourir tous les ennemis non encore assignés
	for enemy in _enemies:
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
