# =============================================================================
# player.gd
# Script attaché au nœud Player (CharacterBody2D)
# =============================================================================

extends CharacterBody2D

const PROJECTILE_SCENE = preload("res://scenes/projectile/projectile.tscn")

# -----------------------------------------------------------------------------
# CONSTANTES
# -----------------------------------------------------------------------------

const SPEED = 200.0
const INVINCIBLE_DURATION = 1.0

# Attaque-dash : le joueur fonce vers la souris pour infliger des dégâts
const ATTACK_DASH_SPEED = 500.0
const ATTACK_DASH_DURATION = 0.30
const ATTACK_DASH_COOLDOWN = 1.2
const ATTACK_DAMAGE = 1

# Knockback + stun infligés au joueur après avoir touché un ennemi
const PLAYER_KNOCKBACK_SPEED = 300.0
const PLAYER_KNOCKBACK_DURATION = 0.25
const PLAYER_STUN_DURATION = 0.8

# Dash de déplacement (touche configurable)
const DASH_SPEED = 600.0
const DASH_DURATION = 0.3
const DASH_COOLDOWN = 0.8

# Projectile lancé par le joueur (clic droit)
const PLAYER_PROJECTILE_SPEED   = 500.0
const PLAYER_PROJECTILE_DAMAGE  = 1
const PLAYER_PROJECTILE_COOLDOWN = 0.5

# -----------------------------------------------------------------------------
# VARIABLES D'ÉTAT
# -----------------------------------------------------------------------------

var health: int = 25
var max_health: int = 25
var is_invincible: bool = false
var invincible_timer: float = 0.0

# Dash de déplacement
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO

# Attaque-dash
var is_attack_dashing: bool = false
var attack_dash_timer: float = 0.0
var attack_dash_cooldown_timer: float = 0.0
var attack_dash_direction: Vector2 = Vector2.ZERO

# Stun + knockback du joueur après impact
var is_stunned: bool = false
var stun_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

var facing_direction: Vector2 = Vector2.DOWN
var inventory: Control = null

# Projectile du joueur
var projectile_cooldown_timer: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $Visual

# -----------------------------------------------------------------------------
# _ready()
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("player")
	_update_health_bar()
	z_index = 2
	$AttackArea.body_entered.connect(_on_attack_hit)

# -----------------------------------------------------------------------------
# _get_inventory()
# Récupère la référence à l'inventaire (lazy loading)
# -----------------------------------------------------------------------------
func _get_inventory() -> Control:
	if not inventory:
		inventory = get_tree().get_first_node_in_group("inventory")
		if inventory:
			print("Inventaire trouvé et connecté au joueur")
		else:
			print("ERREUR : Inventaire introuvable !")
	return inventory

# -----------------------------------------------------------------------------
# _physics_process(delta)
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_handle_dash(delta)
	_handle_attack_dash(delta)
	_handle_stun(delta)
	if not is_dashing and not is_attack_dashing and not is_stunned:
		_handle_movement()
	_handle_invincibility(delta)
	_update_visual()
	if projectile_cooldown_timer > 0.0:
		projectile_cooldown_timer -= delta

# -----------------------------------------------------------------------------
# _unhandled_input(event)
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# Attaque-dash sur clic gauche
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not is_stunned and not is_dashing and attack_dash_cooldown_timer <= 0.0:
			var mouse_pos := get_global_mouse_position()
			var direction := (mouse_pos - global_position).normalized()
			if direction == Vector2.ZERO:
				direction = facing_direction
			_start_attack_dash(direction)
			get_viewport().set_input_as_handled()
		return

	# Tir de projectile sur clic droit
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not is_stunned and projectile_cooldown_timer <= 0.0:
			var mouse_pos := get_global_mouse_position()
			var dir := (mouse_pos - global_position).normalized()
			if dir == Vector2.ZERO:
				dir = facing_direction
			_fire_projectile(dir)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Dash de déplacement
		if event.keycode == Settings.key_dash and not is_dashing and not is_attack_dashing and dash_cooldown_timer <= 0.0:
			_start_dash()
			get_viewport().set_input_as_handled()
			return

		# Ramassage d'objet
		if event.keycode == Settings.key_pickup:
			var items := get_tree().get_nodes_in_group("item")
			for item in items:
				if item.has_method("pickup"):
					var distance := global_position.distance_to(item.global_position)
					if distance <= 50.0:
						var item_name: String = item.pickup()
						var inv := _get_inventory()
						if inv:
							inv.add_item(item_name)
						get_viewport().set_input_as_handled()
						break

