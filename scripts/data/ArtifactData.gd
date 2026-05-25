## ArtifactData.gd
## Static data for one artifact. One .tres per artifact.
class_name ArtifactData
extends Resource

@export var id:            String = ""
@export var artifact_name: String = ""
## "treasure" | "minor" | "major" | "relic" | "combination"
@export var tier:          String = "treasure"
## "head"|"neck"|"torso"|"hand_left"|"hand_right"|"ring_left"|"ring_right"|"feet"|"misc"
@export var slot:          String = "misc"

## stat_name -> int bonus. Keys: "attack" "defense" "spell_power" "knowledge"
## "morale" "luck" "movement" "mana" "gold_per_day" etc.
@export var stat_bonuses: Dictionary = {}

@export var special_ability:      String    = ""
@export var special_ability_desc: String    = ""
@export var combination_parts:    Array[String] = []
@export var icon:                 Texture2D = null
@export var description:          String    = ""

func get_bonus(stat: String) -> int:
	return stat_bonuses.get(stat, 0)

func is_combination() -> bool:
	return not combination_parts.is_empty()
