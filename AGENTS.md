# Contender — Agent Handoff Guide

> **이 문서는 새 Cursor Agent가 이전 대화 없이 프로젝트를 이어가기 위한 인계서다.**  
> 작성 기준: 현재 워크스페이스의 실제 코드 / Scene / Resource / Input Map / 스모크 테스트.  
> **기억·추측으로 시스템을 재구현하지 말 것. 변경 전 해당 `.gd` / `.tres` / `game.tscn`을 다시 열어 확인할 것.**

---

## 1. 프로젝트 개요

| 항목 | 값 |
|---|---|
| 이름 | **Contender** |
| 엔진 | **Godot 4.7.2 Stable** (`project.godot` features: `4.7`) |
| 장르 | 2D **1인칭 POV** 캐주얼 복싱 프로토타입 |
| 렌더러 | **GL Compatibility** |
| 논리 해상도 | **1152×648** (`VisualDisplayLayout.VIEWPORT_SIZE`, `CombatVisualRoot.viewport_size`) |
| 메인 씬 | `res://scenes/game.tscn` |
| 기타 씬 | `scenes/title.tscn`, `scenes/result.tscn` (결과 연동은 `MatchDecision`까지 구현) |
| 타깃 | **Web** 지향 프로토타입. **`export_presets.cfg`는 현재 없음** — 웹 빌드 설정은 아직 미구성. |

`project.godot`에 `window/size`는 명시되어 있지 않다. 비주얼/레이아웃 코드는 전부 **1152×648**을 가정한다.

---

## 2. 확정된 조작 (Input Map)

`project.godot` `[input]` 기준:

| Action | Key | 동작 |
|---|---|---|
| `combat_left_straight` | **J** | Left Straight |
| `combat_right_straight` | **K** | Right Straight |
| `combat_left_hook` | **Shift+J** | Left Hook |
| `combat_right_hook` | **Shift+K** | Right Hook |
| `combat_slip_left` | **A** | Evade Left (movement + timing) |
| `combat_evade_down` | **S** | Evade Down (movement + timing) |
| `combat_slip_right` | **D** | Evade Right (movement + timing) |
| `combat_high_guard` | **Space** | High Guard (hold) |
| `debug_force_player_knockdown` | F1 | 디버그 |
| `debug_force_opponent_knockdown` | F2 | 디버그 |

처리: `scripts/player_combat_input.gd` → `PlayerEvade` / `PlayerActionState` / `PlayerAttackState`.

### 방어 입력 구조 (`player_combat_input.gd` + `player_evade.gd`)

| 동작 | 코드 경로 | 비고 |
|---|---|---|
| **Continuous Evade (A/S/D)** | `EvadeDirection` LEFT/DOWN/RIGHT → `evade_pressed` + `evade_hold_changed` → `PlayerEvade` | Movement와 Timing 분리 |
| **High Guard** | Space **hold** → `is_guarding` + `guard_changed` → `PlayerActionState.GUARD` | Evade와 독립 |
| **(무방비)** | Evade Window 비활성 + Guard OFF | HIT |

#### Continuous Evade (Player)

- **Movement**: A/S/D hold → small POV target offset + World parallax. Recovery / post-lock **없음**. Player POV와 World weaving은 **SmoothDamp**. Opponent Down Nstance lowering만 **`move_toward`**.
  - Player POV LEFT/RIGHT/DOWN `(0, +10)` / release → CENTER. **Player X = 0** (full-frame clipping 방지).
  - LEFT↔RIGHT: World shared head-motion SmoothDamp + position-based weave dip. Presentation only.
  - Horizontal World: Crowd **30** / Ring **65** / Opponent **130**.
- **Timing Window**: 유효 press 시 `evade_window = 0.18`, `evade_retrigger_interval = 0.12`. **Stamina 소모 없음.**
- Stamina 부족이어도 **Movement는 허용**, Window만 거부
- Hold 중 자동 재발동 없음. OS key-repeat 무시
- Attack Startup/Active: Gameplay Evade 금지. Recovery `attack_to_evade = 0.35` 이후 cancel 가능
- Same hand (Left Straight/Hook, Right Straight/Hook)는 Recovery 100%와 손 재사용 간격(기본 0.45초, 공격 시작부터)을 둘 다 채워야 한다. LEFT와 RIGHT 타이머는 따로다. Opposite hand는 `attack_to_attack` 0.50 캔슬만 쓰고, 전역 쿨다운은 없다. Pressure Fighter는 같은 손 재사용 간격을 줄이지 않는다.
- LEFT/RIGHT Continuous Evade는 정착 시 DOWN과 같은 머리 높이다. 좌우는 사선 아래로 보인다. 가로는 Crowd 30 / Ring 65 / Opponent 130, 세로는 DOWN과 같은 Crowd 10 / Ring 22 / Opponent 40이다.
- High Guard와 Continuous Evade는 같이 켜진다. Evade를 시작해도 Guard는 풀리지 않는다. Guard가 켜져 있으면 `p.highguard.png`, Guard만 놓으면 Evade가 남아 있어도 `p.Nstance.png`다. 판정은 EVADE, 그다음 BLOCK, 그다음 HIT다. 같이 켜도 스태미나는 쓰지 않는다.
- 일반 HIT는 어느 쪽 공격도 멈추지 않는다. KD, 통계, 압박, 피격 연출은 들어간다. 행동 정지는 Knockdown과 Finisher Freeze뿐이다. 한 공격 token은 HIT/BLOCK/EVADE를 한 번만 resolve한다. Pressure Fighter는 반대 손 연계만 빠르게 한다.
- Evade → Attack / Guard: slip recovery 없이 즉시 가능 (Attack 시작 시 window end + POV CENTER)
- `PlayerActionState` = IDLE / ATTACKING / GUARD 만 (SLIP exclusive state 제거)