# -----------------------------------------------------------------------------
# _handle_movement()
# Lit les entrées clavier et déplace le joueur (ZQSD / AZERTY)
# -----------------------------------------------------------------------------
func _handle_movement() -> void:
	var direction := Vector2(
		(-1.0 if Input.is_key_pressed(Settings.key_move_left) else 0.0) + (1.0 if Input.is_key_pressed(Settings.key_move_right) else 0.0),
		(-1.0 if Input.is_key_pressed(Settings.key_move_up) else 0.0) + (1.0 if Input.is_key_pressed(Settings.key_move_down) else 0.0)
	)

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		facing_direction = direction

		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")

		if direction.x < 0:
			animated_sprite.flip_h = true
		elif direction.x > 0:
			animated_sprite.flip_h = false
	else:
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")

	velocity = direction * SPEED
	move_and_slide()

# -----------------------------------------------------------------------------
# _handle_invincibility(delta)
# Gère le timer d'invincibilité après avoir reçu un coup
# -----------------------------------------------------------------------------
func _handle_invincibility(delta: float) -> void:
	if not is_invincible:
		return
	invincible_timer -= delta
	if invincible_timer <= 0.0:
		is_invincible = false

# -----------------------------------------------------------------------------
# _update_visual()
# Gère la couleur/transparence du sprite selon l'état actuel.
# Priorité : stun > attaque-dash > dash déplacement > invincible > normal
# -----------------------------------------------------------------------------
func _update_visual() -> void:
	if is_stunned:
		# Rouge clignotant : le joueur est étourdi après l'impact
		$Visual.modulate = Color(1.0, 0.3, 0.3, 0.6 if fmod(stun_timer, 0.15) < 0.075 else 1.0)
	elif is_attack_dashing:
		# Bleu clignotant : le joueur est intangible pendant l'attaque-dash
		$Visual.modulate = Color(0.5, 0.8, 1.0, 0.6 if fmod(attack_dash_timer, 0.1) < 0.05 else 1.0)
	elif is_dashing:
		# Semi-transparent : intangible pendant le dash de déplacement
		$Visual.modulate = Color(1.0, 1.0, 1.0, 0.6 if fmod(dash_timer, 0.15) < 0.075 else 1.0)
	elif is_invincible:
		# Clignotement blanc après avoir reçu un coup
		$Visual.modulate = Color(1.0, 1.0, 1.0, 0.3 if fmod(invincible_timer, 0.2) < 0.1 else 1.0)
	else:
		$Visual.modulate = Color.WHITE

# -----------------------------------------------------------------------------
# take_damage(amount)
# Fonction publique : appelée par d'autres scripts pour blesser le joueur.
# -----------------------------------------------------------------------------
func take_damage(amount: int) -> void:
	if is_invincible:
		return
	# Intangible pendant les deux types de dash
	if is_dashing or is_attack_dashing:
		return

	health -= amount
	is_invincible = true
	invincible_timer = INVINCIBLE_DURATION

	print("Joueur PV : %d / %d" % [health, max_health])
	_update_health_bar()

	if health <= 0:
		_die()

# -----------------------------------------------------------------------------
# _die()
# -----------------------------------------------------------------------------
func _die() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/game_over.tscn")

# -----------------------------------------------------------------------------
# _update_health_bar()
# -----------------------------------------------------------------------------
func _update_health_bar() -> void:
	$HealthBar.max_value = max_health
	$HealthBar.value = health

# -----------------------------------------------------------------------------
# _handle_attack_dash(delta)
# Gère la progression du dash d'attaque (mouvement + hitbox active)
# -----------------------------------------------------------------------------
func _handle_attack_dash(delta: float) -> void:
	if attack_dash_cooldown_timer > 0.0:
		attack_dash_cooldown_timer -= delta

	if not is_attack_dashing:
		return

	attack_dash_timer -= delta

	if attack_dash_timer > 0.0:
		velocity = attack_dash_direction * ATTACK_DASH_SPEED
		move_and_slide()
		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")
		# Orienter le sprite dans la direction du dash
		if attack_dash_direction.x < 0:
			animated_sprite.flip_h = true
		elif attack_dash_direction.x > 0:
			animated_sprite.flip_h = false
	else:
		# Le dash s'est terminé sans toucher d'ennemi
		_end_attack_dash()

