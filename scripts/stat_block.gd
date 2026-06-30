extends Resource
class_name StatBlock
# =============================================================================
# StatBlock — bloc de statistiques réutilisable.
# Resource de données pure : décrit les caractéristiques chiffrées d'une forme
# jouable (ou potentiellement d'une entité). Référencé par PlayableForm.stats.
# =============================================================================

## Points de vie maximum de la forme.
@export var max_health: float = 25.0

## Vitesse de déplacement en pixels/seconde.
@export var move_speed: float = 200.0

## Dégâts de base infligés par les attaques de la forme.
@export var damage: float = 3.0

## Poids de la forme (influence inertie, knockback, etc.).
@export var weight: float = 1.0
