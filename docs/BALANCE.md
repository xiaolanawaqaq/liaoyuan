# 燎原 — deterministic campaign rules and balance

## Design intent

Five fixed 14×10 puzzles, with an inspectable threat rather than random ignition trials. Planning never advances time. A first-time player can complete the tutorial with three shovel actions; later levels add two-step tree clearing, scheduled wind changes, competing fronts, and timed water protection. The supplied solutions finish in 6–8 resolutions. Unused action points do not carry over.

This is a game model, not a real-world fire-safety simulator. The campaign makes no claim of affiliation with or submission to an official event.

## Public rules

### Heat and simultaneous fire

- Fire reaches all eight neighboring cells, including diagonals. There is no extra diagonal distance penalty and no corner-blocking exception.
- Each neighbor that was already burning at the start of resolution contributes **1 heat**, or **2 heat** if the neighbor-to-target direction has a positive dot product with the current wind. Contributions add.
- Heat thresholds are grass **3**, shrub **3**, tree **4**, house **4**. Rock, water, firebreak, and ash cannot accumulate heat or burn.
- On a dry, non-burning cell, incoming heat is added to stored heat. With no incoming heat, stored heat cools by **1**, never below zero.
- Reaching the threshold ignites the cell. Its heat counter resets to zero. New fire cannot spread until the next resolution; the whole turn is simultaneous.
- Burning lifetimes are grass **2**, shrub **3**, tree **4**, house **2**. A fire with one remaining tick still sends heat before becoming ash. New fire starts with its full lifetime.
- Any house ignition immediately loses the level. Victory occurs only when all fire has naturally exhausted and every house remains intact. Tools never directly set victory.

### Wind and foresight

`state.wind` is the wind used by the **imminent** end-turn resolution. `state.forecast[0..2]` shows the **following** three resolutions, not the current one. After ending a turn, the previous `forecast[0]` becomes `wind`.

Each level has a public `winds` schedule. After the last entry, the final wind persists. There is no random wind walk, fuel roll, hidden probability, or RNG object in the state. The seed changes only decorative `cell.variant`; all gameplay, scores, and winning sequences are seed-independent.

`forecast_next(state)` and `end_turn(state)` use the same pure transition calculation. Given an unchanged planning state, their **entire returned dictionaries are equal**. The preview predicts the outcome of pressing End Turn now; later tool actions can change it. A valid tool action immediately recomputes `state.danger`.

### Tools and water timing

All tools cost **1 AP**. All tools reject burning cells; **water is preventive protection, not an extinguisher**.

| Tool | Valid target | Effect |
|---|---|---|
| Shovel | Non-burning grass or shrub, wet or dry | Permanent firebreak; clears heat and wet timer |
| Axe | Non-burning tree, wet or dry | Leaves grass; clears heat, preserves existing wet timer |
| Water | Non-burning grass, shrub, tree, or house | Clears heat and sets `wet = 3` |

Making a tree into a firebreak takes **axe + shovel = 2 AP**. Axe is not a valid substitute for shovel on shrubs.

Water blocks **all** incoming heat for the next **three complete resolutions**. The protection test happens before decrementing the timer:

| Before resolution | Protected during this resolution? | After resolution |
|---|---|---|
| `wet = 3` | Yes | `wet = 2` |
| `wet = 2` | Yes | `wet = 1` |
| `wet = 1` | Yes | `wet = 0` |
| `wet = 0` | No | `wet = 0` |

Water can refresh a partially spent timer. Repeating it when `wet == 3` is rejected with a reason and spends no AP. Any invalid action is a complete no-op. Ending a terminal game is also a complete no-op.

## Conservation and stars

Vegetation value is grass **1**, shrub **2**, tree **3**. Houses do not enter this denominator; keeping **all** houses is a separate mandatory victory condition.

- `init_value` is fixed from the original map, before initial ignition.
- `burnt_value` is charged **at ignition**, including initial fires. Exhaustion does not charge it again.
- `cleared_value` is vegetation removed by tools: axe removes **2**, shovel on the remaining grass removes the last **1**, shovel on shrub removes **2**.
- `saved_value = init_value - burnt_value - cleared_value`.
- `saved_fraction = saved_value / init_value`.
- `lost_fraction` and `loss_fraction` are aliases for `1 - saved_fraction`.
- `init_fuel` and `burnt_fuel` retain their separate cell-count meaning. Stars use weighted value, not this count.

A victory earns:

- **3 stars:** at least **70%** vegetation saved **and** completion at or before the level's `par`.
- **2 stars:** at least **45%** saved, including runs with good conservation that miss par.
- **1 star:** any other victory.
- **0 stars:** playing or lost.

Removing more forest never shrinks the original denominator and never increases conservation. Action count is displayed but is not a separate star gate. Undo restores both AP and conservation accounting.

## Verified campaign balance

All results below are obtained by applying the stored tool sequences and calling `end_turn`, without changing cells, budgets, outcomes, or scores. No-defense runs genuinely call `end_turn` each iteration and lose from an ignited house.

| Level | Main lesson | AP/turn | Par | Winning turns | Actions | Vegetation saved | Burned value | Cleared value | Stars | No-defense loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 初火 · 三格防线 | Water-to-water grass line; diagonal closure | 3 | 8 | 6 | 3 | 113/132 = **85.61%** | 16 | 3 | 3 | Turn 10 |
| 2 树桥 · 两步开路 | Axe leaves fuel; finish with shovel | 3 | 10 | 8 | 4 | 90/124 = **72.58%** | 28 | 6 | 3 | Turn 11 |
| 3 转风 · 留住南岸 | Two exits; east-to-south wind planning | 2 | 10 | 8 | 6 | 122/144 = **84.72%** | 16 | 6 | 3 | Turn 7 |
| 4 两线 · 借水争时 | Two fronts; temporary cover while completing another line | 2 | 10 | 8 | 8 | 106/141 = **75.18%** | 26 | 9 | 3 | Turn 5 |
| 5 林场 · 三处守望 | Three houses; preserve west tree bridges while removing east fuel | 3 | 11 | 8 | 10 | 125/175 = **71.43%** | 42 | 8 | 3 | Turn 7 |

### Reproducible strategies

Coordinates below and in `tests/solutions.json` are **zero-based** `(column, row)`. After each numbered turn, resolve once; after the listed actions, continue empty turns until the stated victory.

1. **Tutorial:** Turn 1 shovel `(5,3)`, `(5,4)`, `(5,5)`. This three-cell vertical line meets water at both ends, blocking direct and diagonal spread. Win after resolution 6.
2. **Tree bridge:** Turn 1 axe then shovel `(6,3)`, then axe `(6,4)`. Turn 2 shovel `(6,4)`. Both connections are now permanent breaks. Win after resolution 8.
3. **Wind change:** Turn 1 shovel `(6,1)`, `(6,2)`. Turn 2 shovel `(6,3)`, `(4,4)`. Turn 3 shovel `(2,4)`, `(3,4)`. The east exit closes before the nearby fire arrives; the south exit closes before the later front. Win after resolution 8.
4. **Two fronts:** Turn 1 axe then shovel `(4,2)`. Turn 2 water `(4,3)` and shovel `(9,6)`. Turn 3 shovel `(9,7)`, `(9,8)`. Turn 4 axe then shovel the still-protected `(4,3)`. Water buys time; it is not the whole defense. Win after resolution 8.
5. **Finale:** Turn 1 water `(4,2)` and shovel `(4,3)`, `(4,7)`. Turn 2 water `(4,6)`, then axe and shovel `(11,3)`. Turn 3 shovel `(11,4)`, `(11,5)`. Renew `(4,2)` on turn 4 and `(4,6)` on turn 5. The valuable west tree bridges survive, while the mixed east bridge is permanently cut. Win after resolution 8.

The stored JSON includes all empty turns up to the **first** victory. A GUI runner should perform exactly each turn's actions, then press End Turn once. Do not append an extra post-victory turn.

### Real scoring counterexamples

Tests also perform these actual playable runs:

- Level 2's normal solution: **3 stars**, 72.58% saved.
- Same solution plus six unnecessary axes in the protected forest: **2 stars**, 62.90% saved.
- Same solution plus twenty unnecessary axes: **1 star**, 40.32% saved.
- Level 1's normal break, followed by watering `(1,3)` and `(2,3)` on turn 2: delayed combustion gives a real **turn-9** victory with the same 85.61% saved, but **2 stars** because par is 8.

Thus all star tiers and the timing gate are checked using real victories, not fabricated `status = won` fixtures.

## Integration contract

### State and cells

Required original state keys are preserved: `level`, `ap`, `ap_max`, `turn`, `wind`, `forecast`, `cells`, `status`, `reason`, `huts`, `hut_alive`, `init_fuel`, `burnt_fuel`, `danger`.