AI의 `"NONE"`은 방어를 선택하지 않은 **decision 결과 문자열**이다. Opponent AI Slip은 기존 one-shot 구조 유지.

### 복구 금지 (제거됨)

다음 입력/시스템은 **의도적으로 제거**되었다. 다시 넣지 말 것.

- **Duck 전용 시스템** (`combat_duck` / 구 `DefenseType.DUCK` / Head-Body 연동) — `EvadeDirection.DOWN`은 Continuous Evade 방향일 뿐 Duck 복원이 아님
- **Head / Body Target Toggle** (`combat_toggle_target` 등)
- Player Slip recovery / post-lock / `slip_to_*` cancel thresholds

---

## 3. 현재 전투 시스템 (확정)

핵심 자원은 둘뿐이다.

### 3.1 Stamina (행동 자원)

- **공격 시작 시에만** 소모 (`stamina_cost`). Evade / Guard / Movement / 피격은 소모하지 않는다.
- Visual Movement와 Evade Window는 Stamina와 독립.
- HIT / BLOCK / EVADE로 **피격 Stamina 감소 없음**.
- 피격으로 **regen delay reset 없음**.
- 자연 회복·반복 공격 fatigue·Round Break `+25` 유지.
- **Low Stamina는 행동 속도를 늦추지 않는다.** Startup / Active / Recovery는 Stamina와 무관.
- Stamina가 낮을수록 **받는 KD damage가 커진다** (`KnockdownVulnerability`). EVADE는 항상 0. BLOCK은 `0.25 × vulnerability`.
- Stamina 0 → `Exhausted` (공격만 불가). `exhausted_recovery_threshold` 25까지 유지. 경직/슬로우는 없다.

노드: `PlayerStamina`, `OpponentStamina`.

### 3.2 Knockdown Meter (피격 게이지)

- 범위 **0.0 ~ 300.0**, 초기 0.
- HP가 아니다. **≥ 100 → Knockdown** (Final KO가 아님).
- 노드: `PlayerKnockdownMeter`, `OpponentKnockdownMeter` (`scripts/knockdown_meter.gd`).

### 3.3 HIT / BLOCK / EVADE

Resolvers: `player_offense_resolver.gd`, `player_defense_resolver.gd`.  
`guard_knockdown_damage_multiplier` 기본 **0.25**.

| 결과 | KD Meter | Hit Stun | Stamina |
|---|---|---|---|
| **HIT** | `knockdown_damage` 전량 | 없음. 공격과 입력은 계속된다 | 변화 없음 |
| **BLOCK** (High Guard) | × **0.25** | 없음 | 변화 없음 |
| **EVADE** (Evade Window 활성) | **0** | 없음 | 변화 없음 |

동시 Active 트레이드: `HitResolveCoordinator`가 같은 프레임 처리를 조율.

### 3.4 Knockdown 이후

1. KD ≥ 100 → (결정타 HIT만) `FinisherImpactFreeze` → freeze 종료 → `KnockdownManager.begin_*_knockdown()`
2. Count **1~10** (`count_interval` 기본 1.0s) — Freeze 종료 후에만 시작
3. Knockdown 시작 시 **1회** `RecoveryChanceSettings.resolve_recovery(stamina)`
4. 성공 → 지정 count에서 기립 → **KD Meter = 50**, Stamina **+15**, Fighting
5. 실패 → Count 10 → **Final KO**
6. Round Break: Stamina **+25**, KD Meter **−15** (`round_knockdown_meter_recovery`)

Debug F1/F2 `force_knockdown`은 Finisher Freeze를 건너뛰고 즉시 begin.

Random KO roll / Just / Counter / Head-Body KO 경로 **없음**.

### 3.5 플레이어가 이해해야 할 규칙 (요약)

1. 공격하면 Stamina가 줄어든다.  
2. 맞으면 KD Meter가 오른다.  
3. 가드하면 KD 증가가 크게 줄어든다.  
4. A/S/D Evade Window 중이면 공격을 완전히 피한다.  
5. KD 100이면 다운된다.  
6. 10 Count 안에 못 일어나면 KO다.

---

