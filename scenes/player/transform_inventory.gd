extends Node
class_name TransformInventory
# =============================================================================
# TransformInventory
# Nœud à ajouter comme ENFANT du slime (player). Gère 3 slots de transformation
# FIXES, jamais vides : chaque slot contient une PlayableForm, par défaut le
# slime de base. Pilote le TransformHandler pour changer de forme.
#
# - On démarre sur le slot 1, tous les slots en slime de base.
# - devour(form) : la forme mangée remplit le SLOT ACTIF et le slime s'y transforme.
# - switch_to / next / prev / slots 1..3 : change de slot actif (avec cooldown).
# - G (clear_active_slot) : remet le slot actif en slime de base.
# - reset_for_new_run (mort) : tous les slots reviennent en slime de base, slot 1.
#
# L'UI n'est PAS gérée ici : on émet inventory_changed à chaque modification.
# =============================================================================

# Émis à chaque modification (devour, switch, G, reset).
# Transmet l'état des slots (Array[PlayableForm], jamais vide) et l'index actif.
signal inventory_changed(forms: Array, active_index: int)

# Handler de transformation (étape 4) qui applique réellement les formes.
@export var handler: TransformHandler
# Forme de base : le slime nu, remplissage par défaut de chaque slot.
@export var base_form: PlayableForm
# Délai minimal (secondes) entre deux switchs, anti-spam.
@export var switch_cooldown: float = 0.25

# Nombre de slots fixes.
const SLOT_COUNT := 3

# Contenu des slots (taille SLOT_COUNT, jamais d'élément vide).
var slots: Array[PlayableForm] = []
# Index du slot actif (0..SLOT_COUNT-1).
var active_index: int = 0

var _switch_timer: float = 0.0

# Navigation : touches lettres en keycode logique (intuitif en AZERTY).
const _ACTION_LETTERS := {
	"transform_prev": KEY_A,
	"transform_next": KEY_R,
	"transform_base": KEY_G,
}
# Slots directs : rangée de chiffres par position PHYSIQUE (robuste en AZERTY).
const _ACTION_SLOTS := [KEY_1, KEY_2, KEY_3]


func _ready() -> void:
	_ensure_input_actions()

	# Branche devour sur le ramassage des drops : tout objet portant le signal
	# forme_ramassee (item.gd) nous prévient à sa prise. On réutilise ainsi le
	# mécanisme de ramassage existant sans le remplacer.
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group("item"):
		_connect_item(node)

	# 3 slots, tous en slime de base. On démarre sur le slot 1.
	_fill_with_base()
	active_index = 0
	_apply(slots[active_index])
	_emit_changed()


func _process(delta: float) -> void:
	if _switch_timer > 0.0:
		_switch_timer -= delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("transform_next"):
		switch_next()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("transform_prev"):
		switch_prev()
		get_viewport().set_input_as_handled()
		return
	# G : vide le slot courant (remis en slime de base).
	if event.is_action_pressed("transform_base"):
		clear_active_slot()
		get_viewport().set_input_as_handled()
		return
	# Slots directs 1..SLOT_COUNT.
	for i in range(SLOT_COUNT):
		if event.is_action_pressed("transform_slot_%d" % (i + 1)):
			switch_to(i)
			get_viewport().set_input_as_handled()
			return


# === SLOTS ===

# Mange une forme : elle remplit le SLOT ACTIF et le slime s'y transforme.
func devour(form: PlayableForm) -> void:
	if form == null:
		return
	# Copie profonde : modifier la forme en jeu ne contamine jamais la ressource
	# d'origine (.tres) ni les autres entités.
	slots[active_index] = form.duplicate(true)
	_apply(slots[active_index])
	_emit_changed()


# Change de slot actif (borné). Respecte le cooldown anti-spam.
func switch_to(index: int) -> void:
	if _switch_timer > 0.0:
		return  # switch demandé pendant le cooldown : ignoré
	active_index = clampi(index, 0, SLOT_COUNT - 1)
	_switch_timer = switch_cooldown
	_apply(slots[active_index])
	_emit_changed()


# Slot suivant (wrap).
func switch_next() -> void:
	switch_to((active_index + 1) % SLOT_COUNT)


# Slot précédent (wrap).
func switch_prev() -> void:
	switch_to((active_index - 1 + SLOT_COUNT) % SLOT_COUNT)


# G : remet le slot actif en slime de base et s'y transforme.
func clear_active_slot() -> void:
	slots[active_index] = base_form
	_switch_timer = switch_cooldown
	_apply(base_form)
	_emit_changed()


# Réinitialisation roguelike (mort) : tous les slots repassent en slime de base
# et on revient au slot 1. État identique à un début de partie.
func reset_for_new_run() -> void:
	_fill_with_base()
	active_index = 0
	_apply(slots[active_index])
	_emit_changed()


# Forme actuellement incarnée (contenu du slot actif). Jamais null en usage normal.
func get_active_form() -> PlayableForm:
	return slots[active_index]


# Vrai si le slot actif n'est PAS un slime de base (le joueur est transformé).
func is_transformed() -> bool:
	if base_form == null:
		return false
	var f: PlayableForm = slots[active_index]
	return f != null and f.id != base_form.id


# === CAPACITÉS (relais form-agnostiques) ===
# À appeler depuis le contrôleur du slime sur ses entrées attaque / compétence.

func use_attack() -> void:
	if handler:
		handler.use_attack()

func use_ability() -> void:
	if handler:
		handler.use_ability()


# === SIGNAL ===

func _emit_changed() -> void:
	inventory_changed.emit(slots, active_index)

# Réémet l'état courant sans rien modifier (synchro initiale d'une UI).
func emit_state() -> void:
	_emit_changed()


# === INTERNE ===

func _apply(form: PlayableForm) -> void:
	if handler and form:
		handler.apply(form)

func _fill_with_base() -> void:
	slots.clear()
	for _i in range(SLOT_COUNT):
		slots.append(base_form)


# === RAMASSAGE DES DROPS ===

func _on_node_added(node: Node) -> void:
	_connect_item(node)

func _connect_item(node: Node) -> void:
	# Tout objet exposant forme_ramassee (item.gd) est connecté à devour.
	if node.has_signal("forme_ramassee") and not node.forme_ramassee.is_connected(_on_form_devoured):
		node.forme_ramassee.connect(_on_form_devoured)

func _on_form_devoured(form: PlayableForm) -> void:
	# Les drops sans forme (âmes classiques) émettent null : devour les ignore.
	devour(form)


# === ENTRÉES ===

# Crée les actions de transformation si le projet ne les définit pas déjà.
func _ensure_input_actions() -> void:
	for action_name in _ACTION_LETTERS:
		_ensure_action(action_name, _ACTION_LETTERS[action_name], false)
	for i in _ACTION_SLOTS.size():
		_ensure_action("transform_slot_%d" % (i + 1), _ACTION_SLOTS[i], true)

func _ensure_action(action_name: String, key: Key, physical: bool) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	if physical:
		ev.physical_keycode = key
	else:
		ev.keycode = key
	InputMap.action_add_event(action_name, ev)
