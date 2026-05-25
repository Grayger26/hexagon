## SpellData.gd
## Static data for one spell. One .tres per spell.
class_name SpellData
extends Resource

@export var id:         String = ""
@export var spell_name: String = ""
@export var school:     String = ""   ## "fire" | "air" | "water" | "earth"
@export var level:      int    = 1    ## 1–5
@export var mana_cost:  int    = 1

## "damage" | "buff" | "debuff" | "heal" | "summon" | "terrain" | "map"
@export var effect_type:   String = "damage"
@export var base_value:    float  = 0.0
@export var power_scaling: float  = 1.0
@export var duration:      int    = 0    ## rounds; 0 = instant, -1 = whole combat
## "single_enemy"|"single_ally"|"aoe_ground"|"all_enemies"|"all_allies"|"self"|"map_tile"
@export var target_type:   String = "single_enemy"
@export var aoe_radius:    int    = 0

@export var stat_affected: String = ""
@export var stat_modifier: float  = 0.0
@export var expert_value:  float  = 0.0

@export var wisdom_required: int = 0

@export var icon:           Texture2D = null
@export var cast_animation: String    = ""
@export var description:    String    = ""

## mastery: 0=none 1=Basic 2=Advanced 3=Expert
func calculate_value(spell_power: int, mastery: int) -> float:
	var val := base_value + power_scaling * spell_power
	match mastery:
		1: val *= 1.25
		2: val *= 1.50
		3: val = expert_value if expert_value > 0.0 else val * 1.75
	return val
