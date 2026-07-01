extends Resource
class_name PlayableForm
# =============================================================================
# PlayableForm — définition d'une forme jouable.
# Resource de données pure : regroupe tout ce qui caractérise une forme que le
# joueur peut incarner (identité, visuel, attaque, compétence, statistiques).
# =============================================================================

## Identifiant unique et stable de la forme (ex: &"slime", &"soldat").
@export var id: StringName = &""

## Nom affiché à l'écran (UI, menus).
@export var display_name: String = ""

## Animations du sprite de la forme (idle, walk, etc.).
@export var sprite_frames: SpriteFrames

## Animations de MORT de la forme (doit contenir une anim "death", non bouclée).
## Optionnel : si absent, aucune animation de mort n'est jouée pour cette forme.
@export var death_frames: SpriteFrames

## Scène de l'attaque principale instanciée par cette forme.
@export var attack_scene: PackedScene

## Scène de la compétence/capacité spéciale de cette forme.
@export var ability_scene: PackedScene

## Bloc de statistiques (PV, vitesse, dégâts, poids) de la forme.
@export var stats: StatBlock

## Icône représentant la forme (UI de sélection, HUD).
@export var icon: Texture2D
