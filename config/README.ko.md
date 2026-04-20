# 설정

[English](README.md) | 한국어

이 디렉터리는 템플릿에서 실제로 가장 먼저 수정하게 되는 영역입니다. 저장소를 자기 환경에 맞게 적용하려면 보통 매니페스트보다 이 디렉터리부터 보게 됩니다.

## 먼저 수정할 파일

### 1. `platform-values*.env`

이 파일들에서는 다음 값을 주로 설정합니다.

- 호스트명
- 스토리지 설정
- 비밀번호와 민감값
- Kubernetes 매니페스트에 주입되는 번들 값

예시:

- `config/platform-values.env.example`
- `config/platform-values.dev.env`
- `config/platform-values.staging.env`
- `config/platform-values.prod.env`

### 2. `service-runtime.env.example`

로컬 Docker Compose 예제에서 사용하는 값입니다.

- 로컬 호스트 포트
- Adminer 기본 대상 DB

### 3. `environments/*.psd1`

다음 워크플로우에서 반복 인자를 줄이고 싶을 때 씁니다.

- 검증
- 번들 생성
- 승격
- 기본 출력 경로

자세한 내용은 [environments/README.ko.md](environments/README.ko.md)를 참고하면 됩니다.

### 4. `profiles/*.psd1`

번들 구조 자체를 바꾸고 싶을 때 사용합니다.

- 어떤 Kubernetes 디렉터리를 포함할지
- 어떤 service 디렉터리를 포함할지
- 계획 문서에 어떤 설명을 표시할지

자세한 내용은 [profiles/README.ko.md](profiles/README.ko.md)를 참고하면 됩니다.

## `*.psd1` 카탈로그 파일은 무엇인가

이 디렉터리의 PowerShell 데이터 파일은 초보 사용자가 바로 수정해야 하는 파일이라기보다, 템플릿 유지보수자가 구조를 정의할 때 주로 쓰는 파일입니다.

예를 들면 다음 정보가 들어 있습니다.

- 서비스 빌드 전제
- 런타임 바인딩
- 파이프라인 메타데이터
- 플랫폼 값 카탈로그
- 시크릿 카탈로그

저장소를 그냥 가져다 쓰는 입장이라면, 초반에는 이 파일들을 바로 수정할 필요가 없는 경우가 많습니다.

## 추천 수정 순서

1. `platform-values.<env>.env` 파일 생성
2. 예제 도메인과 비밀번호 교체
3. 로컬 compose 를 쓸 경우 `service-runtime.env.example` 수정
4. 번들 렌더링 또는 검증
5. 그 다음에 전체 구조가 필요할 때만 프로필이나 카탈로그 수정
