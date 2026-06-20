extends "res://scripts/base_enemy.gd"
# Ennemi à distance : maintient une distance optimale et tire des projectiles

# === PARAMÈTRES SPÉCIFIQUES ===
@export var shoot_cooldown: float = 2.0
@export var shoot_windup: float = 0.5
@export var optimal_distance: float = 300.0
@export var min_distance: float = 200.0
@export var max_distance: float = 400.0
@export var projectile_scene: PackedScene = preload("res://scenes/projectile/projectile.tscn")

# === NŒUDS SPÉCIFIQUES ===
@onready var visual: ColorRect = $Visual

# === VARIABLES SPÉCIFIQUES ===
var shoot_timer: float = 0.0

# === INITIALISATION ===

func _ready() -> void:
	patrol_arrive_distance = 30.0
	patrol_wait_min = 1.0
	patrol_wait_max = 3.0
	drop_nom = "Âme de Slime"
	drop_couleur = Color.BLACK
	drop_polygone = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	debug_path_color = Color(0.0, 0.75, 1.0, 0.85)  # cyan pour les ennemis à distance
	super._ready()
	state = State.PATROL

func _physics_process(delta: float) -> void:
	if shoot_timer > 0:
		shoot_timer -= delta
	super._physics_process(delta)

# === ÉTATS SPÉCIFIQUES ===

func _state_engage(_delta: float) -> void:
	if player == null or not _player_in_same_room():
		player = null
		state = State.PATROL
		_pick_patrol_point()
		return

	var dist = global_position.distance_to(player.global_position)
	var target = EnemyManager.get_target_position(self)

	_navigate_to(target)
	_face_player()

	if shoot_timer <= 0 and dist >= min_distance and dist <= max_distance:
		state = State.ATTACK
		windup_timer = shoot_windup

func _state_attack(delta: float) -> void:
	if not _debut_attaque(delta):
		return

	_shoot_projectile()
	shoot_timer = shoot_cooldown

	if player and _player_in_same_room():
		state = State.ENGAGE
	else:
		player = null
		state = State.PATROL
		_pick_patrol_point()

# === TIR ===

func _shoot_projectile() -> void:
	if projectile_scene == null or player == null:
		return
	var projectile = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)
	projectile.global_position = global_position + facing_direction * 20.0
	projectile.set_direction(facing_direction)

# === NAVIGATION ===

func _navigate_to(target: Vector2) -> void:
	nav_agent.set_target_position(target)

	if nav_agent.is_navigation_finished():
		return

	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	var separation = _calculate_separation()
	var player_avoidance = _calculate_player_avoidance()

	direction = (direction + separation + player_avoidance).normalized()
	nav_agent.set_velocity(direction * move_speed)

func _calculate_separation() -> Vector2:
	var sep := Vector2.ZERO
	for enemy in _get_neighbors():
		var dist = global_position.distance_to(enemy.global_position)
		if dist < separation_radius and dist > 0:
			sep += (global_position - enemy.global_position).normalized() * (separation_radius - dist) / separation_radius
	return sep.normalized() * separation_force if sep.length() > 0 else Vector2.ZERO

func _calculate_player_avoidance() -> Vector2:
	if player == null:
		return Vector2.ZERO
	var dist = global_position.distance_to(player.global_position)
	var avoid_r = min_distance * 0.8
	if dist < avoid_r and dist > 0:
		var strength = (avoid_r - dist) / avoid_r
		return (global_position - player.global_position).normalized() * separation_force * strength * 1.5
	return Vector2.ZERO

# === MORT ===

func _mort_nettoyage() -> void:
	var tween = create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