## 4. 공격 데이터 (실제 Resource 기준)

스크립트 기본값 + `.tres` 오버라이드.  
**`.tres`에 필드가 없으면 스크립트 `@export` 기본값이 적용된다.**

### 4.1 Player — `data/attacks/*.tres` + `AttackData`

| Attack | Startup | Active | Recovery | stamina_cost | knockdown_damage | 비고 |
|---|---|---|---|---|---|---|
| Left Straight | **0.10** | **0.08** | **0.11** | **4** | **8** | Recovery 단축. `.tres` 비어 있으면 스크립트 기본 |
| Right Straight | 0.14 | 0.09 | **0.14** | 5 | 10 | `.tres` 명시 |
| Left Hook | 0.18 | 0.10 | **0.18** | 7 | 13 | `.tres` 명시 |
| Right Hook | 0.22 | 0.11 | **0.21** | 8 | 15 | `.tres` 명시 |

### 4.2 Opponent — `data/opponent_attacks/*.tres` + `OpponentAttackData`

| Attack | Startup | Active | Recovery | stamina_cost | knockdown_damage | AI 사용 |
|---|---|---|---|---|---|---|
| Left Straight | **0.8** | **0.1** | **0.50** | **4** | **8** | ✅ Straight-only. `.tres` 비어 있음 → 스크립트 기본(Recovery 기본 0.5) |
| Right Straight | **0.9** | **0.1** | **0.55** | **5** | **10** | ✅ `.tres`에 Recovery **0.55** 명시 |
| Left Hook | 1.0 | 0.12 | 0.60 | 7 | 13 | ❌ 리소스만 존재, AI 미사용 |
| Right Hook | 1.1 | 0.12 | 0.65 | 8 | 15 | ❌ 리소스만 존재, AI 미사용 |

필드명: 구 `stamina_damage` → **`knockdown_damage`** 로 마이그레이션 완료.

---

## 5. 제거된 시스템 (재구현 금지)

다음을 “빠진 기능”으로 오해해 다시 만들지 말 것.

| 제거됨 | 설명 |
|---|---|
| **HP / PlayerHealth** | `player_health.gd` 없음. HP 바 없음. |
| **Random KO Chance** | `KoChanceSettings` / `*_ko_chance.tres` 삭제됨. |
| **Just Attack** | 타이밍 보너스·배수 없음. |
| **Counter / Counter Window** | `PlayerCounterWindow` 등 삭제. Slip 직후 공격도 일반 공격. |
| **Head / Body Target** | 타깃 enum·토글·HUD·스탯 없음. |
| **Duck 전용 시스템** | `combat_duck` / Head-Body 연동 Duck 없음. `EvadeDirection.DOWN`만 존재. |
| **피격 Stamina Damage** | `apply_stamina_damage` 제거. HIT이 Stamina를 깎지 않음. |

---

## 6. Opponent AI

스크립트: `scripts/opponent_ai.gd`  
Opponent AI is locked to the former Normal baseline in `opponent_difficulty_settings.gd`. Easy/Hard resources are removed. Reflex and Pressure Fighter change timing only while those traits are active (`effective = base × modifier`).

| Field | Baseline |
|---|---|
| reaction_delay | 0.16 |
| mistake_chance | 0.20 |
| aggression | 0.62 |
| attack_interval | 0.10–0.30 |
| follow_up_chance | 0.60 |
| follow_up_delay | 0.05–0.12 |

### 정책

- **`ACTIVE_ATTACK_TYPES` = Left/Right Straight only** (Hook 후보에서 제외).
- 방어 decision: `"SLIP_LEFT"` / `"SLIP_RIGHT"` / `"GUARD"` / `"NONE"`.  
  - Slip → `OpponentActionState` Slip 상태  
  - Guard → `set_guard_held(true)` (hold)  
  - `"NONE"` → 반응하지 않음 (실수·비선택). **전용 defense state가 아님**.
- `OpponentAttackState.attack_cooldown` 기본 **0.0**.
- Offense pacing: Recovery가 끝나면 다음 판단을 바로 한다. 공격을 하지 않기로 한 경우에만 `attack_interval` 0.10–0.30을 쉰다.
- **Combo**: 첫 펀치에서 단발 40% / 2타 40% / 3타 20%. 후속타마다 반대손 70% / 같은 손 30%를 다시 고른다. 같은 손은 Recovery가 끝나고 시작 간격 0.45초가 지나야 한다. 아직 불가능하면 반대손으로 바꾸지 않고 기다리거나 콤보를 끝낸다. 각 후속타는 새 attack token이며 스태미나를 따로 쓴다.
- Block 70% / Evade 90%는 다음 공격 판단 한 번에서만 공격 가능성을 올린다. 그 우선 시간은 Block 0.20초, Evade 0.35초이고, 방금 들어간 가드나 슬립이 끝나기 전에는 줄지 않는다. 이미 Active인 플레이어 펀치는 이 시간보다 방어가 먼저다. 피해나 속도는 변하지 않는다.
- `reaction_delay`: 플레이어 공격 Startup 이후 방어 반응 지연.
- `mistake_chance` / `aggression` / `low_stamina_threshold` + `low_stamina_wait_chance` 유지.
- **`counter_chance` 필드 없음** (삭제됨). `hook_weight`는 리소스에 남아 있으나 AI가 Hook을 고르지 않음.

