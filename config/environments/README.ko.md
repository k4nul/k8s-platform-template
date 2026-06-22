# 환경 프리셋

[English](README.md) | 한국어

이 디렉터리에는 검증, 번들 생성, 승격, 값 파일 생성 스크립트에서 반복 인자를 줄이기 위한 재사용 가능한 환경 프리셋이 들어 있습니다.

## 포함된 프리셋

- `dev.psd1`: 개발 친화적인 `web-platform` 기준선
- `staging.psd1`: 사전 운영 검증용 `shared-services` 기준선
- `prod.psd1`: 운영 지향의 `shared-services` 기준선

## 프리셋이 주로 제어하는 값

- `ValuesFile`: 기본 값 파일 경로
- `ValidationValuesFile`: 공개 기본값으로 저장소 검증을 실행할 때 사용할 값 파일
- `DockerRegistry`: 사설 이미지를 도입했을 때만 쓰는 선택형 레지스트리 호스트
- `Version`: 기본 이미지 태그 또는 검증용 태그
- `Profile`: 기본 번들 프로필
- `Applications`: 기본 애플리케이션 선택
- `DataServices`: 기본 데이터 서비스 선택
- `OutputPath`: 번들 생성 워크플로우의 기본 출력 경로
- `ArchivePath`: 번들 생성 또는 승격 워크플로우의 기본 ZIP 경로
- `PromotionExtractPath`: 번들 승격 워크플로우의 기본 압축 해제 경로
- `RenderedPath`: 저장소 검증 워크플로우에서 사용할 수 있는 선택형 렌더링 번들 경로

## 프리셋 사용 예시

```powershell
.\scripts\invoke-repository-validation.ps1 -EnvironmentPreset dev
.\scripts\invoke-bundle-delivery.ps1 -EnvironmentPreset dev
```

프리셋은 강제 규칙이라기보다 공통 기본값에 가깝습니다. 그래서 명시적으로 인자를 더 주면 프리셋 값을 계속 덮어쓸 수 있습니다.

즉 `dev` 를 시작점으로 삼은 뒤에도 아래 항목을 추가 인자로 바꿀 수 있습니다.

- 프로필
- 애플리케이션 목록
- 데이터 서비스 목록
- 출력 경로

프리셋 파일을 바로 고치기 전에 명령줄에서 먼저 실험해보기에 좋습니다.

## 검증 매트릭스

템플릿 검증은 `config/environments/*.psd1`의 모든 프리셋을 환경 매트릭스 항목으로 렌더링합니다. 값 파일은 명시적인 `-ValuesFile`, `ValidationValuesFile`, `ValuesFile`, `config/platform-values.env.example` 순서로 결정됩니다.

포함된 프리셋은 `ValidationValuesFile`을 `config/platform-values.env.example`로 지정합니다. 그래서 공개 검증은 로컬 `platform-values.<env>.env` 파일에 들어갈 수 있는 사이트별 호스트명, 스토리지 경로, 비밀값 자리표시에 의존하지 않습니다.

생성한 환경 값 파일을 수정한 뒤 검증하려면 명시적으로 전달하세요.

```powershell
.\scripts\invoke-repository-validation.ps1 `
  -EnvironmentPreset dev `
  -ValuesFile config\platform-values.dev.env
```

전체 렌더 매트릭스만 직접 실행할 수도 있습니다. 이 명령은 환경 프리셋 항목을 먼저 검증한 뒤 `config/profiles/` 아래의 모든 프로필 항목을 검증합니다.

```powershell
.\scripts\validate-render-matrix.ps1
```

번들을 렌더링하지 않고 같은 매트릭스 범위와 값 파일 해석만 확인하려면 다음 명령을 사용합니다.

```powershell
.\scripts\show-render-matrix.ps1 -Format markdown
```

생성한 값 파일 하나를 전체 공개 매트릭스에 대입해 확인하려면 두 명령 모두에 `-ValuesFile`을 명시합니다.

```powershell
.\scripts\show-render-matrix.ps1 -ValuesFile config\platform-values.dev.env -Format markdown
.\scripts\validate-render-matrix.ps1 -ValuesFile config\platform-values.dev.env
```
