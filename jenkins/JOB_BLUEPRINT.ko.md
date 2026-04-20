# Jenkins 잡 청사진

[English](JOB_BLUEPRINT.md) | 한국어

권장하는 범용 폴더 레이아웃은 다음과 같습니다.

```text
platform/
  dev/
    repository-validation
    bundle-delivery
    bundle-promotion
  staging/
    repository-validation
    bundle-delivery
    bundle-promotion
  prod/
    repository-validation
    bundle-delivery
    bundle-promotion
```

## 이 레이아웃을 권장하는 이유

- 애플리케이션 예제가 바뀌어도 저장소 단위 잡 구조는 안정적으로 유지됩니다.
- delivery 와 promotion 단계가 명확하게 분리됩니다.
- 환경 프리셋이 Jenkins 폴더 구조에 자연스럽게 대응됩니다.
- 위 폴더 이름은 예시일 뿐입니다. `sandbox`, `qa`, `production` 같은 이름을 써도 같은 구조를 그대로 적용할 수 있습니다.

## 시드 기본값

- `job-seed.Jenkinsfile` 에서 `SEED_ENVIRONMENT_PRESETS` 를 비워두면 현재 `config/environments` 에 있는 모든 프리셋에 대해 잡이 생성됩니다.
- `SEED_REPO_URL` 의 기본값은 `https://github.com/k4nul/k8s-platform-template.git` 입니다.
- 이 템플릿을 포크하거나 미러링해서 쓴다면, 생성된 DSL 을 적용하기 전에 `SEED_REPO_URL` 을 자신의 저장소 주소로 바꿔야 SCM 기반 잡이 올바른 저장소를 바라봅니다.

## 선택형 서비스 잡

현재 공개 이미지 기반 샘플 서비스는 전용 Jenkins 빌드 잡이 필요하지 않습니다.

나중에 자체 서비스와 Jenkinsfile 을 추가하면, 계획과 seed DSL 을 다시 생성해서 해당 서비스 잡이 자동으로 나타나게 할 수 있습니다.
