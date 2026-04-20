# 프로필

[English](README.md) | 한국어

프로필은 재사용 가능한 번들 구성을 설명합니다.

예시는 다음과 같습니다.

- `minimal-application`: 네임스페이스와 스토리지 같은 최소 기반만 포함
- `developer-sandbox`: 자주 쓰는 플랫폼 구성요소를 포함한 작은 샌드박스
- `web-platform`: 게이트웨이 중심의 공개 웹 스택
- `shared-services`: 내부 공용 플랫폼 기준선
- `full`: 저장소의 모든 항목 포함

아래 명령으로 여러 프로필을 나란히 비교할 수 있습니다.

```powershell
.\scripts\show-profile-catalog.ps1 -Format markdown
```