Added state keys: `schema_version`, `seed`, `init_value`, `burnt_value`, `cleared_value`, `actions_used`.

Cells retain `tile`, `burn`, `wet`, `variant` and add:

- `heat`: currently stored integer heat.
- `threshold`: tile's ignition threshold, zero if nonflammable.
- `cleared`: cumulative removed vegetation value from this original map cell; supports scoring and save validation.

`turn` is the current planning turn, starting at 1. Completed resolutions are `turn - 1`, which is returned as `stats(state).turn`. `burn` means remaining outgoing-heat resolutions, not an animation counter. `danger` is the sorted, unique index array of cells that will ignite on the imminent resolution.

Constants include `WET_TICKS = 3`, `TOOL_COSTS`, `HEAT_THRESHOLDS`, original tile identifiers, `DIRS`, `DIR_CH`, `TILE_NAMES`, `TOOL_NAMES`, `LEVELS`, `COLS`, and `ROWS`. Every level includes `name`, `goal`, `brief`, `tip`, `par`, `ap`, `seed`, plus the map, initial fires, and wind schedule.

### Transition/preview dictionary

`forecast_next(state)` and `end_turn(state)` both return:

- `ignited`, `exhausted`, `threatened_huts`: sorted index arrays.
- `heat`, `incoming_heat`, `wet`, `burn`: 140-entry integer arrays indexed by cell. `heat/wet/burn` are the exact post-resolution counters. `incoming_heat` is effective received heat, **zero for protected cells**; newly ignited cells' resulting heat is zero.
- `wind`: wind used for this resolution.
- `next_wind`, `next_forecast`: the following planning state's wind display.
- `forecast`: a detached copy of the original three-future-wind display.
- `wind_changed`: whether the following planning state's wind differs.
- `hut_lost`, `spread`, `status`, `ignored`.

After a terminal outcome, preview/end-turn returns `ignored = true`, empty event index arrays, unchanged counters and wind, and never mutates state.

### Undo and saving

`clone_state(state)` is a recursive detached dictionary/array copy. Keep one snapshot before each valid planning action, restore it by assigning another clone, and clear the planning undo stack after resolving a turn. No RNG object exists to share or advance accidentally. The sim intentionally does not own UI undo history.

State contains only ordinary JSON values. Use:

- `serialize_state(state) -> Dictionary`
- `deserialize_state(JSON.parse_string(text)) -> Dictionary`

Both return a validated, detached state, or `{}` for invalid data. Schema version 1 is deliberately strict: unknown/missing fields, nonintegral counters, bad ranges, impossible tile conversions, altered original totals, inconsistent burn/clearing/house accounting, contradictory result status, and stale wind or danger are rejected. JSON numeric floats are normalized to integers. Only fixed-map decorative variants are accepted.

This is validation for local save integrity, **not** cryptographic proof that an arbitrary hand-crafted save followed a legal historical action sequence. Old RNG-based saves are not compatible. Keep UI metadata and undo history outside the serialized simulation dictionary.

## Automated validation

Run with a finite timeout:

```sh
timeout 35 godot --headless --path . --check-only --script res://scripts/sim.gd
timeout 35 godot --headless --path . --script res://scripts/test_sim.gd
```

Verified using Godot **4.6.3.stable.official.7d41c59c4**. The full suite exits 0 with **126427 passed, 0 failed**. It includes:

- Map/metadata validity, fixed initialization, and all five stored three-star solutions.
- All five genuine no-defense defeats, with exact loss turns.
- Full preview/event equality and per-cell heat/wet/burn equality after each checked resolution.
- All eight wind directions, diagonal reach, additive heat, cooling, simultaneous spread, and burn lifetime.
- Three full protected water resolutions, fourth-resolution expiry, refresh, hot-cell cooling, and no extinguishing.
- Tool legality, all action costs, zero AP, unused AP behavior, and invalid-action immutability.
- Snapshot isolation, deterministic undo/replay, and detached preview/save arrays.
- Mid-planning, in-progress, won, and lost JSON save round trips; malformed-input matrices.
- Terminal immutability and genuine 0/1/2/3-star scoring, including the par gate and anti-axe-farming checks.
- Twenty additional seeded, legally generated campaign playthroughs checking forecast, undo, conservation monotonicity, saving, and bounded completion.

Controlled miniature board fixtures are used only for isolated heat/water rules. Campaign solutions, balance results, and scoring victories never edit simulation state to make a win.
