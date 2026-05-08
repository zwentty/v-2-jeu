# =============================================================================
# steering.gd
# Classe utilitaire pure pour les comportements de mouvement (steering behaviors)
# 
# Cette classe ne s'attache à aucun nœud. Chaque fonction est statique et retourne
# une direction normalisée (Vector2) que l'ennemi peut combiner avec d'autres forces.
#
# BEHAVIORS DISPONIBLES :
# - Seek : Se déplace vers une cible
# - Flee : S'éloigne d'une cible
# - Orbit : Tourne autour d'une cible à un rayon donné
# - Wander : Déviation aléatoire pour un mouvement plus naturel
# - Separate : Repousse les voisins pour éviter le regroupement (clumping)
# - Arrive : Comme Seek mais ralentit en approchant
# =============================================================================

class_name Steering

# =============================================================================
# SEEK - Se déplace vers une cible
# Retourne la direction normalisée de current_pos vers target_pos
# =============================================================================
static func seek(current_pos: Vector2, target_pos: Vector2) -> Vector2:
	return (target_pos - current_pos).normalized()

# =============================================================================
# FLEE - S'éloigne d'une cible
# Retourne la direction normalisée opposée à la cible
# =============================================================================
static func flee(current_pos: Vector2, target_pos: Vector2) -> Vector2:
	return (current_pos - target_pos).normalized()

# =============================================================================
# ORBIT - Tourne autour d'une cible à un rayon donné
# 
# Paramètres :
# - current_pos : Position actuelle de l'agent
# - target_pos : Position de la cible (centre de l'orbite)
# - radius : Rayon de l'orbite (distance idéale à maintenir)
# - angle : Angle actuel sur l'orbite (en radians)
#
# Cette fonction fait deux choses :
# 1. Calcule un point sur l'orbite et dirige l'agent vers ce point
# 2. Applique une correction radiale pour maintenir le bon rayon
# =============================================================================
static func orbit(
	current_pos: Vector2,
	target_pos: Vector2,
	radius: float,
	angle: float
) -> Vector2:
	# Point cible sur l'orbite (cercle parfait)
	var orbit_point = target_pos + Vector2(cos(angle), sin(angle)) * radius
	var to_orbit = (orbit_point - current_pos)
	
	# Correction radiale : si trop loin/proche du bon rayon, se recadre
	# Plus on est loin du rayon idéal, plus la force de correction est forte
	var dist = current_pos.distance_to(target_pos)
	var radial = (target_pos - current_pos).normalized() * (dist - radius) * 0.5
	
	# Combiner les deux forces
	return (to_orbit.normalized() + radial).normalized()

# =============================================================================
# WANDER - Déviation aléatoire légère
# 
# Ajoute un comportement "errant" pour éviter un mouvement trop robotique.
# Le wander_angle doit être incrémenté à l'extérieur (dans la boucle principale).
#
# Paramètres :
# - current_velocity : Vélocité actuelle de l'agent
# - wander_angle : Angle de déviation (modifié progressivement)
# - strength : Force de la déviation (0.0 = pas de déviation, 1.0 = forte déviation)
# =============================================================================
static func wander(current_velocity: Vector2, wander_angle: float, strength: float = 0.4) -> Vector2:
	# Cercle de "wander" devant l'agent
	var circle_center = current_velocity.normalized()
	# Déplacement sur le cercle selon wander_angle
	var displacement = Vector2(cos(wander_angle), sin(wander_angle)) * strength
	return (circle_center + displacement).normalized()

# =============================================================================
# SEPARATE - Repousse l'agent de ses voisins
# 
# Évite le regroupement (clumping) en créant une force qui repousse l'agent
# de tous les voisins proches. Plus un voisin est proche, plus la force est forte.
#
# Paramètres :
# - current_pos : Position actuelle de l'agent
# - neighbors : Array d'agents voisins (avec global_position)
# - separation_radius : Distance en dessous de laquelle on repousse
# - separation_force : Multiplicateur de la force de répulsion
# =============================================================================
static func separate(
	current_pos: Vector2,
	neighbors: Array,
	separation_radius: float,
	separation_force: float
) -> Vector2:
	var sep = Vector2.ZERO
	
	for neighbor in neighbors:
		if neighbor == null:
			continue
		
		var dist = current_pos.distance_to(neighbor.global_position)
		
		# Si le voisin est dans le rayon de séparation
		if dist < separation_radius and dist > 0.01:
			# Direction pour s'éloigner du voisin
			var push = (current_pos - neighbor.global_position).normalized()
			# Plus le voisin est proche, plus la force est forte
			# Formule : force inversement proportionnelle à la distance
			sep += push * (1.0 - dist / separation_radius)
	
	# Normaliser et appliquer le multiplicateur de force
	if sep != Vector2.ZERO:
		sep = sep.normalized() * separation_force
	
	return sep

# =============================================================================
# ARRIVE - Se déplace vers une cible en ralentissant à l'approche
# 
# Comme Seek mais réduit progressivement la vitesse en entrant dans le slow_radius.
# Permet d'arriver en douceur sans dépasser la cible.
#
# Paramètres :
# - current_pos : Position actuelle de l'agent
# - target_pos : Position de la cible
# - slow_radius : Rayon dans lequel on commence à ralentir
# - move_speed : Vitesse maximale de déplacement
#
# Retourne : Vélocité (direction × vitesse), pas juste une direction normalisée
# =============================================================================
static func arrive(
	current_pos: Vector2,
	target_pos: Vector2,
	slow_radius: float,
	move_speed: float
) -> Vector2:
	var to_target = target_pos - current_pos
	var dist = to_target.length()
	
	# Si très proche, arrêter
	if dist < 1.0:
		return Vector2.ZERO
	
	# Dans le slow_radius on ralentit progressivement
	# En dehors, vitesse maximale
	var speed = move_speed if dist > slow_radius else move_speed * (dist / slow_radius)
	
	return to_target.normalized() * speed
