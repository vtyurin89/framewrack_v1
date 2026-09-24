# Текстовые энкаунтеры: структура диалогов

Документ описывает формат и рантайм текстовых (EVENT / INTRO / MAIN_STORY) энкаунтеров:
как автору писать `dialogs` в JSON, как это парсится, и как ведёт себя UI,
включая фазу подготовки к проверке с использованием предметов.

## 1. Где что лежит

| Слой | Файл |
| --- | --- |
| JSON-данные энкаунтера | `data/encounters/events/*.json` |
| Парсинг JSON → ресурсы | `scripts/encounters/starting_god_registry.gd` |
| Обёртка в EVENT | `scripts/encounters/story_event_registry.gd` |
| Регистрация в очереди актов | `scripts/managers/story_event_manager.gd` |
| Рантайм-контроллер | `scripts/managers/encounter_manager.gd` |
| UI диалога | `scripts/ui/dialog_event_ui.gd` |
| Модель узла | `scripts/resources/dialog_node_data.gd` |
| Модель выбора | `scripts/resources/dialog_choice_data.gd` |
| Модель исхода | `scripts/resources/dialog_outcome_data.gd` |
| Проверки характеристик | `scripts/managers/stat_check_resolver.gd`, `scripts/managers/stat_check_manager.gd` |
| Предметы-бусты к броску | `scripts/resources/stat_check_boost_catalog.gd` |

## 2. Регистрация энкаунтера

Энкаунтер попадает на карту через очередь сюжетных событий. В
`StoryEventManager._rebuild_catalog()`:

```gdscript
_register_event(
    "enc_specimen_614",              # id события
    StoryEvent.Faction.ROBOT,        # фракция (HUMAN / ROBOT / CHIMERA / GENERIC)
    "enc_specimen_614",              # id JSON-файла без расширения
    false,                           # one_shot (одноразовое?)
    [2, 3]                           # allowed_acts (пусто = все акты)
)
```

`_build_queue_for_act()` формирует очередь на акт по весам фракций, а
`build_encounter_for_act()` грузит JSON и кладёт в `payload`:
`story_event_id`, `act`, `faction_tag`.

## 3. Верхний уровень JSON

```jsonc
{
  "id": "enc_example",
  "god_name": "English title",       // используется как заголовок
  "god_name_ru": "Русский заголовок",
  "title_key": "",                    // необязательный ключ перевода (приоритетнее)
  "image_path": "res://assets/.../art.png", // арт правой панели
  "dialogs": {
    "start": { /* узел */ },
    "node_2": { /* узел */ }
  }
}
```

- Стартовый узел всегда ищется по id `start` (`dialog.start_node_id = "start"`).
- Все узлы из `dialogs` парсятся по ключам; `end_encounter` — служебный id.

## 4. Узел (`DialogNodeData`)

```jsonc
"node_id": {
  "narrator_text_en": "Описание (курсив, абзацы через \n\n).",
  "narrator_text_ru": "Описание (курсив).",
  "speech_text_en": "\"Реплика существа.\"",
  "speech_text_ru": "«Реплика существа.»",
  "choices": [ /* см. §5 */ ],

  // Механики повторного использования:
  "options_inherit": "start",        // скопировать choices из другого узла
  "disable_used_choices": true,      // серые уже применённые choice_id

  // Push-your-luck (см. §8):
  "branch_chances": [0.2, 0.4, 0.75],
  "branch_success_node": "escaped",
  "branch_failure_node": "hall",
  "narrator_variants_en": ["...", "...", "..."],
  "narrator_variants_ru": ["...", "...", "..."],
  "speech_pool_en": ["...", "..."],
  "speech_pool_ru": ["...", "..."],
  "speech_pool_visits": [0, 1]
}
```

Правила отображения:

- `narrator_text_*` рендерится курсивом, каждый абзац отдельным `[i]…[/i]`.
- `speech_text_*` рендерится как обычный (не курсивный) текст, отделённый пустой строкой.
- Если оба поля пусты и нет вариантов/пула — используется `text_en` / `text_ru` / `text_key`.
- Если у узла нет `choices`, UI добавляет кнопку `KEY_CONTINUE`, завершающую энкаунтер.

## 5. Выбор (`DialogChoiceData`)

### 5.1 Навигация без броска

```jsonc
{
  "id": "opt_go",                     // choice_id (стабилен между перезаходами)
  "text_en": "Go deeper",
  "text_ru": "Идти глубже",
  "next_dialog_id": "node_2",
  "reward": { /* необязательная награда, см. §6 */ }
}
```

### 5.2 Проверка характеристики

```jsonc
{
  "id": "opt_force",
  "text_en": "[STR Check] Break the door open",
  "text_ru": "[Проверка STR] Выломать дверь",
  "stat_check": "STR",                // STR | AGI | END | INT | LCK | HUM
  "difficulty": "HARD",               // TRIVIAL | EASY | MEDIUM | HARD | EXTREME | AUTO
  "check_dc": 0,                      // legacy-переопределение требуемых успехов
  "stat_pool_bonus": 0,               // доп. модификатор пула кубиков
  "success_next_dialog_id": "ok_node",
  "failure_next_dialog_id": "fail_node",
  "success_reward": { /* необязательно */ },
  "failure_reward": { /* необязательно */ }
}
```

Текст `[Проверка …]` автоматически префиксуется статистикой и превью кубиков (см.
`DialogChoiceData.format_stat_check_label`). Награды можно ставить как на сам бросок
(`success_reward` / `failure_reward`), так и на узлы-приёмники.

### 5.3 Требования к выбору

| Поле | Значение |
| --- | --- |
| `require_item` / `require_item_id` | выбор виден только при наличии предмета |
| `require_harmful` / `require_harmful_item` | нужен хотя бы один вредоносный модуль |
| `require_chips` | минимум нейро-чипов |
| `cost_chips` / `spend_chips` | списать чипы при выборе |

## 6. Награды и исходы (`DialogOutcomeData`)

Внутри `reward` (или `success_reward` / `failure_reward`) задаётся `type`:

| `type` | Действие |
| --- | --- |
| `item` / `grant_item` | выдать предмет (`item_id`, `amount`) |
| `neuro_chips` / `chips_tier` | нейро-чипы |
| `humanity` / `endurance` / `strength` / `agility` / `intelligence` / `luck` | стат |
| `damage` / `hp_loss` / `hp_loss_tier` | урон (`amount`, `tier`, `percent`) |
| `exp` / `exp_tier` | опыт (`tier`, `percent`) |
| `heal` / `heal_percent` | лечение — только как эффект внутри `compound.effects` |
| `loot` / `loot_offer` / `reward_loot` | экран наград (`pool`, `pick_count`, `item_ids`) |
| `item_choice` / `select_item` | выбор предмета из пула |
| `combat` / `fight` | бой (`enemy_ids`, `elite`, `faction`) |
| `shop` | магазин (`price_multiplier`) |
| `spend_chips` | списать чипы |
| `compound` | контейнер `effects: [ … ]` из любых типов выше |

Дополнительно, рядом с `type` можно указать `"flags": ["флаг"]` — сюжетные флаги
(см. §9). Для `combat` доступны `elite: true`, `faction`, `enemy_ids`.

`compound` — как собрать несколько эффектов в один исход:

```jsonc
"reward": {
  "type": "compound",
  "effects": [
    { "type": "exp_tier", "tier": "TRIVIAL" },
    { "type": "loot", "pool": "tiered_gear", "pick_count": 1 },
    { "type": "heal_percent", "percent": 0.3 }
  ]
}
```

Управляющий эффект (бой / лут / предмет) становится `outcome.kind`, остальные
применяются как сайд-эффекты через `EncounterManager._apply_payload_effects`.

### Пулы лута

