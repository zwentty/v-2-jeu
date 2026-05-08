extends Node

enum Role { PRESSURE, FLANK }
enum Side { LEFT, RIGHT }

const MAX_ATTACKERS := 2
const CLOSE_DISTANCE := 100.0

var _enemies: Array[Node] = []
var _roles: Dictionary = {}
var _sides: Dictionary = {}
var _flank_ratios: Dictionary = {}
var _player: Node2D = null

func register(enemy: Node) -> void:
	if enemy in _enemies:
		return
	_enemies.append(enemy)

func unregister(enemy: Node) -> void:
	_enemies.erase(enemy)
	_roles.erase(enemy.get_instance_id())
	_sides.erase(enemy.get_instance_id())
	_flank_ratios.erase(enemy.get_instance_id())

func get_role(enemy: Node) -> Role:
	return _roles.get(enemy.get_instance_id(), Role.PRESSURE)

func get_side(enemy: Node) -> Side:
	return _sides.get(enemy.get_instance_id(), Side.LEFT)

func get_flank_ratio(enemy: Node) -> float:
	return _flank_ratios.get(enemy.get_instance_id(), 0.6)

func can_attack(_enemy: Node) -> bool:
	var count := 0
	for e in _enemies:
		if is_instance_valid(e) and e.state == e.State.ATTACK:
			count += 1
	return count < MAX_ATTACKERS

func _process(_delta: float) -> void:
	_find_player()
	if _player == null:
		return
	_cleanup()
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
	
	var sorted = _enemies.duplicate()
	sorted.sort_custom(func(a, b):
		return a.global_position.distance_squared_to(_player.global_position) < b.global_position.distance_squared_to(_player.global_position)
	)
	
	_roles.clear()
	_sides.clear()
	_flank_ratios.clear()
	
	# Séparer les ennemis en deux catégories
	var pressures: Array[Node] = []
	var flankers: Array[Node] = []
	
	for enemy in sorted:
		var dist = enemy.global_position.distance_to(_player.global_position)
		# Si < 200px ou le plus proche, devient PRESSURE
		if dist < CLOSE_DISTANCE or pressures.size() == 0:
			pressures.append(enemy)
			_roles[enemy.get_instance_id()] = Role.PRESSURE
		else:
			flankers.append(enemy)
			_roles[enemy.get_instance_id()] = Role.FLANK
	
	# Le premier pressure sert de référence pour les calculs
	var reference_enemy = pressures[0] if pressures.size() > 0 else null
	
	# Collecter les flankers avec leurs distances perpendiculaires
	var flankers_with_dist: Array[Dictionary] = []
	
	for enemy in flankers:
		if reference_enemy and _player:
			var line_dir = reference_enemy.global_position.direction_to(_player.global_position)
			var to_enemy = reference_enemy.global_position.direction_to(enemy.global_position)
			# Produit vectoriel pour savoir si à gauche ou droite
			var cross = line_dir.x * to_enemy.y - line_dir.y * to_enemy.x
			_sides[enemy.get_instance_id()] = Side.RIGHT if cross > 0 else Side.LEFT
			# Distance perpendiculaire à la ligne
			var perp_dist = abs(cross) * reference_enemy.global_position.distance_to(enemy.global_position)
			flankers_with_dist.append({"enemy": enemy, "dist": perp_dist})
		else:
			_sides[enemy.get_instance_id()] = Side.LEFT
			flankers_with_dist.append({"enemy": enemy, "dist": 0.0})
	
	# Séparer les flankers par côté
	if flankers_with_dist.size() > 0:
		var left_flankers: Array[Dictionary] = []
		var right_flankers: Array[Dictionary] = []
		
		for item in flankers_with_dist:
			var side = _sides[item["enemy"].get_instance_id()]
			if side == Side.LEFT:
				left_flankers.append(item)
			else:
				right_flankers.append(item)
		
		# Trier chaque côté par distance perpendiculaire
		left_flankers.sort_custom(func(a, b): return a["dist"] < b["dist"])
		right_flankers.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		# Attribuer les ratios pour LEFT : le plus loin contourne le plus
		for i in left_flankers.size():
			var t = float(i) / max(1, left_flankers.size() - 1)
			var ratio = lerp(0.85, 0.2, t)  # Plus l'index est élevé, plus le ratio est faible
			_flank_ratios[left_flankers[i]["enemy"].get_instance_id()] = ratio
			print("LEFT Flanker ", i, "/", left_flankers.size(), " - Dist: ", int(left_flankers[i]["dist"]), " - Ratio: ", "%.2f" % ratio)
		
		# Attribuer les ratios pour RIGHT : le plus loin contourne le plus
		for i in right_flankers.size():
			var t = float(i) / max(1, right_flankers.size() - 1)
			var ratio = lerp(0.85, 0.2, t)
			_flank_ratios[right_flankers[i]["enemy"].get_instance_id()] = ratio
			print("RIGHT Flanker ", i, "/", right_flankers.size(), " - Dist: ", int(right_flankers[i]["dist"]), " - Ratio: ", "%.2f" % ratio)
