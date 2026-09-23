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
| `combat_slip_left` | **A** | Slip Left |
| `combat_slip_right` | **D** | Slip Right |
| `combat_high_guard` | **Space** | High Guard (hold) |
| `debug_force_player_knockdown` | F1 | 디버그 |
| `debug_force_opponent_knockdown` | F2 | 디버그 |

처리: `scripts/player_combat_input.gd` → `PlayerActionState` / `PlayerAttackState`.

### 방어 입력 구조 (`player_combat_input.gd`)

세 경로가 다르며, 하나로 묶인 `DefenseType` 상태가 아니다.

| 동작 | 코드 경로 | 비고 |
|---|---|---|
| **Slip Left / Right** | `DefenseType` enum (`SLIP_LEFT` / `SLIP_RIGHT`) → `defense_requested` | enum 값은 Slip만 |
| **High Guard** | Space **hold** → `is_guarding` + `guard_changed(is_guarding)` | `DefenseType`에 없음 |
| **(무방비)** | Slip/Guard 미사용 시의 Idle | 별도 defense state / enum 값 **없음** |

AI의 `"NONE"`은 방어를 선택하지 않은 **decision 결과 문자열**이다. `DefenseType`이나 전용 defense state가 아니다.

### 복구 금지 (제거됨)

다음 입력/시스템은 **의도적으로 제거**되었다. 다시 넣지 말 것.

- **Duck** (`combat_duck` / `DefenseType.DUCK`)
- **Head / Body Target Toggle** (`combat_toggle_target` 등)

---

## 3. 현재 전투 시스템 (확정)

핵심 자원은 둘뿐이다.

### 3.1 Stamina (행동 자원)

- **자신의 공격 시작 시에만** 소모 (`stamina_cost`).
- HIT / BLOCK / EVADE로 **피격 Stamina 감소 없음**.
- 피격으로 **regen delay reset 없음**.
- 자연 회복·반복 공격 fatigue·Round Break `+25` 유지.
- **Low Stamina Action Speed**: `ActionSpeedSettings` — 스태미나가 낮으면 행동 duration이 길어짐 (`minimum_action_speed` 기본 0.60).
- Stamina는 **KO 확률·KD Meter 증가량에 직접 영향 없음**.

노드: `PlayerStamina`, `OpponentStamina`.

### 3.2 Knockdown Meter (피격 게이지)

- 범위 **0.0 ~ 100.0**, 초기 0.
- HP가 아니다. **≥ 100 → Knockdown** (Final KO가 아님).
- 노드: `PlayerKnockdownMeter`, `OpponentKnockdownMeter` (`scripts/knockdown_meter.gd`).

### 3.3 HIT / BLOCK / EVADE

Resolvers: `player_offense_resolver.gd`, `player_defense_resolver.gd`.  
`guard_knockdown_damage_multiplier` 기본 **0.25**.

| 결과 | KD Meter | Hit Stun | Stamina |
|---|---|---|---|
| **HIT** | `knockdown_damage` 전량 | **0.35s** (`HitStun`) | 변화 없음 |
| **BLOCK** (High Guard) | × **0.25** | 없음 | 변화 없음 |
| **EVADE** (Slip 성공) | **0** | 없음 | 변화 없음 |

동시 Active 트레이드: `HitResolveCoordinator`가 같은 프레임 처리를 조율.

### 3.4 Knockdown 이후

1. KD ≥ 100 → `KnockdownManager.begin_*_knockdown()`
2. Count **1~10** (`count_interval` 기본 1.0s)
3. Knockdown 시작 시 **1회** `RecoveryChanceSettings.resolve_recovery(stamina)`
4. 성공 → 지정 count에서 기립 → **KD Meter = 50**, Stamina **+15**, Fighting
5. 실패 → Count 10 → **Final KO**
6. Round Break: Stamina **+25**, KD Meter **−15** (`round_knockdown_meter_recovery`)

Random KO roll / Just / Counter / Head-Body KO 경로 **없음**.

### 3.5 플레이어가 이해해야 할 규칙 (요약)

