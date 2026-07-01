# =============================================================================
# run_timer.gd  (autoload : RunTimer)
# Affichage du compte à rebours de run en HAUT À GAUCHE de l'écran.
# Autoload (CanvasLayer) : reste à l'écran d'une salle à l'autre sans avoir à
# l'ajouter dans chaque salle. Purement de l'AFFICHAGE : le décompte réel vit
# dans GameState (run_time_left / run_time_expired).
# Masqué hors gameplay (menu, victoire...) : visible seulement si un joueur est
# présent dans la scène.
# =============================================================================
extends CanvasLayer

## Seuil (secondes) sous lequel le timer passe en rouge.
@export var low_time_threshold: float = 30.0

@onready var label: Label = $Label


func _process(_delta: float) -> void:
	var gs := get_node_or_null("/root/GameState")
	var has_player := get_tree().get_first_node_in_group("player") != null
	visible = gs != null and has_player
	if not visible:
		return

	var t: float = maxf(gs.run_time_left, 0.0)
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	label.text = "%d:%02d" % [minutes, seconds]
	label.modulate = Color(1.0, 0.3, 0.3) if t <= low_time_threshold else Color.WHITE
