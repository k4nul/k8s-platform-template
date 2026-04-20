# 서비스 예제

[English](README.md) | 한국어

이 디렉터리에는 범용 Kubernetes 애플리케이션 예제와 맞춰둔 로컬 Docker Compose 예제가 들어 있습니다.

## 설계 원칙

- 공개 이미지 우선
- 기본적으로 사설 레지스트리 불필요
- 샘플 서비스는 저장소 내부 빌드 단계 없이 사용 가능
- 각 서비스 폴더마다 별도의 `README.md` 제공

## 포함된 서비스

- `nginx-web`: `nginx:1.28-alpine` 기반 정적 사이트 예제
- `httpbin`: `mccutchen/go-httpbin:v2.15.0` 기반 API 테스트 서비스
- `whoami`: `traefik/whoami:v1.10.4` 기반 라우팅 테스트 서비스
- `adminer`: `adminer:5.3.0-standalone` 기반 데이터베이스 UI

## 공통 사용 예시

```powershell
docker compose --env-file ..\config\service-runtime.env.example up -d
```

## 공통 환경 파일

`config/service-runtime.env.example` 을 수정해서 다음 값을 바꿀 수 있습니다.

- 로컬 호스트 포트
- Adminer 기본 데이터베이스 대상

런타임 변수와 compose 기대값을 자동 요약으로 보고 싶다면 `scripts/show-service-runtime-plan.ps1 -Format markdown` 을 사용하면 됩니다.
