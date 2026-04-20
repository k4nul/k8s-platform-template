# 범용 Kubernetes 및 Jenkins 플랫폼 템플릿

[English](README.md) | 한국어

이 저장소는 특정 회사 전용 서비스나 고정 포트 규칙에 묶이지 않도록 정리한 재사용 가능한 플랫폼 템플릿입니다. 범용 Kubernetes 매니페스트, 선택형 Jenkins 자동화, 공개 이미지를 사용하는 애플리케이션 예제를 함께 제공합니다.

## 변경된 점

- 기본 경로에서 사설 애플리케이션 이미지를 제거했습니다.
- 애플리케이션 예제를 공개 이미지 기반으로 정리했습니다.
  - `nginx-web`
  - `httpbin`
  - `whoami`
  - `adminer`
- 예전 `31500` 대역 포트를 `80`, `8080`, `3306`, `5432` 같은 일반 포트로 교체했습니다.
- 환경 값은 `config/platform-values*.env` 와 `config/service-runtime.env.example` 에서 쉽게 수정할 수 있게 정리했습니다.

## 저장소 구조

- `config/`: 수정 가능한 값 파일, 프로필, 환경 프리셋, 서비스 카탈로그
- `jenkins/`: 검증, 번들 생성, 승격, 시드 자동화를 위한 범용 Jenkins 잡
- `k8s/`: 배포 단계와 성격에 따라 나눈 Kubernetes 매니페스트
- `scripts/`: 렌더링, 검증, 계획 확인, 번들 보조 스크립트
- `services/`: 공개 이미지 기반 로컬 Docker Compose 예제

상위 폴더와 각 애플리케이션/컴포넌트 폴더에는 각각 별도 `README.md` 가 있습니다. 핵심 상위 폴더에는 대응되는 `README.ko.md` 도 함께 추가했습니다.

## 범용 애플리케이션 예제

- `nginx-web`: `nginx:1.28-alpine` 기반 정적 사이트 예제
- `httpbin`: `mccutchen/go-httpbin:v2.15.0` 기반 HTTP 테스트 엔드포인트
- `whoami`: `traefik/whoami:v1.10.4` 기반 요청 확인 서비스
- `adminer`: `adminer:5.3.0-standalone` 기반 데이터베이스 UI

## 공용 플랫폼 컴포넌트

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

## 일반적인 사용 흐름

1. 먼저 프로필을 비교합니다.

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
```

2. 환경 값 파일을 생성하거나 복사합니다.

```powershell
.\scripts\new-platform-environment.ps1 -EnvironmentPreset dev -EnvironmentName dev
```

3. 선택한 번들 구성을 미리 봅니다.

```powershell
.\scripts\show-platform-plan.ps1 `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -Format markdown
```

4. 저장소와 렌더링 결과를 검증합니다.

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
```

5. 번들을 렌더링하고 아카이브합니다.

```powershell
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

보다 빠른 시작이 필요하면 [QUICKSTART.ko.md](QUICKSTART.ko.md)를 참고하면 됩니다.

## 참고 사항

- 기본값은 공개 이미지를 사용하므로, 템플릿을 직접 커스터마이징하지 않는 한 사설 레지스트리가 필요하지 않습니다.
- 예제 호스트명은 `example.com` 기준이므로 실제 환경에 맞게 바꿔야 합니다.
- 생성된 값 파일은 템플릿을 가져다 쓰는 사용자가 직접 수정하는 것을 전제로 합니다.
- 공개 이미지 예제 기준으로는 Jenkins 서비스 이미지 빌드 잡이 기본 생성되지 않습니다.
