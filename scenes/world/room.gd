# =============================================================================
# room.gd
# Script générique attaché au nœud racine d'une salle (Node2D).
# Chaque salle est une scène distincte, construite sur l'origine locale. Ce script :
#   - construit la région de navigation au RUNTIME (à partir des exports),
#   - crée l'inventaire et restaure l'état du joueur (vie + inventaire),
#   - place le joueur sur le Marker2D d'arrivée fourni par la porte empruntée,
#   - détecte quand la salle est nettoyée → ouvre toutes les portes (groupe "door"),
#   - déclenche la victoire si c'est la dernière salle (is_final_room),
#   - mémorise les salles nettoyées (pas de re-spawn quand on y revient).
#
# Les transitions entre salles sont gérées par les portes elles-mêmes (door.gd) :
# chaque porte connaît sa salle cible et le Marker2D d'arrivée. Les portes peuvent
# être placées dans n'importe quelle direction (haut/bas/gauche/droite).
# =============================================================================
extends Node2D

# --- Configuration de la salle (à régler dans l'éditeur, par scène) ---

# Zone marchable de la salle (contour extérieur de la navigation).
@export var play_area: Rect2 = Rect2(32, 32, 2496, 1376)

# Obstacles MANUELS supplémentaires (optionnels). Normalement inutile : les
# collisions des tuiles et des murs sont détectées automatiquement (voir plus bas).
@export var obstacle_rects: Array[Rect2] = []

# Rayon de l'agent : marge laissée autour des obstacles dans le maillage de nav.
@export var nav_agent_radius: float = 30.0

# Couches de collision parsées pour creuser les trous (tuiles avec hitbox, murs…).
# Par défaut : toutes les couches.
@export_flags_2d_physics var nav_collision_mask: int = 0xFFFFFFFF

# Dernière salle : la nettoyer déclenche la victoire (aucune porte ne mène plus loin).
@export var is_final_room: bool = false

# --- État interne ---
var room_cleared: bool = false        # Tous les ennemis de la salle sont morts
var transition_started: bool = false  # Évite de déclencher la victoire 2 fois

# _enter_tree (et non _ready) car les _ready des enfants (ennemis) s'exécutent
# AVANT celui du parent : les ennemis doivent pouvoir trouver la salle tôt.
func _enter_tree() -> void:
	add_to_group("room")

func _ready() -> void:
	# --- Inventaire (interface fixe) ---
	var inventory_canvas := CanvasLayer.new()
	add_child(inventory_canvas)

	var inventory_scene: PackedScene = load("res://scenes/ui/inventory.tscn")
	var inventory := inventory_scene.instantiate()
	inventory.process_mode = Node.PROCESS_MODE_ALWAYS
	inventory.add_to_group("inventory")
	inventory_canvas.add_child(inventory)

	# --- Navigation : une seule région pour cette salle ---
	_build_navigation()

	# --- Bouton pause ---
	$UILayer/PauseButton.pressed.connect(_on_pause_pressed)

	# --- Salle déjà nettoyée (on y revient) : pas de combat, portes ouvertes ---
	var gs := _game_state()
	if gs != null and gs.is_room_cleared(scene_file_path):
		_liberer_ennemis()
		room_cleared = true
		_on_room_cleared()

	# --- Placer le joueur + restaurer son état (différé : joueur prêt après) ---
	call_deferred("_restore_state", inventory)

# Construit le NavigationRegion2D de la salle.
# La zone marchable = play_area, dans laquelle on CREUSE automatiquement les
# collisions statiques (tuiles avec hitbox + murs + barrières de porte) en
# bakant depuis la géométrie réelle. Ainsi, ajouter/modifier une tuile met à
# jour le chemin des ennemis sans rien coder.
func _build_navigation() -> void:
	var nav_region := NavigationRegion2D.new()
	add_child(nav_region)
	move_child(nav_region, 0)

	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = nav_agent_radius

	# Contour extérieur = limite marchable de la salle.
	var p := play_area.position
	var s := play_area.size
	nav_poly.add_outline(PackedVector2Array([
		Vector2(p.x, p.y),
		Vector2(p.x + s.x, p.y),
		Vector2(p.x + s.x, p.y + s.y),
		Vector2(p.x, p.y + s.y),
	]))

	# Trous manuels supplémentaires (optionnels).
	for r in obstacle_rects:
		var rp := r.position
		var rs := r.size
		nav_poly.add_outline(PackedVector2Array([
			Vector2(rp.x, rp.y),
			Vector2(rp.x, rp.y + rs.y),
			Vector2(rp.x + rs.x, rp.y + rs.y),
			Vector2(rp.x + rs.x, rp.y),
		]))

	# Parser les collisions statiques sous la racine de la salle et baker :
	# chaque tuile/objet ayant une hitbox devient un trou dans le maillage.
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.parsed_collision_mask = nav_collision_mask

	var src := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(nav_poly, src, self)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, src)

	nav_region.navigation_polygon = nav_poly

# Accès à l'autoload GameState par chemin de nœud (et non par l'identifiant
# global) : ainsi le script compile même si l'éditeur n'a pas encore rechargé
# le projet après l'ajout de l'autoload.
func _game_state() -> Node:
	return get_node_or_null("/root/GameState")

# Place le joueur sur le Marker2D d'arrivée, puis restaure vie + inventaire.
func _restore_state(inventory: Node) -> void:
	var gs := _game_state()
	if gs == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and gs.next_spawn_point != "":
		var marker := get_node_or_null(gs.next_spawn_point)
		if marker != null:
			player.global_position = marker.global_position
		gs.next_spawn_point = ""  # consommé
	gs.restore_player(player, inventory)

# Libère tous les ennemis de la salle (utilisé quand on revient dans une salle
# déjà nettoyée : elle doit rester vide).
func _liberer_ennemis() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()

# =============================================================================
# _on_pause_pressed() / _input() — menu pause
# =============================================================================
func _on_pause_pressed() -> void:
	var pause_scene: PackedScene = load("res://scenes/menus/pause.tscn")
	var pause: Control = pause_scene.instantiate()
	$UILayer.add_child(pause)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not get_tree().paused:
			_on_pause_pressed()
			get_viewport().set_input_as_handled()

# =============================================================================
# _process(delta)
# Détecte la salle nettoyée, ouvre les portes, gère la victoire finale.
# =============================================================================
func _process(_delta: float) -> void:
	if transition_started:
		return

	# --- Détecter si la salle est nettoyée ---
	if not room_cleared:
		if get_tree().get_nodes_in_group("enemy").is_empty():
			room_cleared = true
			_on_room_cleared()

	# --- Dernière salle nettoyée → victoire ---
	if room_cleared and is_final_room:
		_victoire()

# Appelée quand la salle vient d'être nettoyée : ouvre les portes et mémorise
# l'état "nettoyée".
func _on_room_cleared() -> void:
	var gs := _game_state()
	if gs != null:
		gs.mark_room_cleared(scene_file_path)
	for d in get_tree().get_nodes_in_group("door"):
		d.open()
	print("Salle nettoyée ! Les portes s'ouvrent.")

func _victoire() -> void:
	transition_started = true
	print("Victoire ! Toutes les salles sont nettoyées !")
	get_tree().change_scene_to_file("res://scenes/menus/victory.tscn")
