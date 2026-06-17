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
const SPEED = 200.0

# Durée d'invincibilité après avoir reçu un coup (en secondes)
const INVINCIBLE_DURATION = 1.0

# Distance de la hitbox d'attaque par rapport au joueur
const ATTACK_DISTANCE = 50.0

# Durée de l'attaque (temps où la hitbox reste active)
const ATTACK_DURATION = 0.2

# Cooldown entre deux attaques (temps minimum entre deux clics)
const ATTACK_COOLDOWN = 0.5

# Dégâts infligés par l'attaque
const ATTACK_DAMAGE = 1

# Vitesse du dash en pixels par seconde
const DASH_SPEED = 600.0

# Durée du dash en secondes
const DASH_DURATION = 0.3

# Cooldown du dash en secondes
const DASH_COOLDOWN = 0.8

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

# Est-ce que le joueur est en train de faire un dash ?
var is_dashing: bool = false

# Timer du dash (durée restante du dash)
var dash_timer: float = 0.0

# Timer du cooldown du dash
var dash_cooldown_timer: float = 0.0

# Direction du dash
var dash_direction: Vector2 = Vector2.ZERO

# Direction dans laquelle le joueur regarde (utile plus tard pour l'attaque)
# Vector2.DOWN = (0, 1) par défaut → le joueur regarde vers le bas au départ
var facing_direction: Vector2 = Vector2.DOWN

# Est-ce que le joueur est en train d'attaquer ?
var is_attacking: bool = false

# Timer de l'attaque (durée d'activation de la hitbox)
var attack_timer: float = 0.0

# Timer du cooldown d'attaque (temps avant de pouvoir attaquer à nouveau)
var attack_cooldown_timer: float = 0.0

# Référence à l'inventaire
var inventory: Control = null

# Référence à l'AnimatedSprite2D pour gérer les animations
@onready var animated_sprite: AnimatedSprite2D = $Visual

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
	
	# Initialiser la barre de vie
	_update_health_bar()
	
	# Définir le z_index du joueur pour être toujours au-dessus des cadavres
	z_index = 2
	
	# Connecter le signal de l'Area2D pour détecter les ennemis touchés
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
# Appelée à CHAQUE FRAME physique (par défaut 60 fois/seconde).
# "delta" = temps écoulé depuis la dernière frame (≈ 0.016 s à 60fps).
# On multiplie toujours les vitesses par delta pour que le jeu soit
# indépendant du framerate (sinon un PC à 30fps irait 2x plus lentement).
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_handle_dash(delta)
	if not is_dashing:
		_handle_movement()
	_handle_invincibility(delta)
	_handle_attack(delta)

# -----------------------------------------------------------------------------
# _unhandled_input(event)
# Gère les entrées clavier ponctuelles (ramassage)
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Touche de dash (configurable)
		if event.keycode == Settings.key_dash and not is_dashing and dash_cooldown_timer <= 0.0:
			_start_dash()
			get_viewport().set_input_as_handled()
			return
		
		# Touche de ramassage (configurable)
		if event.keycode == Settings.key_pickup:
			# Chercher les objets à proximité
			var items := get_tree().get_nodes_in_group("item")
			
			for item in items:
				# Vérifier si l'objet a la méthode pickup (objet ramassable)
				if item.has_method("pickup"):
					# Vérifier la distance
					var distance := global_position.distance_to(item.global_position)
					if distance <= 50.0:  # Portée de ramassage : 50 pixels
						# Ramasser l'objet
						var item_name: String = item.pickup()
						var inv := _get_inventory()
						if inv:
							inv.add_item(item_name)
						get_viewport().set_input_as_handled()
						break  # Ne ramasser qu'un objet à la fois

