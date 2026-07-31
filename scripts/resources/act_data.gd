class_name ActData
extends Resource

@export_range(1, 3) var act_index: int = 1
@export var title: String = "Act"
@export_range(5, 20) var layer_count: int = 10
@export var boss_encounter_data: EncounterData
## Primary enemy faction for generated combat nodes this act.
@export var primary_faction: String = "human"
@export var normal_threat_budget: int = 18
@export var elite_threat_budget: int = 32
