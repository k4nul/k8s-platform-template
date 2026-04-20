# 환경 프리셋

[English](README.md) | 한국어

이 디렉터리에는 검증, 번들 생성, 승격, 값 파일 생성 스크립트에서 반복 인자를 줄이기 위한 재사용 가능한 환경 프리셋이 들어 있습니다.

## 포함된 프리셋

- `dev.psd1`: 개발 친화적인 작은 `web-platform` 기준선
- `staging.psd1`: 사전 운영 검증용으로 조금 더 넓은 `shared-services` 기준선
- `prod.psd1`: 운영 지향의 `shared-services` 기준선

## 자주 쓰는 키

- `ValuesFile`: 기본 값 파일 경로
- `DockerRegistry`: 사설 이미지를 도입했을 때만 쓰는 선택형 레지스트리 호스트
- `Version`: 기본 이미지 태그 또는 검증용 태그
- `Profile`: 기본 번들 프로필
- `Applications`: 기본 애플리케이션 선택
- `DataServices`: 기본 데이터 서비스 선택
- `IncludeJenkins`: 선택된 번들에 Jenkins 컴포넌트를 포함할지 여부
- `OutputPath`: 번들 생성 워크플로우의 기본 출력 경로
- `ArchivePath`: 번들 생성 또는 승격 워크플로우의 기본 ZIP 경로
- `PromotionExtractPath`: 번들 승격 워크플로우의 기본 압축 해제 경로
- `RenderedPath`: 저장소 검증 워크플로우에서 사용할 수 있는 선택형 렌더링 번들 경로

스크립트에서 명시적으로 넘긴 인자는 프리셋 값을 계속 덮어쓰므로, 프리셋은 강제 규칙이라기보다 공통 기본값 역할을 합니다.
