class_name DialogOutcomeData
extends Resource
## Result of a dialog choice branch (success or failure).

enum OutcomeKind {
	CONTINUE, ## Jump to next_node_id
	END, ## Close dialog / complete encounter
	COMBAT, ## Start a combat from enemy_ids
	HEAL, ## Restore HP then continue or end
	DAMAGE, ## Deal damage to player then continue or end
	GRANT_ITEM, ## Give item_id (× item_amount) then continue or end
	GRANT_STAT, ## Permanent player_stats bonus then continue or end
	SELECT_ITEM, ## Open SelectItemUI with an item pool, then continue or end
	SKIP, ## Complete encounter with no further effect
	SHOP, ## Close dialog and open the merchant shop UI
}

@export var kind: OutcomeKind = OutcomeKind.END
@export var message_key: String = ""
@export var next_node_id: String = ""
@export var heal_amount: int = 0
@export var damage_amount: int = 0
@export var item_id: String = ""
@export var item_amount: int = 1
@export var stat_name: String = ""
@export var stat_amount: int = 0
@export var enemy_ids: Array[String] = []
@export var faction: String = ""
@export var threat_budget: int = 0
## SELECT_ITEM: pool key (e.g. uncommon_weapon, grenade) or explicit ids.
@export var item_pool_id: String = ""
@export var item_pool_ids: Array[String] = []
## Optional run buff applied alongside the outcome (e.g. enemies_start_1hp).
@export var buff_id: String = ""
@export var buff_amount: int = 0
## SHOP: price scale applied to stock (0.8 discount / 1.0 list / 1.25 markup).
@export var price_multiplier: float = 1.0
## Optional compound reward list from story JSON (`reward.effects`).
var payload_effects: Array = []


static func make_end(message_key: String = "") -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.END
	o.message_key = message_key
	return o


static func make_continue(next_id: String, message_key: String = "") -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.CONTINUE
	o.next_node_id = next_id
	o.message_key = message_key
	return o


static func make_combat(enemy_ids: Array[String], message_key: String = "") -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.COMBAT
	o.enemy_ids = enemy_ids.duplicate()
	o.message_key = message_key
	return o


static func make_heal(amount: int, next_id: String = "", message_key: String = "") -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.HEAL
	o.heal_amount = amount
	o.next_node_id = next_id
	o.message_key = message_key
	return o


static func make_damage(amount: int, next_id: String = "", message_key: String = "") -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.DAMAGE
	o.damage_amount = amount
	o.next_node_id = next_id
	o.message_key = message_key
	return o


static func make_item(
	item_id: String, next_id: String = "", message_key: String = "", amount: int = 1
) -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.GRANT_ITEM
	o.item_id = item_id
	o.item_amount = maxi(amount, 1)
	o.next_node_id = next_id
	o.message_key = message_key
	return o


static func make_stat(
	stat_name: String, amount: int, next_id: String = "", message_key: String = ""
) -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.GRANT_STAT
	o.stat_name = stat_name
	o.stat_amount = amount
	o.next_node_id = next_id
	o.message_key = message_key
	return o


static func make_select_item(
	pool_id: String, next_id: String = "", message_key: String = ""
) -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.SELECT_ITEM
	o.item_pool_id = pool_id
	o.next_node_id = next_id
	o.message_key = message_key
	return o


static func make_shop(
	price_multiplier: float = 1.0, message_key: String = ""
) -> DialogOutcomeData:
	var o := DialogOutcomeData.new()
	o.kind = OutcomeKind.SHOP
	o.price_multiplier = price_multiplier
	o.message_key = message_key
	return o