Easy / Hard 난이도 리소스는 제거되었다. 위 baseline이 유일한 AI 기본값이다.

Opponent는 플레이어가 공격하지 않아도 0.65–1.35초마다 선제 방어를 본다. 그 판단의 35%만 행동하고, 그중 75%는 High Guard(0.55–0.90초), 25%는 좌우 Slip이다. 판단은 자주 해도 매번 행동이 나오지는 않는다. 공격 중이나 가드 중에 타이머가 끝났다면 전체 간격을 다시 시작하지 않고, 행동이 끝나면 바로 다음 판단으로 돌아간다. 일반 HIT는 공격, 콤보, AI 판단을 멈추지 않는다. KD와 피격 연출은 그대로다. 클린 HIT 뒤의 압박 방어는 경직 종료를 기다리지 않고, 그 판정이 끝난 뒤 행동할 수 있을 때 예약된다. Opponent는 Recovery 뒤에 0.10~0.30초를 더 기다리지 않는다. 좌우 스트레이트는 Player와 Opponent가 같은 시간이다. 왼쪽 0.10/0.08/0.11, 오른쪽 0.14/0.09/0.14. Startup 또는 Active 중 맞는 클린 HIT만 받은 KD에 ×1.50이 더해진다. Recovery와 Idle은 일반 HIT다. 공격 pattern은 단발 30%, 빠른 2타 30%, 3타 20%, 0.15~0.30초를 둔 2타 20%다. 선제 방어 간격은 0.50~1.00초, 행동 확률 45%, 가드 65% / 슬립 35%다. 막기 70%, 피하기 90%는 다음 공격 판단 한 번만 공격 쪽으로 기울인다. 판단은 일부러 불완전하고, 전투 규칙만 같다. 클린 HIT마다 압박 방어 기회는 한 번이고, 그 예약은 일반 공격 결정보다 먼저다. 1타는 방어 85% / 반응 0.06초, 2타는 95% / 0.03초, 3타부터는 100% / 0.01초다. 이 압박 방어는 가드 45%, 슬립 55%다. 100%는 같은 압박에서 3타 이상을 이미 맞은 다음 기회에만 적용된다. 플레이어 스태미나는 방어 확률이 아니라 반응 시간만 바꾼다. 100%는 ×1.00, 75%는 ×0.90, 50%는 ×0.75, 25%는 ×0.55, 0%는 ×0.40이고 사이는 선형이다. 최종 반응은 base × stamina × trait이며 최소 0.01초다. 플레이어 공격 동작 시간은 느려지지 않는다. 이미 예약된 방어는 플레이어 Active 직전에 따라잡는다. 압박 가드 유지는 0.45초다. Reflex는 이 반응 시간만 절반으로 줄인다.

---

## 7. Knockdown / Count / Recovery

- `KnockdownManager`: Fighting → Player/Opponent Down → Count → Recover 또는 Final KO.
- Recovery는 **다운 시 1회 roll** (`RecoveryChanceSettings`), 카운트마다 재roll 하지 않음.
- 성공 기립: **KD = max × 0.50** (300 기준 150), Stamina **+15**.
- Count 중 KD Meter 변화 없음. Final KO 후 Round Break KD 회복 적용 안 함.
- Round timer는 knockdown 중 pause (`RoundManager` ↔ `KnockdownManager`).

Recovery 리소스: `data/ko/player_recovery_chance.tres`, `opponent_recovery_chance.tres`  
(기본값: max 0.85 / min 0.05 / exponent 1.25 / stand-up count 1–9 / stamina +15).

---

## 8. Match / Round

A match is best of 3, first to 2. Each round lasts 60 seconds and ends by Final KO or a decision. A 2–0 score skips round 3. Every round has one winner: a scoring draw uses a fixed tie-break (knockdowns, KD damage, landed punches, evades + blocks, thrown punches, then the round number). Judge 10-point cards stay separate from the match score. Final KO awards that round only; the result scene opens when a fighter reaches 2 wins.

Round start fully resets stamina, KD, exhaustion, actions, guard, evade, slip, hit stun, and pending AI defense. Only the win counters persist. The old break heal (`+25` stamina, `−15` KD) is not applied.

KD meter maximum is **300**. Standing up sets the meter to 50% of that maximum (150). Stand-up stamina recovery stays **+15**.

Every new round resets gameplay and visuals together. OpponentVisual must not keep a Knockdown, Down, or Final KO pose into the next round. When the new round is fighting, the AI state and the sprite have to match. A callback left over from the previous round must not put the down pose back.

