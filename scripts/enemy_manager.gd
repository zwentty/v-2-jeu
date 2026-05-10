extends Node

enum Role { INTERCEPT, FLANK_LEFT, FLANK_RIGHT, CHASE }

const MAX_ATTACKERS := 2
const UPDATE_RATE := 0.5
const PREDICT_TIME := 0.8
const INTERCEPT_DISTANCE := 330.0
const FLANK_DISTANCE := 270.0
const CHASE_DISTANCE := 230.0
const ENCIRCLE_ZONE_RATIO := 0.75
const RUSH_DURATION := 2.0

var _enemies: Array[Node] = []
var _roles: Dictionary = {}
var _target_positions: Dictionary = {}
var _player: Node2D = null
var _timer: float = 0.0
var _rush_mode: bool = false
var _rush_cooldown: float = 0.0

func register(enemy: Node) -> void:
	if enemy in _enemies:
		return
	_enemies.append(enemy)
	enemy.set_meta("assigned", false)

func unregister(enemy: Node) -> void:
	_enemies.erase(enemy)
	_roles.erase(enemy.get_instance_id())
	_target_positions.erase(enemy.get_instance_id())

func get_role(enemy: Node) -> Role:
	return _roles.get(enemy.get_instance_id(), Role.CHASE)

func get_target_position(enemy: Node) -> Vector2:
	return _target_positions.get(enemy.get_instance_id(), _player.global_position if _player else Vector2.ZERO)

func can_attack(_enemy: Node) -> bool:
	var count := 0
	for e in _enemies:
		if is_instance_valid(e) and e.state == e.State.ATTACK:
			count += 1
	return count < MAX_ATTACKERS

func _process(delta: float) -> void:
	_find_player()
	if _player == null:
		return
	_cleanup()
	
	# Décrémenter le cooldown du mode rush
	if _rush_cooldown > 0.0:
		_rush_cooldown -= delta
	
	_timer += delta
	if _timer >= UPDATE_RATE:
		_timer = 0.0
		_reassign_roles()

func _find_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players = get_tree().get_nodes_in_group("player")
	_player = players[0] if players.size() > 0 else null

func _cleanup() -> void:
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and e.state != e.State.DEAD)

func _reassign_roles() -> void:
	if _enemies.size() == 0 or _player == null:
		return
	
	# Prédiction de la position future du joueur
	var player_velocity = _player.velocity
	var player_dir = Vector2.RIGHT
	
	if player_velocity.length() > 10:
		player_dir = player_velocity.normalized()
	
	var future_pos = _player.global_position + player_velocity * PREDICT_TIME
	
	# Vérifier si le joueur est encerclé
	var is_encircled = _is_player_encircled()
	
	# Activer le mode rush si encerclé
	if is_encircled:
		_rush_mode = true
		_rush_cooldown = RUSH_DURATION
	
	# Désactiver le mode rush si le cooldown est écoulé
	if _rush_cooldown <= 0.0:
		_rush_mode = false
	
	# Mode rush : tous les ennemis foncent sur le joueur
	if _rush_mode:
		for enemy in _enemies:
			_roles[enemy.get_instance_id()] = Role.INTERCEPT
			_target_positions[enemy.get_instance_id()] = future_pos
			enemy.set_meta("assigned", true)
		print("RUSH MODE ACTIVE - Cooldown: ", "%.1f" % _rush_cooldown, "s")
		return
	
	# Positions cibles pour chaque rôle
	var role_positions = {
		Role.INTERCEPT: future_pos + player_dir * INTERCEPT_DISTANCE,
		Role.FLANK_LEFT: future_pos + player_dir.rotated(-PI / 2.0) * FLANK_DISTANCE,
		Role.FLANK_RIGHT: future_pos + player_dir.rotated(PI / 2.0) * FLANK_DISTANCE,
	}
	
	# Reset des assignations
	for enemy in _enemies:
		enemy.set_meta("assigned", false)
	
	# Assigner les rôles prioritaires
	_assign_best_enemy(Role.INTERCEPT, role_positions[Role.INTERCEPT])
	_assign_best_enemy(Role.FLANK_LEFT, role_positions[Role.FLANK_LEFT])
	_assign_best_enemy(Role.FLANK_RIGHT, role_positions[Role.FLANK_RIGHT])
	
	# Le reste = CHASE (derrière le joueur)
	for enemy in _enemies:
		if enemy.get_meta("assigned"):
			continue
		
		_roles[enemy.get_instance_id()] = Role.CHASE
		_target_positions[enemy.get_instance_id()] = future_pos - player_dir * CHASE_DISTANCE
		enemy.set_meta("assigned", true)

func _is_player_encircled() -> bool:
	if _enemies.size() < 3 or _player == null:
		return false
	
	# Vérifier la couverture angulaire autour du joueur
	var angles: Array[float] = []
	
	for enemy in _enemies:
		var dir = _player.global_position.direction_to(enemy.global_position)
		var angle = dir.angle()
		angles.append(angle)
	
	if angles.size() < 3:
		return false
	
	angles.sort()
	
	# Calculer le plus grand écart entre les angles
	var max_gap = 0.0
	for i in angles.size():
		var next_i = (i + 1) % angles.size()
		var gap = angles[next_i] - angles[i]
		if next_i == 0:  # Dernier vers premier (boucle autour de TAU)
			gap += TAU
		max_gap = max(max_gap, gap)
	
	# Écart maximum acceptable dépend du nombre d'ennemis
	# Plus il y a d'ennemis, plus on tolère un grand écart
	# 3 ennemis: 140° | 4 ennemis: 160° | 5+ ennemis: 180°
	var max_acceptable_gap = lerp(PI * 0.78, PI, min((_enemies.size() - 3) / 2.0, 1.0))
	
	print("Enemies: ", _enemies.size(), " | Max gap: ", rad_to_deg(max_gap), "° | Acceptable: ", rad_to_deg(max_acceptable_gap), "° | Encircled: ", max_gap < max_acceptable_gap)
	return max_gap < max_acceptable_gap

func _assign_best_enemy(role: Role, target_pos: Vector2) -> void:
	var best_enemy = null
	var best_score = INF
	
	for enemy in _enemies:
		if enemy.get_meta("assigned"):
			continue
		
		var dist = enemy.global_position.distance_to(target_pos)
		
		# Bonus si garde son rôle actuel (stabilité)
		if _roles.get(enemy.get_instance_id(), -1) == role:
			dist -= 50.0
		
		if dist < best_score:
			best_score = dist
			best_enemy = enemy
	
	if best_enemy == null:
		return
	
	_roles[best_enemy.get_instance_id()] = role
	_target_positions[best_enemy.get_instance_id()] = target_pos
	best_enemy.set_meta("assigned", true)
