# Боевые столкновения: полная механика

Документ описывает всю логику боя: жизненный цикл, ходы, урон, статусы, ИИ врагов,
способности, особые механики, баланс и точки расширения.

## 1. Карта кода

| Слой | Файл |
| --- | --- |
| Ядро боя | `scripts/combat/combat_manager.gd` (extends Node, создаётся сценой боя) |
| Игрок-статы | `scripts/player/player_stats.gd`, `scripts/player/actor_stats.gd` |
| Инвентарь/HP/AP | `scripts/inventory/inventory_controller.gd`, `scripts/inventory/body_grid.gd` |
| Статусы бойцов | `scripts/combat/status_controller.gd`, `scripts/resources/status_effect_data.gd`, `data/statuses/*.tres` |
| Статусы клеток | `scripts/resources/item_status.gd` |
| Трейты предметов | `scripts/combat/trait_manager.gd`, `data/traits.csv`, `data/trait_catalog.csv` |
| Враг (рантайм) | `scripts/enemies/enemy_instance.gd` (extends ActorStats) |
| ИИ / интенты | `scripts/enemies/enemy_ai.gd` |
| Способности | `scripts/resources/enemy_ability.gd`, `scripts/enemies/enemy_ability_executor.gd` |
| Эффекты способностей | `scripts/enemies/effects/effect_*.gd` |
| Данные | `data/enemies.csv`, `data/abilities.csv`, `data/items.csv`, `data/enemy_groups/*.tres` |
| Группы врагов | `scripts/resources/enemy_group.gd`, `scripts/managers/enemy_manager.gd` |
| Баланс/сложность | `scripts/global/game_settings.gd`, `scripts/resources/combat_config.gd` |
| Снабжение боем | `scripts/managers/encounter_manager.gd`, `scripts/main.gd`, `scripts/ui/combat_ui.gd` |
| Каналы событий | `scripts/global/event_bus.gd` |

## 2. Жизненный цикл боя

```
INACTIVE → (start_combat) → PLAYER_TURN ⇄ ENEMY_TURN → VICTORY | DEFEAT
```

- `CombatManager.start_combat(enemy_datas, max_attackers)` — точка входа.
  1. `_ensure_ability_executor()`, `_prepare_new_combat()` (сброс терминального состояния).
  2. Сброс combat-баффов игрока, очистка статусов игрока, очистка ростера.
  3. Создание `EnemyInstance` из `EnemyData` (см. §10).
  4. `_reset_all_item_combat_uses()`, `_clear_all_item_statuses()`, пересчёт смежностей сетки.
  5. `_apply_start_of_combat_player_buffs()` (напр. Sharp Spikes).
  6. `_apply_enemy_battle_start_passives()` (strong_start и т.п.).
  7. `EventBus.combat_started`, `_apply_enemy_preemptive_strikes()` (см. §12).
  8. Проверка смерти игрока → `_lose()`, иначе `_begin_player_turn()`.
- Состояния: `CombatState { INACTIVE, PLAYER_TURN, ENEMY_TURN, VICTORY, DEFEAT }`,
  UI-фаза `Phase { …, VICTORY_REWARDS }`.
- `_set_state()` испускает `state_changed`, `phase_changed`, и `EventBus.turn_started`.

### 2.1 Ход игрока

`_begin_player_turn()` — строгий конвейер:

1. `_vaeron_charge_damage = 0`; сброс hit-счётчиков Psychosis.
2. `_reset_player_resources()`:
   - Block сбрасывается (кроме Calculation Retention: сохраняет до 10),
   - `max_ap = inventory.get_max_ap()` (база 3 + бонусы сетки), `current_ap = max_ap`,
   - `player_turn_index += 1`; на 1-м ходу применяется модификатор Eye of Pale Maiden,
   - AP-кап Slimy Parasite, сброс «использований за ход».
3. `_apply_slimy_parasite_turn_damage()` — урон паразита (1-й ход с ним — грация).
4. `_player_pre_turn_phase()` — негативные статусы (DoT, стан):
   - DoT-урон идёт напрямую в HP; при смерти → `_lose()`;
   - стан (`skip_turn`) завершает ход и сразу запускает `_begin_enemy_turn()`.
5. `_player_start_turn_phase()` — позитивные статусы (лечение), старт-ауры предметов
   (Neuro Tick), автоматические выстрелы (Sighting Shot).
