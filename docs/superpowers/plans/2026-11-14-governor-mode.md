# Governor Mode (v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The player governs a first-level subnational unit, with an office title that depends on the unit type, a state budget, federal transfers, a unit election, and a party directory subordinate to the national party.

**Architecture:** A new sim object `StateGov` (RefCounted, owned by `GameWorld.governor`) derives its economy one-way from the parent country. `world.player` stays the parent country with `in_office = false`, so `NationAI` keeps running it; a new `GameWorld.role()` tells the interface which of four roles applies. Competences come from `data/competences.json`.

**Tech Stack:** Godot 4.7, GDScript. Headless tests `godot --headless --path . -s tests/X.gd` (print `RESULT: N failures`); interface tests `--ui-NAME`; whole suite `tools/run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-11-14-governor-mode-design.md`

## Global Constraints

- New code, comments and docs in English; game msgids (`tr("...")`) stay in Portuguese.
- `StateGov` and `Competences` live in `scripts/sim/` and are never autoloads (sim and `-s` tests cannot see autoloads).
- Every window or tab is an editable `.tscn`, never built in code. Windows live in `scenes/ui/panels/`, scripts in `scripts/ui/`.
- v1 does not write back into the national accounts: `StateGov` never assigns to any `Country` field.
- Only first-level units (`parent == -1`) are playable; municipalities are not.
- Democratic means `Country.dem >= 4.0`, as everywhere else in the code.
- Old saves load in country mode. One branch, `claude/governador` (worktree `.claude/worktrees/governador`).
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

- Country with one first-level unit (state would equal the country): creation refused, start screen does not offer it. Pinned in Task 3 and Task 8.
- Save from before this feature, loaded: country mode, no governor, nothing crashes. Task 5.
- Union is a dictatorship: no unit election is ever scheduled, and losing the post means game over only through a union change. Task 6 and Task 7.
- Governed unit removed or merged away by a divisions edit: the game ends with "unit gone" instead of erroring on a missing id. Task 7.
- A day-skip (+7/+30) crossing a union change: the skip pauses on the decision and resumes. Task 7.

---

### Task 1: Office title per unit type

**Files:**
- Modify: `scripts/sim/subdivisions.gd` (types dict, `add_type`, `to_dict`/`from_dict` already save `types` wholesale at line ~945)
- Test: `tests/subdivisions.gd`

**Interfaces:**
- Produces: `Subdivisions.DEFAULT_OFFICE := {"name": "Governador", "female": false}`, `Subdivisions.OFFICE_BY_TYPE_NAME := {"Município": {"name": "Prefeito", "female": false}, "Cidade": {...same...}}`, `func office_of(type_id: int) -> Dictionary` (`{name, female}`), `func set_office(type_id: int, office_name: String, female := false) -> Dictionary` (`{ok, msg}`).

- [ ] **Step 1: Write the failing tests** in `tests/subdivisions.gd`: a type named "Município" has `office_of(id).name == "Prefeito"`; "Estado" and a custom type "Cantão" give "Governador"; `set_office(t, "  ")` returns `ok == false`; `set_office(t, "Intendente").ok` then `office_of(t).name == "Intendente"`; after `from_dict(to_dict())` the custom office survives; a types array without office keys (old save) still answers with the defaults.
- [ ] **Step 2: Run** `godot --headless --path . -s tests/subdivisions.gd`. Expected: FAIL (`office_of` not defined).
- [ ] **Step 3: Implement.** Types keep two optional keys, `office` (String) and `office_female` (bool); `office_of` falls back to `OFFICE_BY_TYPE_NAME[type name]`, then `DEFAULT_OFFICE`.
- [ ] **Step 4: Run** the same test. Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `Unit types carry the name of their executive office`.

### Task 2: Competences data

**Files:**
- Create: `data/competences.json`, `scripts/sim/competences.gd`, `tests/competences.gd`

**Interfaces:**
- Produces: `class_name Competences`; `const AREAS := ["health", "education", "public_security", "infrastructure", "taxes"]`; `static func for_country(iso: String) -> Dictionary` (area to `"state"|"union"|"shared"`); `static func decides(iso: String, area: String) -> bool` (true for `state` and `shared`); `static func is_unitary(iso: String) -> bool`; `static func state_weight(iso: String) -> float` (share of `AREAS` the state decides, `shared` counting half).

