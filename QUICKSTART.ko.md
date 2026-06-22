# 빠른 시작

[English](QUICKSTART.md) | 한국어

이 문서는 처음 저장소를 받은 사람이 구조를 이해하고, 값 파일을 만들고, 로컬 예제를 돌리거나 Kubernetes 번들을 렌더링할 수 있도록 돕는 입문용 가이드입니다.

## 준비물

권장 도구는 다음과 같습니다.

- PowerShell 또는 `pwsh`
- `git`
- 라이브 클러스터 없이 렌더링된 매니페스트 스키마를 검증하려면 `kubeconform`
- 클러스터 검증이나 적용을 하려면 `kubectl`
- Helm 컴포넌트를 검증하거나 설치하려면 `helm`
- 로컬 compose 예제를 돌리려면 Docker

모든 도구가 없어도 저장소 탐색은 가능하지만, 일부 검증 단계는 건너뛰게 됩니다.
정확한 도구 누락 동작은 [docs/troubleshooting.md](docs/troubleshooting.md)를 참고하세요.

## 1. 어떤 구성을 쓸지 먼저 확인

내장된 프로필과 환경 프리셋을 먼저 비교합니다.

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

자주 쓰는 시작점은 다음과 같습니다.

- `minimal-application`: 네임스페이스와 스토리지 같은 최소 기반만 포함
- `developer-sandbox`: 공용 서비스가 포함된 가벼운 샌드박스
- `web-platform`: 게이트웨이 중심의 공개 웹 스택
- `shared-services`: 공용 클러스터 기준선

## 2. 수정 가능한 값 파일 생성

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentPreset dev `
  -EnvironmentName dev `
  -Force
```

예를 들어 `config/platform-values.dev.env` 같은 파일이 만들어집니다.

계속 진행하기 전에 최소한 아래 값은 바꾸는 것이 좋습니다.

- `example.com` 기반 호스트명
- NFS 서버와 경로 같은 스토리지 설정
- 비밀번호와 민감값

로컬 compose 예제도 쓰려면 다음 파일도 함께 봅니다.

- `config/service-runtime.env.example`

## 3. 어떤 리소스가 포함되는지 미리 보기

```powershell
.\scripts\show-platform-plan.ps1 `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -Format markdown

.\scripts\show-platform-values-plan.ps1 `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -Format markdown
```

이 단계에서는 두 가지를 확인할 수 있습니다.

- 어떤 디렉터리와 컴포넌트가 포함되는지
- 값 파일에 어떤 항목이 필요한지

## 4. 저장소 검증

```powershell
.\scripts\validate-template.ps1
.\scripts\show-render-matrix.ps1 -Format markdown
.\scripts\validate-render-matrix.ps1
.\scripts\show-validation-readiness.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

- `validate-template.ps1`: 템플릿 구조, 공개 스모크 렌더링, 렌더 매트릭스, 보안 기준 검증
- `show-render-matrix.ps1`: 번들을 모두 렌더링하지 않고 공개 환경/프로필 매트릭스 확인
- `validate-render-matrix.ps1`: 모든 공개 매트릭스 항목 렌더링 및 검증
- `show-validation-readiness.ps1`: 현재 워크스테이션에서 가능한 검증과 막힌 검증 확인
- `invoke-repository-validation.ps1`: 워크스테이션 검증과 렌더링 자산 검증까지 포함한 실제 사용 흐름

`invoke-repository-validation.ps1 -EnvironmentPreset dev`는 기본적으로 프리셋의 공개 `ValidationValuesFile`을 사용합니다. `config/platform-values.dev.env`를 수정한 뒤에는 명시적으로 전달하세요.

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

수정한 값 파일이 모든 공개 매트릭스 항목과 맞는지 전달 전에 넓게 확인하려면 다음 명령을 추가로 실행합니다.

```powershell
.\scripts\validate-render-matrix.ps1 -ValuesFile config\platform-values.dev.env
```

공개 기본값 렌더 매트릭스, 스키마 검증기 fallback, CRD 기반 리소스 처리, Kubernetes 보안 기준 검사는 [docs/testing.md](docs/testing.md)를 참고하세요.

## 5. 번들 렌더링

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

렌더링된 번들에는 보통 다음 항목이 들어갑니다.

- `k8s/`
- `services/`
- `DEPLOYMENT_BUNDLE.md`
- `bundle-manifest.json`
- `validate-bundle.ps1` 및 배포 helper 스크립트
- `CLUSTER_PREFLIGHT.md`
- `CLUSTER_SECRET_PLAN.md`
- `VALIDATION_READINESS.md`
- `PROFILE_CATALOG.md`
- `PLATFORM_PLAN.md`
- `PLATFORM_VALUES_PLAN.md`
- 서비스 빌드, 설정, 의존성, 입력 계획 문서
- `SERVICE_RUNTIME_PLAN.md`

`DEPLOYMENT_BUNDLE.md`를 번들 색인으로 사용하세요. 선택한 프로필과 값 파일 기준으로 생성된 helper, 계획 문서, 배포 명령을 함께 보여줍니다.

기본 출력 경로는 보통 `out/delivery/<environment>/` 입니다.

## 6. 다음 경로 선택

### 경로 A: 로컬 Compose 예제만 실행

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

같은 방식으로 아래 디렉터리도 실행할 수 있습니다.

- `services/httpbin`
- `services/whoami`
- `services/adminer`

### 경로 B: Kubernetes 번들 검토 또는 적용

렌더링 후 일반적인 순서는 다음과 같습니다.

```powershell
.\out\delivery\dev\validate-bundle.ps1
.\out\delivery\dev\cluster-bootstrap\check-secret-templates.ps1
.\out\delivery\dev\cluster-bootstrap\status-secrets.ps1
.\out\delivery\dev\apply-manifests.ps1
.\out\delivery\dev\install-helm-components.ps1 -PrepareRepos
.\out\delivery\dev\status-bundle.ps1
```

적용 전에 생성된 bootstrap secret 템플릿을 실제 값으로 수정하세요. 배포가 namespace와 secret 준비 전에는 멈춰야 한다면 `status-secrets.ps1 -FailOnMissing`를 사용합니다.

샘플 앱만 적용하고 싶다면:

```powershell
kubectl apply -f .\out\delivery\dev\k8s\400_platform_nginx-web\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_httpbin\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_whoami\
```

## 7. CI/CD 흐름이 필요하다면

Jenkins 잡이 필요하면 `../jenkins-pipeline-template` 저장소를 사용합니다.

## 8. 다음에 읽으면 좋은 문서

- 저장소 개요: [README.ko.md](README.ko.md)
- 값과 프리셋: [config/README.ko.md](config/README.ko.md)
- 매니페스트 구조: [k8s/README.ko.md](k8s/README.ko.md)
- 로컬 예제: [services/README.ko.md](services/README.ko.md)
- 스크립트 안내: [scripts/README.ko.md](scripts/README.ko.md)
- 검증과 문제 해결: [docs/testing.md](docs/testing.md), [docs/troubleshooting.md](docs/troubleshooting.md)
