# =============================================================================
# player.gd
# Script attaché au nœud Player (CharacterBody2D)
# =============================================================================

# "extends CharacterBody2D" signifie que ce script HÉRITE de la classe
# CharacterBody2D de Godot. Cela nous donne accès à :
#   - la propriété "velocity" (vecteur de déplacement)
#   - la méthode "move_and_slide()" (gestion physique + collisions)
extends CharacterBody2D

# -----------------------------------------------------------------------------
# CONSTANTES
# Les constantes ne changent jamais pendant le jeu (mot-clé "const").
# On les écrit en MAJUSCULES par convention.
# -----------------------------------------------------------------------------

# Vitesse de déplacement du joueur en pixels par seconde
const SPEED = 150.0

# Durée d'invincibilité après avoir reçu un coup (en secondes)
const INVINCIBLE_DURATION = 1.0

# -----------------------------------------------------------------------------
# VARIABLES D'ÉTAT
# Ces valeurs changent pendant le jeu (mot-clé "var").
# ":= " est l'affectation avec inférence de type (Godot devine le type).
# -----------------------------------------------------------------------------

# Points de vie actuels
var health: int = 3

# Points de vie maximum
var max_health: int = 3

# Est-ce que le joueur est en ce moment invincible ?
var is_invincible: bool = false

# Compteur interne qui mesure le temps d'invincibilité restant
var invincible_timer: float = 0.0

# Direction dans laquelle le joueur regarde (utile plus tard pour l'attaque)
# Vector2.DOWN = (0, 1) par défaut → le joueur regarde vers le bas au départ
var facing_direction: Vector2 = Vector2.DOWN

# -----------------------------------------------------------------------------
# _ready()
# Appelée UNE SEULE FOIS quand le nœud entre dans la scène.
# C'est l'équivalent d'un constructeur / d'une initialisation.
# -----------------------------------------------------------------------------
func _ready() -> void:
	# On ajoute le joueur au groupe "player".
	# Les groupes sont des étiquettes : n'importe quel autre script peut faire
	# get_tree().get_first_node_in_group("player") pour trouver ce nœud.
	add_to_group("player")

# -----------------------------------------------------------------------------
# _physics_process(delta)
# Appelée à CHAQUE FRAME physique (par défaut 60 fois/seconde).
# "delta" = temps écoulé depuis la dernière frame (≈ 0.016 s à 60fps).
# On multiplie toujours les vitesses par delta pour que le jeu soit
# indépendant du framerate (sinon un PC à 30fps irait 2x plus lentement).
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_invincibility(delta)

# -----------------------------------------------------------------------------
# _handle_movement()
# Lit les entrées clavier et déplace le joueur.
# Séparé dans sa propre fonction pour garder _physics_process() lisible.
# -----------------------------------------------------------------------------
func _handle_movement() -> void:
	# Input.get_axis("négatif", "positif") retourne :
	#   -1.0 si "négatif" est pressé
	#    0.0 si rien n'est pressé (ou les deux)
	#   +1.0 si "positif" est pressé
	# "ui_left"/"ui_right" = flèches gauche/droite (actions par défaut de Godot)
	var direction := Vector2(
		Input.get_axis("ui_left", "ui_right"),   # axe horizontal
		Input.get_axis("ui_up",   "ui_down")     # axe vertical
	)

	# Si le joueur appuie sur une direction...
	if direction != Vector2.ZERO:
		# .normalized() garantit que la vitesse en diagonale est identique
		# à la vitesse en ligne droite. Sans ça, aller en diagonale serait
		# ~1.41x plus rapide (Pythagore : √(1²+1²) ≈ 1.41).
		direction = direction.normalized()

		# On mémorise la dernière direction pour savoir où le joueur regarde.
		# Utile plus tard pour placer une hitbox d'attaque dans la bonne direction.
		facing_direction = direction

	# On assigne la vélocité. "velocity" est une propriété de CharacterBody2D.
	# Elle représente le déplacement souhaité par frame.
	velocity = direction * SPEED

	# move_and_slide() utilise "velocity" pour déplacer le nœud.
	# Elle gère automatiquement les collisions :
	#   - le joueur glisse le long des murs au lieu de se bloquer
	#   - elle corrige "velocity" si une collision a lieu
	# NOTE : on utilise un CircleShape2D pour la collision du joueur (dans le .tscn)
	# car un rectangle a des "coins" qui accrochent les murs → le bug de collage.
	# Un cercle glisse parfaitement sur n'importe quel angle de mur.
	move_and_slide()

# -----------------------------------------------------------------------------
# _handle_invincibility(delta)
# Gère le clignotement et le timer d'invincibilité.
# -----------------------------------------------------------------------------
func _handle_invincibility(delta: float) -> void:
	if not is_invincible:
		return  # Rien à faire si le joueur n'est pas invincible

	# On diminue le timer d'invincibilité
	invincible_timer -= delta

	# Clignotement visuel : on alterne la transparence en fonction du temps
	# "fmod" = modulo sur float. fmod(temps, 0.2) oscille entre 0 et 0.2 en boucle.
	# Si l'oscillation est < 0.1 → semi-transparent, sinon → opaque.
	$Visual.modulate.a = 0.3 if fmod(invincible_timer, 0.2) < 0.1 else 1.0

	# Quand le timer atteint 0, l'invincibilité est terminée
	if invincible_timer <= 0.0:
		is_invincible = false
		$Visual.modulate.a = 1.0  # On remet la couleur opaque

# -----------------------------------------------------------------------------
# take_damage(amount)
# Fonction PUBLIQUE : appelée par d'autres scripts pour blesser le joueur.
# "Public" = accessible depuis n'importe quel autre script.
# -----------------------------------------------------------------------------
func take_damage(amount: int) -> void:
	# Si le joueur est déjà invincible, on ignore le coup
	if is_invincible:
		return

	health -= amount

	# On déclenche l'invincibilité
	is_invincible = true
	invincible_timer = INVINCIBLE_DURATION

	print("Joueur PV : %d / %d" % [health, max_health])

	# Si les PV tombent à 0 ou moins → mort
	if health <= 0:
		_die()

# -----------------------------------------------------------------------------
# _die()
# Fonction PRIVÉE (préfixe "_") : ne devrait pas être appelée depuis l'extérieur.
# -----------------------------------------------------------------------------
func _die() -> void:
	print("Game Over !")
	# get_tree() donne accès à l'arbre de scène complet.
	# reload_current_scene() recharge la scène depuis le début.
	get_tree().reload_current_scene()
