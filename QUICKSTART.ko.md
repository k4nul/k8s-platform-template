# 빠른 시작

[English](QUICKSTART.md) | 한국어

## 1. 프로필 선택

먼저 기본 번들 형태를 확인합니다.

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

자주 쓰는 시작점은 다음과 같습니다.

- `minimal-application`: 네임스페이스와 스토리지 같은 최소 기반만 포함
- `developer-sandbox`: MySQL, Redis, NGINX, metrics 가 포함된 작은 샌드박스
- `web-platform`: Gateway API, DNS 자동화, metrics, 공개 데모 앱 중심 구성
- `shared-services`: 공용 클러스터 애드온과 선택형 앱 예제 중심 구성

## 2. 수정 가능한 값 준비

프리셋으로 환경 값 파일을 생성합니다.

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentPreset dev `
  -EnvironmentName dev `
  -Force
```

그 다음 아래 파일을 수정합니다.

- `config/platform-values.dev.env`
- 로컬 compose 예제도 쓸 경우 `config/service-runtime.env.example`

## 3. 선택한 번들 미리보기

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

## 4. 검증

```powershell
.\scripts\validate-template.ps1
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

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

## 6. 실제 클러스터에 적용

일반적인 적용 순서는 다음과 같습니다.

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

## 7. 로컬 Compose 예제 실행

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

같은 패턴으로 아래 디렉터리도 실행할 수 있습니다.

- `services/httpbin`
- `services/whoami`
- `services/adminer`