Each round, Player and Opponent each draw exactly one Fighter Trait. They may draw the same trait. Effects are applied live and never written back onto base values. The trait card shows both sides before the clock starts.

| 항목 | 기본 |
|---|---|
| Rounds | 3 |
| Round duration | 60s |
| Break | 10s |
| Break Stamina | +25 |
| Break KD | −15 |

- `CombatStats` → 라운드 스냅샷 → `RoundScorer` (10-Point Must).
- **Knockdown net 최우선**. 동점이면 effective offense.
- Effective offense:  
  `attacks_landed × 1.0 + knockdown_damage_dealt × 0.05`  
  (`draw_threshold` 1.5, 패자 최소점 7).
- `MatchDecision`: Decision / KO / Draw 결과 → `MatchResultData` (Result 씬 연동용).

---

## 9. Visual Architecture

```
CombatPrototype (game.tscn root)
├── CombatVisualRoot          ← shake / world parallax 오케스트레이션
│   ├── BackgroundVisual      ← CrowdLayer + RingLayer
│   ├── OpponentVisual
│   └── PlayerVisual
├── DebugHUD (CanvasLayer)    ← Stamina / KD Meter / 상태 텍스트
└── (전투 로직 노드들…)
```

**HUD는 반드시 `CombatVisualRoot` 바깥.**  
Screen shake / POV / parallax가 HUD·KD·Stamina 바를 흔들지 않게 하기 위함.

---

## 10. Player Asset 정책 (매우 중요)

| 규칙 | 값 |
|---|---|
| 소스 PNG | **1536×864** full-frame transparent |
| Viewport | **1152×648** |
| Scale | **0.75** (양축 동일) |
| `Sprite2D.centered` | **false** |
| `Sprite2D.offset` | **Vector2.ZERO** |
| `asset_base_position` | **Vector2.ZERO** (top-left = viewport origin) |
| Pose 전환 | **텍스처 스왑만**. pose별 개별 scale/alignment **금지** |

구현: `player_visual.gd`, `visual_display_layout.gd`.  
에셋 예: `assets/player/p.Nstance.png`, `p.L_straight.png`, …

---

## 11. Opponent Visual

- **STARTUP**: Stance 유지 (Straight PNG 안 보여줌).
- **ACTIVE**: Straight PNG 표시 → `attack_pose_hold_seconds` **0.20** 후 Stance.
- Combat **Recovery**가 길어도 펀치 PNG 표시 시간을 늘리지 않음 (**Combat timing ≠ Visual timing**).
- HIT: `o.hit.png`, `hit_hold_seconds` 기본 **0.22**.
- Knockdown: hit 텍스처 + **Y drop 70px**.
- Scale: contain 기준 ≈ **648/1024**; 기본 `asset_base_position` ≈ `(90, 0)`.
- Priority: `DOWN > HIT > ATTACK > DEFENSE > IDLE`.

---

## 12. 구현된 Visual Motion (현재 코드에 있는 것만)

### Idle Breathing (`PlayerVisual` / `OpponentVisual`)

- Idle만. Base → **+Y** → Base (위로 올라가지 않음).
- 기본: `breathing_amplitude = 6`, `breathing_cycle_seconds = 1.6`.
- Attack/Guard/Evade movement/Hit/Knockdown/KO에서 중단.

### Continuous Evade POV (`PlayerVisual` + `PlayerEvade`)

- 별도 Evade 스프라이트 없음. Player **X translation = 0** (1536×864 full-frame ↔ 1152×648 exact fill → 어떤 X 이동도 clipping).
- Player Y만 소량 SmoothDamp: LEFT/RIGHT/DOWN `(0,+10)`.
- 회피감은 World/Opponent relative motion이 담당.

### World Parallax (`CombatVisualRoot` → BG + Opponent)

- Shared head-motion: `_head_lateral` / `_head_down` SmoothDamp (velocity continuity, no segment restart).
- LEFT → World **+X** / RIGHT → World **-X** / DOWN → World **-Y**.
- Horizontal: Crowd **30** / Ring **65** / Opponent **130**.
- Down Y: Crowd **10** / Ring **22** / Opponent **40**.
- LEFT↔RIGHT weave: position-based `(1-|lat|)^2 * blend` dip (−Y). Opp **45** / Ring **22** / Crowd **10**.
- DOWN successful pass-by: **`(0, -40)`** (40px upward). LEFT/RIGHT pass-by X **±130**. Stack ≤ ~80.
- Opponent는 `parallax_offset` additive.
- Opponent는 `parallax_offset` additive. `asset_base_position.y`는 `max(DOWN 40, weave 45) + pass-by 40` = **85**라서, 최대 DOWN에서 캔버스 하단이 viewport 바닥(648)에 맞는다. CENTER에서는 그 85px만큼 아래에 있다. Scale은 contain **0.6328125** 유지. BottomBleed 없음.

### Background Overscan (`BackgroundVisual`)

