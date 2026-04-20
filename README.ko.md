# 범용 Kubernetes 및 Jenkins 플랫폼 템플릿

[English](README.md) | 한국어

이 저장소는 특정 회사 전용 서비스, 사설 이미지 전제, 고정 레거시 포트 규칙 없이 Kubernetes 플랫폼 번들을 구성할 수 있도록 만든 공개용 재사용 템플릿입니다.

이 템플릿에는 다음이 함께 들어 있습니다.

- 범용 Kubernetes 매니페스트
- 수정 가능한 환경 값 파일
- 공개 이미지 기반 애플리케이션 예제
- 검증, 번들 생성, 승격, 시드 자동화를 위한 선택형 Jenkins 흐름

## 이런 경우에 잘 맞습니다

다음이 필요하다면 이 저장소가 잘 맞습니다.

- 새 플랫폼 저장소의 시작점
- 공용 클러스터 구성요소와 간단한 앱 예제를 함께 담은 템플릿
- PowerShell 중심의 검증 및 번들 렌더링 흐름
- 다른 팀이 포크해서 바로 사용할 수 있는 공개 저장소

반대로 다음이 목적이라면 다른 형태가 더 나을 수 있습니다.

- 하나의 고정된 운영 플랫폼만 바로 배포하고 싶은 경우
- Helm 차트만으로 구성된 저장소를 원하는 경우
- 특정 언어 애플리케이션 스타터를 원하는 경우

## 기본으로 포함된 것

### 공개 이미지 애플리케이션 예제

- `nginx-web`: `nginx:1.28-alpine` 기반 정적 사이트 예제
- `httpbin`: `mccutchen/go-httpbin:v2.15.0` 기반 HTTP 테스트 엔드포인트
- `whoami`: `traefik/whoami:v1.10.4` 기반 요청 확인 서비스
- `adminer`: `adminer:5.3.0-standalone` 기반 데이터베이스 UI

### 공용 플랫폼 컴포넌트

- `301_platform_mysql`: MySQL
- `301_platform_postgresql`: PostgreSQL
- `302_platform_redis`: Redis
- `303_platform_memcached`: Memcached
- `304_platform_nginx`: 리버스 프록시
- `305_platform_metrics-server`: metrics API
- `306_platform_external-dns`: DNS 자동화 values 스캐폴드
- `307_platform_harbor`: 내부 레지스트리 values 스캐폴드
- `308_platform_gateway-api`: Gateway 및 HTTPRoute 예제
- `309_platform_nginx-gateway-fabric`: Gateway 컨트롤러 values 스캐폴드
- `310_platform_longhorn`: 스토리지 values 스캐폴드
- `311_platform_kubernetes-dashboard`: 대시보드 values 스캐폴드
- `312_platform_vertical-pod-autoscaler`: VPA values 스캐폴드

## 처음 왔다면 이 순서로 보세요

1. 빠른 시작 문서 확인: [QUICKSTART.ko.md](QUICKSTART.ko.md)
2. 사용할 수 있는 프로필과 프리셋 비교:

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-environment-preset-plan.ps1 -Format markdown
```

3. 수정 가능한 값 파일 생성:

```powershell
.\scripts\new-platform-environment.ps1 `
  -EnvironmentPreset dev `
  -EnvironmentName dev `
  -Force
```

4. 저장소 기본 검증:

```powershell
.\scripts\validate-template.ps1
```

5. 번들 렌더링:

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

## 자주 쓰는 흐름

### 템플릿 구조만 먼저 보고 싶을 때

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
.\scripts\show-platform-plan.ps1 -Profile web-platform -Applications nginx-web,httpbin,whoami -DataServices redis -Format markdown
```

### 로컬에서 Docker Compose 예제만 실행하고 싶을 때

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

자세한 내용은 [services/README.ko.md](services/README.ko.md)를 보면 됩니다.

### Kubernetes 번들을 검토하거나 적용하고 싶을 때

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

렌더링된 번들에는 `k8s/`, `services/`, 계획 문서, 준비 상태 문서, 선택형 Jenkins 자산이 `out/` 아래에 생성됩니다.

### Jenkins 잡까지 만들고 싶을 때

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

Jenkins 흐름은 [jenkins/README.ko.md](jenkins/README.ko.md)를 참고하면 됩니다.

## 보통 가장 먼저 수정하는 파일

대부분의 사용자는 초반에 아래 파일만 수정하면 됩니다.

- `config/platform-values.<env>.env`: 호스트명, 스토리지, 비밀번호, 번들 값
- `config/service-runtime.env.example`: 로컬 Docker Compose 포트
- `config/environments/*.psd1`: 검증, 생성, 승격 기본값

템플릿 구조 자체를 유지할 생각이라면, 더 깊은 `*.psd1` 카탈로그는 바로 건드릴 필요가 없습니다.

## 저장소 안내 지도

- [config/README.ko.md](config/README.ko.md): 값 파일, 프리셋, 카탈로그
- [k8s/README.ko.md](k8s/README.ko.md): 매니페스트 구조, 번호 규칙, 배포 단계
- [services/README.ko.md](services/README.ko.md): 로컬 Docker Compose 예제
- [scripts/README.ko.md](scripts/README.ko.md): 주요 진입 스크립트
- [jenkins/README.ko.md](jenkins/README.ko.md): Jenkins 잡과 Job DSL 흐름

## 중요한 기본값

- 기본값은 공개 이미지를 사용하므로, 직접 사설 이미지를 도입하지 않는 한 사설 레지스트리가 필요하지 않습니다.
- 예제 호스트명은 `example.com` 기준이므로 실제 환경에 맞게 교체해야 합니다.
- 예전 `31500` 대역 포트는 `80`, `8080`, `3306`, `5432` 같은 일반 포트로 정리했습니다.
- 공개 이미지 예제 기준으로는 Jenkins 서비스 이미지 빌드 잡이 기본 생성되지 않습니다.
- 이 저장소의 주요 진입점은 PowerShell 기준으로 작성되어 있습니다.

## 추가로 읽으면 좋은 문서

- 빠른 시작: [QUICKSTART.ko.md](QUICKSTART.ko.md)
- 배포 환경 메모: [DEPLOYMENT_ENV.md](DEPLOYMENT_ENV.md)
- 환경 체크리스트: [ENV_CHECKLIST.md](ENV_CHECKLIST.md)
- 운영 메모: [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md)

## 공개 저장소로 사용할 때 바꿔야 하는 것

이 저장소를 포크해서 쓰려면 최소한 아래는 자기 환경에 맞게 바꾸는 것이 좋습니다.

- `example.com` 기반 도메인
- 생성된 env 파일 안의 비밀번호와 민감값
- Jenkins 시드 잡의 SCM 설정
- 실제로 운영하지 않을 선택형 플랫폼 컴포넌트