1. 공격하면 Stamina가 줄어든다.  
2. 맞으면 KD Meter가 오른다.  
3. 가드하면 KD 증가가 크게 줄어든다.  
4. Slip하면 공격을 완전히 피한다.  
5. KD 100이면 다운된다.  
6. 10 Count 안에 못 일어나면 KO다.

---

## 4. 공격 데이터 (실제 Resource 기준)

스크립트 기본값 + `.tres` 오버라이드.  
**`.tres`에 필드가 없으면 스크립트 `@export` 기본값이 적용된다.**

### 4.1 Player — `data/attacks/*.tres` + `AttackData`

| Attack | Startup | Active | Recovery | stamina_cost | knockdown_damage | 비고 |
|---|---|---|---|---|---|---|
| Left Straight | **0.10** | **0.08** | **0.18** | **4** | **8** | `.tres` 오버라이드 없음 → 스크립트 기본 |
| Right Straight | 0.14 | 0.09 | 0.24 | 5 | 10 | `.tres` 명시 |
| Left Hook | 0.18 | 0.10 | 0.30 | 7 | 13 | `.tres` 명시 |
| Right Hook | 0.22 | 0.11 | 0.36 | 8 | 15 | `.tres` 명시 |

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
| **Duck** | 입력·액션·비주얼·AI 선택 없음. |
| **피격 Stamina Damage** | `apply_stamina_damage` 제거. HIT이 Stamina를 깎지 않음. |

---

## 6. Opponent AI

스크립트: `scripts/opponent_ai.gd`  
난이도 리소스: `data/difficulty/{easy,normal,hard}.tres`  
씬 기본: **`normal.tres`** (`game.tscn` → `OpponentAI.difficulty`).

### 정책

- **`ACTIVE_ATTACK_TYPES` = Left/Right Straight only** (Hook 후보에서 제외).
- 방어 decision: `"SLIP_LEFT"` / `"SLIP_RIGHT"` / `"GUARD"` / `"NONE"`.  
  - Slip → `OpponentActionState` Slip 상태  
  - Guard → `set_guard_held(true)` (hold)  
  - `"NONE"` → 반응하지 않음 (실수·비선택). **전용 defense state가 아님**.
- `OpponentAttackState.attack_cooldown` 기본 **0.0**.
- Offense pacing: Attack → Startup/Active/Recovery → `attack_interval` → 다음 결정.
- **Follow-up**: Recovery 후 반대손 Straight 시도 (`follow_up_chance` / delay).
- `reaction_delay`: 플레이어 공격 Startup 이후 방어 반응 지연.
- `mistake_chance` / `aggression` / `low_stamina_threshold` + `low_stamina_wait_chance` 유지.
- **`counter_chance` 필드 없음** (삭제됨). `hook_weight`는 리소스에 남아 있으나 AI가 Hook을 고르지 않음.

### Difficulty 실효값 (Normal = 스크립트 기본 + `aggression=0.62`만 오버라이드)

| | Easy (`.tres`) | Normal (대부분 스크립트 기본) | Hard (`.tres`) |
|---|---|---|---|
| reaction_delay | 0.50 | 0.28 | 0.14 |
| attack_interval | 0.35–0.70 | 0.10–0.30 | 0.03–0.15 |
| follow_up_chance | 0.25 | 0.60 | 0.80 |
| follow_up_delay | 0.12–0.25 | 0.05–0.12 | 0.02–0.08 |
| aggression | 0.35 | **0.62** | 0.78 |
| mistake_chance | 0.45 | 0.20 | 0.08 |

---

## 7. Knockdown / Count / Recovery

- `KnockdownManager`: Fighting → Player/Opponent Down → Count → Recover 또는 Final KO.
- Recovery는 **다운 시 1회 roll** (`RecoveryChanceSettings`), 카운트마다 재roll 하지 않음.
- 성공 기립: **KD = 50** (`recovery_knockdown_meter`), Stamina **+15** (`recovery_stamina_amount`).
- Count 중 KD Meter 변화 없음. Final KO 후 Round Break KD 회복 적용 안 함.
- Round timer는 knockdown 중 pause (`RoundManager` ↔ `KnockdownManager`).

