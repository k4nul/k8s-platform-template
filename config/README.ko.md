# 설정

[English](README.md) | 한국어

이 디렉터리는 템플릿에서 사용자가 직접 수정할 수 있는 설정 영역입니다.

주요 구성은 다음과 같습니다.

- `platform-values*.env`: 렌더링되는 Kubernetes 자산에 들어갈 환경별 값
- `service-runtime.env.example`: 공개 이미지 예제의 로컬 compose 실행용 환경 변수
- `environments/`: `dev`, `staging`, `prod` 같은 재사용 가능한 프리셋
- `profiles/`: 번들 구성을 재사용하기 위한 프로필
- `*.psd1`: 계획 확인 및 검증 스크립트가 참조하는 카탈로그 파일

대부분의 사용자는 먼저 `.env` 파일을 수정하고, 템플릿 구조 자체를 바꾸고 싶을 때만 더 깊은 카탈로그 파일을 손보면 됩니다.
