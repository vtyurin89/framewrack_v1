class_name StatusEffect
extends RefCounted
## Canonical status effect IDs used by combat systems.
## Runtime blueprints live in res://data/statuses/*.tres (StatusEffectData).

const SENSOR_GLITCH := "sensor_glitch"
const SUMMONED_CREATURE := "summoned_creature"
const EVASION := "evasion"
const FLEEING := "fleeing"
const FRENZY := "frenzy"
const BLEED := "bleed"
const SLOW := "slow"
const VULNERABILITY := "vulnerability"
const STRENGTH_BUFF := "strength"  ## Permanent STR is applied via modify_stat / ally_buff, not this id.