# -----------------------------------------------------------------------------
# _start_attack_dash(direction)
# Lance l'attaque-dash dans la direction donnée
# -----------------------------------------------------------------------------
func _start_attack_dash(direction: Vector2) -> void:
	is_attack_dashing = true
	attack_dash_timer = ATTACK_DASH_DURATION
	attack_dash_direction = direction
	attack_dash_cooldown_timer = ATTACK_DASH_COOLDOWN
	# Hitbox positionnée légèrement en avant du joueur
	$AttackArea.position = direction * 16.0
	$AttackArea.monitoring = true
	$AttackArea/AttackVisual.visible = true

# -----------------------------------------------------------------------------
# _end_attack_dash()
# Stoppe l'attaque-dash et désactive la hitbox
# -----------------------------------------------------------------------------
func _end_attack_dash() -> void:
	is_attack_dashing = false
	$AttackArea.monitoring = false
	$AttackArea/AttackVisual.visible = false

# -----------------------------------------------------------------------------
# _on_attack_hit(body)
# Appelée quand la hitbox touche un corps pendant l'attaque-dash.
# Inflige des dégâts, puis applique un knockback + stun au joueur.
# -----------------------------------------------------------------------------
func _on_attack_hit(body: Node2D) -> void:
	if not body.is_in_group("enemy") or not body.has_method("take_damage"):
		return
	if not is_attack_dashing:
		return

	body.take_damage(ATTACK_DAMAGE)
	print("Ennemi touché par l'attaque-dash !")

	# Direction de rebond : s'éloigner de l'ennemi touché
	var knockback_dir := (global_position - body.global_position).normalized()
	if knockback_dir == Vector2.ZERO:
		knockback_dir = -attack_dash_direction

	# Stopper le dash et appliquer le stun + knockback
	_end_attack_dash()
	knockback_velocity = knockback_dir * PLAYER_KNOCKBACK_SPEED
	knockback_timer = PLAYER_KNOCKBACK_DURATION
	is_stunned = true
	stun_timer = PLAYER_STUN_DURATION

# -----------------------------------------------------------------------------
# _handle_stun(delta)
# Gère le stun et le knockback du joueur après un impact ennemi.
# Pendant le stun, le joueur ne peut ni bouger ni attaquer.
# -----------------------------------------------------------------------------
func _handle_stun(delta: float) -> void:
	if not is_stunned:
		return

	stun_timer -= delta

	# Appliquer le knockback pendant sa durée, puis immobiliser
	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity = knockback_velocity
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	if stun_timer <= 0.0:
		is_stunned = false

# -----------------------------------------------------------------------------
# _handle_dash(delta)
# Gère le dash de déplacement (touche configurable dans Settings)
# -----------------------------------------------------------------------------
func _handle_dash(delta: float) -> void:
	if not is_dashing:
		if dash_cooldown_timer > 0.0:
			dash_cooldown_timer -= delta
		return

	dash_timer -= delta

	if dash_timer > 0.0:
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")
	else:
		is_dashing = false
		dash_cooldown_timer = DASH_COOLDOWN

# -----------------------------------------------------------------------------
# _start_dash()
# Lance un dash de déplacement dans la direction actuelle du joueur
# -----------------------------------------------------------------------------
func _start_dash() -> void:
	is_dashing = true
	dash_timer = DASH_DURATION
	dash_direction = facing_direction if facing_direction != Vector2.ZERO else Vector2.DOWN
	print("Dash lancé dans la direction : ", dash_direction)

# -----------------------------------------------------------------------------
# _fire_projectile(direction)
# Instancie un projectile orienté vers la souris, marqué comme source "player"
# -----------------------------------------------------------------------------
func _fire_projectile(direction: Vector2) -> void:
	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.source = "player"
	projectile.speed = PLAYER_PROJECTILE_SPEED
	projectile.damage = PLAYER_PROJECTILE_DAMAGE
	# Mask 6 = layer 2 (murs) + layer 4 (ennemis), au lieu du mask ennemi qui cible layer 1 (joueur)
	projectile.collision_mask = 6
	projectile.global_position = global_position
	projectile.set_direction(direction)
	get_tree().current_scene.add_child(projectile)
	projectile_cooldown_timer = PLAYER_PROJECTILE_COOLDOWN