- [ ] **Step 1: Write the failing test**: for `BRA`: `decides("BRA", "health")`, not `is_unitary("BRA")`; for `USA`: `decides("USA", "public_security")`; for `FRA`: `is_unitary("FRA")` and `state_weight("FRA") < state_weight("BRA")`; an unknown iso gets the default table; every entry only holds the three values above and every area.
- [ ] **Step 2: Run** `-s tests/competences.gd`. Expected: FAIL.
- [ ] **Step 3: Implement.** JSON shape: `{"default": {...}, "unitary_default": {...}, "federal": ["BRA","USA","DEU","ARG","MEX","IND","AUS","CAN","RUS","NGA","CHE"], "countries": {"BRA": {...}, "USA": {...}}}`. Countries not in `federal` use `unitary_default` (most areas `union`, `infrastructure` `shared`). Load once, cache in a static var.
- [ ] **Step 4: Run.** Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `Competences table per country`.

### Task 3: StateGov core (economy and budget)

**Files:**
- Create: `scripts/sim/state_gov.gd`, `tests/governor.gd`

**Interfaces:**
- Consumes: `Subdivisions.pop_share(id)`, `Competences.decides`, `Country.y_usd()`.
- Produces: `class_name StateGov`; vars `unit_id: int`, `union_iso: String`, `party_id := -1`, `approval := 0.5`, `next_election := -1.0`, `in_office := true`, `tax_rate: float`, `spend: Dictionary` (area to share of state GDP), `debt := 0.0`, `transfers_in := 0.0`; `static func create(world: GameWorld, unit_id: int) -> Dictionary` (`{ok, msg, gov}`; refuses a non-first-level unit and a country with a single first-level unit); `func union(world) -> Country`; `func gdp(world) -> float`; `func pop(world) -> float`; `func revenue(world) -> float`; `func spending(world) -> float`; `func set_spend(area: String, share: float) -> Dictionary`; `func step_month(world) -> void`.

- [ ] **Step 1: Write the failing tests** in `tests/governor.gd` (`_world(iso)` helper as in `tests/politics.gd`): `create` on a Brazilian state gives `ok`; `create` on a municipality gives `ok == false`; for a country with one first-level unit gives `ok == false`; sum of `gdp` over all first-level units of `BRA` is at most `union.y_usd()`; `set_spend("education", 0.05).ok`, and for an area the union decides (e.g. `FRA` `health`) `ok == false`; **no feedback**: snapshot `y`, `pop`, `revenue`, `spending`, `debt_loc` of the union, run `step_month` twelve times, assert all equal.
- [ ] **Step 2: Run** `-s tests/governor.gd`. Expected: FAIL.
- [ ] **Step 3: Implement.** `gdp = union.y_usd() * pop_share * relative_income`, with `relative_income` the unit's `pop_w`-weighted factor, clamped 0.4 to 2.5 and normalized so the first-level units sum to 1 (compute once per `create`, store as `gdp_share`). `revenue = tax_rate * gdp + transfers_in`; `step_month` accrues `debt` when spending exceeds revenue and reads nothing it writes.
- [ ] **Step 4: Run.** Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `StateGov: derived economy and budget`.

### Task 4: Federal transfers and funding requests

**Files:**
- Modify: `scripts/sim/state_gov.gd`, `tests/governor.gd`

**Interfaces:**
- Consumes: `Politics.distance(a, b)`, `world.politics.ruling_party(iso)`, `Competences.state_weight`.
- Produces: `func affinity(world) -> float` (0 to 1, from the distance between the governor's party and the union's ruling party; `1.0` for the same party); `func monthly_transfer(world) -> float`; `func request_funds(world) -> Dictionary` (`{ok, msg, amount}`; cooldown `FUNDS_COOLDOWN_MONTHS := 6`; chance rises with `affinity` and `approval`; draws from `world.rng`).

- [ ] **Step 1: Write the failing tests**: with a fixed seed, `monthly_transfer` is larger when the governor's party is the union's ruling party than when it is the farthest party; a second `request_funds` inside six months returns `ok == false` and a cooldown message; a successful request raises `transfers_in`.
- [ ] **Step 2: Run** `-s tests/governor.gd`. Expected: FAIL.
- [ ] **Step 3: Implement.** `monthly_transfer = union.revenue * pop_share * (1.0 - state_weight) * (0.6 + 0.8 * affinity)`; `step_month` sets `transfers_in` from it. Transfers are not deducted from the union (v1 rule in the spec).
- [ ] **Step 4: Run.** Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `StateGov: federal transfers and funding requests`.

### Task 5: World integration, roles and saves

**Files:**
- Modify: `scripts/sim/world.gd` (`governor` var, `set_governor`, `role`, `_on_month`, `to_dict`/`load_dict`, `tick_day` untouched), `scripts/sim/legislation.gd` (`role`, `ROLE_ACTIONS` gets `governor` and `unit_opposition`)
- Test: `tests/governor.gd`, `tests/save_compat.gd`