6. Планирование интентов всех врагов (`_plan_all_intentions(true)`).
7. `_set_state(PLAYER_TURN)`; игрок активирует предметы вручную (`activate_item`).
8. Конец хода: `end_player_turn()` → `_player_post_turn_phase()` (тикают пост-турн статусы,
   временные бонусы, статусы предметов) → урон Bionic Larva → `_begin_enemy_turn()`.

### 2.2 Ход врагов

`_begin_enemy_turn()`:

1. `_set_state(ENEMY_TURN)`.
2. `_commit_passive_armor_into_block()` — пассивная пространственная броня сетки превращается
   в реальный Block игрока (превью `(+N)` весь ход игрока → реальный Block на ход врагов).
3. `reset_attacker_slots()`.
4. `_run_enemy_actions()`:
   - Снимок живых актёров; далее по каждому:
     1. `_expire_enemy_block_for_turn_start` (Block врага обнуляется в начале его хода,
        кроме `permanent_shield`).
     2. `_enemy_pre_turn_phase_async` — DoT/стан/flee; может убить врага (см. §12).
     3. `_enemy_start_turn_phase` — `lab_contour` (+Block), позитивные статусы.
     4. `_enemy_pre_action_phase` — `begin_enemy_turn()` + PRE_ACTION способности.
     5. `_enemy_main_action_phase_async` — розыгрыш запланированной способности (см. §8).
     6. `_enemy_post_turn_phase` — тик corpse-таймера, пост-турн статусы, `end_enemy_turn()`.
   - Между врагами пауза `ENEMY_ACTION_GAP`.
5. Конец раунда: `grid.tick_corruption()`; если все враги мертвы → `_win()`, иначе → `_begin_player_turn()`.

## 3. Ресурсы

| Ресурс | Описание |
| --- | --- |
| HP | Игрок: `inventory.current_hp` / `max_hp` (END 2 → база 40). Враг: `EnemyInstance.current_hp`. |
| Block | Поглощает урон; у игрока сбрасывается каждый его ход, у врага — в начале его хода. |
| AP | База 3 + `grid.get_total_max_ap_bonus()`; сбрасывается каждый ход; стоимость активации предмета (`ap_cost`, модифицируется `TRAIT_ADJACENT_AP_TAX`). |
| Humanism/статы | `PlayerStats` — база + flat + экипировка + combat-баффы. |

Расчёт HP: `ActorStats.get_max_hp(base) = base + endurance * 5`.
Урон игроку: `InventoryController.apply_damage(amount, block)` возвращает урон, прошедший в HP.
Bio-Failover (имплант) может отменить летальный урон (`try_biological_failover`).

## 4. Урон игрок → враг

Основной путь: `activate_item()` → `_resolve_single_enemy()` → `_deal_damage_to()`.

1. `_calc_damage(placed)`:
   - `data.roll_damage(player_stats)` (база + скейлинг предмета),
   - `+ adjacency_bonus` (`grid.get_adjacency_damage_bonus_for`),
   - затем `player_statuses.modify_outgoing_damage` (weakness −25%, slow −20%, frenzy +50%).
2. `_consume_attack_trait_bonus` (напр. Burn Damage +4).
3. `_deal_damage_to(index, dmg, …, damage_type, pierce_block, placed, is_direct_attack)`:
   - Sensor Glitch: 50% шанс перенацелить на другого врага;
   - Preventive Strikes: +10% если враг почти полный;
   - входящий множитель врага (`vulnerability`/`panic` ×1.5);
   - крит игрока: `luck` (см. §5), множитель 1.4 + бонусы (`BRUTAL_CRITS`, оружие);
   - Bonk (см. §5) ×20;
   - `enemy.apply_incoming_damage(final, pierce)`: Evasion → Block → HP;
   - Thorns врага отражается в игрока;
   - крит-триггер Headshot: weakness + возврат 1 AP;
   - Psychosis (Chem-Junkie): +1 STR после 3 прямых попаданий за ход;
   - смерть → `_on_enemy_defeated` + `enemy_died` (см. §12).
4. Пост-эффекты предмета: `_apply_on_hit_weapon_statuses`, lifesteal, armorless-heal,
   Oracle kill bonus, stackable damage boost.

Прочие цели:
- `_resolve_all_enemies` — AOE по всем живым.
- `_resolve_auto_scatter_async` — 3 выстрела (1-й в цель, 2–3 случайные).
- `_resolve_consumable_enemy` — расходники по врагу.
- `_resolve_self` — броня/лечение/хирургия вредоносных модулей.

## 5. Критические удары и Bonk