- Parallax amplitude는 줄이지 않는다. Crowd/Ring만 viewport + motion bleed를 uniform scale로 덮는다.
- Bleed (한쪽, CombatVisualRoot가 계산 후 safety **4px** 추가):
  - Crowd H **30+4**, V **10 + weave 10 + 4**
  - Ring H **65+4**, V **22 + weave 22 + 4**
- Scale은 기존 cover의 **시각 중심** 기준. Bottom anchor를 추가 높이의 절반만큼 내려 framing center를 유지한다.
- Player scale **0.75**와 Opponent contain scale은 overscan 대상이 아니다.

### Combat Freeze와 Evade clear

- `RoundManager._freeze_combat()` (Round End, 이후 Break, Decision, Match KO)에서:
  - held input clear
  - `PlayerEvade.clear_all()` (window + movement, stamina 추가 소모 없음)
  - `CombatVisualRoot.clear_continuous_evade_presentation()` — parallax/head-motion snap CENTER, pass-by clear, Player POV snap CENTER
- HIT / Knockdown의 기존 clear는 유지한다.
- 다음 Fighting은 CENTER에서 시작한다.

### Hit Shake (`CombatVisualRoot`만)

- Opponent HIT(플레이어가 때림): strength **3** / **0.10s**.
- Player HIT(플레이어가 맞음): strength **7** / **0.15s**.
- BLOCK / EVADE: shake 없음.
- **Finisher HIT**(결정타): 일반 HIT와 동일하게 짧은 impact shake → Freeze 중에는 shake 정지 → Knockdown 진입 시 clear.
- Knockdown 상태 진입 시 shake clear.

### Knockdown Impact Shake (sprite-local, not screen)

- Opponent: entry-only vertical jolt (`knockdown_impact_shake_y` **10** / count **3** / **0.18s**) then settle on drop **70px**.
- Player POV: 동일 개념, 더 작게 (`y` **6**). Count 중 반복 없음.

### Knockdown Finisher Impact Freeze (`FinisherImpactFreeze`)

- **발동**: 실제 HIT로 KD Meter ≥ 100 → Knockdown 확정 시에만 1회. BLOCK / EVADE / 일반 HIT / 이미 DOWN / Final KO / Debug F1·F2 **제외**.
- **Controller**: `scripts/finisher_impact_freeze.gd` (`game.tscn` → `FinisherImpactFreeze`).
- **기본값**: `finisher_freeze_duration = 2.0` (wall-clock / `Time.get_ticks_msec`). **`Engine.time_scale` 사용 안 함** (항상 1.0 유지).
- **순서**: HIT → KD full → Impact Freeze (pose 유지 + screen effect) → `KnockdownManager.begin_*_knockdown()` → impact shake/drop → Count.
- Freeze 중: Round timer `pause_for_finisher()`, meter updates off, input/buffer/AI 차단, combat visual motion 정지, 결정타 attack/HIT pose 유지.
- **Screen Effect**: `FinisherImpactEffect` (CanvasLayer) — 짧은 white flash only (`flash_peak_alpha` 0.35 / `flash_duration` 0.12). Flash 후 원본 화면. dark overlay 없음. HUD와 분리.
- Freeze 종료 시: Player attacker면 Attack pose → Idle stance (`PlayerVisual.set_finisher_freeze(false)`). Opponent attacker는 기존 `cancel_and_disable()` IDLE re-emit으로 stance.
- **Cleanup**: 정상 종료 / `cancel_and_restore` / `_exit_tree` / match 종료 시 overlay 제거.

### Additive compose

- Player: `base + breathing + action + pov(evade) + opponent_down_idle + knockdown + knockdown_impact`
- Opponent: `base + breathing + action + parallax + knockdown + knockdown_impact`
- Root: `base + shake`
- Player POV / World weaving: **SmoothDamp**.
- Opponent Down Nstance lowering: **`move_toward`**.
- **FatigueVignette** (CanvasLayer, HUD보다 아래): Player Stamina만. `intensity = pow(1 - ratio, 2)`. 가장자리만 어둡고 중앙은 비움.
- **Exhausted Ghost**: Player Stamina 0에서만. Main sprite는 항상 불투명. Ghost 2개는 같은 texture/anchor를 따르고 작은 drift만 더한다. Stamina 25에서 fade out. Opponent Stamina는 이 이펙트를 켜지 않는다.
- Tweens: `_breathing_tween`, `_shake_tween`, `_knockdown_impact_tween`

### Opponent Down Nstance Lowering (`PlayerVisual`)

- Opponent DOWN/COUNT 시 Player Nstance에 `opponent_down_idle_offset_y` **+90** (additive, Inspector).
- Finisher Freeze 중에는 미적용. Freeze 종료 → Nstance → Opponent Down 이후 적용.
- Opponent Recover → `move_toward`로 0 복귀. Player Down 시 강제 0. Final KO(상대)는 lowered 유지 가능.
- Guard gameplay와 무관 (presentation only).

### 아직 구현되지 않음 (완료라고 쓰지 말 것)

