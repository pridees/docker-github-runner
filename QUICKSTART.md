# Quick Start Guide

Быстрый старт для запуска GitHub Actions Runner в Docker за 5 минут.

## Шаг 1: Клонируйте репозиторий

```bash
git clone <your-repo-url>
cd docker-github-runner
```

## Шаг 2: Создайте .env файл

```bash
cp .env.example .env
```

## Шаг 3: Получите Registration Token

### Вариант A: Через GitHub UI (Простой)

1. Откройте GitHub:
   - **Для репозитория**: `https://github.com/OWNER/REPO/settings/actions/runners/new`
   - **Для организации**: `https://github.com/organizations/ORG/settings/actions/runners/new`

2. Выберите Linux и скопируйте токен из команды:
   ```bash
   ./config.sh --url https://github.com/... --token YOUR_TOKEN
   ```

3. Вставьте токен в `.env`:
   ```bash
   TOKEN=YOUR_TOKEN_HERE
   GITHUB_URL=https://github.com/your-org/your-repo
   ```

### Вариант B: Через API (Автоматический)

1. Создайте Personal Access Token:
   - Откройте: https://github.com/settings/tokens/new
   - Scopes: `repo` (для репозитория) или `admin:org` (для организации)
   - Скопируйте токен

2. Используйте скрипт:
   ```bash
   export GITHUB_TOKEN=ghp_your_personal_access_token

   # Для репозитория
   ./get-token.sh repo OWNER REPO

   # Для организации
   ./get-token.sh org ORG_NAME
   ```

   Скрипт автоматически обновит `.env` файл.

## Шаг 4: Запустите Runner

### Вариант A: Docker Compose (Рекомендуется)

```bash
docker-compose up -d
```

### Вариант B: Docker Run

```bash
docker build -t github-runner .

docker run -d \
  --name github-runner \
  --env-file .env \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Вариант C: Makefile

```bash
make build
make run
```

## Шаг 5: Проверьте статус

```bash
# Логи
docker-compose logs -f
# или
docker logs -f github-runner

# Статус в GitHub
# Откройте: Settings → Actions → Runners
# Вы должны увидеть ваш runner со статусом "Idle"
```

## Шаг 6: Используйте в Workflow

Создайте `.github/workflows/test.yml`:

```yaml
name: Test Self-Hosted Runner

on: [push]

jobs:
  test:
    runs-on: self-hosted

    steps:
      - uses: actions/checkout@v4

      - name: Hello from self-hosted runner
        run: |
          echo "Running on self-hosted runner!"
          hostname
          docker --version
```

Сделайте commit и push - job запустится на вашем runner!

## Troubleshooting

### Token expired (Токен истек)

Registration token действителен только 1 час. Получите новый:

```bash
./get-token.sh repo OWNER REPO  # обновит .env
docker-compose restart          # перезапустит runner
```

### Runner не появляется в GitHub

1. Проверьте логи: `docker-compose logs`
2. Проверьте TOKEN и GITHUB_URL в `.env`
3. Убедитесь, что у вас есть права на добавление runner'ов

### Permission denied (Docker socket)

```bash
# Linux
sudo usermod -aG docker $USER
# Перелогиньтесь после этого

# macOS
# Убедитесь, что Docker Desktop запущен
```

## Полезные команды

```bash
# Просмотр логов
make logs
# или
docker-compose logs -f

# Остановка
make stop
# или
docker-compose down

# Перезапуск
make restart
# или
docker-compose restart

# Проверка конфигурации
make test

# Очистка
make clean
```

## Что дальше?

- Прочитайте полную документацию в [README.md](README.md)
- Настройте кастомные labels в `.env`
- Запустите несколько runner'ов: `docker-compose up -d --scale github-runner=3`
- Настройте автоматическое обновление токена через GitHub API

## Важно

- ⚠️ Registration token действителен только 1 час
- ⚠️ Не используйте self-hosted runners для публичных репозиториев
- ✅ Рекомендуется использовать ephemeral режим (`EPHEMERAL=true`)
- ✅ Runner автоматически удаляется из GitHub при остановке контейнера

Готово! Ваш self-hosted runner запущен и готов к работе. 🚀