**Interfaces:**
- Consumes: `StateGov.create`, `Politics.join_party`.
- Produces: `GameWorld.governor: StateGov` (null in country mode); `func set_governor(unit_id: int, diff: String) -> Dictionary` (sets `player` to the union, `in_office = false`, joins the union's ruling party at start, creates the `StateGov`); `func role() -> String` returning `"head"`, `"opposition"`, `"governor"` or `"unit_opposition"`; `GameWorld.office_title() -> String` (the title of the governed unit's type, or empty). `StateGov.to_dict()` and `static func from_dict(d: Dictionary) -> StateGov`.

- [ ] **Step 1: Write the failing tests**: after `set_governor`, `role() == "governor"`, `player.iso` is the union, `governed() == null`, and a year of `tick_day` leaves the union evolving (its `y` changes); `Legislation.role` equals `role()` in governor mode and `can(w, "present")` is false; `to_dict`/`load_dict` round-trips `governor`, `approval`, `party_id`; in `tests/save_compat.gd`, a save dict with no `governor` key loads with `governor == null` and `role() == "head"`.
- [ ] **Step 2: Run** both tests. Expected: FAIL.
- [ ] **Step 3: Implement.** `_on_month` calls `governor.step_month(self)` when set. Save key `"governor"` is omitted when null.
- [ ] **Step 4: Run** both tests. Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `World: governor mode state, roles and saves`.

### Task 6: Party, unit election and directory in opposition

**Files:**
- Modify: `scripts/sim/state_gov.gd`, `scripts/sim/world.gd` (monthly election check), `scripts/sim/politics.gd` (directory helpers)
- Test: `tests/governor.gd`

**Interfaces:**
- Consumes: `Politics.join_party`, `Politics.party_fund`, `Politics.spend_fund`.
- Produces: `StateGov.hold_election(world) -> Dictionary` (`{won: bool, winner_party: int}`; the player's party wins when `approval` beats the best rival drawn from `world.rng`); `Politics.directory_fund(world) -> float` (`party_fund * DIRECTORY_FUND_SHARE`, `DIRECTORY_FUND_SHARE := 0.35`); `Politics.national_veto(world) -> bool` (true when the distance between the player's compass and the national party line exceeds `COALITION_REBEL_DISTANCE`, blocking the next candidacy); `func enter_unit_opposition(world, why: String) -> void`.

- [ ] **Step 1: Write the failing tests**: with `approval` forced to 0.95 the election is won, with 0.05 it is lost and `role() == "unit_opposition"`; a democratic union schedules `next_election > 0`, a union with `dem < 4.0` leaves `next_election == -1.0` across 5 simulated years; `directory_fund` is strictly below `party_fund`; `national_veto` is true for a leader whose compass is on the opposite corner of the national party's, and false for a leader at the party's own compass.
- [ ] **Step 2: Run** `-s tests/governor.gd`. Expected: FAIL.
- [ ] **Step 3: Implement.** Opposition reuses `Politics.criticize`, `Politics.campaign` and the poll spends, routed to the unit's approval. `Politics.censure` returns `{ok: false}` while `governor != null` (no assembly in v1).
- [ ] **Step 4: Run.** Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `StateGov: election, opposition directory and national line`.

### Task 7: Union change and unit lifecycle

**Files:**
- Modify: `scripts/sim/state_gov.gd`, `scripts/sim/world.gd`
- Test: `tests/governor.gd`

**Interfaces:**
- Consumes: `Territories.owner_at(pos, world)`, `GameWorld.resolve_owner(iso)`, `Politics.distance`, `COALITION_MAX_DISTANCE`, `ask_player`, `_finish`.
- Produces: `func current_union(world) -> Country` (cession owner at the unit's `center`, else `resolve_owner(unit.owner)`); `func check_union(world) -> void` (monthly; on change, runs `_change_union`); `func compass_keeps(world, new_union: Country) -> bool` (`Politics.distance` between `leader.econ/social` and the new union's ruling party, `<= COALITION_MAX_DISTANCE`); `World.finish_unit_gone()` ending the game with reason `"unidade"`.

- [ ] **Step 1: Write the failing tests**: simulate annexation by assigning the governed unit's country as `annexed_by` another union: democratic new union with a distant compass gives `role() == "unit_opposition"` and a pending party choice, with a close compass gives `"governor"`; dictatorship new union (`dem < 4.0`) with a distant compass sets `world.over == true`, with a close compass auto-joins `ruling_party` and keeps `role() == "governor"`; deleting the governed unit from `subdivisions.units` ends the game with reason `"unidade"`; a split where the capital lies in the piece that keeps the id keeps `unit_id`, and in the other piece the governor follows the piece that contains the capital.
- [ ] **Step 2: Run** `-s tests/governor.gd`. Expected: FAIL.
- [ ] **Step 3: Implement.** In a democracy the new party is chosen through `ask_player` with one option per party of the new union (reusing the party picker in Task 8); the compass is read before joining. The prompt sets `always: true` so it also arrives in opposition.
- [ ] **Step 4: Run.** Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `StateGov: union change by compass, regime rules, unit lifecycle`.

