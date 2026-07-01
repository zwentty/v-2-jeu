# =============================================================================
# death_sequence.gd
# Cinématique de mort du slime. Scène autonome (CanvasLayer) instanciée à la
# mort et superposée au jeu. Découplée du slime : elle reçoit seulement un
# Node2D (la cible à cadrer) et sa Camera2D via start().
#
# Déroulé, orchestré par UN AnimationPlayer (une seule timeline synchronisée) :
#   1. get_tree().paused = true  -> le GAMEPLAY gèle. Cette séquence (racine +
#      enfants) est en PROCESS_MODE_ALWAYS, donc elle continue de tourner.
#   2. Zoom progressif de la caméra sur le perso (rapide puis ralenti, ease-out).
#   3. Iris noir circulaire qui se referme, centré sur la position ÉCRAN du perso.
#   4. « Game Over » en fondu.
#   5. Bouton « Rejouer » en fondu, cliquable pendant la pause.
#   6. Clic Rejouer -> retire la pause et relance une run propre.
#
# La timeline est construite PAR CODE à partir des paramètres @export ci-dessous,
# de sorte que TOUT le game feel se règle depuis l'inspecteur, sans toucher au
# code. (Si tu préfères clé-framer la timeline à la main dans l'éditeur, dis-le :
# on remplace _build_animation() par une Animation statique dans la .tscn.)
# =============================================================================
extends CanvasLayer

# --- Paramètres réglables dans l'inspecteur (game feel) -----------------------
## Durée du zoom caméra (secondes).
@export var zoom_duration: float = 0.8
## Facteur de zoom final (multiplie le zoom de départ de la caméra).
@export var final_zoom_factor: float = 2.5
## Durée de fermeture de l'iris (secondes).
@export var iris_duration: float = 0.9
## Rayon de départ de l'iris (assez grand pour tout révéler, coins compris).
@export var iris_start_radius: float = 2.5
## Douceur du bord du cercle (smoothstep).
@export var edge_softness: float = 0.05
## Délai après écran noir avant l'apparition du « Game Over ».
@export var text_delay: float = 0.25
## Délai après le « Game Over » avant l'apparition du bouton « Rejouer ».
@export var button_delay: float = 0.4
## Durée des fondus du texte et du bouton.
@export var fade_duration: float = 0.4
## Scène à charger pour relancer une nouvelle run (début de run).
@export_file("*.tscn") var restart_scene: String = "res://scenes/world/salle_1.tscn"

# --- Références internes -------------------------------------------------------
@onready var iris: ColorRect = $IrisRect
@onready var label: Label = $Center/VBox/GameOverLabel
@onready var button: Button = $Center/VBox/RejouerButton
@onready var anim: AnimationPlayer = $AnimationPlayer

var _target: Node2D = null
var _camera: Camera2D = null
var _start_zoom: Vector2 = Vector2.ONE

# Piloté par l'AnimationPlayer (0->1, ease-out), appliqué à la caméra dans
# _process. On passe par une variable-proxy car la caméra n'est PAS enfant de
# cette scène : l'AnimationPlayer ne peut pas cibler son NodePath directement.
var zoom_t: float = 0.0


func _ready() -> void:
	button.pressed.connect(_on_rejouer_pressed)


# -----------------------------------------------------------------------------
# start(target, camera)
# Point d'entrée appelé par le slime à sa mort. target = nœud à cadrer,
# camera = sa Camera2D. Lance la pause et la timeline.
# -----------------------------------------------------------------------------
func start(target: Node2D, camera: Camera2D) -> void:
	_target = target
	_camera = camera
	if _camera:
		_start_zoom = _camera.zoom
		# On exempte la caméra de la pause pour que son zoom/transform se mette
		# bien à jour pendant le gel du jeu (ceinture + bretelles avec
		# force_update_scroll dans _process).
		_camera.process_mode = Node.PROCESS_MODE_ALWAYS

	# État initial de l'overlay.
	var mat := iris.material as ShaderMaterial
	mat.set_shader_parameter("radius", iris_start_radius)
	mat.set_shader_parameter("softness", edge_softness)
	label.modulate.a = 0.0
	button.modulate.a = 0.0
	button.disabled = true
	_update_iris_center() # centre l'iris dès la première frame

	_build_animation()

	get_tree().paused = true
	anim.play("death")


