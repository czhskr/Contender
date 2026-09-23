# Contender Assets

현재 디스크에 있는 PNG만 적는다. 없는 파일을 “예정”으로 적지 않는다.  
시각 컨트롤러는 `ResourceLoader.exists`로 로드하며, 없으면 ColorRect/Label 폴백을 쓴다.

## Layout 규칙 (요약)

| 항목 | 값 |
|---|---|
| Player 소스 | 1536×864 full-frame transparent |
| Viewport | 1152×648 |
| Player scale | 0.75 (양축), `centered = false`, offset/base = origin |
| Pose 전환 | 텍스처 스왑만 (pose별 scale/alignment 금지) |

상세는 `AGENTS.md` §10–§11, `scripts/visual_display_layout.gd`.

## Background — `assets/background/`

| File | 용도 |
|---|---|
| `bg_crowd.png` | Crowd layer (`BackgroundVisual`) |
| `bg_ring.png` | Ring layer (`BackgroundVisual`) |

## Player — `assets/player/`

| File | 용도 |
|---|---|
| `p.Nstance.png` | Idle / stance |
| `p.L_straight.png` | Left Straight |
| `p.R_straight.png` | Right Straight |
| `p.L_hook.png` | Left Hook |
| `p.R_hook.png` | Right Hook |
| `p.highguard.png` | High Guard |

**없음 (의도):** Slip PNG — Player Slip은 `PlayerVisual`의 `pov_offset`만 사용.  
**없음:** hit / knockdown 전용 PNG — Knockdown 시 idle 텍스처 등을 재사용.

## Opponent — `assets/opponent/`

| File | 용도 |
|---|---|
| `o.Nstance.png` | Idle / stance (Startup 포함) |
| `o.L_straight.png` | Left Straight (ACTIVE 표시) |
| `o.R_straight.png` | Right Straight (ACTIVE 표시) |
| `o.L_slip.png` | Slip Left |
| `o.R_slip.png` | Slip Right |
| `o.highguard.png` | High Guard |
| `o.hit.png` | HIT / Knockdown / KO 표시 |

**없음:** Opponent Hook PNG — Hook 공격 데이터는 있으나 AI·비주얼 미사용.

## 제거된 경로 (다시 만들지 말 것)

Duck, Head/Body hit, 구 naming(`left_idle.png`, `duck.png`, `head_hit.png` 등)은 **사용하지 않는다**.
