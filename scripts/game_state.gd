extends Node
# =============================================================================
# game_state.gd  (autoload : GameState)
# Conserve l'état du joueur (vie + inventaire) entre les scènes de salle.
# Chaque salle est une scène distincte : on sauvegarde l'état avant de changer
# de scène, puis on le restaure dans la salle suivante.
# =============================================================================

# Vie sauvegardée du joueur. -1 = aucune sauvegarde (le joueur garde sa vie
# par défaut, ex. au tout début d'une partie).
var player_health: int = -1
var player_max_health: int = -1

# Inventaire sauvegardé : {nom_objet: quantité}
var inventory_items: Dictionary = {}

# Salles déjà nettoyées : {chemin_scène: true}. Une salle nettoyée ne
# refait pas spawn ses ennemis quand on y revient.
var cleared_rooms: Dictionary = {}

# Nom du Marker2D où placer le joueur dans la PROCHAINE salle chargée.
# Défini par la porte empruntée (door.target_spawn). "" = laisser la position
# définie dans la scène (ex. tout début de partie).
var next_spawn_point: String = ""

# =============================================================================
# Timer de run (compte à rebours de 3 minutes)
# Persiste d'une salle à l'autre (autoload). Ne décompte que pendant le
# gameplay (un joueur présent) et se fige avec get_tree().paused. À 0, on émet
# run_time_expired -> le joueur déclenche sa mort (cf. player.gd).
# =============================================================================
const RUN_DURATION: float = 180.0 # 3 minutes

# Émis une seule fois quand le temps de run atteint 0.
signal run_time_expired

# Secondes restantes dans la run courante.
var run_time_left: float = RUN_DURATION
# Vrai une fois le temps écoulé (évite de ré-émettre / de décompter en négatif).
var _run_expired: bool = false

# =============================================================================
# reset()
# Remet l'état à zéro. À appeler au lancement d'une nouvelle partie.
# =============================================================================
func reset() -> void:
	player_health = -1
	player_max_health = -1
	inventory_items = {}
	cleared_rooms = {}
	next_spawn_point = ""
	# Nouvelle run : on remet le compte à rebours à plein.
	run_time_left = RUN_DURATION
	_run_expired = false

# =============================================================================
# _process(delta)
# Fait tourner le compte à rebours de run, uniquement pendant le gameplay
# (un joueur est présent dans la scène). L'autoload étant PAUSABLE, le décompte
# se fige automatiquement quand get_tree().paused est vrai (pause / cinématique).
# =============================================================================
func _process(delta: float) -> void:
	if _run_expired:
		return
	# Pas de joueur (menu, victoire, écran de fin...) : on ne décompte pas.
	if get_tree().get_first_node_in_group("player") == null:
		return
	run_time_left -= delta
	if run_time_left <= 0.0:
		run_time_left = 0.0
		_run_expired = true
		run_time_expired.emit()

# =============================================================================
# Suivi des salles nettoyées
# =============================================================================
func mark_room_cleared(scene_path: String) -> void:
	if scene_path != "":
		cleared_rooms[scene_path] = true

func is_room_cleared(scene_path: String) -> bool:
	return cleared_rooms.get(scene_path, false)

# =============================================================================
# save_player(player, inventory)
# Sauvegarde la vie du joueur et le contenu de l'inventaire.
# =============================================================================
func save_player(player: Node, inventory: Node) -> void:
	if player != null:
		player_health = player.health
		player_max_health = player.max_health
	if inventory != null:
		inventory_items = inventory.items.duplicate(true)

# =============================================================================
# restore_player(player, inventory)
# Restaure la vie et l'inventaire sauvegardés (si une sauvegarde existe).
# =============================================================================
func restore_player(player: Node, inventory: Node) -> void:
	if player != null and player_health >= 0:
		player.max_health = player_max_health
		player.health = player_health
		if player.has_method("_update_health_bar"):
			player._update_health_bar()
	if inventory != null and not inventory_items.is_empty():
		inventory.items = inventory_items.duplicate(true)
		if inventory.has_method("update_display"):
			inventory.update_display()
