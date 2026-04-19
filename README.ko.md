[English](README.md) | **한국어**

# claude-code-statusline

> **흘끗 보면 됩니다.**  
> [Claude Code](https://www.anthropic.com/claude-code)의 한도, 컨텍스트, 계정. 묻지 않아도 늘 같은 자리에 있습니다.

`/usage`, `/context`, `claude auth status`로 작업을 멈추는 대신, 그저 보면 됩니다.

## 미리보기

**개인 계정**

![개인 계정 렌더링](docs/images/personal.png)

**팀 계정 (경고 포함)**

![팀 계정 렌더링](docs/images/team.png)

## 한눈에

- **`5h` 한도**: 사용률 bar, %, 리셋까지 남은 시간. 15분 미만은 `!`로 강조합니다.
- **`Week` 한도**: 사용률 bar, %, 리셋까지 남은 시간 (일/시 단위).
- **`✦` 컨텍스트**: 모델명, bar, %, 토큰 카운트. 50%와 80%에서 색이 바뀌고 90% 초과 시 `!`. 1M 이상은 `1.2M`로 축약합니다.
- **`@` 계정**: 개인은 `@ Name`, 팀은 `@ Name (OrgName)`으로 표시해 여러 계정을 오갈 때 헷갈리지 않습니다.
- **`$` 비용**: 세션 누적. $2와 $5에서 색이 바뀌고 초과 시 `!`로 강조합니다.
- **cwd, `⎇` git, `❯` vim**: 작업 위치, 브랜치와 더티 상태 (`⌥` worktree 포함), vim 모드.

## 설치

```sh
curl -fsSL https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.sh | sh
```

수동 설치: `statusline.sh`를 `~/.claude/statusline.sh`에 두고 `~/.claude/settings.json`에 추가:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

## 설정

모든 임계값은 `CCSL_*` 환경변수로 덮어쓸 수 있습니다.

| 변수 | 기본값 | 의미 |
|---|---|---|
| `CCSL_BAR_WIDTH` | `10` | bar 셀 수 |
| `CCSL_CTX_WARN` | `50` | 컨텍스트 % 노랑 임계 |
| `CCSL_CTX_CRIT` | `80` | 컨텍스트 % 빨강 임계 |
| `CCSL_FIRE_THRESHOLD` | `90` | 컨텍스트 `!` 임계 |
| `CCSL_LIMIT_WARN_MIN` | `15` | 5시간 리셋 `!` 임계 (분) |
| `CCSL_COST_WARN` | `2.0` | 비용 노랑 임계 ($) |
| `CCSL_COST_CRIT` | `5.0` | 비용 빨강 임계 ($) |
| `CCSL_GIT_TIMEOUT` | `1` | git 호출 상한 (초) |

예: `CCSL_CTX_WARN=30 claude`

## 동작 원리

- **계정 정체성**은 `~/.claude.json`의 `oauthAccount`를 직접 읽습니다. CLI 호출을 거치지 않으므로 병렬 세션에서도 흔들리지 않습니다. 자동 생성 조직명은 정규식으로 걸러 개인과 팀을 자동 판별합니다.
- **가볍게 동작합니다.** 단일 jq 호출과 Unit Separator로 필드를 한 번에 추출하고, git 정보는 CWD별 5초 TTL 파일 캐시로 재사용합니다.
- **누락에 너그럽습니다.** `rate_limits`, `vim.mode`, `~/.claude.json`, `jq` 중 무엇이 없어도 해당 요소만 생략하고 나머지는 그대로 표시합니다.

## 테스트

```sh
./tests/run.sh              # ANSI strip 후 스냅샷 diff
./tests/run.sh --update     # 의도된 포맷 변경 후 재생성
```

호스트의 git/HOME/캐시를 건드리지 않도록 임시 디렉토리에 격리되어 실행됩니다.

## 의존성

`jq`, `git`, `curl` + macOS/Linux 표준 coreutils.

## 라이선스

MIT. [LICENSE](LICENSE) 참조.
