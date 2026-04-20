# Jenkins

[English](README.md) | 한국어

이 디렉터리에는 저장소 자체를 위한 범용 Jenkins 자동화가 들어 있습니다.

## 주요 잡

- `repository-validation.Jenkinsfile`: 저장소 구조와 렌더링 결과를 검증
- `bundle-delivery.Jenkinsfile`: 번들을 렌더링, 검증, 아카이브
- `bundle-promotion.Jenkinsfile`: 전달된 번들을 다시 검증하고 선택적으로 배포
- `job-seed.Jenkinsfile`: 공통 잡 계획을 바탕으로 Jenkins 폴더와 파이프라인 잡을 생성

## 중요 참고 사항

- 기본 샘플 애플리케이션은 공개 이미지를 사용하므로 서비스별 이미지 빌드 잡이 필수가 아닙니다.
- `show-jenkins-job-plan.ps1` 와 `export-jenkins-job-dsl.ps1` 는 여전히 번들 단위의 검증, 생성, 승격 잡을 만들어 줍니다.
- 서비스 단위 잡은 해당 서비스에 실제 Jenkinsfile 이 있고, 카탈로그에서도 활성화되어 있을 때만 나타납니다.
- 각 Jenkinsfile 앞단에는 agent readiness preflight 가 있어 `kubectl`, `helm` 같은 도구가 없을 때 더 빨리, 더 명확하게 실패합니다.
- `job-seed.Jenkinsfile` 의 프리셋 목록은 기본 공란이며, 이는 `config/environments` 에 있는 프리셋을 모두 사용하겠다는 의미입니다.
- `job-seed.Jenkinsfile` 의 기본 저장소 URL 은 `https://github.com/k4nul/k8s-platform-template.git` 입니다. 템플릿을 포크하거나 미러링해서 쓴다면 `SEED_REPO_URL` 을 바꿔야 합니다.

## 자주 쓰는 명령

```powershell
.\scripts\show-jenkins-job-plan.ps1 -EnvironmentPreset dev -Format markdown
.\scripts\export-jenkins-job-dsl.ps1 -EnvironmentPreset dev -OutputPath .\out\jenkins\seed-job-dsl.groovy
```

환경 프리셋 대신 커스텀 selection 을 쓰고 싶다면:

```powershell
.\scripts\export-jenkins-job-dsl.ps1 `
  -SelectionName sandbox `
  -Profile web-platform `
  -Applications nginx-web,httpbin,whoami `
  -DataServices redis `
  -RepoUrl https://github.com/k4nul/k8s-platform-template.git `
  -OutputPath .\out\jenkins\seed-job-dsl.groovy
```
