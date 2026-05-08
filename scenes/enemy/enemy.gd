extends CharacterBody2D

enum State { IDLE, PATROL, ENGAGE, ATTACK, DEAD }

@export var move_speed: float = 180.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.2
@export var attack_windup: float = 0.4
@export var health: int = 3
@export var separation_radius: float = 60.0
@export var separation_force: float = 130.0

const HITBOX_ACTIVE_DURATION: float = 0.25
const ATTACK_DISTANCE: float = 55.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var detection_area: Area2D = $DetectionArea
@onready var attack_area: Area2D = $AttackArea
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var hitbox_visual: Polygon2D = $AttackHitbox/Visual

var state: State = State.IDLE
var player: Node2D = null
var facing_direction: Vector2 = Vector2.RIGHT
var patrol_target: Vector2 = Vector2.ZERO
var patrol_timer: float = 0.0
var patrol_wait: float = 2.5
var attack_timer: float = 0.0
var windup_timer: float = 0.0
var wander_angle: float = 0.0
var room_number: int = 1
var room_min_x: float = 0.0
var room_max_x: float = 2560.0

func _ready() -> void:
	add_to_group("enemy")
	
	if global_position.x < 2560.0:
		room_number = 1
		room_min_x = 0.0
		room_max_x = 2560.0
	else:
		room_number = 2
		room_min_x = 2560.0
		room_max_x = 5120.0
	
	_update_health_bar()
	
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 20.0
	nav_agent.radius = 25.0
	nav_agent.neighbor_distance = 250.0
	nav_agent.max_neighbors = 8
	nav_agent.max_speed = move_speed
	nav_agent.avoidance_enabled = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	EnemyManager.register(self)
	
	detection_area.body_entered.connect(_on_player_detected)
	attack_hitbox.body_entered.connect(_on_hitbox_hit)
	
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	
	_pick_patrol_point()

func _physics_process(delta: float) -> void:
	attack_timer -= delta
	wander_angle += randf_range(-0.2, 0.2)
	
	match state:
		State.IDLE:    _state_idle(delta)
		State.PATROL:  _state_patrol(delta)
		State.ENGAGE:  _state_engage(delta)
		State.ATTACK:  _state_attack(delta)
		State.DEAD:    _state_dead()

func _state_idle(delta: float) -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	patrol_timer -= delta
	if patrol_timer <= 0:
		_pick_patrol_point()
		state = State.PATROL

func _state_patrol(delta: float) -> void:
	if global_position.distance_to(patrol_target) < 12.0:
		patrol_timer = patrol_wait
		state = State.IDLE
		return
	_navigate_to(patrol_target)

func _state_engage(delta: float) -> void:
	if player == null or not _player_in_same_room():
		state = State.PATROL
		_pick_patrol_point()
		return
	
	var dist = global_position.distance_to(player.global_position)
	
	# Peu importe le rôle : si à portée d'attaque, on attaque
	if dist < ATTACK_DISTANCE and attack_timer <= 0 and EnemyManager.can_attack(self):
		state = State.ATTACK
		windup_timer = attack_windup
		return
	
	# Le rôle est dynamique : le manager le recalcule chaque frame
	var role = EnemyManager.get_role(self)
	
	if role == EnemyManager.Role.PRESSURE:
		_move_pressure()
	else:
		_move_flank()

func _move_pressure() -> void:
	_navigate_to(player.global_position)
	_face_player()

func _move_flank() -> void:
	var dir_to_player = global_position.direction_to(player.global_position)
	var side = EnemyManager.get_side(self)
	var ratio = EnemyManager.get_flank_ratio(self)
	var lateral = dir_to_player.rotated(PI / 2.0 if side == EnemyManager.Side.RIGHT else -PI / 2.0)
	# Mélange entre direction vers joueur et direction latérale
	var mixed_dir = (dir_to_player * ratio + lateral * (1.0 - ratio)).normalized()
	var target = global_position + mixed_dir * 300.0
	_navigate_to(target)
	_face_player()

func _state_attack(delta: float) -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	
	if player:
		facing_direction = (player.global_position - global_position).normalized()
	
	if windup_timer > 0:
		windup_timer -= delta
		return
	
	if attack_timer <= 0:
		_trigger_attack()
		attack_timer = attack_cooldown
		
		await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
		if state == State.ATTACK and player:
			state = State.ENGAGE

func _state_dead() -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()

func _trigger_attack() -> void:
	attack_hitbox.position = facing_direction * 40.0
	hitbox_shape.disabled = false
	hitbox_visual.visible = true
	await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
	if hitbox_shape:
		hitbox_shape.disabled = true
		hitbox_visual.visible = false

func _on_hitbox_hit(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(attack_damage)

func _on_player_detected(body: Node2D) -> void:
	if body.is_in_group("player") and state != State.DEAD:
		player = body
		state = State.ENGAGE

func _navigate_to(target: Vector2) -> void:
	nav_agent.set_target_position(target)
	if nav_agent.is_navigation_finished():
		return
	var next_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_pos)
	var desired = direction * move_speed
	var f_sep = Steering.separate(global_position, _get_neighbors(), separation_radius, separation_force)
	var final_vel = (desired + f_sep).limit_length(move_speed)
	if final_vel.length() > 0.1:
		facing_direction = final_vel.normalized()
	nav_agent.set_velocity(final_vel)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func _get_neighbors() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(
		func(e): return e != self and is_instance_valid(e) and e.state != State.DEAD
	)

func _face_player() -> void:
	if player:
		facing_direction = (player.global_position - global_position).normalized()

func _player_in_same_room() -> bool:
	return (room_number == 1 and player.global_position.x < 2560.0) or \
	       (room_number == 2 and player.global_position.x >= 2560.0)

func _pick_patrol_point() -> void:
	var offset := Vector2(randf_range(-150, 150), randf_range(-150, 150))
	patrol_target = global_position + offset
	patrol_target.x = clamp(patrol_target.x, room_min_x + 100, room_max_x - 100)

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_update_health_bar()
	if health <= 0:
		die()

func die() -> void:
	state = State.DEAD
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	EnemyManager.unregister(self)
	
	var item_scene: PackedScene = load("res://scenes/items/item.tscn")
	var item: Node2D = item_scene.instantiate()
	item.global_position = global_position
	item.item_name = "Butin d'ennemi"
	get_parent().add_child(item)
	queue_free()

func _update_health_bar() -> void:
	$HealthBar.max_value = 3
	$HealthBar.value = health
