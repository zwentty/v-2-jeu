extends CharacterBody2D
# Classe de base commune à tous les ennemis.
# Gère : machine à états, navigation, patrouille, détection, salle, santé, drop.
# Les sous-classes implémentent _state_engage, _state_attack, _navigate_to, _mort_nettoyage.

# === ÉTATS ===
enum State { IDLE, PATROL, ENGAGE, ATTACK, DEAD }

# === PARAMÈTRES COMMUNS (modifiables dans l'éditeur) ===
@export var move_speed: float = 180.0
@export var health: int = 3
@export var separation_radius: float = 60.0
@export var separation_force: float = 130.0

# === NŒUDS COMMUNS ===
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var detection_area: Area2D = $DetectionArea

# === VARIABLES COMMUNES ===
var state: State = State.IDLE
var player: Node2D = null
var facing_direction: Vector2 = Vector2.RIGHT
var patrol_target: Vector2 = Vector2.ZERO
var patrol_timer: float = 0.0
var windup_timer: float = 0.0
# Bornes de la salle (lues depuis le nœud racine de la salle au _ready).
var room_min_x: float = 0.0
var room_max_x: float = 2560.0
var room_min_y: float = 0.0
var room_max_y: float = 1440.0

# Configurables par les sous-classes avant super._ready()
var patrol_arrive_distance: float = 20.0
var patrol_wait_min: float = 2.0
var patrol_wait_max: float = 2.0
var max_health: int = 0
var debug_path_color: Color = Color(1.0, 0.5, 0.0, 0.85)  # orange (mêlée par défaut)

# Drop à la mort — à renseigner dans _ready() de la sous-classe
var drop_nom: String = ""
var drop_couleur: Color = Color.BLACK
var drop_polygone: PackedVector2Array = PackedVector2Array()
# Forme jouable transmise au drop à la mort. À assigner par scène d'ennemi dans
# l'éditeur (référence .tres), puisqu'une Resource ne se code pas en dur.
@export var drop_form: PlayableForm = null

# === INITIALISATION ===

func _ready() -> void:
	add_to_group("enemy")

	# Lire les bornes de la salle depuis son nœud racine (groupe "room").
	var room := get_tree().get_first_node_in_group("room")
	if room != null and "play_area" in room:
		var pa: Rect2 = room.play_area
		room_min_x = pa.position.x
		room_max_x = pa.position.x + pa.size.x
		room_min_y = pa.position.y
		room_max_y = pa.position.y + pa.size.y

	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 20.0
	nav_agent.radius = 25.0
	nav_agent.neighbor_distance = 250.0
	nav_agent.max_neighbors = 8
	nav_agent.max_speed = move_speed
	nav_agent.avoidance_enabled = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	nav_agent.debug_enabled = true
	nav_agent.debug_use_custom = true
	nav_agent.debug_path_custom_color = debug_path_color
	nav_agent.debug_path_custom_point_size = 6.0

	EnemyManager.register(self)
	detection_area.body_entered.connect(_on_player_detected)

	max_health = health
	_pick_patrol_point()
	_update_health_bar()

# Désenregistre l'ennemi quand il quitte l'arbre (ex. changement de scène),
# pour éviter des références mortes dans EnemyManager (autoload persistant).
func _exit_tree() -> void:
	EnemyManager.unregister(self)

# === BOUCLE PRINCIPALE ===

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:   _state_idle(delta)
		State.PATROL: _state_patrol(delta)
		State.ENGAGE: _state_engage(delta)
		State.ATTACK: _state_attack(delta)
		State.DEAD:   _state_dead()

# === ÉTATS (communs) ===

func _state_idle(delta: float) -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	patrol_timer -= delta
	if patrol_timer <= 0:
		_pick_patrol_point()
		state = State.PATROL

func _state_patrol(_delta: float) -> void:
	_navigate_to(patrol_target)
	if global_position.distance_to(patrol_target) < patrol_arrive_distance:
		patrol_timer = randf_range(patrol_wait_min, patrol_wait_max)
		state = State.IDLE

func _state_engage(_delta: float) -> void:
	pass

func _state_attack(_delta: float) -> void:
	pass

func _state_dead() -> void:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()

# Partie commune de _state_attack : arrêt, orientation, windup.
# Retourne true quand le windup est terminé et que l'action peut s'exécuter.
func _debut_attaque(delta: float) -> bool:
	velocity = Vector2.ZERO
	nav_agent.set_velocity(Vector2.ZERO)
	move_and_slide()
	if player:
		facing_direction = (player.global_position - global_position).normalized()
	if windup_timer > 0:
		windup_timer -= delta
		return false
	return true

# === SANTÉ ===

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_update_health_bar()
	if health <= 0:
		die()

func die() -> void:
	state = State.DEAD
	EnemyManager.unregister(self)
	if drop_nom != "":
		var item_scene: PackedScene = load("res://scenes/items/item.tscn")
		var item: Node2D = item_scene.instantiate()
		item.global_position = global_position
		item.item_name = drop_nom
		item.item_color = drop_couleur
		item.item_polygon = drop_polygone
		item.carried_form = drop_form
		get_parent().add_child(item)
	_mort_nettoyage()

func _mort_nettoyage() -> void:
	queue_free()

func _update_health_bar() -> void:
	var bar = get_node_or_null("HealthBar")
	if bar:
		bar.max_value = max_health
		bar.value = health

# === NAVIGATION (à surcharger) ===

func _navigate_to(_target: Vector2) -> void:
	pass

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

func _get_neighbors() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(
		func(e): return e != self and is_instance_valid(e) and e.state != State.DEAD
	)

# === UTILITAIRES COMMUNS ===

func _face_player() -> void:
	if player:
		facing_direction = (player.global_position - global_position).normalized()

func _player_in_same_room() -> bool:
	# Une salle = une scène : le joueur est toujours dans la même salle que l'ennemi.
	return player != null

func _pick_patrol_point() -> void:
	var offset := Vector2(randf_range(-150, 150), randf_range(-150, 150))
	patrol_target = global_position + offset
	patrol_target.x = clamp(patrol_target.x, room_min_x + 100, room_max_x - 100)
	patrol_target.y = clamp(patrol_target.y, room_min_y + 100, room_max_y - 100)

func _on_player_detected(body: Node2D) -> void:
	if body.is_in_group("player") and state != State.DEAD:
		player = body
		if _player_in_same_room():
			state = State.ENGAGE
