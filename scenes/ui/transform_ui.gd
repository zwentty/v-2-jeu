extends Control
class_name TransformUI
# =============================================================================
# TransformUI — affichage minimal de l'inventaire de transformations.
#
# S'abonne au signal inventory_changed du TransformInventory et, à chaque
# émission, reconstruit une rangée d'icônes (PlayableForm.icon) dans l'ordre de
# l'inventaire, la forme active mise en évidence (opacité plus forte).
#
# L'UI ne fait QU'AFFICHER : elle lit uniquement ce que transporte le signal
# (liste des formes + index actif), sans aller fouiller dans la logique de
# l'inventaire, et ne déclenche aucun switch.
# =============================================================================

# Taille d'affichage de chaque icône.
const ICON_SIZE := Vector2(96, 96)
# Opacité des icônes : forme active vs. formes inactives.
const ALPHA_ACTIVE := 1.0
const ALPHA_INACTIVE := 0.4

# Inventaire source. Optionnel : si laissé vide, on le retrouve via le joueur.
@export var inventory: Node

var _row: HBoxContainer


func _ready() -> void:
	_row = get_node_or_null("Row")
	if _row == null:
		# Crée une rangée centrée si la scène n'en fournit pas.
		_row = HBoxContainer.new()
		_row.name = "Row"
		_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_row.add_theme_constant_override("separation", 16)
		_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_row)

	# Différé : le joueur (et donc son TransformInventory) n'est pas forcément
	# prêt quand l'UI fait son _ready selon l'ordre des nœuds dans la salle.
	_connect_inventory.call_deferred()


func _connect_inventory() -> void:
	var inv := _resolve_inventory()
	if inv and inv.has_signal("inventory_changed"):
		inv.inventory_changed.connect(_on_inventory_changed)
		# Première peinture : on demande à l'inventaire de réémettre son état,
		# plutôt que de lire ses variables internes.
		if inv.has_method("emit_state"):
			inv.emit_state()


# Reconstruit la rangée d'icônes à partir des données du signal.
func _on_inventory_changed(forms: Array, active_index: int) -> void:
	# Vider la rangée (retrait immédiat pour éviter tout doublon visuel).
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()

	# Inventaire vide (slime sous base_form) : aucune icône affichée.
	for i in range(forms.size()):
		var form: PlayableForm = forms[i]
		var icon := TextureRect.new()
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if form != null:
			icon.texture = form.icon
		# Mise en évidence de la forme active via l'opacité.
		icon.modulate.a = ALPHA_ACTIVE if i == active_index else ALPHA_INACTIVE
		_row.add_child(icon)


# Retourne l'inventaire explicitement assigné, sinon le cherche sous le joueur.
func _resolve_inventory() -> Node:
	if inventory:
		return inventory
	var p := get_tree().get_first_node_in_group("player")
	if p:
		for c in p.get_children():
			if c.has_signal("inventory_changed"):
				return c
	return null
