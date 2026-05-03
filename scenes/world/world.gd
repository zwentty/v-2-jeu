# =============================================================================
# world.gd
# Script attaché au nœud World (Node2D)
# Crée la région de navigation au RUNTIME et vérifie la victoire.
# =============================================================================
extends Node2D

# Variable pour éviter de vérifier plusieurs fois la victoire
var victory_triggered: bool = false

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
	# Murs = 32px d'épaisseur de chaque côté.
	# Zone marchable = (32, 32) → (2528, 1408)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(32, 32),
		Vector2(2528, 32),
		Vector2(2528, 1408),
		Vector2(32, 1408),
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

# =============================================================================
# _process(delta)
# Vérifie à chaque frame si tous les ennemis sont morts
# =============================================================================
func _process(delta: float) -> void:
	# Si la victoire a déjà été déclenchée, ne rien faire
	if victory_triggered:
		return
	
	# Compter le nombre d'ennemis restants dans le groupe "enemy"
	var enemies := get_tree().get_nodes_in_group("enemy")
	
	# Si aucun ennemi ne reste, déclarer la victoire
	if enemies.is_empty():
		victory_triggered = true
		print("Victoire ! Tous les ennemis sont éliminés !")
		get_tree().change_scene_to_file("res://scenes/menus/victory.tscn")