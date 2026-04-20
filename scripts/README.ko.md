# 스크립트

[English](README.md) | 한국어

이 디렉터리에는 템플릿을 운영할 때 사용하는 주요 진입점 스크립트가 들어 있습니다.

가장 자주 쓰는 명령은 다음과 같습니다.

- `validate-template.ps1`: 저장소 구조와 예제 자산 검증
- `invoke-repository-validation.ps1`: 메인 검증 흐름 실행
- `invoke-bundle-delivery.ps1`: 번들을 렌더링, 검증, 아카이브
- `invoke-bundle-promotion.ps1`: 전달된 번들을 풀어서 재검증
- `render-platform-assets.ps1`: 번들을 직접 렌더링
- `show-platform-plan.ps1`: 선택된 컴포넌트 미리보기
- `show-platform-values-plan.ps1`: 필요한 값 미리보기
- `show-service-runtime-plan.ps1`: compose 런타임 변수 미리보기
- `show-jenkins-job-plan.ps1`: 범용 Jenkins 잡 체인 미리보기