### Task 8: Start screen, roles in the HUD and titles in texts

**Files:**
- Modify: `scenes/ui/start_screen.tscn`, `scripts/ui/main.gd` (`_build_start_screen`, start flow near line 441), `scripts/ui/hud.gd` (`_apply_role`, `_refresh_office`), `scenes/ui/hud.tscn` (group assignments), `scenes/ui/dock.tscn`
- Test: `tests/ui_governor.gd`

**Interfaces:**
- Consumes: `GameWorld.role()`, `GameWorld.office_title()`, `GameWorld.set_governor`.
- Produces: scene groups `governor_only` and `unit_opposition_only`, hidden unless `role()` matches; `gov_only` and `opposition_only` both hidden in governor roles; a `sovereign_only` group hidden whenever `world.governor != null` (military, currency, trade, divisions editing, world); a "Country / Unit" toggle plus a unit list on the start screen, listing only first-level units of countries with at least two of them.

- [ ] **Step 1: Write the failing interface test** `tests/ui_governor.gd` modeled on `tests/ui_opposition.gd`: start in governor mode on a Brazilian state; assert `dock_military`, `dock_currency`, `dock_trade`, `dock_world` are hidden and `dock_panel`, `dock_fiscal`, `dock_economy`, `dock_union` visible; a unit of a municipality type is not in the start list; the player label shows "Governador" for a state and the title changes with `set_office`.
- [ ] **Step 2: Run** `godot --path . -- --ui-governor --shots=/tmp/gm-shots`. Expected: FAIL.
- [ ] **Step 3: Implement** in the scenes (groups, toggle, list) and `_apply_role`; texts that say "governador" read `world.office_title()` with `role_text` for window titles.
- [ ] **Step 4: Run** the same command. Expected: `RESULT: 0 failures`.
- [ ] **Step 5: Commit** `Start screen and HUD roles for governor mode`.

### Task 9: State windows

**Files:**
- Create: `scenes/ui/panels/state_panel.tscn`, `state_budget.tscn`, `union_panel.tscn`, `directory_panel.tscn` and their scripts `scripts/ui/state_panel.gd`, `state_budget.gd`, `union_panel.gd`, `directory_panel.gd`
- Modify: `scenes/ui/hud.tscn` (windows and dock items `dock_union`, `dock_directory`), `scripts/ui/divisions_panel.gd` (office-name field per type, calling `set_office`)
- Test: `tests/ui_governor.gd`

**Interfaces:**
- Consumes: everything from Tasks 3 to 7.
- Produces: `StatePanel` (approval, GDP, population, party, next election), `StateBudget` (tax slider and one slider per area; areas the union decides are disabled with a hint), `UnionPanel` (affinity, monthly transfer, a "Request funds" button calling `request_funds`), `DirectoryPanel` (`unit_opposition_only`: directory fund, campaign, criticize, poll, national line status).

- [ ] **Step 1: Extend the failing interface test**: opening each window in its role shows its labels filled; the budget slider of a union-decided area is disabled; clicking "Request funds" twice shows the cooldown message; the directory window is closed and locked in `governor` role and open in `unit_opposition`.
- [ ] **Step 2: Run** `godot --path . -- --ui-governor --shots=/tmp/gm-shots`. Expected: FAIL.
- [ ] **Step 3: Implement** the four scenes and scripts (values found by node name, as `hud.gd` already does); the divisions panel shows the office field only for the type it is editing.
- [ ] **Step 4: Run.** Expected: `RESULT: 0 failures`; look at the screenshots.
- [ ] **Step 5: Commit** `State windows: panel, budget, union and directory`.

### Task 10: Docs, translations and full suite

**Files:**
- Modify: `README.md` (a "Governor mode" section and the controls and windows tables), `locale/` via `godot --headless --path . --script tools/extract_pot.gd -- --merge`

- [ ] **Step 1:** Write the README section from the spec: what the mode is, the four roles, competences, transfers, union change rules.
- [ ] **Step 2:** Run the pot merge and fill the English and Spanish msgids for new strings.
- [ ] **Step 3: Run** `tools/run_tests.sh all`. Expected: every line `ok`.
- [ ] **Step 4: Commit** `Governor mode: docs and translations`.