- Telegraph / 공격 예고 연출
- 신규 전투 시스템, 별도 Damage/HP, Counter/Target 부활
- Web export preset

---

## 13. Scene / Script / Resource 지도

### Scene

| Path | 역할 |
|---|---|
| `scenes/game.tscn` | 메인 전투 프로토타입 (모든 전투·비주얼 배선) |
| `scenes/title.tscn` | 타이틀 |
| `scenes/result.tscn` | 결과 |

### Combat core

| Script | 책임 |
|---|---|
| `combat_prototype.gd` | 입력 HUD, KD 바, knockdown 시그널 연결 |
| `player_combat_input.gd` | 입력 → 시그널 |
| `player_attack_state.gd` / `opponent_attack_state.gd` | Startup/Active/Recovery |
| `player_action_state.gd` / `opponent_action_state.gd` | Player: Idle/Attacking/Guard · Opponent: Idle/Slip/Guard |
| `player_evade.gd` | Continuous Evade Movement + Timing Window |
| `player_action_buffer.gd` | Attack recovery cancel (attack_to_attack/evade/guard) |
| `player_offense_resolver.gd` / `player_defense_resolver.gd` | HIT/BLOCK/EVADE + KD |
| `hit_resolve_coordinator.gd` | 동시 Active 조율 |
| `hit_stun.gd` | 일반 HIT는 경직이 없다 |
| `knockdown_meter.gd` | 0–100 미터 |
| `knockdown_manager.gd` | Down / Count / Recovery / Final KO |
| `finisher_impact_freeze.gd` | 결정타 Impact Freeze presentation (Count 앞단) |
| `finisher_impact_effect.gd` | Freeze 시작 white flash (real-time; no dark hold overlay) |
| `round_manager.gd` | 라운드·브레이크·타이머 |
| `combat_stats.gd` / `combat_side_stats.gd` | 통계 |
| `round_scorer.gd` / `match_decision.gd` | 채점·판정 |
| `opponent_ai.gd` | AI |
| `player_stamina.gd` / `opponent_stamina.gd` | 스태미나 |

### Visual

| Script | 책임 |
|---|---|
| `combat_visual_root.gd` | Shake + Parallax 오케스트레이션 |
| `background_visual.gd` | Crowd/Ring |
| `player_visual.gd` | POV player + breathing + continuous evade POV + opponent-down idle |
| `opponent_visual.gd` | Opponent poses + breathing + parallax offset |
| `visual_display_layout.gd` | 1152×648 / 0.75 / opponent contain |
| `visual_texture_resolver.gd` | 안전 텍스처 로드 |

### Data

- `data/attacks/`, `data/opponent_attacks/`
- `data/difficulty/`, `data/ko/*_recovery_chance.tres`
- `data/action_speed/`

---

## 14. CombatStats / RoundScorer

### `CombatSideStats` 유지 필드

- `attacks_thrown`, `attacks_landed`, `blocked_hits`, `attacks_evaded`
- `knockdown_damage_dealt` (실제 타깃 KD에 적용된 양)
- `knockdowns`

제거됨: `head_hits`, `body_hits`, `just_attacks`, `counter_hits`, `stamina_damage_dealt`.

### Scoring

```
effective = landed * 1.0 + knockdown_damage_dealt * 0.05
```

KD net ≠ 0 → 승자 10점, 패자 `max(7, 9 - kd_margin)`.  
KD net = 0 이고 `|offense_diff| ≤ 1.5` → 10–10 draw.

---

## 15. 테스트

프로젝트 루트에서 (Godot 4.7.2):

```text
godot --headless --path . -s res://kd_meter_smoke_test.gd
godot --headless --path . -s res://combat_simplify_smoke_test.gd
godot --headless --path . -s res://balance_smoke_test.gd
godot --headless --path . -s res://ai_pacing_smoke_test.gd
godot --headless --path . -s res://hit_stun_smoke_test.gd
godot --headless --path . -s res://visual_motion_smoke_test.gd
godot --headless --path . -s res://action_buffer_smoke_test.gd
godot --headless --path . -s res://continuous_evade_smoke_test.gd
godot --headless --path . -s res://finisher_impact_freeze_smoke_test.gd
godot --headless --path . --quit-after 2
```

| 파일 | 목적 |
|---|---|
| `kd_meter_smoke_test.gd` | KD Meter, 공격 KD 값, legacy 시스템 부재, HUD |
| `combat_simplify_smoke_test.gd` | Duck/Target/Just/Counter 제거, Straight-only AI |
| `balance_smoke_test.gd` | AI interval/follow-up, coordinator |
| `ai_pacing_smoke_test.gd` | cooldown 0, follow-up, difficulty |
| `hit_stun_smoke_test.gd` | HitStun 컴포넌트·씬 배선 |
| `visual_motion_smoke_test.gd` | Breathing/Continuous Evade POV/Parallax/Shake/Recovery |
| `action_buffer_smoke_test.gd` | Action Buffer / Attack Recovery Cancel / Evade cancel |
| `continuous_evade_smoke_test.gd` | Continuous Evade Movement/Timing/stamina/pass-by/down-idle |
| `finisher_impact_freeze_smoke_test.gd` | 결정타 Impact Freeze / pose hold / Count 순서 / no time_scale |

