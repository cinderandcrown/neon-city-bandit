# Game Center competition plan

Nicholas wants Game Center used to the fullest to drive skill-only competition.
**Do not build this until Level 1 fun-pass plays well on TestFlight.** Ship fun fixes first; then land this plan in small PRs.

Rules (binding):

- Skill only. No paid entries, wagers, or real-value prizes.
- If any reward is random, show the odds in UI.
- ASC scripts are config-only (no version submit / release). Never push tags.
- Auth never blocks play. Access point on **menu + results only**, never during play.
- Check every API against current GameKit docs and the iOS 26 Games app. Do not invent APIs. Gate newer APIs with `#available` / `if #available`.

## Already in repo (baseline)

- Entitlement `com.apple.developer.game-center` + non-blocking auth (`MagpieApp` / `GameCenterService`).
- Catalog: `Assets/GameCenter/catalog.json` (`daily_heist`, `most_wanted_weekly`, `best_combo`, ~15 achievements including `bandit_of_both_worlds`).
- ASC helper: `scripts/appstore_connect.py ensure-game-center` (config only).
- Daily score submit + campaign achievements hooks in `HeistScene`.
- CloudKit ghost store exists in code but **ghost data via CloudKit is still off** for the pace feature below — use leaderboard pace instead until CloudKit is approved.

## Target experience

### 1. Leaderboards

| Board | ID | Cadence | Score |
| --- | --- | --- | --- |
| Daily Heist | `daily_heist` | Recurring 1 day (`P1D`) | `DailyScore` (time + loot + clean) |
| Most Wanted | `most_wanted_weekly` | Recurring 7 days (`P7D`) | Level-win / campaign score |
| Best Combo | `best_combo` | Classic | Max combo |
| Per-level best time | `level_time_<district>` | Classic all-time | Lower is better (ASC ascending) |

- Tag runs with **leaderboard context** (level / district id) via `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)` — documented GameKit API.
- Recurring boards: when loading entries, pass `.allTime` for `timeScope` (Apple: scope applies to non-recurring boards only).
- ASC: extend `catalog.json` + `ensure-game-center` (idempotent; treat 409/422 as already there). Enable App ID `GAME_CENTER` capability before archive (Trash Stack pattern) so cloud profiles include the entitlement. Wire the step in `testflight.yml` after `ensure-bundle-id` / before archive. `check_signed_app` must require `com.apple.developer.game-center`.

### 2. Results screen hook (friend pressure)

On win/fail results (not during play):

1. Load local + friends entries (`loadEntries(for:timeScope:)` / friends range APIs that exist on the deployment OS).
2. Show **your rank**, the **friend just above you**, and the gap: e.g. `0.8s behind Jake` (time boards) or `120 pts behind Jake` (score boards).
3. One-tap **Retry**.
4. **Beat my time** share — prefer Game Center challenge / share sheet APIs that exist; fallback: present leaderboard UI + `UIActivityViewController` with deep link.

Gate any iOS 26-only UI with availability checks; older OS gets rank + retry + leaderboard button.

### 3. Challenges + Games app Activities

- **Challenges:** create from leaderboards (WWDC25 / Games app). No custom server. “Beat my time” should issue a challenge when the API is available; otherwise open the leaderboard challenge UI / share fallback.
- **Activities (`GKGameActivity` / `GKGameActivityDefinition`):** iOS 26+. Configure Daily Heist + per-level activities in ASC/Xcode GameKit bundle. Implement `GKGameActivityListener` / `player(_:wantsToPlay:)` to deep-link into that run (`daily` vs `neon_docks` / etc.). Start/end activity around the run; `setScore(on:to:context:)` when available.
- If Activities APIs are missing on the OS: keep playing; deep link via custom URL (`magpie://heist/daily`, `magpie://heist/<district>`) and leaderboard-challenge fallback only.

### 4. Pace marker (no CloudKit ghost yet)

CloudKit ghost samples stay **off** until approved.

- Show a **pace line** / ghost silhouette driven by leaderboard scores (#1 or selected friend): convert their score/time into a progress fraction along the heist and draw a marker on the progress bar + optional translucent bandit at estimated world X.
- When CloudKit ghosts are allowed later, swap the pace estimator for real samples without changing the results UX.

### 5. Achievements (~15, first-session friendly)

Keep `Assets/GameCenter/catalog.json` as source of truth. Tiering:

- Session 1: `first_heist`, early stomp/mask unlocks, maybe first death-recovery.
- Mid: three-star, no-damage, district clears, crew rescue.
- Shared: `bandit_of_both_worlds` via **Game Center game group** with Trash Stack (`Cinder Crown Bandit Universe`). Prefer group achievements; CloudKit/URL claim only if groups fail.

Report progress with `GKAchievement` — never invent custom server unlocks.

### 6. Access point + auth

- Authenticate as early as title/menu (non-blocking). Play works signed out.
- `GKAccessPoint` visible on title/menu and results only; hide for the entire playing phase (including pause-over-play if the run is live).
- No Game Center overlays mid-run.

## Small PR sequence (after fun-pass)

1. **ASC + entitlement CI** — App ID `GAME_CENTER`, `ensure-game-center` in `testflight.yml`, `check_signed_app` requires entitlement; catalog per-level time boards. Config only.
2. **Score plumbing** — submit Daily + Most Wanted + per-level time + combo with context; unit tests on score helpers.
3. **Results competition strip** — rank / friend-above / gap / Retry / Beat my time (leaderboard fallback). Sim screenshots of results + leaderboard UI.
4. **Pace marker** — progress-bar pace from leaderboard scores (no CloudKit).
5. **Challenges + Activities** — `#available(iOS 26, *)` Activities listener + deep links; challenge create where documented; URL fallback.
6. **Game group + shared badge** — ASC group with Trash Stack; unlock outfit when `bandit_of_both_worlds` reports.

## Evidence (per competition PR)

- Real simulator screenshots: results strip (rank + friend gap) and Game Center leaderboard UI.
- No drawn mockups. No tags.

## Docs / APIs to re-check before each PR

- [GameKit](https://developer.apple.com/documentation/gamekit) — `GKLeaderboard`, `GKAchievement`, `GKAccessPoint`, challenges.
- WWDC25 “Get started with Game Center” — challenges from leaderboards, Activities, Games app.
- [Creating activities for your game](https://developer.apple.com/documentation/gamekit/creating-activities-for-your-game) — `GKGameActivity` / listener (iOS 26+).
- [Apple Games app](https://developer.apple.com/games-app/) — what surfaces leaderboards / challenges / activities.

If an API is missing, deprecated, or undocumented: skip it, note the gap in the PR, and keep the fallback path.
