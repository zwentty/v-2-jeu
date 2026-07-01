# =============================================================================
# player.gd
# Script attaché au nœud Player (CharacterBody2D)
# =============================================================================

extends CharacterBody2D

const PROJECTILE_SCENE = preload("res://scenes/projectile/projectile.tscn")
const DEATH_SEQUENCE_SCENE = preload("res://scenes/menus/death_sequence.tscn")
# Nom de l'animation de mort attendue dans les death_frames d'une forme.
const DEATH_ANIM: StringName = &"death"

# -----------------------------------------------------------------------------
# CONSTANTES
# -----------------------------------------------------------------------------

const SPEED = 200.0
const INVINCIBLE_DURATION = 1.0

# Projectile lancé par le joueur (clic droit)
const PLAYER_PROJECTILE_SPEED   = 500.0
const PLAYER_PROJECTILE_DAMAGE  = 3
const PLAYER_PROJECTILE_COOLDOWN = 0.5

# -----------------------------------------------------------------------------
# VARIABLES D'ÉTAT
# -----------------------------------------------------------------------------

var health: int = 5
var max_health: int = 5
# Vitesse courante : valeur de base, écrasée par le move_speed de la forme active
# (appliquée par le TransformHandler via le StatBlock de la forme).
var move_speed: float = SPEED
var is_invincible: bool = false
var invincible_timer: float = 0.0

# Drapeaux génériques pilotés par les capacités (attaque/compétence de la forme
# active). Le joueur n'implémente plus aucun dash/stun : il s'efface simplement.
#   control_locked : le joueur ne se déplace plus de lui-même (dash, stun…).
#   is_intangible  : le joueur ignore les dégâts reçus (i-frames du dash…).
var control_locked: bool = false
var is_intangible: bool = false

var facing_direction: Vector2 = Vector2.DOWN
var inventory: Control = null

# Garde-fou : évite de relancer la cinématique de mort plusieurs fois.
var _is_dying: bool = false

# Projectile du joueur
var projectile_cooldown_timer: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $Visual
# TransformInventory enfant (façade des transformations). Trouvé par capacité,
# sans dépendre du type concret ni du nom exact du nœud.
@onready var transform_inventory: Node = _find_transform_inventory()

# -----------------------------------------------------------------------------
# _ready()
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("player")
	_update_health_bar()
	z_index = 2

	# Fin du compte à rebours de run (GameState) -> le joueur meurt.
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("run_time_expired") \
			and not gs.run_time_expired.is_connected(_on_run_time_expired):
		gs.run_time_expired.connect(_on_run_time_expired)

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
	# En cours de mort : on n'exécute plus la logique de gameplay (mouvement,
	# visuel...) qui écraserait l'animation de mort avant que la pause ne prenne
	# effet (elle ne s'applique qu'à la frame suivante).
	if _is_dying:
		return
	# Pendant qu'une capacité pilote le joueur (dash, stun…), il ne bouge pas de
	# lui-même : la capacité appelle alors move_and_slide à sa place.
	if not control_locked:
		_handle_movement()
	_handle_invincibility(delta)
	_update_visual()
	if projectile_cooldown_timer > 0.0:
		projectile_cooldown_timer -= delta

# -----------------------------------------------------------------------------
# _unhandled_input(event)
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# On ne traite que les pressions de touche clavier ou de bouton souris
	var is_key: bool = event is InputEventKey
	var is_mouse_button: bool = event is InputEventMouseButton
	if not is_key and not is_mouse_button:
		return
	if not event.pressed:
		return
	if is_key and event.echo:
		return

	# Attaque de la forme active (façade type-agnostique). La forme de base monte
	# son attaque-dash, les formes-ennemis la leur : le joueur ne connaît rien du
	# type concret. Cooldown/stun éventuels sont gérés par l'attaque elle-même.
	if Settings.binding_matches_event(Settings.attaque_binding, event):
		if transform_inventory:
			transform_inventory.use_attack()
			get_viewport().set_input_as_handled()
		return

	# Compétence de la forme active. La forme de base monte « manger les âmes » ;
	# les formes-ennemis n'ont pas de compétence (ability_scene vide) : use_ability
	# n'a alors aucun effet — la règle « seule la base peut manger » est structurelle.
	if Settings.binding_matches_event(Settings.competence_binding, event):
		if transform_inventory:
			transform_inventory.use_ability()
			get_viewport().set_input_as_handled()
		return

	# Tir de projectile sur clic droit
	if is_mouse_button and event.button_index == MOUSE_BUTTON_RIGHT:
		if not control_locked and projectile_cooldown_timer <= 0.0:
			var mouse_pos := get_global_mouse_position()
			var dir := (mouse_pos - global_position).normalized()
			if dir == Vector2.ZERO:
				dir = facing_direction
			_fire_projectile(dir)
			get_viewport().set_input_as_handled()
		return

	# Ramassage d'objet classique (touche clavier configurable)
	if is_key and event.keycode == Settings.key_pickup:
		if _try_pickup_items(false):
			get_viewport().set_input_as_handled()
		return