Recovery 리소스: `data/ko/player_recovery_chance.tres`, `opponent_recovery_chance.tres`  
(기본값: max 0.85 / min 0.05 / exponent 1.25 / stand-up count 1–9 / stamina +15).

---

## 8. Round / Scoring / Decision

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
- Attack/Guard/Slip/Hit/Knockdown/KO에서 중단.

### Player Slip POV (`PlayerVisual`)

- 별도 Slip 스프라이트 없음. `pov_offset` 이동.
- 기본: `slip_pov_x = 42`, `slip_pov_y = 14`, tween `0.10s`.
- Left: `(-42, +14)` / Right: `(+42, +14)` — **절대 목표** (누적 drift 방지).

### World Parallax (`CombatVisualRoot` → BG + Opponent)

- Player Slip Left → World **+X** / Slip Right → World **-X**.
- Crowd **6** / Ring **14** / Opponent **24** px. tween `0.10s`.
- Opponent는 `parallax_offset` additive.

### Hit Shake (`CombatVisualRoot`만)

- Opponent HIT(플레이어가 때림): strength **3** / **0.10s**.
- Player HIT(플레이어가 맞음): strength **7** / **0.15s**.
- BLOCK / EVADE / Knockdown: shake 없음 (다운 시 clear).

### Additive compose

- Player: `base + breathing + action + pov + knockdown`
- Opponent: `base + breathing + action + parallax + knockdown`
- Root: `base + shake`
- Tween 분리: `_breathing_tween`, `_pov_tween`, `_parallax_tween`, `_shake_tween`

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
| `player_action_state.gd` / `opponent_action_state.gd` | Idle/Slip/Guard |
| `player_offense_resolver.gd` / `player_defense_resolver.gd` | HIT/BLOCK/EVADE + KD |
| `hit_resolve_coordinator.gd` | 동시 Active 조율 |
| `hit_stun.gd` | 0.35s 경직 |
| `knockdown_meter.gd` | 0–100 미터 |
| `knockdown_manager.gd` | Down / Count / Recovery / Final KO |
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
| `player_visual.gd` | POV player + breathing + slip POV |
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
godot --headless --path . --quit-after 2
```

| 파일 | 목적 |
|---|---|
| `kd_meter_smoke_test.gd` | KD Meter, 공격 KD 값, legacy 시스템 부재, HUD |
| `combat_simplify_smoke_test.gd` | Duck/Target/Just/Counter 제거, Straight-only AI |
| `balance_smoke_test.gd` | Hit Stun 0.35, AI interval/follow-up, coordinator |
| `ai_pacing_smoke_test.gd` | cooldown 0, follow-up, difficulty |
| `hit_stun_smoke_test.gd` | HitStun 컴포넌트·씬 배선 |
| `visual_motion_smoke_test.gd` | Breathing/POV/Parallax/Shake/Recovery 0.50·0.55 |

전투 판정을 우회하는 compatibility hack으로 테스트를 통과시키지 말 것.

---

## 16. 개발 규칙

1. **정상 동작 시스템을 이유 없이 재설계하지 말 것** (특히 Stamina↔KD 분리, Straight-only AI, Hit Stun 0.35).
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
3. Visual Motion: Idle Breathing, Slip POV, Parallax, Hit Shake.
4. Opponent Straight Recovery: L **0.50** / R **0.55** (각각 +0.05s 수준).
5. `player_health.gd` 제거 완료(파일 없음).

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
2. 조작: J/K, Shift+J/K, A/D, Space.  
3. Stamina 바와 KD 바가 DebugHUD에 있는지, Slip 시 월드 패럴랙스/플레이어 POV가 반대 방향인지.  
4. 스모크 6종 + headless `game.tscn` 실행.  
5. 전투 규칙을 바꾸기 전에 이 문서 §3–§5와 해당 `.tres`를 재확인.  
6. Visual만 손댈 때는 Combat Startup/Active/Recovery를 건드리지 말 것 (예외는 명시된 Recovery 튜닝뿐).
