# GitHub Actions Self-Hosted Runner in Docker

Docker-контейнер для запуска GitHub Actions self-hosted runner. Поддерживает автоматическую регистрацию и graceful shutdown.

## Особенности

- ✅ Автоматическая регистрация runner'а при старте контейнера
- ✅ Graceful shutdown с корректным удалением runner'а из GitHub
- ✅ Поддержка ephemeral режима (одноразовые runner'ы)
- ✅ Docker-in-Docker поддержка для workflows с Docker
- ✅ Безопасность: работа от непривилегированного пользователя
- ✅ Настраиваемые labels и группы runner'ов
- ✅ Актуальная версия Ubuntu 22.04 и GitHub Actions Runner

## Требования

- Docker 20.10+
- Docker Compose 2.0+ (опционально)
- Registration token от GitHub (действителен 1 час)

## Получение Registration Token

### Для репозитория:

1. Перейдите в Settings → Actions → Runners
2. Нажмите "New self-hosted runner"
3. Скопируйте токен из команды `./config.sh --url ... --token YOUR_TOKEN`

### Для организации:

1. Перейдите в Organization Settings → Actions → Runners
2. Нажмите "New runner"
3. Скопируйте токен

### Через GitHub API:

```bash
# Для репозитория
curl -X POST \
  -H "Authorization: token YOUR_PAT" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/registration-token

# Для организации
curl -X POST \
  -H "Authorization: token YOUR_PAT" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/orgs/ORG/actions/runners/registration-token
```

**Важно:** Personal Access Token (PAT) должен иметь scope `repo` (для репозитория) или `admin:org` (для организации).

## Быстрый старт

### Вариант 1: Docker Run

```bash
docker build -t github-runner .

docker run -d \
  --name github-runner \
  -e TOKEN="YOUR_REGISTRATION_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Вариант 2: Docker Compose

1. Скопируйте `.env.example` в `.env`:
```bash
cp .env.example .env
```

2. Отредактируйте `.env` и укажите ваши значения:
```bash
TOKEN=your_token_here
GITHUB_URL=https://github.com/your-org/your-repo
```

3. Запустите контейнер:
```bash
docker-compose up -d
```

4. Проверьте логи:
```bash
docker-compose logs -f
```

## Переменные окружения

### Обязательные

| Переменная | Описание | Пример |
|-----------|----------|--------|
| `TOKEN` | Registration token от GitHub (действителен 1 час) | `ABCDEFGHIJKLMNOPQRSTUVWXYZ` |
| `GITHUB_URL` | URL репозитория или организации | `https://github.com/owner/repo` |

### Опциональные

| Переменная | Описание | По умолчанию |
|-----------|----------|--------------|
| `RUNNER_NAME` | Имя runner'а | hostname контейнера |
| `RUNNER_WORKDIR` | Рабочая директория | `_work` |
| `RUNNER_GROUP` | Группа runner'ов | `Default` |
| `RUNNER_LABELS` | Метки через запятую | `docker,self-hosted` |
| `EPHEMERAL` | Ephemeral режим (одноразовый) | `true` |
| `DISABLE_AUTO_UPDATE` | Отключить автообновления | `false` |
| `REPLACE_EXISTING` | Заменить существующий runner | `false` |

## Примеры использования

### Ephemeral Runner (рекомендуется для Docker)

Ephemeral runner обрабатывает только один job и затем удаляется:

```bash
docker run -d \
  -e TOKEN="YOUR_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -e EPHEMERAL=true \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Постоянный Runner

```bash
docker run -d \
  --restart unless-stopped \
  -e TOKEN="YOUR_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -e EPHEMERAL=false \
  -e RUNNER_NAME="my-persistent-runner" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Кастомные Labels

```bash
docker run -d \
  -e TOKEN="YOUR_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -e RUNNER_LABELS="docker,self-hosted,gpu,cuda-11.8" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Запуск нескольких Runner'ов

```bash
docker-compose up -d --scale github-runner=3
```

## Использование в Workflows

После запуска runner'а используйте его в своих GitHub Actions workflows:

```yaml
name: CI

on: [push]

jobs:
  build:
    runs-on: [self-hosted, docker]  # Используйте ваши labels

    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: |
          echo "Running on self-hosted runner!"
          docker --version
```

## Docker-in-Docker

Контейнер монтирует Docker socket хоста, что позволяет запускать Docker команды в workflows:

```yaml
jobs:
  docker-build:
    runs-on: [self-hosted, docker]

    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t myapp .

      - name: Run tests in container
        run: docker run myapp npm test
```

## Безопасность

⚠️ **Важные соображения безопасности:**

1. **Не используйте self-hosted runners для публичных репозиториев** - вредоносный код из fork'ов может выполниться на вашей инфраструктуре
2. **Docker socket** - монтирование `/var/run/docker.sock` дает полный доступ к Docker хосту
3. **Изоляция** - используйте отдельные runner'ы для критичных проектов
4. **Ephemeral режим** - рекомендуется для уменьшения поверхности атаки
5. **Сетевая изоляция** - рассмотрите использование отдельных сетей для runner'ов

## Мониторинг и логи

### Просмотр логов

```bash
# Docker
docker logs -f github-runner

# Docker Compose
docker-compose logs -f
```

### Проверка статуса

Проверьте статус runner'а в GitHub:
- Репозиторий: Settings → Actions → Runners
- Организация: Organization Settings → Actions → Runners

## Обновление Runner

### Автоматическое обновление

По умолчанию runner автоматически обновляется. Чтобы отключить:

```bash
-e DISABLE_AUTO_UPDATE=true
```

### Обновление Docker образа

```bash
# Пересоберите образ с новой версией
docker build --build-arg RUNNER_VERSION=2.321.0 -t github-runner .

# Или обновите версию в Dockerfile и пересоберите
docker-compose build --no-cache
docker-compose up -d
```

## Устранение неполадок

### Runner не регистрируется

1. Проверьте, что токен действителен (срок действия 1 час)
2. Проверьте правильность GITHUB_URL
3. Убедитесь, что у вас есть права на добавление runner'ов

### Runner не удаляется при остановке

```bash
# Вручную удалите runner через GitHub UI или API
curl -X DELETE \
  -H "Authorization: token YOUR_PAT" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/RUNNER_ID
```

### Docker permission denied

Убедитесь, что Docker socket доступен:
```bash
ls -la /var/run/docker.sock
```

## Ссылки

- [GitHub Actions Self-Hosted Runners Documentation](https://docs.github.com/actions/hosting-your-own-runners)
- [Self-Hosted Runner API](https://docs.github.com/rest/actions/self-hosted-runners)
- [GitHub Runner Releases](https://github.com/actions/runner/releases)

## Лицензия

MIT
