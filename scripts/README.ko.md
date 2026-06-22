# 스크립트

[English](README.md) | 한국어

이 디렉터리에는 템플릿을 탐색하고, 검증하고, 렌더링하고, 번들로 묶을 때 쓰는 주요 진입점 스크립트가 들어 있습니다.

## 자주 쓰는 명령

### 템플릿 구조 확인

- `show-profile-catalog.ps1`: 프로필 비교
- `show-environment-preset-plan.ps1`: 환경 프리셋 비교
- `show-render-matrix.ps1`: 번들을 렌더링하지 않고 프로필/환경 렌더 검증 매트릭스 확인
- `show-platform-plan.ps1`: 선택된 컴포넌트 미리보기
- `show-platform-values-plan.ps1`: 필요한 값 미리보기
- `show-service-runtime-plan.ps1`: compose 런타임 변수 미리보기

### 준비 상태와 사전 점검

- `show-validation-readiness.ps1`: 로컬 도구 준비 상태, 선택 번들 특성, 권장 검증 명령 보고
- `show-cluster-preflight.ps1`: 배포 전 클러스터 namespace, storage, CRD, Helm 소스 기대값 보고
- `show-cluster-secret-plan.ps1`: 필요한 secret 이름, 키, 예시 bootstrap 명령 보고

렌더링된 번들에도 선택한 프로필과 값 파일 기준의 `VALIDATION_READINESS.md`, `CLUSTER_PREFLIGHT.md`, `CLUSTER_SECRET_PLAN.md`가 포함됩니다.

`show-validation-readiness.ps1 -Format json`은 원시 도구 누락 목록과 그룹화된 요구사항을 함께 제공합니다. 렌더링된 스키마 검증은 `kubeconform` 또는 `kubectl` 중 하나만 있으면 충족되므로 단일 요구사항 `kubeconform or kubectl`로 표시됩니다.

### 검증

- `validate-template.ps1`: 저장소 구조와 예제 자산 검증
- `invoke-repository-validation.ps1`: 메인 검증 흐름 실행
- `validate-render-matrix.ps1`: 공개 기본값 기준 프로필/환경 조합 렌더링 및 검증
- `validate-platform-assets.ps1`: 렌더링된 자산 직접 검증
- `validate-kubernetes-security-baseline.ps1`: 렌더링된 Kubernetes YAML의 위험한 기본값과 기준선 누락 점검
- `validate-workstation.ps1`: `kubectl`, `kubeconform`, `helm` 같은 로컬 도구 점검

렌더링된 매니페스트 스키마 검증은 `kubeconform`이 있으면 먼저 사용하고, 없으면 `kubectl apply --dry-run=client --validate=true`로 fallback합니다. 외부 검증기가 둘 다 없을 때 비엄격 검증은 경고를 출력하고 렌더링된 YAML의 `apiVersion`, `kind`, `metadata.name` 구조 사전 점검은 계속 실행합니다. CI에서 특정 검증기를 고정해야 한다면 템플릿, 저장소, 매트릭스, 플랫폼 자산 검증 명령에 `-SchemaValidator kubeconform` 또는 `-SchemaValidator kubectl`을 전달하세요.

`validate-template.ps1`은 필수 저장소 파일, 가벼운 PowerShell 테스트, 서비스 카탈로그와 공개 값, 공개 스모크 렌더링, 렌더링된 스모크 번들 검증을 실행한 뒤 `validate-render-matrix.ps1`을 호출합니다. 스모크와 매트릭스 렌더링 검증은 높은 심각도의 Kubernetes 보안 기준 findings가 있으면 실패합니다. 매트릭스는 모든 포함 환경 프리셋과 공개 프로필 모양을 `config/platform-values.env.example`로 검증하므로 렌더링 번들을 저장소에 남기지 않고 프로필, 프리셋, 기본값 drift를 확인할 수 있습니다. 렌더링 없이 범위만 검토하려면 `show-render-matrix.ps1 -Format markdown` 또는 `-Format json`을 사용합니다.

`invoke-repository-validation.ps1`은 템플릿 게이트보다 넓습니다. 템플릿 검증, 엄격한 워크스테이션 검증, 선택 프리셋의 렌더링 번들 검증을 함께 실행합니다. 엄격한 워크스테이션 검증은 기본적으로 `kubectl`과 `helm`을 요구하므로, 현재 머신에서 막힌 검증이 무엇인지 먼저 보려면 `show-validation-readiness.ps1`을 사용하세요.

### 렌더링과 전달

- `render-platform-assets.ps1`: 번들을 직접 렌더링
- `invoke-bundle-delivery.ps1`: 번들을 렌더링, 검증, 아카이브
- `invoke-bundle-promotion.ps1`: 전달된 번들을 풀어서 재검증
- `new-platform-environment.ps1`: 프리셋 기반 값 파일 생성

## 대표 흐름 예시

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-render-matrix.ps1 -Format markdown
.\scripts\new-platform-environment.ps1 -EnvironmentPreset dev -EnvironmentName dev -Force
.\scripts\validate-render-matrix.ps1
.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev -ValuesFile config\platform-values.dev.env
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

프리셋만 지정한 저장소 검증은 프리셋에 `ValidationValuesFile`이 있으면 그 값을 사용합니다. 생성한 환경 값 파일을 수정한 뒤에는 명시적인 `-ValuesFile` 형식을 실행하세요.

## 어떤 스크립트를 언제 쓰나

- 무엇을 포함할지 결정 중이면 `show-*` 스크립트
- 생성 전에 안정성을 확인하고 싶으면 `validate-*` 스크립트
- 실제 작업 흐름 전체를 돌리고 싶으면 `invoke-*` 스크립트
- 전체 delivery 흐름 없이 바로 렌더링만 하고 싶으면 `render-platform-assets.ps1`
