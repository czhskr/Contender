# Contender

**Contender**는 웹에서 간단하게 플레이할 수 있는  
2D 1인칭 시점 복싱 게임입니다.

공격과 방어를 단순한 키 조작으로 구성하면서도,
스태미나 관리, 가드, 회피, 카운터 위험, 다운과 판정 등을 통해
복싱의 공방과 타이밍을 표현하는 것을 목표로 제작했습니다.

## Play

> Web에서 바로 플레이할 수 있습니다.

**[Play Contender](여기에_GitHub_Pages_주소)**

※ Chrome 기반 데스크톱 브라우저 플레이를 권장합니다.

---

## Controls

| 키 | 동작 |
|---|---|
| J | 왼손 스트레이트 |
| K | 오른손 스트레이트 |
| Shift + J | 왼손 훅 |
| Shift + K | 오른손 훅 |
| A | 왼쪽 회피 |
| S | 아래 회피 |
| D | 오른쪽 회피 |
| Space | 하이 가드 |
| ESC | 일시정지 |

---

## Game Modes

### 일반 모드

기본 복싱 규칙으로 진행되는 모드입니다.

공격, 가드, 회피와 스태미나를 활용해 상대를 다운시키고
KO 또는 판정으로 승리하는 것이 목표입니다.

### 특성 모드

매 라운드 플레이어와 상대에게 서로 다른 특성이 부여됩니다.

공격력, 방어력, 스태미나 운용, 회피 및 연속 공격 등
전투 스타일에 영향을 주는 특성에 맞춰 전략을 바꿔야 합니다.

---

## Core Mechanics

- 왼손/오른손 스트레이트 및 훅
- 하이 가드
- 방향 회피
- 스태미나 관리
- 공격 중 피격에 대한 Counter-Hit 위험
- Knockdown / 10 Count / Recovery
- KO 및 판정
- 라운드 시스템
- 난이도별 Opponent AI
- 라운드별 Trait 시스템

---

## Development

- **Engine:** Godot Engine 4.7.2
- **Language:** GDScript
- **Platform:** Web
- **Resolution:** 1152 × 648
- **Deployment:** GitHub Pages
- **Development Support:** AI Coding Assistant

생성형 AI를 기획, 코드 작성, 디버깅 및 반복적인 밸런스 검증에
활용했습니다.

AI가 생성한 결과를 그대로 사용하는 방식이 아니라,
실제 플레이 테스트와 스모크 테스트를 통해 동작을 확인하고
문제가 있는 부분을 반복적으로 수정하는 방식으로 개발했습니다.

---

## AI-Assisted Development

이 프로젝트에서는 AI Coding Assistant를 다음 과정에 활용했습니다.

- 전투 시스템 구조 설계
- Opponent AI 구현 및 조정
- Knockdown / Recovery 시스템 구현
- Trait 시스템 구현
- UI 및 Web 배포 기능 구현
- 테스트 코드 작성
- 오류 분석 및 회귀 테스트

특히 전투 밸런스와 AI 행동은 생성된 코드를 그대로 확정하지 않고,
실제 플레이 결과를 바탕으로 원인을 분석한 뒤 여러 차례 수정했습니다.

---

## Web Version

Web 버전은 브라우저의 오디오 정책을 고려하여
리소스 로딩이 완료된 뒤 **시작하기** 버튼을 눌러 게임을 실행합니다.

화면은 16:9 비율을 기준으로 제작되었으며,
브라우저 크기에 맞춰 비율을 유지한 상태로 조정됩니다.

---

## Project Structure

```text
assets/      Game assets
data/        Combat and game data
scenes/      Godot scenes
scripts/     Game scripts
tests/       Smoke and regression tests
web_shell/   Custom Web loading/start screen
docs/        GitHub Pages Web build