# -----------------------------------------------------------------------------
# _handle_movement()
# Lit les entrées clavier et déplace le joueur.
# Séparé dans sa propre fonction pour garder _physics_process() lisible.
# Utilise les touches ZQSD : Z=haut, Q=gauche, S=bas, D=droite
# -----------------------------------------------------------------------------
func _handle_movement() -> void:
	# On lit les touches depuis Settings
	var direction := Vector2(
		(-1.0 if Input.is_key_pressed(Settings.key_move_left) else 0.0) + (1.0 if Input.is_key_pressed(Settings.key_move_right) else 0.0),  # axe horizontal
		(-1.0 if Input.is_key_pressed(Settings.key_move_up) else 0.0) + (1.0 if Input.is_key_pressed(Settings.key_move_down) else 0.0)   # axe vertical
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
		
		# Jouer l'animation de marche
		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")
		
		# Inverser le sprite horizontalement selon la direction
		if direction.x < 0:
			animated_sprite.flip_h = true
		elif direction.x > 0:
			animated_sprite.flip_h = false
	else:
		# Le joueur ne bouge pas → animation idle
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")

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
	
	# Si le joueur est en train de faire un dash, il est intangible
	if is_dashing:
		return

	health -= amount

	# On déclenche l'invincibilité
	is_invincible = true
	invincible_timer = INVINCIBLE_DURATION

	print("Joueur PV : %d / %d" % [health, max_health])
	
	# Mettre à jour la barre de vie
	_update_health_bar()

	# Si les PV tombent à 0 ou moins → mort
	if health <= 0:
		_die()

# -----------------------------------------------------------------------------
# _die()
# Fonction PRIVÉE (préfixe "_") : ne devrait pas être appelée depuis l'extérieur.
# -----------------------------------------------------------------------------
func _die() -> void:
	# On charge l'écran de défaite.
	# change_scene_to_file() remplace toute la scène actuelle par game_over.tscn.
	get_tree().change_scene_to_file("res://scenes/menus/game_over.tscn")

# -----------------------------------------------------------------------------
# _update_health_bar()
# Met à jour la barre de vie en fonction des PV actuels du joueur
# -----------------------------------------------------------------------------
func _update_health_bar() -> void:
	$HealthBar.max_value = max_health
	$HealthBar.value = health

# -----------------------------------------------------------------------------
# _handle_attack(delta)
# Gère le système d'attaque : détection du clic, positionnement de la hitbox
# vers la souris, et timer d'activation.
# -----------------------------------------------------------------------------
func _handle_attack(delta: float) -> void:
	# Décrémenter le cooldown de l'attaque si nécessaire
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	
	# Si on est en train d'attaquer, on décrémente le timer
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			# L'attaque est terminée, on désactive la hitbox
			is_attacking = false
			$AttackArea.monitoring = false
			$AttackArea/AttackVisual.visible = false
		return
	
	# Détection du clic gauche pour lancer une attaque
	# On vérifie que le cooldown est écoulé avant de permettre une nouvelle attaque
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_attacking and attack_cooldown_timer <= 0.0:
		# Calculer la direction vers la souris
		var mouse_pos := get_global_mouse_position()
		var direction := (mouse_pos - global_position).normalized()
		
		# Positionner la hitbox d'attaque (grande sphère jaune) dans cette direction
		$AttackArea.position = direction * ATTACK_DISTANCE
		
		# Activer l'attaque
		is_attacking = true
		attack_timer = ATTACK_DURATION
		$AttackArea.monitoring = true
		$AttackArea/AttackVisual.visible = true
		
		# Réinitialiser le cooldown de l'attaque
		attack_cooldown_timer = ATTACK_COOLDOWN

# -----------------------------------------------------------------------------
# _on_attack_hit(body)
# Appelée quand la hitbox d'attaque touche un ennemi
# -----------------------------------------------------------------------------
func _on_attack_hit(body: Node2D) -> void:
	# Vérifier que c'est bien un ennemi et qu'il a une méthode take_damage
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(ATTACK_DAMAGE)
		print("Ennemi touché !")

# -----------------------------------------------------------------------------
# _handle_dash(delta)
# Gère le système de dash : durée du dash et cooldown
# -----------------------------------------------------------------------------
func _handle_dash(delta: float) -> void:
	# Si le joueur n'est pas en train de faire un dash, on gère juste le cooldown
	if not is_dashing:
		if dash_cooldown_timer > 0.0:
			dash_cooldown_timer -= delta
		return
	
	# On décrémente le timer du dash
	dash_timer -= delta
	
	if dash_timer > 0.0:
		# On continue le dash : déplacement rapide dans la direction du dash
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
		# Animation de marche pendant le dash
		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")
		# Clignotement léger pour indiquer l'intangibilité
		$Visual.modulate.a = 0.6 if fmod(dash_timer, 0.15) < 0.075 else 1.0
	else:
		# Le dash est terminé
		is_dashing = false
		dash_cooldown_timer = DASH_COOLDOWN
		$Visual.modulate.a = 1.0  # On remet la couleur opaque

# -----------------------------------------------------------------------------
# _start_dash()
# Lance un nouveau dash dans la direction actuelle du joueur
# -----------------------------------------------------------------------------
func _start_dash() -> void:
	is_dashing = true
	dash_timer = DASH_DURATION
	# On utilise la direction actuelle du joueur pour le dash
	dash_direction = facing_direction if facing_direction != Vector2.ZERO else Vector2.DOWN
	print("Dash lancé dans la direction : ", dash_direction)
