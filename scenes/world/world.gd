# =============================================================================
# world.gd
# Script attaché au nœud World (Node2D)
# Crée la région de navigation au RUNTIME et vérifie la victoire.
# =============================================================================
extends Node2D

# Variable pour éviter de vérifier plusieurs fois la victoire
var victory_triggered: bool = false

# Variable pour éviter de masquer la porte plusieurs fois
var door_disappeared: bool = false

# Tracker la salle actuelle du joueur (1 ou 2)
var current_player_room: int = 1

func _ready() -> void:
	# -------------------------------------------------------------------------
	# 1. Créer le nœud NavigationRegion2D et l'ajouter à la scène.
	#    Ce nœud publie un NavigationPolygon au NavigationServer2D.
	# -------------------------------------------------------------------------
	var nav_region := NavigationRegion2D.new()
	add_child(nav_region)

	# On le place en 1er enfant (après Ground visuellement) pour qu'il soit
	# traité tôt dans l'arbre.
	move_child(nav_region, 0)

	# -------------------------------------------------------------------------
	# 2. Créer le NavigationPolygon.
	#    - L'outline extérieur (sens horaire) = zone MARCHABLE.
	#    - Les outlines intérieurs (sens anti-horaire) = TROUS (obstacles).
	# -------------------------------------------------------------------------
	var nav_poly := NavigationPolygon.new()

	# --- Contour extérieur : la zone navigable (à l'intérieur des murs) ---
	# Salle 1 avec ouverture pour la porte (Y: 670 à 770)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(32, 32),
		Vector2(2528, 32),
		Vector2(2528, 1408),
		Vector2(32, 1408),
	]))

	# --- Salle 2 avec ouverture pour la porte (Y: 670 à 770) ---
	# Zone marchable = (2592, 32) → (5088, 1408)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(2592, 32),
		Vector2(5088, 32),
		Vector2(5088, 1408),
		Vector2(2592, 1408),
	]))

	# --- Trous : les 5 rochers (160x160 - doublé pour la navigation) ---
	# Chaque rocher est centré à sa position, avec une marge de 80px au lieu de 40px.
	# Sens ANTI-HORAIRE pour indiquer un trou.

	# Rock1 centré en (400, 300)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(320, 220),
		Vector2(320, 380),
		Vector2(480, 380),
		Vector2(480, 220),
	]))

	# Rock2 centré en (1000, 650)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(920, 570),
		Vector2(920, 730),
		Vector2(1080, 730),
		Vector2(1080, 570),
	]))

	# Rock3 centré en (1800, 850)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(1720, 770),
		Vector2(1720, 930),
		Vector2(1880, 930),
		Vector2(1880, 770),
	]))

	# Rock4 centré en (700, 1100)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(620, 1020),
		Vector2(620, 1180),
		Vector2(780, 1180),
		Vector2(780, 1020),
	]))

	# Rock5 centré en (2100, 400)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(2020, 320),
		Vector2(2020, 480),
		Vector2(2180, 480),
		Vector2(2180, 320),
	]))

	# --- Obstacles Salle 2 ---

	# Rock1_Room2 centré en (2960, 300)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(2880, 220),
		Vector2(2880, 380),
		Vector2(3040, 380),
		Vector2(3040, 220),
	]))

	# Rock2_Room2 centré en (3560, 650)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(3480, 570),
		Vector2(3480, 730),
		Vector2(3640, 730),
		Vector2(3640, 570),
	]))

	# Rock3_Room2 centré en (4360, 850)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(4280, 770),
		Vector2(4280, 930),
		Vector2(4440, 930),
		Vector2(4440, 770),
	]))

	# Rock4_Room2 centré en (3260, 1100)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(3180, 1020),
		Vector2(3180, 1180),
		Vector2(3340, 1180),
		Vector2(3340, 1020),
	]))

	# Rock5_Room2 centré en (4660, 400)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(4580, 320),
		Vector2(4580, 480),
		Vector2(4740, 480),
		Vector2(4740, 320),
	]))

	# -------------------------------------------------------------------------
	# 3. make_polygons_from_outlines() transforme les outlines en triangles
	#    navigables. C'est le "baking" du mesh de navigation.
	# -------------------------------------------------------------------------
	nav_poly.make_polygons_from_outlines()

	# -------------------------------------------------------------------------
	# 4. Assigner le polygone à la région. Dès cet instant le
	#    NavigationServer2D connaît la carte et les NavigationAgent2D
	#    peuvent calculer des chemins.
	# -------------------------------------------------------------------------
	nav_region.navigation_polygon = nav_poly
	# -------------------------------------------------------------------------
	# 2ème NavigationRegion2D pour la salle 2
	# -------------------------------------------------------------------------
	var nav_region_2 := NavigationRegion2D.new()
	add_child(nav_region_2)
	move_child(nav_region_2, 1)

	# Créer le deuxième NavigationPolygon pour la salle 2
	var nav_poly_2 := NavigationPolygon.new()

	# --- Contour extérieur : salle 2 ---
	nav_poly_2.add_outline(PackedVector2Array([
		Vector2(2592, 32),
		Vector2(5088, 32),
		Vector2(5088, 1408),
		Vector2(2592, 1408),
	]))

	# --- Obstacles Salle 2 ---

	# Rock1_Room2 centré en (2960, 300)
	nav_poly_2.add_outline(PackedVector2Array([
		Vector2(2880, 220),
		Vector2(2880, 380),
		Vector2(3040, 380),
		Vector2(3040, 220),
	]))

	# Rock2_Room2 centré en (3560, 650)
	nav_poly_2.add_outline(PackedVector2Array([
		Vector2(3480, 570),
		Vector2(3480, 730),
		Vector2(3640, 730),
		Vector2(3640, 570),
	]))

	# Rock3_Room2 centré en (4360, 850)
	nav_poly_2.add_outline(PackedVector2Array([
		Vector2(4280, 770),
		Vector2(4280, 930),
		Vector2(4440, 930),
		Vector2(4440, 770),
	]))

	# Rock4_Room2 centré en (3260, 1100)
	nav_poly_2.add_outline(PackedVector2Array([
		Vector2(3180, 1020),
		Vector2(3180, 1180),
		Vector2(3340, 1180),
		Vector2(3340, 1020),
	]))

	# Rock5_Room2 centré en (4660, 400)
	nav_poly_2.add_outline(PackedVector2Array([
		Vector2(4580, 320),
		Vector2(4580, 480),
		Vector2(4740, 480),
		Vector2(4740, 320),
	]))

	# Bake et assigner le polygone
	nav_poly_2.make_polygons_from_outlines()
	nav_region_2.navigation_polygon = nav_poly_2
	
	# -------------------------------------------------------------------------
	# 5. Connecter le bouton pause
	# -------------------------------------------------------------------------
	$UILayer/PauseButton.pressed.connect(_on_pause_pressed)
	
	# -------------------------------------------------------------------------
	# 6. Initialiser la visibilité des masques (salle 1 visible, salle 2 masquée)
	# -------------------------------------------------------------------------
	$MaskRoom2.visible = true
	$MaskRoom1.visible = false

