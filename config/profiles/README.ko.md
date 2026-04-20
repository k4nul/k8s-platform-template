# 프로필

[English](README.md) | 한국어

프로필은 재사용 가능한 번들 구성을 설명합니다. 먼저 큰 틀을 고른 다음, 애플리케이션과 데이터 서비스를 추가하거나 제거하는 방식으로 생각하면 이해하기 쉽습니다.

## 포함된 프로필

- `minimal-application`: 네임스페이스와 스토리지 같은 최소 기반만 포함
- `developer-sandbox`: 공용 서비스가 포함된 가벼운 샌드박스
- `web-platform`: 게이트웨이 중심의 공개 웹 스택
- `shared-services`: 공용 클러스터 기준선
- `full`: 저장소의 모든 항목 포함

## 어떻게 고르면 좋은가

아래 명령으로 여러 프로필을 나란히 비교할 수 있습니다.

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
```

질문별로 보면 대략 이렇게 고를 수 있습니다.

- "가장 작은 시작점이 필요하다" -> `minimal-application`
- "빨리 테스트해보고 싶다" -> `developer-sandbox`
- "웹 서비스 예제 스택이 필요하다" -> `web-platform`
- "공용 클러스터 구성요소가 먼저다" -> `shared-services`

## 중요한 점

프로필을 골랐다고 해서 끝까지 그대로 고정되는 것은 아닙니다. 명령줄 인자로 애플리케이션이나 데이터 서비스를 추가하거나 빼면서 세부 구성을 계속 조정할 수 있습니다.
