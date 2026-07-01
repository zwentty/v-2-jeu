extends Area2D
class_name SlimeDashAttack
# =============================================================================
# Attaque-dash du slime de base.
#
# Extraite de player.gd : le slime fonce vers le curseur, traverse les ennemis
# en infligeant des dégâts, puis subit un knockback + stun à l'impact.
#
# Expose trigger() : l'interface commune que TOUTES les attaques/compétences-slime
# exposent pour être déclenchées par le TransformHandler (cf. transform_handler.gd).
#
# Cette scène pilote elle-même le CharacterBody2D du joueur via deux drapeaux
# génériques (le joueur ne contient plus aucune logique de dash) :
#   - player.control_locked : le joueur ne se déplace plus de lui-même
#   - player.is_intangible  : le joueur ignore les dégâts (pendant le dash)
# Le nœud étant enfant du TransformHandler, il n'existe QUE tant que la forme de
# base est active : une fois transformé, il est libéré et cesse de tourner.
# =============================================================================

# === PARAMÈTRES (équivalents des constantes de l'ancien player.gd) ===
@export var dash_speed: float = 500.0          # vitesse du dash (px/s)
@export var dash_duration: float = 0.30        # durée du dash
@export var dash_cooldown: float = 1.2         # délai entre deux dashs
@export var attack_damage: int = 3             # dégâts infligés à l'ennemi touché
@export var knockback_speed: float = 300.0     # rebond du joueur après impact
@export var knockback_duration: float = 0.25   # durée du rebond
@export var stun_duration: float = 0.8         # durée du stun après impact
@export var hitbox_offset: float = 16.0        # avance de la hitbox devant le joueur

# === NŒUDS ===
@onready var _hitbox: CollisionShape2D = $CollisionShape2D
@onready var _visual: Polygon2D = $Visual

# === ÉTAT INTERNE (entièrement possédé par cette scène, plus par le player) ===
var _player: CharacterBody2D = null
var _cooldown_timer: float = 0.0

var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO

var _is_stunned: bool = false
var _stun_timer: float = 0.0
var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0


func _ready() -> void:
	# Inactive et invisible par défaut.
	monitoring = false
	_hitbox.disabled = true
	_visual.visible = false


# Interface commune appelée par le TransformHandler (use_attack()).
func trigger() -> void:
	var player := _get_player()
	if player == null:
		return
	# Indisponible pendant un dash, un stun ou tant que le cooldown court.
	if _is_dashing or _is_stunned or _cooldown_timer > 0.0:
		return

	var dir := (player.get_global_mouse_position() - player.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = player.facing_direction
	_start_dash(player, dir)


# -----------------------------------------------------------------------------
# _physics_process(delta)
# Tourne uniquement quand la forme de base est active (sinon le nœud est libéré).
# Le joueur s'efface (control_locked) : c'est ici qu'est appelé move_and_slide.
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if _is_dashing:
		_process_dash(delta)
	elif _is_stunned:
		_process_stun(delta)


# === DASH ===

func _start_dash(player: CharacterBody2D, dir: Vector2) -> void:
	_is_dashing = true
	_dash_timer = dash_duration
	_dash_dir = dir
	_cooldown_timer = dash_cooldown

	# Le joueur cède le contrôle et devient intangible le temps du dash.
	player.control_locked = true
	player.is_intangible = true

	monitoring = true
	_hitbox.disabled = false
	_visual.visible = true


func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		# Dash terminé sans toucher d'ennemi.
		_end_dash()
		return

	var player := _player
	player.velocity = _dash_dir * dash_speed
	player.move_and_slide()

	# La hitbox suit le joueur, légèrement en avant dans la direction du dash.
	global_position = player.global_position + _dash_dir * hitbox_offset

	# Animation + orientation du sprite du joueur pendant le dash.
	var spr: AnimatedSprite2D = player.animated_sprite
	if spr.animation != "walk":
		spr.play("walk")
	if _dash_dir.x < 0:
		spr.flip_h = true
	elif _dash_dir.x > 0:
		spr.flip_h = false
	# Bleu clignotant : le joueur est intangible pendant l'attaque-dash.
	spr.modulate = Color(0.5, 0.8, 1.0, 0.6 if fmod(_dash_timer, 0.1) < 0.05 else 1.0)

	# Détecte les ennemis DÉJÀ en contact (un ennemi « collé » au lancement ne
	# déclencherait jamais body_entered : on lit donc les chevauchements).
	for body in get_overlapping_bodies():
		_hit_enemy(body, player)
		if not _is_dashing:
			return  # un coup a réussi : le dash a laissé place au stun


func _end_dash(release_control: bool = true) -> void:
	_is_dashing = false
	monitoring = false
	_hitbox.disabled = true
	_visual.visible = false
	if release_control:
		_release_player()


# === IMPACT ===

func _hit_enemy(body: Node2D, player: CharacterBody2D) -> void:
	if not body.is_in_group("enemy") or not body.has_method("take_damage"):
		return
	if not _is_dashing:
		return

	body.take_damage(attack_damage)

	# Direction de rebond : s'éloigner de l'ennemi touché.
	var knockback_dir := (player.global_position - body.global_position).normalized()
	if knockback_dir == Vector2.ZERO:
		knockback_dir = -_dash_dir

	# Termine le dash (sans rendre le contrôle : le stun prend le relais).
	_end_dash(false)
	_start_stun(knockback_dir)


# === STUN + KNOCKBACK ===

func _start_stun(knockback_dir: Vector2) -> void:
	_is_stunned = true
	_stun_timer = stun_duration
	_knockback_velocity = knockback_dir * knockback_speed
	_knockback_timer = knockback_duration
	# Toujours immobilisé, mais redevient vulnérable pendant le stun.
	if _player:
		_player.control_locked = true
		_player.is_intangible = false


func _process_stun(delta: float) -> void:
	var player := _player
	_stun_timer -= delta

	# Knockback pendant sa durée, puis immobilisation jusqu'à la fin du stun.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		player.velocity = _knockback_velocity
		player.move_and_slide()
	else:
		player.velocity = Vector2.ZERO

	# Rouge clignotant : le joueur est étourdi après l'impact.
	player.animated_sprite.modulate = Color(1.0, 0.3, 0.3, 0.6 if fmod(_stun_timer, 0.15) < 0.075 else 1.0)

	if _stun_timer <= 0.0:
		_is_stunned = false
		_release_player()


# === JOUEUR ===

# Rend le contrôle au joueur et rétablit son apparence normale.
func _release_player() -> void:
	if not is_instance_valid(_player):
		return
	_player.control_locked = false
	_player.is_intangible = false
	_player.animated_sprite.modulate = Color.WHITE


# Résolution paresseuse : le groupe "player" n'existe pas encore au _ready de
# cette scène (instanciée avant que le joueur ne s'y ajoute).
func _get_player() -> CharacterBody2D:
	if not is_instance_valid(_player):
		var p := get_tree().get_first_node_in_group("player")
		if p is CharacterBody2D:
			_player = p
	return _player


# Filet de sécurité : si la scène est libérée en plein dash/stun (changement de
# forme), on rend impérativement le contrôle au joueur pour ne pas le figer.
func _exit_tree() -> void:
	_release_player()