- Крит игрока: `PlayerStats.get_crit_chance() = max(0, (luck − 1) × 0.05)`.
  Множитель `EnemyInstance.CRIT_DAMAGE_MULT = 1.4` + `TRAIT_BRUTAL_CRITS` (+0.1 за пункт).
- Bonk: только у оружия с `TRAIT_BONK`; шанс `CombatConfig.bonk_crit_chance` (0.02)
  `+ max(0, (luck − 1) × 0.005)`; множитель `CombatConfig.bonk_crit_multiplier` (20).
- Враг критует по своему `luck` и `ferocity` (×1.7).

## 6. Урон враг → игрок

`apply_enemy_damage_to_player(amount, attacker, damage_type)`:

1. `_apply_player_spike_reflect` (Sharp Spikes/Thorns) — только physical.
2. Evasion игрока полностью гасит удар (расход 1 стека).
3. `player_statuses.modify_incoming_damage` (vulnerability/panic ×1.5).
4. `inventory.apply_damage(incoming, current_block)`; Block уменьшается.
5. При смерти → `EventBus.player_died` / `_lose()`.

## 7. Статусы бойцов

`StatusController` управляет `StatusInstance` (на `StatusEffectData`).
Типы наложения: `STACKS`, `DURATION`, `PERMANENT`. Фазы тика:
`PRE_TURN_NEGATIVE`, `START_TURN_POSITIVE`, `ON_ATTACK`, `ON_TAKE_DAMAGE`, `POST_TURN`.

| id | Эффект | Тип |
| --- | --- | --- |
| poison | Урон = стеки в начале хода, −1 стек | stacks |
| bleed | То же (тик в pre-turn) | stacks |
| burn | 2 fire-урона в начале хода, −1 стек (1 стек = 1 ход) | stacks |
| stun | Пропуск фазы действия, тикает по duration | duration |
| weakness | Исходящий физ. урон −25% | duration |
| slow | Исходящий урон −20% (кап 3) | duration |
| vulnerability | Входящий физ. урон +50% | duration |
| panic | Входящий урон +50% | duration |
| rust | 25% шанс промаха/клина; кап 5, тикает | stacks |
| evasion | Гасит следующий удар за стек (кап 9) | stacks |
| ferocity | Крит-множитель 1.7 | duration |
| frenzy | Следующая атака +50%, тратится после удара | duration |
| thorns / sharp_spikes | Отражает урон атакующему | stacks |
| healing / repair | Лечение в начале хода (3 / 4) | duration |
| healing_curse | Входящее лечение вдвое | duration |
| sensor_glitch | 50% перенацел. атаки, кап 3 | stacks |
| hacked | Косметическая порча HUD | stacks |
| summoned_creature | Permanent: бежит при смерти хозяина, не даёт XP | permanent |
| war_god_corruption | Max HP = 1 на бой | permanent |
| fleeing | Побег в начале следующего хода | duration |

Модификаторы реализованы в `StatusController` (константы множителей — там же).
Наложение: `apply_player_status` / `apply_status_to_enemy(_instance)`.

## 8. Статусы клеток инвентаря (`ItemStatus`)

Типы: `COOLDOWN`, `OVERLOAD`, `INACTIVE`, `TAINTED`, `STICKY` (`item_status.gd`).

- `COOLDOWN`/`OVERLOAD`/`INACTIVE` блокируют активацию; `INACTIVE` ещё и пассивные бонусы.
- `TAINTED` наносит урон при активации (`get_taint_damage`).
- `STICKY` снимается при активации, но навсегда (до конца боя) +1 к базовому кулдауну экземпляра
  (`combat_cooldown_bonus`); сам статус тикает и истекает.
- Наложение по клетке: `apply_cell_damage(target_cell, status, duration)`
  (случайная не-вредоносная цель при `(-1,-1)`); `STICKY` только на `usable` без кулдауна.
- В начале боя статусы очищаются (`_clear_all_item_statuses`).
- `_clear_end_of_combat_item_state()` при победе/поражении/аборте чистит статусы **и**
  `combat_cooldown_bonus`, чтобы штраф не жил вне боя.

## 9. Ростер, группы и координация атак

- `EnemyManager.get_encounter_for_node(layer, is_elite, faction)` выбирает `EnemyGroup`
  из `data/enemy_groups/*.tres` (starter-слои ≤2, mid, elite; фильтр по фракции и слою).
- `EnemyGroup.max_attackers_per_turn` задаёт **Group Intent Coordination**: сколько
  тяжелых атакующих действий разрешено за один ход врагов.
- `try_reserve_attacker_slot()` резервирует слот; `_can_commit_offensive` не даёт
  запланировать больше атак, чем кап → враги выбирают не-атакующие действия.
