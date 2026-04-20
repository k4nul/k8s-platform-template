# 빠른 시작

[English](QUICKSTART.md) | 한국어

이 문서는 처음 저장소를 받은 사람이 구조를 이해하고, 값 파일을 만들고, 로컬 예제를 돌리거나 Kubernetes 번들을 렌더링할 수 있도록 돕는 입문용 가이드입니다.

## 준비물

권장 도구는 다음과 같습니다.

- PowerShell 또는 `pwsh`
- `git`
- 클러스터 검증이나 적용을 하려면 `kubectl`
- Helm 컴포넌트를 검증하거나 설치하려면 `helm`
- 로컬 compose 예제를 돌리려면 Docker

모든 도구가 없어도 저장소 탐색은 가능하지만, 일부 검증 단계는 건너뛰게 됩니다.

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
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

- `validate-template.ps1`: 템플릿 구조 자체 검증
- `invoke-repository-validation.ps1`: 실제 사용 흐름에 가까운 검증

## 5. 번들 렌더링

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

렌더링된 번들에는 보통 다음 항목이 들어갑니다.

- `k8s/`
- `services/`
- `DEPLOYMENT_BUNDLE.md`
- `CLUSTER_PREFLIGHT.md`
- `CLUSTER_SECRET_PLAN.md`
- `PLATFORM_VALUES_PLAN.md`
- `SERVICE_RUNTIME_PLAN.md`
- `jenkins/JOB_PLAN.md`
- `jenkins/seed-job-dsl.groovy`

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
.\out\delivery\dev\cluster-bootstrap\status-secrets.ps1
.\out\delivery\dev\apply-manifests.ps1
.\out\delivery\dev\install-helm-components.ps1 -PrepareRepos
.\out\delivery\dev\status-bundle.ps1
```

샘플 앱만 적용하고 싶다면:

```powershell
kubectl apply -f .\out\delivery\dev\k8s\400_platform_nginx-web\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_httpbin\
kubectl apply -f .\out\delivery\dev\k8s\400_platform_whoami\
```

## 7. Jenkins 흐름이 필요하다면

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

Jenkins 설정 흐름은 `jenkins/README.ko.md` 를 참고하면 됩니다.

## 8. 다음에 읽으면 좋은 문서

- 저장소 개요: [README.ko.md](README.ko.md)
- 값과 프리셋: [config/README.ko.md](config/README.ko.md)
- 매니페스트 구조: [k8s/README.ko.md](k8s/README.ko.md)
- 로컬 예제: [services/README.ko.md](services/README.ko.md)
- 스크립트 안내: [scripts/README.ko.md](scripts/README.ko.md)