# -----------------------------------------------------------------------------
# _process : applique le zoom piloté par la timeline et garde l'iris centré sur
# la position ÉCRAN du perso (qui bouge quand la caméra zoome / est clampée).
# -----------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if _camera and is_instance_valid(_camera):
		_camera.zoom = _start_zoom.lerp(_start_zoom * final_zoom_factor, zoom_t)
		# Force la caméra à pousser sa transform au viewport MALGRÉ la pause,
		# pour que get_canvas_transform() reflète le zoom courant.
		_camera.force_update_scroll()
	_update_iris_center()


# Convertit la position MONDE du perso en position ÉCRAN normalisée (0..1) et la
# passe au shader. On ne centre PAS bêtement au milieu de l'écran.
func _update_iris_center() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var vp := get_viewport()
	var screen_pos := vp.get_canvas_transform() * _target.global_position
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var center := Vector2(screen_pos.x / size.x, screen_pos.y / size.y)
	(iris.material as ShaderMaterial).set_shader_parameter("center", center)


# -----------------------------------------------------------------------------
# _build_animation()
# Construit la timeline complète (une Animation "death") à partir des @export.
# Tous les chemins ciblent des nœuds LOCAUX de cette scène (résolus depuis le
# root_node de l'AnimationPlayer = cette scène), sauf le zoom qui passe par la
# variable-proxy zoom_t.
# -----------------------------------------------------------------------------
func _build_animation() -> void:
	# Bornes temporelles de chaque étape.
	var iris_start := zoom_duration
	var iris_end := iris_start + iris_duration
	var label_start := iris_end + text_delay
	var button_start := label_start + button_delay
	var total := button_start + fade_duration

	var a := Animation.new()
	a.length = total

	# --- Piste zoom : zoom_t 0->1, ease-out (échantillonné pour garantir la courbe).
	var t_zoom := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_zoom, ".:zoom_t")
	a.value_track_set_update_mode(t_zoom, Animation.UPDATE_CONTINUOUS)
	var steps := 8
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var eased := 1.0 - pow(1.0 - f, 3.0) # ease-out cubique : rapide puis lent
		a.track_insert_key(t_zoom, zoom_duration * f, eased)

	# --- Piste iris : radius grand -> légèrement négatif (garantit un noir plein).
	var t_iris := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_iris, "IrisRect:material:shader_parameter/radius")
	a.value_track_set_update_mode(t_iris, Animation.UPDATE_CONTINUOUS)
	a.track_insert_key(t_iris, iris_start, iris_start_radius)
	a.track_insert_key(t_iris, iris_end, -edge_softness - 0.01)

	# --- Piste texte « Game Over » : fondu d'opacité.
	var t_label := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_label, "Center/VBox/GameOverLabel:modulate:a")
	a.value_track_set_update_mode(t_label, Animation.UPDATE_CONTINUOUS)
	a.track_insert_key(t_label, label_start, 0.0)
	a.track_insert_key(t_label, label_start + fade_duration, 1.0)

	# --- Piste bouton « Rejouer » : fondu d'opacité.
	var t_btn := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t_btn, "Center/VBox/RejouerButton:modulate:a")
	a.value_track_set_update_mode(t_btn, Animation.UPDATE_CONTINUOUS)
	a.track_insert_key(t_btn, button_start, 0.0)
	a.track_insert_key(t_btn, button_start + fade_duration, 1.0)

	# --- Fin de timeline : rendre le bouton cliquable.
	var t_call := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(t_call, ".")
	a.track_insert_key(t_call, button_start + fade_duration, {
		"method": &"_enable_button",
		"args": [],
	})

	var lib := AnimationLibrary.new()
	lib.add_animation(&"death", a)
	# Remplace la librairie par défaut si elle existe déjà.
	if anim.has_animation_library(""):
		anim.remove_animation_library("")
	anim.add_animation_library("", lib)


func _enable_button() -> void:
	button.disabled = false


# -----------------------------------------------------------------------------
# Clic « Rejouer » : on RETIRE d'abord la pause, puis on relance une run propre.
# Ta run = séquence salle_1..salle_4 pilotée par GameState : une nouvelle run =
# reset de GameState + rechargement de la salle de départ (pas reload de la
# salle courante). Recrée un joueur neuf (forme de base, inventaire vide).
# -----------------------------------------------------------------------------
func _on_rejouer_pressed() -> void:
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("reset"):
		gs.reset()
	get_tree().change_scene_to_file(restart_scene)