# -----------------------------------------------------------------------------
# _try_pickup_items(ame_only)
# Ramasse l'objet ramassable le plus proche (dans un rayon de 50 px).
# Si ame_only est vrai, ne considère que les âmes ; sinon, ignore les âmes.
# Retourne true si un objet a été ramassé.
# -----------------------------------------------------------------------------
func _try_pickup_items(ame_only: bool) -> bool:
	for item in get_tree().get_nodes_in_group("item"):
		if not item.has_method("pickup"):
			continue
		if item.est_ame() != ame_only:
			continue
		if global_position.distance_to(item.global_position) <= 50.0:
			var item_name: String = item.pickup()
			var inv := _get_inventory()
			if inv:
				inv.add_item(item_name)
			return true
	return false

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

	velocity = direction * move_speed
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
# Priorité : capacité en cours (dash/stun) > invincible > normal
# -----------------------------------------------------------------------------
func _update_visual() -> void:
	# Une capacité pilote le joueur : elle gère elle-même le modulate du sprite.
	if control_locked:
		return
	if is_invincible:
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
	# Intangible quand une capacité l'a rendu tel (i-frames du dash, etc.)
	if is_intangible:
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
# Fin du compte à rebours de run : le joueur meurt (réutilise la cinématique).
func _on_run_time_expired() -> void:
	_die()

func _die() -> void:
	if _is_dying:
		return
	_is_dying = true

	# Animation de mort du slime, jouée sur SON propre sprite (le joueur possède
	# son Visual). En PROCESS_MODE_ALWAYS pour qu'elle s'anime malgré la pause du
	# jeu déclenchée par la cinématique. Non bouclée : se fige sur la dernière frame.
	_play_death_animation()

	# Cinématique de mort superposée (scène autonome, découplée du slime).
	# On NE réinitialise PAS ici (on_death changerait le sprite en pleine
	# cinématique) : la run repart proprement quand le bouton « Rejouer »
	# recharge la salle de départ (joueur neuf, forme de base, inventaire vide).
	var seq := DEATH_SEQUENCE_SCENE.instantiate()
	get_tree().current_scene.add_child(seq)
	seq.start(self, $Camera2D)

# -----------------------------------------------------------------------------
# _play_death_animation()
# Joue l'animation de mort de la FORME ACTIVE (soldat -> mort du soldat, etc.).
# Si la forme n'a pas de death_frames, on ne joue rien (sprite laissé tel quel).
# En PROCESS_MODE_ALWAYS pour s'animer malgré la pause. Non bouclée : se fige
# sur la dernière frame.
# -----------------------------------------------------------------------------
func _play_death_animation() -> void:
	# Récupère les frames de mort de la forme active (null si aucune).
	var frames: SpriteFrames = null
	if transform_inventory and transform_inventory.has_method("get_active_form"):
		var form = transform_inventory.get_active_form()
		if form != null:
			frames = form.death_frames

	# Pas d'animation de mort pour cette forme : on ne fait rien.
	if frames == null or not frames.has_animation(DEATH_ANIM):
		return

	# Rend au joueur le contrôle qu'une capacité aurait pris (dash/stun) pour ne
	# pas ré-écraser le sprite de mort. La scène de capacité, elle, se fige avec
	# la pause du jeu déclenchée par la cinématique (PROCESS_MODE hérité).
	control_locked = false
	is_intangible = false
	animated_sprite.modulate = Color.WHITE
	animated_sprite.flip_h = false
	animated_sprite.process_mode = Node.PROCESS_MODE_ALWAYS
	animated_sprite.sprite_frames = frames
	animated_sprite.play(DEATH_ANIM)

# -----------------------------------------------------------------------------
# on_death()
# Réinitialisation roguelike : à la mort, l'inventaire de transformations est
# entièrement vidé et le slime repasse sous sa forme de base. Après cet appel,
# l'état est identique à un début de run.
# -----------------------------------------------------------------------------
func on_death() -> void:
	if transform_inventory and transform_inventory.has_method("reset_for_new_run"):
		transform_inventory.reset_for_new_run()

# Retrouve le TransformInventory enfant (par capacité, sans dépendre de son
# type concret ni du nom du nœud).
func _find_transform_inventory() -> Node:
	for child in get_children():
		if child.has_method("reset_for_new_run"):
			return child
	return null

# -----------------------------------------------------------------------------
# _update_health_bar()
# -----------------------------------------------------------------------------
func _update_health_bar() -> void:
	$HealthBar.max_value = max_health
	$HealthBar.value = health

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