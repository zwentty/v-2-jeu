extends "res://scripts/base_enemy.gd"
# Ennemi mêlée : attaque au corps à corps avec hitbox directionnelle + bouclier réactif

# === PARAMÈTRES SPÉCIFIQUES ===
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.2
@export var attack_windup: float = 0.4

const HITBOX_ACTIVE_DURATION: float = 0.25
const ATTACK_DISTANCE: float = 55.0

# === BOUCLIER ===
const BOUCLIER_COOLDOWN: float = 5.0
const BOUCLIER_DUREE: float = 1.5

# === NŒUDS SPÉCIFIQUES ===
@onready var attack_area: Area2D = $AttackArea
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var hitbox_visual: Polygon2D = $AttackHitbox/Visual

# === VARIABLES SPÉCIFIQUES ===
var attack_timer: float = 0.0
var wander_angle: float = 0.0

var bouclier_pret: bool = false
var bouclier_actif: bool = false
var bouclier_timer: float = 0.0
var bouclier_direction: Vector2 = Vector2.ZERO
var bouclier_visual: Polygon2D = null

# === INITIALISATION ===

func _ready() -> void:
	patrol_arrive_distance = 12.0
	patrol_wait_min = 2.5
	patrol_wait_max = 2.5
	drop_nom = "Âme de Soldat"
	drop_couleur = Color.BLACK
	drop_polygone = PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	super._ready()
	attack_hitbox.body_entered.connect(_on_hitbox_hit)
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	_creer_visuel_bouclier()

func _physics_process(delta: float) -> void:
	attack_timer -= delta
	wander_angle += randf_range(-0.2, 0.2)

	if not bouclier_pret and not bouclier_actif:
		bouclier_timer += delta
		if bouclier_timer >= BOUCLIER_COOLDOWN:
			bouclier_pret = true
			bouclier_timer = 0.0
			modulate = Color(0.6, 0.85, 1.0)

	if bouclier_actif and bouclier_visual and player and is_instance_valid(player):
		bouclier_visual.rotation = (player.global_position - global_position).angle()

	super._physics_process(delta)

# === SANTÉ (override avec bouclier) ===

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return

	var dir_attaque := Vector2.RIGHT
	if player and is_instance_valid(player):
		dir_attaque = (player.global_position - global_position).normalized()

	if bouclier_pret:
		_activer_bouclier(dir_attaque)
		return

	if bouclier_actif:
		return

	health -= amount
	_update_health_bar()
	if health <= 0:
		die()

# === ÉTATS SPÉCIFIQUES ===

func _state_engage(_delta: float) -> void:
	if player == null or not _player_in_same_room():
		player = null
		state = State.PATROL
		_pick_patrol_point()
		return

	var dist = global_position.distance_to(player.global_position)

	if dist < ATTACK_DISTANCE and attack_timer <= 0 and EnemyManager.can_attack(self):
		state = State.ATTACK
		windup_timer = attack_windup
		return

	var target = EnemyManager.get_target_position(self)
	_navigate_to(target)
	_face_player()

func _state_attack(delta: float) -> void:
	if not _debut_attaque(delta):
		return

	if attack_timer <= 0:
		_trigger_attack()
		attack_timer = attack_cooldown

		await get_tree().create_timer(HITBOX_ACTIVE_DURATION).timeout
		if state == State.ATTACK and player and _player_in_same_room():
			state = State.ENGAGE
		elif state == State.ATTACK:
			player = null
			state = State.PATROL
			_pick_patrol_point()

# === ATTAQUE ===

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

# === NAVIGATION ===

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

# === MORT ===

func _mort_nettoyage() -> void:
	hitbox_shape.disabled = true
	hitbox_visual.visible = false
	queue_free()

# === BOUCLIER ===

func _creer_visuel_bouclier() -> void:
	bouclier_visual = Polygon2D.new()
	var points: Array[Vector2] = []
	var r_int := 28.0
	var r_ext := 52.0
	var demi_angle := deg_to_rad(65.0)
	var nb_pas := 10

	for i in range(nb_pas + 1):
		var angle := -demi_angle + (2.0 * demi_angle * i / nb_pas)
		points.append(Vector2(cos(angle), sin(angle)) * r_ext)
	for i in range(nb_pas + 1):
		var angle := demi_angle - (2.0 * demi_angle * i / nb_pas)
		points.append(Vector2(cos(angle), sin(angle)) * r_int)

	bouclier_visual.polygon = PackedVector2Array(points)
	bouclier_visual.color = Color(0.25, 0.65, 1.0, 0.85)
	bouclier_visual.z_index = 1
	bouclier_visual.visible = false
	add_child(bouclier_visual)

func _activer_bouclier(direction: Vector2) -> void:
	bouclier_pret = false
	bouclier_actif = true
	bouclier_direction = direction
	bouclier_visual.rotation = direction.angle()
	bouclier_visual.visible = true
	modulate = Color.WHITE

	await get_tree().create_timer(BOUCLIER_DUREE).timeout

	if not is_instance_valid(self) or state == State.DEAD:
		return
	bouclier_actif = false
	bouclier_visual.visible = false
	bouclier_timer = 0.0