- Ростер: `add_summoned_enemy`, `remove_enemy_instance/at`, `purge_dead_enemies`;
  UI перестраивается по `EventBus.enemy_roster_changed`.
- Максимум юнитов в группе — 3 (`EnemyGroup.resolve_enemy_datas`).

## 10. Создание врага и скейлинг

`EnemyInstance.setup(blueprint)`:
- статы из CSV (`str/agi/end/int/lck`),
- `max_hp = (base_hp + endurance * 5) * GameSettings.get_enemy_hp_multiplier()`,
  затем dev-кап `DEV_FORCE_ENEMY_HP = 20` (только если `base_hp ≤ 20`),
- копирование списка способностей,
- passives: трейты не из `MECHANIC_TRAIT_IDS` накладываются как статусы.
- `get_current_act_number() = turns_taken + 1` (1-based номер хода).

`GameSettings` (сложность): множители HP (0.85/1.0/1.25), урона (0.85/1.0/1.15),
весов HEAVY (0.35/1.0/1.75) и LIGHT (1.35/1.0/0.75).

## 11. ИИ и интенты

Пайплайн (`EnemyAI`):

1. **На планировании** (`commit_main_action`) выбирается главная способность и
   телеграфируется (`CombatIntention.from_ability`).
2. Приоритет выбора:
   - форс-фоллоу (`requires_prepare` / заряды),
   - Desperate Attack (низкое HP),
   - скриптовые ИИ по id врага (`_pick_scripted_main`),
   - взвешенная «колода» (`_choose_weighted`, вес × множитель сложности),
   - fallback на не-атакующее при заполненном капе.
3. **На розыгрыше** (`resolve_main_action`) берётся уже запланированная способность;
   при особых условиях — переоценка (`should_recommit_intention`, `reevaluate_enemy_intention`).
4. `trigger_pre_action_phase` — PRE_ACTION способности по интервалу (напр. `ENEMY_STUDY`).
5. Скриптовые ИИ есть у: slaver_master, corp_deserter, pocket_thief, scrapper_tank,
   field_medic, faceless_lady, elder_vaeron/pods, arbiter_guard, grenadier_drone, warden,
   the_unknown, specimen_614, scavenger_chimera.

## 12. Способности и эффекты

`EnemyAbility` (CSV `data/abilities.csv`):
- `target_type`: `self | player | ally | all_allies`;
- `main_effect` → обработчик в `EnemyAbilityExecutor`:
  `damage, heal, modify_stat, status, shield, summon, brand_stim, steal_chips, flee,
  ally_buff, force_insert, steal_item, cell_damage, devour_kin`;
- поля: `min_val/max_val`, `scaling_stat`, `hit_count`, `cooldown_turns`, `max_charges`,
  `hp_threshold`, `trigger_interval`, `available_from_turn`, `requires_prepare`,
  `type` (`DAMAGE/BLOCK/HEAL/SPECIAL/PRE_ACTION/MULTI_HIT`), `weight_class`, `ai_weight`;
- `effect_params` — pipe-список рантайм-модификаторов, разбираемых эффектами
  (напр. `block|N`, `poison|N|if_hp`, `cell_damage|STATUS|N`, `auto_insert|ITEM|fail|chance`,
  `force_insert|ITEM|chance`, `self_block`, `force_spawn`).

Исполнение: `EnemyAbilityExecutor.execute(caster, index, ability)` находит обработчик,
применяет эффект, тикает кулдаун, тратит prepare.

## 13. Особые механики врагов

- **The Unknown**: шанс пережить летальный урон (`revive_chance`, убывает).
- **Elder Vaeron + Stasis Pods**: сценарийный ИИ, воскрешение, кража предмета,
  возврат предмета после смерти пода, кап Block.
- **Slaver Master**: призыв миньонов; при смерти хозяина миньоны бегут.
- **Faceless Lady**: скриптовый инжект, пермаментное удаление из спавн-пулов после убийства.
- **Chem-Junkie**: `unpredictable` (реролл интента при уроне), `psychosis` (+1 STR за 3 попадания).
- **Specimen-614**: `permanent_shield`, `strong_start`, `lab_contour`; при флаге
  `specimen_614_escaped` — `preemptive_strike`: до первого хода игрока бесплатный
  Swift Strike +2 Poison (`_apply_enemy_preemptive_strikes`).