Спец-ключи `pool`, которые обрабатывает `EncounterManager._try_open_dialog_loot`:

| `pool` | Результат |
| --- | --- |
| `rare_pick_3` | 3 редких/очерарных предмета на выбор |
| `rare_weapon` / `rare_module` | один редкий предмет нужного типа |
| `rare_weapon_and_module` | оба, выбор 2 |
| `tiered_gear` / `tiered_item` | 1 случайный uncommon/rare/very_rare (не расходник) |
| `tiered_consumable` / `tiered_supply` | то же, но расходник |

Прямые пулы (`grenade`, `uncommon_weapon`) выдаются без экрана выбора
через `_try_resolve_direct_item_pool`.

## 7. Фаза подготовки проверки и предметы-бусты

Самое важное для геймплея: **перед броском** открывается промежуточная фаза, где
игрок может применить предметы ради дополнительных кубиков, а затем подтвердить
бросок или отменить его.

Поток управления:

1. Игрок нажимает выбор с `stat_check` → `DialogEventUI._on_choice_pressed()`.
2. `has_stat_check()` → `DialogEventUI._begin_stat_check_prepare(choice)`.
   - **Текст узла (`narrator_text`/`speech_text`) остаётся на экране** —
     именно поэтому «флейвор» действия (например, «Дверь выглядит очень прочной…»)
     должен лежать в `narrator_text` узла, который содержит сам выбор-проверку.
   - `StatCheckBoostCatalog.list_offerable()` добавляет кнопки предметов-бустов.
   - Кнопки `KEY_STAT_CHECK_START` и `KEY_STAT_CHECK_CANCEL`.
3. `_on_confirm_stat_check()` → `_run_stat_check()` →
   `EncounterManager.resolve_choice_stat_check()` → бросок через
   `StatCheckManager.perform_resolved_check()`, затем результат в модалке
   `StatCheckRollModal`.
4. При успехе берётся `success_outcome`, при провале — `failure_outcome`.

Следствие для автора: **нельзя** помещать текст-завязку проверки на узел-результат
(`*_ok` / `*_fail`) — в момент, когда игрок применяет бусты, UI показывает текущий
узел. Вынесите действие в отдельный узел с проверкой:

```jsonc
"room1": {
  "narrator_text": "Дверь заперта. Можно взломать или выломать.",
  "choices": [
    { "id": "opt_lp", "text": "Использовать отмычку", "require_item": "LOCKPICK",
      "next_dialog_id": "room1_lockpick" },
    { "id": "opt_force", "text": "Попробовать выломать дверь",
      "next_dialog_id": "room1_force" },
    { "id": "opt_leave", "text": "Вернуться в главный зал",
      "next_dialog_id": "return_hall" }
  ]
},
"room1_force": {
  "narrator_text": "Дверь выглядит очень прочной, но стоит попробовать её выломать.",
  "choices": [
    { "id": "opt_force_roll", "text": "[STR Check] Навалиться на дверь",
      "stat_check": "STR", "difficulty": "HARD",
      "success_next_dialog_id": "room1_str_ok",
      "failure_next_dialog_id": "room1_str_fail" }
  ]
}
```

Эталон такого построения — `data/encounters/events/enc_wounded_composite.json`
(узел `node_attempt_help` с `[INT Check]`).

### Подсказка о проверке в навигационных выборах

Если выбор только **ведёт** к узлу с проверкой (сам бросок будет на следующем
экране), игрок должен заранее видеть, какая проверка впереди. Поэтому в тексте
такого выбора указывайте теги характеристик в квадратных скобках в конце:

| Куда ведёт | Пример метки |
| --- | --- |
| одна проверка | `Попробовать выломать дверь [STR]` |
| на выбор из нескольких | `Поискать расходники [INT/LCK]` |

Правила:

- Выборы, которые **сами** являются проверкой (`stat_check`), разметку не требуют —
  UI сам подставляет `[STR check] … (STR: Nd6 | …)` через
  `DialogChoiceData.format_stat_check_label()`.
