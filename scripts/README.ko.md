# 스크립트

[English](README.md) | 한국어

이 디렉터리에는 템플릿을 탐색하고, 검증하고, 렌더링하고, 번들로 묶을 때 쓰는 주요 진입점 스크립트가 들어 있습니다.

## 자주 쓰는 명령

### 템플릿 구조 확인

- `show-profile-catalog.ps1`: 프로필 비교
- `show-environment-preset-plan.ps1`: 환경 프리셋 비교
- `show-platform-plan.ps1`: 선택된 컴포넌트 미리보기
- `show-platform-values-plan.ps1`: 필요한 값 미리보기
- `show-service-runtime-plan.ps1`: compose 런타임 변수 미리보기
- `show-jenkins-job-plan.ps1`: Jenkins 잡 체인 미리보기

### 검증

- `validate-template.ps1`: 저장소 구조와 예제 자산 검증
- `invoke-repository-validation.ps1`: 메인 검증 흐름 실행
- `validate-platform-assets.ps1`: 렌더링된 자산 직접 검증
- `validate-workstation.ps1`: `kubectl`, `helm` 같은 로컬 도구 점검

### 렌더링과 전달

- `render-platform-assets.ps1`: 번들을 직접 렌더링
- `invoke-bundle-delivery.ps1`: 번들을 렌더링, 검증, 아카이브
- `invoke-bundle-promotion.ps1`: 전달된 번들을 풀어서 재검증
- `new-platform-environment.ps1`: 프리셋 기반 값 파일 생성

## 대표 흐름 예시

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\new-platform-environment.ps1 -EnvironmentPreset dev -EnvironmentName dev -Force
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

## 어떤 스크립트를 언제 쓰나

- 무엇을 포함할지 결정 중이면 `show-*` 스크립트
- 생성 전에 안정성을 확인하고 싶으면 `validate-*` 스크립트
- 실제 작업 흐름 전체를 돌리고 싶으면 `invoke-*` 스크립트
- 전체 delivery 흐름 없이 바로 렌더링만 하고 싶으면 `render-platform-assets.ps1`