- **Scavenger Chimera**: `rending_pounce` с шансом `force_insert` вредоносного предмета (принудительная вставка);
  `carapace_lunge` со `self_block`; при смерти превращается в `entity_trembling_corpse`
  (`_try_chimera_corpse_transform`), таймер 2 раунда → `revive_from_corpse()` (50% HP,
  +3 STR/+3 LCK, стакается); сородичи с шансом 75% используют `devour_kin`
  (8 чистого урона телу, при добивании полный хил +3 STR/+3 LCK).

## 14. Трейты

- `TraitManager` читает трейты предметов/сетки (в т.ч. `runtime_trait`s).
- Пространственные трейты влияют на урон/броню через `BodyGrid`-смежности.
- `GameSettings` не влияет на трейты; баланс трейтов — в CSV.
- Механические трейты врагов (`EnemyData.MECHANIC_TRAIT_IDS`) не накладываются как статусы:
  `permanent_shield`, `always_reroll_intent`, `unpredictable`, `psychosis`, `strong_start`,
  `lab_contour`, `preemptive_strike`, `trembling_corpse`, `stasis_pod`.

## 15. Начало и конец боя (хуки)

- Старт: `_apply_start_of_combat_player_buffs`, `_apply_enemy_battle_start_passives`,
  `_apply_enemy_preemptive_strikes`, сброс статусов предметов и combat-использований.
- Победа (`_win`): очистка combat-баффов/статусов игрока и врагов,
  `_run_on_combat_end_triggers` (`data.on_combat_end`, пост-боевой дренаж Sinister Bundle),
  `_clear_end_of_combat_item_state`, `combat_ended(true)`.
- Поражение (`_lose`): очистка, `combat_ended(false)`, `GameManager.trigger_game_over()`.
- Аборт (`abort_combat`): жёсткий стоп без повторного game-over.

## 16. Пост-боевые награды

Поток: `combat_ended(true)` → `EncounterManager.notify_combat_finished` →
`_apply_act_boss_victory_recovery` (для боссов: полный хил + снятие вредоносных модулей) →
`request_post_combat_rewards` (RewardScreen). См. `docs/dialog_encounters.md` для лута из
событий; общий пул — `scripts/managers/reward_manager.gd`.

## 17. Сигналы (`EventBus`)

Ключевые: `combat_started`, `combat_ended(victory)`, `turn_started(is_player)`,
`state_changed`, `phase_changed`, `player_hp_changed`, `block_changed`, `ap_changed`,
`enemy_hp_changed`, `enemy_block_changed`, `enemy_intention_changed`, `enemy_selected`,
`enemy_roster_changed`, `enemy_died`, `enemy_healed`, `damage_popup_requested`, `cell_damaged`,
`sticky_grenade_blast`, `combat_log_message`, `combat_item_availability_changed`,
`inventory_changed`, `player_died`, `forced_insertion_requested`.

## 18. Принудительная вставка и спец-предметы

- `request_forced_item_insertion` → ForcedItemScreen (вредоносный модуль).
- `try_auto_insert_item` / `try_auto_insert_or_punish` — авто-вставка с наказанием уроном.
- Sticky grenade: `find_sticky_grenade_cell`, детонация, статусы соседям.
- Хирургия вредоносного модуля: `_perform_harmful_surgery` (активация вредоносного).
- Chimera Larva: `_apply_chimera_larva_pop` (1 урон, заряд, CD 1, уничтожение после 3-го).

## 19. Расширение (чек-лист добавления врага/способности)

1. Строка в `data/enemies.csv` (id, name_key, desc_key, hp, статы, abilities, traits,
   sprite_path, exp, faction, tier, role, threat, power).
2. Способности в `data/abilities.csv` (+ переводы `*_NAME/_DESC/_TEXT`).
3. Эффекты: если `main_effect` новый — обработчик в `scripts/enemies/effects/effect_*.gd`
   и регистрация в `EnemyAbilityExecutor._handlers`.
4. ИИ: ветка в `EnemyAI._pick_scripted_main` (при необходимости).
5. Предметы/статусы/трейты — в соответствующих CSV; спрайты.
6. Переводы в `translations/translations.csv`.
7. Группы: при необходимости новый `.tres` в `data/enemy_groups/`.

## 20. Известные особенности/TODO

- `DEV_FORCE_ENEMY_HP = 20` — временный dev-кап (снимается/пересматривается к релизу).
- Крит-множители и Bonk (`CombatConfig`) — тюнингуемые автолоады.
- Телеграф интента должен совпадать с исполнением: не меняйте `planned_ability`
  в обход `resolve_main_action`, кроме явных переоценок.