- Хинт нужен только на промежуточных навигационных выборах
  (`next_dialog_id` → узел с `stat_check`).
- Формат тега — `[STR]`, `[INT]`, `[LCK]`, для нескольких — `[INT/LCK]`.
- Общие продолжения-циклы (`Continue` → тот же набор уже показанных проверок)
  разметкой не снабжаются.

## 8. Push-your-luck ветвление и случайные реплики

- `branch_chances` — массив шансов по индексу визита узла. Узел с непустым
  `branch_chances` при каждом «свежем» входе бросает `randf() < chance` и
  показывает одну кнопку `Continue`, ведущую в `branch_success_node` (успех) или
  `branch_failure_node` (провал).
  - Счётчик визитов — `DialogEventUI._branch_visits[node.id]`; повторный рендер
    (resize / смена языка) **не** увеличивает его (`_show_node(id, is_rerender=true)`).
- `narrator_variants_en/ru` — варианты текста узла по индексу визита
  (последний повторяется).
- `speech_pool_en/ru` — пул реплик, из которого случайно выбирается одна строка.
- `speech_pool_visits` — для каких визитов показывать пул (пусто = для всех).

Пример (`return_hall`): первые два возврата показывают реплику из пула,
третий — нет.

## 9. Сюжетные флаги и боевые трейты

`reward.flags: ["specimen_614_escaped"]` выставляет флаг в `StoryEventManager`
(кроме `pale_maiden_pact`, у которого своя логика). Флаги можно читать в бою:

```gdscript
# EncounterManager._apply_story_combat_traits()
if StoryEventManager.has_specimen_614_escaped():
    data.trait_ids.append(EnemyData.TRAIT_PREEMPTIVE_STRIKE)
```

Флаг сбрасывается при старте события в `StoryEventManager.notify_event_started()`,
чтобы повторный заход не наследовал состояние.

## 10. Служебные узлы

- `end_encounter` — завершение энкаунтера (закрыть диалог).
- `combat`-исход сам по себе завершает диалог и запускает бой; после победы
  открывается экран пост-боевых наград.
- `options_inherit` + `disable_used_choices` дают «хаб»: общий набор выборов,
  где применённые комнаты блокируются (пример — `enc_deep_pit`, `enc_specimen_614`).

## 11. Полный минимальный пример

```jsonc
{
  "id": "enc_training",
  "god_name": "Old Terminal",
  "god_name_ru": "Старый терминал",
  "image_path": "res://assets/sprites/story/raim_city.png",
  "dialogs": {
    "start": {
      "narrator_text_ru": "В стене мерцает терминал.",
      "choices": [
        { "id": "opt_hack", "text_ru": "Взломать",
          "next_dialog_id": "hack" },
        { "id": "opt_leave", "text_ru": "Уйти",
          "next_dialog_id": "end_encounter" }
      ]
    },
    "hack": {
      "narrator_text_ru": "Пальцы зависают над ржавой клавиатурой.",
      "choices": [
        { "id": "opt_roll", "text_ru": "[Проверка INT] Обойти защиту",
          "stat_check": "INT", "difficulty": "MEDIUM",
          "success_next_dialog_id": "hack_ok",
          "failure_next_dialog_id": "hack_fail" }
      ]
    },
    "hack_ok": {
      "narrator_text_ru": "Доступ получен.",
      "choices": [
        { "text_ru": "Продолжить", "next_dialog_id": "end_encounter",
          "reward": { "type": "compound", "effects": [
            { "type": "exp_tier", "tier": "TRIVIAL" },
            { "type": "loot", "pool": "tiered_gear", "pick_count": 1 }
          ] } }
      ]
    },
    "hack_fail": {
      "narrator_text_ru": "Терминал блокируется.",
      "choices": [
        { "text_ru": "Продолжить", "next_dialog_id": "end_encounter",
          "reward": { "type": "damage", "amount": 3 } }
      ]
    }
  }
}
```