# =============================================================================
# _on_pause_pressed()
# Appelée quand le joueur appuie sur le bouton Pause ou sur ESC
# Charge la scène du menu pause
# =============================================================================
func _on_pause_pressed() -> void:
	var pause_menu = load("res://scenes/menus/pause.tscn").instantiate()
	$UILayer.add_child(pause_menu)

# =============================================================================
# _input(event)
# Appelée pour chaque input (clavier, souris, etc.)
# =============================================================================
func _input(event: InputEvent) -> void:
	# Si on appuie sur ESC et que le jeu n'est pas déjà en pause...
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		_on_pause_pressed()
		get_tree().root.set_input_as_handled()  # Empêcher la propagation

# =============================================================================
# _process(delta)
# Vérifie à chaque frame si tous les ennemis sont morts et gère la porte
# =============================================================================
func _process(delta: float) -> void:
	# Si la victoire a déjà été déclenchée, ne rien faire
	if victory_triggered:
		return
	
	# -----
	# Trouver le joueur et sa salle actuelle
	# -----
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	
	var player = players[0]
	var new_player_room = 1 if player.global_position.x < 2560 else 2
	
	# -----
	# Si le joueur a changé de salle, réafficher la porte et gérer les masques
	# -----
	if new_player_room != current_player_room:
		current_player_room = new_player_room
		door_disappeared = false
		$Porte.visible = true
		$Porte.collision_layer = 2  # Réactiver les collisions
		
		# Gérer la visibilité des masques selon la salle actuelle
		if current_player_room == 1:
			$MaskRoom2.visible = true
			$MaskRoom1.visible = false
		else:
			$MaskRoom1.visible = true
			$MaskRoom2.visible = false
		
		print("Joueur entre dans la salle %d. Porte réaffichée." % current_player_room)
	
	# -----
	# Vérifier si tous les ennemis de la salle actuelle du joueur sont morts
	# -----
	if not door_disappeared:
		var all_enemies := get_tree().get_nodes_in_group("enemy")
		
		# Filtrer les ennemis selon la salle actuelle du joueur
		var enemies_current_room
		if current_player_room == 1:
			enemies_current_room = all_enemies.filter(func(enemy): return enemy.position.x < 2560)
		else:
			enemies_current_room = all_enemies.filter(func(enemy): return enemy.position.x >= 2560)
		
		# Si tous les ennemis de la salle actuelle sont morts, masquer la porte
		if enemies_current_room.is_empty():
			door_disappeared = true
			$Porte.visible = false
			$Porte.collision_layer = 0  # Désactiver les collisions
			print("Porte disparue ! Tous les ennemis de la salle %d sont éliminés." % current_player_room)
	
	# Compter le nombre d'ennemis restants dans le groupe "enemy"
	var enemies := get_tree().get_nodes_in_group("enemy")
	
	# Si aucun ennemi ne reste, déclarer la victoire
	if enemies.is_empty():
		victory_triggered = true
		print("Victoire ! Tous les ennemis sont éliminés !")
		get_tree().change_scene_to_file("res://scenes/menus/victory.tscn")