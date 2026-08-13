class_name StartingGodRegistry
extends RefCounted
## Loads starting-god encounter JSON from res://data/encounters/gods/.
## Supports the authoring format with dialogs.{id}.{narrator_text,speech_text,choices}.

const GODS_DIR := "res://data/encounters/gods/"
const END_ENCOUNTER_ID := "end_encounter"


static func list_god_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open(GODS_DIR)
	if dir == null:
		push_warning("StartingGodRegistry: cannot open %s" % GODS_DIR)
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


static func load_god_encounter(god_id: String) -> IntroEncounterData:
	var path := "%s%s.json" % [GODS_DIR, god_id.strip_edges()]
	if not FileAccess.file_exists(path):
		push_warning("StartingGodRegistry: missing %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("StartingGodRegistry: invalid JSON in %s" % path)
		return null
	return _build_encounter_from_dict(parsed as Dictionary)


static func pick_random_god_encounter() -> IntroEncounterData:
	var ids := list_god_ids()
	if ids.is_empty():
		return load_god_encounter("sleeper_god")
	var pick: String = ids[randi() % ids.size()]
	var encounter := load_god_encounter(pick)
	if encounter == null and pick != "sleeper_god":
		return load_god_encounter("sleeper_god")
	return encounter


static func _build_encounter_from_dict(raw: Dictionary) -> IntroEncounterData:
	var dialog := DialogEventData.new()
	dialog.id = str(raw.get("id", "")).strip_edges()
	dialog.title = LocalizationManager.pick_en_ru(
		str(raw.get("god_name", raw.get("title", ""))),
		str(raw.get("god_name_ru", "")),
		str(raw.get("god_name", raw.get("title", dialog.id)))
	)
	dialog.title_key = str(raw.get("title_key", ""))
	dialog.image_path = _resolve_image_path(str(raw.get("image_path", "")))
	dialog.start_node_id = "start"

	var nodes: Array[DialogNodeData] = []
	## New format: dialogs = { "start": {...}, "branch_1": {...} }
	var dialogs_raw: Variant = raw.get("dialogs", null)
	if typeof(dialogs_raw) == TYPE_DICTIONARY:
		var dialogs: Dictionary = dialogs_raw
		var keys: Array = dialogs.keys()
		keys.sort()
		## Ensure "start" is first when present.
		if dialogs.has("start"):
			keys.erase("start")
			keys.insert(0, "start")
		for key in keys:
			var node_entry: Variant = dialogs[key]
			if typeof(node_entry) != TYPE_DICTIONARY:
				continue
			nodes.append(_parse_dialog_node(str(key), node_entry as Dictionary))
	else:
		## Legacy array format fallback.
		var nodes_raw: Array = raw.get("nodes", [])
		for node_entry in nodes_raw:
			if typeof(node_entry) != TYPE_DICTIONARY:
				continue
			var node_dict: Dictionary = node_entry
			nodes.append(_parse_dialog_node(str(node_dict.get("id", "")), node_dict))

	dialog.nodes = nodes
	if not nodes.is_empty() and dialog.get_node("start") == null:
		dialog.start_node_id = nodes[0].id

	var encounter := IntroEncounterData.new()
	encounter.id = dialog.id
	encounter.title = dialog.title
	encounter.title_key = dialog.title_key
	encounter.type = EncounterData.EncounterType.INTRO
	encounter.story_act = int(raw.get("story_act", 1))
	encounter.chapter_title = LocalizationManager.pick_en_ru(
		str(raw.get("chapter_title_en", "")),
		str(raw.get("chapter_title_ru", "")),
		str(raw.get("chapter_title", ""))
	)
	encounter.dialog_event = dialog
	encounter.encounter_payload = dialog
	encounter.payload = {
		"prologue": bool(raw.get("prologue", true)),
		"god_id": dialog.id,
		"aliases": raw.get("aliases", []),
	}
	return encounter


static func _parse_dialog_node(node_id: String, node_dict: Dictionary) -> DialogNodeData:
	var node := DialogNodeData.new()
	node.id = node_id.strip_edges()
	if node.id.is_empty():
		node.id = str(node_dict.get("id", "")).strip_edges()
	node.narrator_text_en = str(node_dict.get("narrator_text_en", ""))
	node.narrator_text_ru = str(node_dict.get("narrator_text_ru", node_dict.get("narrator_text", "")))
	node.speech_text_en = str(node_dict.get("speech_text_en", ""))
	node.speech_text_ru = str(node_dict.get("speech_text_ru", node_dict.get("speech_text", "")))
	## Unilingual fallback fields (authoring shorthand).
	node.narrator_text = str(node_dict.get("narrator_text", ""))
	node.speech_text = str(node_dict.get("speech_text", ""))
	node.text_en = str(node_dict.get("text_en", ""))
	node.text_ru = str(node_dict.get("text_ru", ""))
	node.text = str(node_dict.get("text", ""))
	node.text_key = str(node_dict.get("text_key", ""))
	## Legacy combined text_ru/text_en without narrator/speech split.
	if (
		node.narrator_text_en.is_empty()
		and node.narrator_text_ru.is_empty()
		and node.speech_text_en.is_empty()
		and node.speech_text_ru.is_empty()
		and node.narrator_text.is_empty()
		and node.speech_text.is_empty()
	):
		if node.text_en.is_empty() and node.text_ru.is_empty() and node.text.is_empty():
			node.text = _localized_text(node_dict)

	var choices: Array[DialogChoiceData] = []
	var choices_raw: Array = node_dict.get("choices", [])
	for choice_entry in choices_raw:
		if typeof(choice_entry) != TYPE_DICTIONARY:
			continue
		choices.append(_parse_choice(choice_entry as Dictionary))
	node.choices = choices
	return node


static func _parse_choice(choice_dict: Dictionary) -> DialogChoiceData:
	var choice := DialogChoiceData.new()
	choice.text_en = str(choice_dict.get("text_en", ""))
	choice.text_ru = str(choice_dict.get("text_ru", ""))
	choice.text = str(choice_dict.get("text", ""))
	if choice.text_en.is_empty() and choice.text_ru.is_empty() and choice.text.is_empty():
		choice.text = _localized_text(choice_dict)
	choice.text_key = str(choice_dict.get("text_key", ""))
	choice.stat_check = str(choice_dict.get("stat_check", ""))
	choice.check_dc = int(choice_dict.get("check_dc", 0))
	choice.stat_pool_bonus = int(choice_dict.get("stat_pool_bonus", 0))
	choice.require_chips = maxi(0, int(choice_dict.get("require_chips", 0)))
	choice.cost_chips = maxi(0, int(choice_dict.get("cost_chips", choice_dict.get("spend_chips", 0))))
	choice.require_item_id = str(
		choice_dict.get("require_item", choice_dict.get("require_item_id", ""))
	).strip_edges()

	var success_next := str(choice_dict.get("success_next_dialog_id", "")).strip_edges()
	var failure_next := str(choice_dict.get("failure_next_dialog_id", "")).strip_edges()
	## Stat-check branches: success/failure next nodes (merchant bargain, etc.).
	if not choice.stat_check.strip_edges().is_empty() and (
		not success_next.is_empty() or not failure_next.is_empty()
	):
		var success_dict := choice_dict.duplicate(true)
		if not success_next.is_empty():
			success_dict["next_dialog_id"] = success_next
		if choice_dict.has("success_reward"):
			success_dict["reward"] = choice_dict.get("success_reward")
		choice.success_outcome = _outcome_from_choice(success_dict)
		if not failure_next.is_empty():
			var fail_dict: Dictionary = {"next_dialog_id": failure_next}
			if choice_dict.has("failure_reward"):
				fail_dict["reward"] = choice_dict.get("failure_reward")
			if choice_dict.has("failure_message_key"):
				fail_dict["message_key"] = choice_dict.get("failure_message_key")
			choice.failure_outcome = _outcome_from_choice(fail_dict)
		else:
			choice.failure_outcome = DialogOutcomeData.make_end()
		## Chip cost applies on the chosen branch after the check resolves.
		if choice.cost_chips > 0:
			if choice.success_outcome != null:
				choice.success_outcome.spend_chips = maxi(
					choice.success_outcome.spend_chips, choice.cost_chips
				)
		return choice

	## New format: next_dialog_id + reward
	if choice_dict.has("next_dialog_id") or choice_dict.has("reward"):
		choice.success_outcome = _outcome_from_choice(choice_dict)
		if choice.cost_chips > 0 and choice.success_outcome != null:
			choice.success_outcome.spend_chips = maxi(
				choice.success_outcome.spend_chips, choice.cost_chips
			)
		return choice

	## Legacy: nested outcome object
	var outcome_raw: Variant = choice_dict.get("outcome", {})
	if typeof(outcome_raw) == TYPE_DICTIONARY:
		choice.success_outcome = _parse_outcome(outcome_raw as Dictionary)
	var fail_raw: Variant = choice_dict.get("failure_outcome", {})
	if typeof(fail_raw) == TYPE_DICTIONARY and not (fail_raw as Dictionary).is_empty():
		choice.failure_outcome = _parse_outcome(fail_raw as Dictionary)
	return choice


static func _outcome_from_choice(choice_dict: Dictionary) -> DialogOutcomeData:
	var next_id := str(choice_dict.get("next_dialog_id", "")).strip_edges()
	var reward_raw: Variant = choice_dict.get("reward", null)
	var o := DialogOutcomeData.new()
	o.message_key = str(choice_dict.get("message_key", "")).strip_edges()

	if next_id == END_ENCOUNTER_ID or next_id.is_empty():
		o.kind = DialogOutcomeData.OutcomeKind.END
		o.next_node_id = ""
	else:
		o.next_node_id = next_id
		o.kind = DialogOutcomeData.OutcomeKind.CONTINUE

	if typeof(reward_raw) == TYPE_DICTIONARY:
		var reward: Dictionary = reward_raw
		var reward_type := str(reward.get("type", "")).strip_edges().to_lower()
		var amount := int(reward.get("amount", 0))
		if o.message_key.is_empty():
			o.message_key = str(reward.get("message_key", "")).strip_edges()

		## Multi-effect bundles (Pale Maiden kiss: +STR / -Humanity + pact).
		var effects_raw: Variant = reward.get("effects", null)
		if effects_raw is Array and not (effects_raw as Array).is_empty():
			o.payload_effects = []
			for entry in effects_raw:
				if typeof(entry) == TYPE_DICTIONARY:
					o.payload_effects.append((entry as Dictionary).duplicate(true))
			_apply_compound_primary_kind(o, next_id)
			_apply_god_flags_from_reward(o, reward)
			_preserve_branch_nav(o, next_id)
			return o

		match reward_type:
			"shop":
				o.kind = DialogOutcomeData.OutcomeKind.SHOP
				o.price_multiplier = float(reward.get("price_multiplier", 1.0))
				if o.price_multiplier <= 0.0:
					o.price_multiplier = 1.0
				o.next_node_id = ""
			"humanity", "endurance", "strength", "agility", "intelligence", "luck":
				o.kind = DialogOutcomeData.OutcomeKind.GRANT_STAT
				o.stat_name = reward_type
				if amount != 0:
					o.stat_amount = amount
				elif reward_type == "endurance":
					o.stat_amount = 2
				else:
					o.stat_amount = 1
			"item", "grant_item":
				o.kind = DialogOutcomeData.OutcomeKind.GRANT_ITEM
				o.item_id = str(reward.get("item_id", "")).strip_edges()
				o.item_amount = amount if amount > 0 else 1
			"neuro_chips", "neuro_chip", "neurochip":
				## Global currency — applied by EncounterManager via GameManager.
				o.kind = DialogOutcomeData.OutcomeKind.GRANT_ITEM
				o.item_id = "NEURO_CHIP"
				o.item_amount = amount if amount > 0 else 10
			"item_choice", "select_item":
				o.kind = DialogOutcomeData.OutcomeKind.SELECT_ITEM
				o.item_pool_id = str(reward.get("pool", reward.get("item_pool_id", ""))).strip_edges()
				o.loot_pick_count = maxi(1, int(reward.get("pick_count", reward.get("loot_pick_count", 1))))
				var ids_raw: Variant = reward.get("item_ids", [])
				if ids_raw is Array:
					for eid in ids_raw:
						var sid := str(eid).strip_edges()
						if not sid.is_empty():
							o.item_pool_ids.append(sid)
			"loot", "loot_offer", "reward_loot":
				## Opens RewardScreen with generated items (pick_count allowed).
				o.kind = DialogOutcomeData.OutcomeKind.SELECT_ITEM
				o.item_pool_id = str(reward.get("pool", reward.get("item_pool_id", ""))).strip_edges()
				o.loot_pick_count = maxi(1, int(reward.get("pick_count", reward.get("loot_pick_count", 1))))
				var loot_ids: Variant = reward.get("item_ids", [])
				if loot_ids is Array:
					for eid2 in loot_ids:
						var sid2 := str(eid2).strip_edges()
						if not sid2.is_empty():
							o.item_pool_ids.append(sid2)
			"damage":
				o.kind = DialogOutcomeData.OutcomeKind.DAMAGE
				o.damage_amount = amount if amount > 0 else int(reward.get("damage_amount", 0))
			"exp", "experience", "xp":
				o.exp_amount = amount if amount > 0 else 0
				## Keep navigation; EXP is applied as a side effect.
				if o.kind == DialogOutcomeData.OutcomeKind.END and not next_id.is_empty() and next_id != END_ENCOUNTER_ID:
					o.kind = DialogOutcomeData.OutcomeKind.CONTINUE
			"combat", "fight":
				o.kind = DialogOutcomeData.OutcomeKind.COMBAT
				o.elite_rewards = bool(reward.get("elite_rewards", reward.get("elite", false)))
				o.faction = str(reward.get("faction", "")).strip_edges()
				var enemy_raw: Variant = reward.get("enemy_ids", [])
				if enemy_raw is Array:
					for eid3 in enemy_raw:
						var sid3 := str(eid3).strip_edges()
						if not sid3.is_empty():
							o.enemy_ids.append(sid3)
			"spend_chips", "cost_chips":
				o.spend_chips = amount if amount > 0 else maxi(0, int(reward.get("spend_chips", 0)))
			"enemies_start_1hp", "cripple_foes":
				## Keep dialog navigation; buff is applied by EncounterManager.
				if o.kind == DialogOutcomeData.OutcomeKind.END:
					o.kind = DialogOutcomeData.OutcomeKind.CONTINUE
				o.buff_id = "enemies_start_1hp"
				o.buff_amount = int(reward.get("battles", amount if amount > 0 else 2))
			"compound":
				pass
			_:
				pass
		if reward_type != "shop":
			_apply_god_flags_from_reward(o, reward)
			_preserve_branch_nav(o, next_id)
	return o


static func _preserve_branch_nav(o: DialogOutcomeData, next_id: String) -> void:
	if next_id != END_ENCOUNTER_ID and not next_id.is_empty():
		o.next_node_id = next_id
	else:
		o.next_node_id = ""


static func _apply_compound_primary_kind(o: DialogOutcomeData, next_id: String) -> void:
	## Pick the strongest control-flow effect; side effects stay in payload_effects.
	for entry in o.payload_effects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = entry
		var ft := str(effect.get("type", "")).strip_edges().to_lower()
		var amount := int(effect.get("amount", 0))
		match ft:
			"combat", "fight":
				o.kind = DialogOutcomeData.OutcomeKind.COMBAT
				o.elite_rewards = bool(effect.get("elite_rewards", effect.get("elite", false)))
				o.faction = str(effect.get("faction", "")).strip_edges()
				var enemy_raw: Variant = effect.get("enemy_ids", [])
				if enemy_raw is Array:
					for eid in enemy_raw:
						var sid := str(eid).strip_edges()
						if not sid.is_empty():
							o.enemy_ids.append(sid)
			"item_choice", "select_item", "loot", "loot_offer", "reward_loot":
				o.kind = DialogOutcomeData.OutcomeKind.SELECT_ITEM
				o.item_pool_id = str(effect.get("pool", effect.get("item_pool_id", ""))).strip_edges()
				o.loot_pick_count = maxi(1, int(effect.get("pick_count", effect.get("loot_pick_count", 1))))
				var ids_raw: Variant = effect.get("item_ids", [])
				if ids_raw is Array:
					for eid2 in ids_raw:
						var sid2 := str(eid2).strip_edges()
						if not sid2.is_empty():
							o.item_pool_ids.append(sid2)
			"damage":
				if o.kind != DialogOutcomeData.OutcomeKind.COMBAT and o.kind != DialogOutcomeData.OutcomeKind.SELECT_ITEM:
					o.kind = DialogOutcomeData.OutcomeKind.DAMAGE
					o.damage_amount = amount if amount > 0 else int(effect.get("damage_amount", 0))
			"item", "grant_item":
				if o.kind in [
					DialogOutcomeData.OutcomeKind.END,
					DialogOutcomeData.OutcomeKind.CONTINUE,
				]:
					o.kind = DialogOutcomeData.OutcomeKind.GRANT_ITEM
					o.item_id = str(effect.get("item_id", "")).strip_edges()
					o.item_amount = maxi(1, amount if amount > 0 else 1)
			"strength", "humanity", "endurance", "agility", "intelligence", "luck":
				if o.kind in [
					DialogOutcomeData.OutcomeKind.END,
					DialogOutcomeData.OutcomeKind.CONTINUE,
				]:
					o.kind = DialogOutcomeData.OutcomeKind.GRANT_STAT
					o.stat_name = ft
					o.stat_amount = amount if amount != 0 else 1
			"exp", "experience", "xp":
				## Applied via payload_effects in EncounterManager — avoid double grant.
				pass
			"spend_chips", "cost_chips":
				## Applied via payload_effects unless already set as outcome.spend_chips.
				if o.spend_chips <= 0:
					o.spend_chips = amount if amount > 0 else maxi(0, int(effect.get("spend_chips", 0)))
			_:
				pass
	if (
		o.kind == DialogOutcomeData.OutcomeKind.END
		and not next_id.is_empty()
		and next_id != END_ENCOUNTER_ID
	):
		o.kind = DialogOutcomeData.OutcomeKind.CONTINUE


static func _apply_god_flags_from_reward(o: DialogOutcomeData, reward: Dictionary) -> void:
	if bool(reward.get("pale_maiden_pact", false)):
		o.buff_id = "pale_maiden_pact"
		o.buff_amount = 1
	var flags_raw: Variant = reward.get("flags", [])
	if flags_raw is Array:
		for f in flags_raw:
			if str(f).strip_edges().to_lower() == "pale_maiden_pact":
				o.buff_id = "pale_maiden_pact"
				o.buff_amount = 1


static func _localized_text(entry: Dictionary) -> String:
	return LocalizationManager.pick_en_ru(
		str(entry.get("text_en", "")),
		str(entry.get("text_ru", "")),
		str(entry.get("text", ""))
	)


static func _parse_outcome(raw: Dictionary) -> DialogOutcomeData:
	var kind_name := str(raw.get("kind", "END")).strip_edges().to_upper()
	var o := DialogOutcomeData.new()
	o.message_key = str(raw.get("message_key", ""))
	o.next_node_id = str(raw.get("next_node_id", ""))
	o.heal_amount = int(raw.get("heal_amount", 0))
	o.damage_amount = int(raw.get("damage_amount", 0))
	o.item_id = str(raw.get("item_id", ""))
	o.item_amount = maxi(1, int(raw.get("item_amount", 1)))
	o.stat_name = str(raw.get("stat_name", ""))
	o.stat_amount = int(raw.get("stat_amount", 0))
	o.item_pool_id = str(raw.get("item_pool_id", "")).strip_edges()
	o.buff_id = str(raw.get("buff_id", "")).strip_edges()
	o.buff_amount = int(raw.get("buff_amount", 0))
	o.price_multiplier = float(raw.get("price_multiplier", 1.0))
	var pool_ids: Array = raw.get("item_pool_ids", [])
	for pid in pool_ids:
		var s := str(pid).strip_edges()
		if not s.is_empty():
			o.item_pool_ids.append(s)
	var enemies: Array = raw.get("enemy_ids", [])
	for eid in enemies:
		o.enemy_ids.append(str(eid))
	match kind_name:
		"CONTINUE":
			o.kind = DialogOutcomeData.OutcomeKind.CONTINUE
		"COMBAT":
			o.kind = DialogOutcomeData.OutcomeKind.COMBAT
		"HEAL":
			o.kind = DialogOutcomeData.OutcomeKind.HEAL
		"DAMAGE":
			o.kind = DialogOutcomeData.OutcomeKind.DAMAGE
		"GRANT_ITEM":
			o.kind = DialogOutcomeData.OutcomeKind.GRANT_ITEM
		"GRANT_STAT":
			o.kind = DialogOutcomeData.OutcomeKind.GRANT_STAT
		"SELECT_ITEM":
			o.kind = DialogOutcomeData.OutcomeKind.SELECT_ITEM
		"SHOP":
			o.kind = DialogOutcomeData.OutcomeKind.SHOP
			if o.price_multiplier <= 0.0:
				o.price_multiplier = 1.0
		"SKIP":
			o.kind = DialogOutcomeData.OutcomeKind.SKIP
		_:
			o.kind = DialogOutcomeData.OutcomeKind.END
	if o.next_node_id == END_ENCOUNTER_ID:
		o.next_node_id = ""
		if o.kind == DialogOutcomeData.OutcomeKind.CONTINUE:
			o.kind = DialogOutcomeData.OutcomeKind.END
	return o


static func _resolve_image_path(path: String) -> String:
	var cleaned := path.strip_edges()
	if cleaned.is_empty():
		return "res://assets/sprites/gods/sleeping_god.png"
	if ResourceLoader.exists(cleaned):
		return cleaned
	## Fallback for sleeper_god.png vs sleeping_god.png naming.
	if cleaned.ends_with("sleeper_god.png"):
		var alt := "res://assets/sprites/gods/sleeping_god.png"
		if ResourceLoader.exists(alt):
			return alt
	return cleaned