전투 판정을 우회하는 compatibility hack으로 테스트를 통과시키지 말 것.

---

## 16. 개발 규칙

1. **정상 동작 시스템을 이유 없이 재설계하지 말 것** (특히 Stamina↔KD 분리, Straight-only AI). 일반 HIT는 행동을 멈추지 않는다.
2. **Combat timing과 Visual timing을 분리**할 것 (Opponent Recovery ≠ punch PNG hold).
3. **Stamina와 KD Meter는 독립** — 피격이 Stamina를 깎거나 KO 확률을 만들지 않음.
4. Player/Opponent **대칭 규칙** 유지 (미터·가드 배율·브레이크 회복).
5. Visual offset은 **additive compose**; base transform 파괴·누적 drift 금지.
6. 밸런스 숫자는 **Resource / Inspector `@export`** 우선.
7. HP, Random KO, Just/Counter, Head/Body, Duck 등 **제거된 시스템을 부활시키지 말 것**.
8. Telegraph 등 신규 연출은 **별도 작업으로 명시될 때만**.
9. 커밋은 사용자가 요청할 때만. 비밀값 커밋 금지.

---

## 17. 현재 상태 / Next Work

### Git 상태

- 브랜치: **`main` @ `73aa87a`** (`docs: update agent handoff`)
- **`origin/main`과 동기화**, working tree **clean**
- 전투 단순화(KD Meter) + Visual Motion은 `d5909a2`에 **커밋·푸시 완료**
- 관련 최근 커밋:
  - `d5909a2` — `refactor: simplify combat system and improve combat visuals`
  - `73aa87a` — `docs: update agent handoff`

### 마지막으로 완료된 작업 (코드 기준)

1. 전투를 **Stamina + Knockdown Meter**로 단순화 (Just/Counter/Duck/Head-Body/Random KO 제거).
2. KD HUD, CombatStats/RoundScorer 정리, Straight-only AI 유지.
3. Visual Motion: Idle Breathing, Continuous Evade POV, Parallax, Hit Shake, Knockdown impact shake, Opponent Down Nstance lowering.
4. Action Buffer + Attack Recovery Cancel (`attack_to_evade` 0.35).
5. **Continuous Evade** (A/S/D Movement + 0.18 Window + retrigger 0.12, Stamina 소모 없음).
6. **Knockdown Finisher Impact Freeze** (`FinisherImpactFreeze`: real **2.0s** freeze + screen effect → 이후 Count). `Engine.time_scale` 미사용.

### Next Work / TODO (미구현 — 완료와 섞지 말 것)

- [ ] **Telegraph** (Opponent 긴 Startup 대비 예고) — 아직 없음. 필요 여부는 플레이 후 결정.
- [ ] Opponent Startup(0.8/0.9) 단축 여부 — **미결정**. 임의 변경 금지.
- [ ] Web `export_presets.cfg` 구성.
- [ ] Title/Result 플로우·메타 진행 강화 (전투 코어 외).
- [ ] 문서/코드 변경분 커밋은 **사용자 요청 시**만.

---

## 18. Known warnings / Technical debt

| 항목 | 상태 |
|---|---|
| `player_health.gd` | 없음 (정상) |
| `assets/README.md` | 현재 `p.*` / `o.*` / `bg_*` 기준으로 정리됨 |
| `export_presets.cfg` | 없음 |
| `project.godot` window size | 미명시 — 코드는 1152×648 가정 |
| `data/attacks/left_straight.tres`, `opponent left_straight.tres` | 필드 오버라이드 비어 있음 → **스크립트 기본값에 의존** (의도된 값과 일치하는지 변경 시 주의) |
| Opponent Hook `.tres` | 데이터만 존재, AI 미사용 — 삭제 필수는 아님 |
| Git | `main` clean / origin 동기화 (`73aa87a` 기준; 이후 로컬 문서 수정은 커밋 전 확인) |
| 스모크 | 로컬에서 PASS 이력 있음. 새 환경에서는 Godot 4.7.2로 재실행 권장 |

---

## 새 Agent 빠른 체크리스트

1. Godot **4.7.2**로 `scenes/game.tscn` 실행.  
2. 조작: J/K, Shift+J/K, A/S/D, Space.  
3. Stamina 바와 KD 바가 DebugHUD에 있는지, Evade 시 월드 패럴랙스/플레이어 POV가 연속 이동하는지.  
4. 스모크 + headless `game.tscn` 실행.  
5. 전투 규칙을 바꾸기 전에 이 문서 §3–§5와 해당 `.tres`를 재확인.  
6. Visual만 손댈 때는 Combat Startup/Active/Recovery를 건드리지 말 것 (예외는 명시된 Recovery 튜닝뿐).
