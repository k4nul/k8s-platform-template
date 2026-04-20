# 서비스 예제

[English](README.md) | 한국어

이 디렉터리에는 `k8s/` 아래의 범용 Kubernetes 애플리케이션 예제와 짝을 이루는 로컬 Docker Compose 예제가 들어 있습니다.

다음 상황에서 이 디렉터리를 사용하면 좋습니다.

- 클러스터에 적용하기 전에 로컬에서 먼저 예제를 보고 싶을 때
- 기본 공개 이미지가 무엇인지 확인하고 싶을 때
- 포트와 간단한 런타임 동작을 빠르게 점검하고 싶을 때

## 설계 원칙

- 공개 이미지 우선
- 기본적으로 사설 레지스트리 불필요
- 샘플 서비스는 저장소 내부 빌드 단계 없이 사용 가능
- 서비스별 디렉터리 분리
- 각 서비스 폴더마다 별도의 `README.md` 제공

## 포함된 서비스

- `nginx-web`: `nginx:1.28-alpine` 기반 정적 사이트 예제
- `httpbin`: `mccutchen/go-httpbin:v2.15.0` 기반 API 테스트 서비스
- `whoami`: `traefik/whoami:v1.10.4` 기반 라우팅 테스트 서비스
- `adminer`: `adminer:5.3.0-standalone` 기반 데이터베이스 UI

## 하나의 예제 실행하기

서비스 디렉터리 안에서 다음처럼 실행합니다.

```powershell
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

예시:

```powershell
cd .\services\nginx-web
docker compose --env-file ..\..\config\service-runtime.env.example up -d
```

## 중지와 정리

```powershell
docker compose down
```

## 공통 런타임 변수

`config/service-runtime.env.example` 에서 다음 값을 바꿀 수 있습니다.

- 로컬 호스트 포트
- Adminer 기본 데이터베이스 대상

런타임 변수와 compose 기대값을 자동 요약으로 보고 싶다면:

```powershell
.\scripts\show-service-runtime-plan.ps1 -Format markdown
```

## `k8s/` 와의 관계

이 compose 예제들은 공개 이미지 기반 Kubernetes 예제를 간단하게 로컬에서 따라 볼 수 있도록 만든 대응 샘플입니다.

다음 용도로 특히 유용합니다.

- 콘텐츠 수정
- 간단한 엔드포인트 테스트
- 클러스터 렌더링 전 스모크 테스트

반면, Kubernetes 배포의 모든 세부 사항을 완전히 동일하게 재현하는 목적은 아닙니다.
