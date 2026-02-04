# Архитектура GitHub Actions Self-Hosted Runner

## Обзор компонентов

```
┌─────────────────────────────────────────────────────────────┐
│                        GitHub.com                            │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Repository / Organization                          │     │
│  │  - Workflows (.github/workflows/*.yml)              │     │
│  │  - Runner Registration (Settings → Actions)         │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ HTTPS (443)
                      │ - Registration
                      │ - Job polling
                      │ - Logs streaming
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                    Docker Host                               │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         GitHub Runner Container                       │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  entrypoint.sh                                │   │  │
│  │  │  - Читает TOKEN из env                        │   │  │
│  │  │  - Регистрирует runner (config.sh)           │   │  │
│  │  │  - Запускает runner (run.sh)                 │   │  │
│  │  │  - Обрабатывает сигналы (cleanup)            │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  GitHub Actions Runner                        │   │  │
│  │  │  - Polling для новых jobs                     │   │  │
│  │  │  - Выполнение workflow steps                  │   │  │
│  │  │  - Отправка логов                             │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  │  User: runner (non-root)                             │  │
│  │  Base: Ubuntu 22.04                                  │  │
│  └────────────┬───────────────────────────────────────┘  │
│               │                                            │
│               │ Docker Socket Mount                        │
│               │ /var/run/docker.sock                       │
│               │                                            │
│  ┌────────────▼───────────────────────────────────────┐  │
│  │         Docker Daemon                               │  │
│  │  - Выполнение docker commands из workflows         │  │
│  │  - Build, run, push containers                      │  │
│  └────────────────────────────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Жизненный цикл Runner'а

### 1. Инициализация (Startup)

```
Container Start
    ↓
entrypoint.sh
    ↓
Проверка переменных окружения
    ├─ TOKEN (обязательно)
    ├─ GITHUB_URL (обязательно)
    └─ Опциональные (RUNNER_NAME, LABELS, etc.)
    ↓
config.sh --unattended
    ├─ Регистрация в GitHub
    ├─ Получение runner ID
    └─ Сохранение конфигурации (.runner, .credentials)
    ↓
run.sh
    ├─ Подключение к GitHub
    ├─ Long-polling для jobs
    └─ Execution loop
```

### 2. Выполнение Job

```
GitHub отправляет job
    ↓
Runner получает job
    ↓
Создание рабочей директории (_work)
    ↓
Клонирование репозитория
    ↓
Выполнение steps
    ├─ Setup actions (checkout, setup-node, etc.)
    ├─ Run commands
    └─ Docker commands (через mounted socket)
    ↓
Отправка логов в GitHub
    ↓
Очистка рабочей директории
    ↓
[Ephemeral] Удаление runner
[Non-ephemeral] Ожидание следующего job
```

### 3. Graceful Shutdown

```
SIGTERM/SIGINT
    ↓
trap в entrypoint.sh
    ↓
cleanup()
    ├─ Завершение текущего job (если есть)
    ├─ config.sh remove --token
    └─ Удаление runner из GitHub
    ↓
Container stop
```

## Взаимодействие с GitHub

### API Endpoints

**Registration:**
```
POST https://api.github.com/repos/:owner/:repo/actions/runners/registration-token
POST https://api.github.com/orgs/:org/actions/runners/registration-token
```

**Runner Operations:**
```
GET  https://api.github.com/repos/:owner/:repo/actions/runners
GET  https://api.github.com/repos/:owner/:repo/actions/runners/:runner_id
DELETE https://api.github.com/repos/:owner/:repo/actions/runners/:runner_id
```

### Аутентификация

1. **Registration Token** (кратковременный)
   - Действителен: 1 час
   - Используется: для регистрации нового runner'а
   - Получение: через UI или API с PAT

2. **Runner Credentials** (долговременный)
   - Создается при регистрации
   - Хранится: `.credentials` и `.runner`
   - Используется: для polling и выполнения jobs

## Безопасность

### Изоляция

```
┌─────────────────────────────────────────┐
│  Host System                             │
│  ┌─────────────────────────────────┐   │
│  │  Container (runner user)         │   │
│  │  - No root access by default     │   │
│  │  - Namespaced PID, NET           │   │
│  │                                   │   │
│  │  ┌─────────────────────────┐    │   │
│  │  │  Docker Socket           │    │   │
│  │  │  ⚠️  Full Docker access  │◄───┼───┼── Security boundary
│  │  └─────────────────────────┘    │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Риски и Митигация

| Риск | Описание | Митигация |
|------|----------|-----------|
| Docker Socket Access | Полный доступ к Docker daemon = root на хосте | - Используйте только для private repos<br>- Изолируйте хост<br>- Используйте Docker rootless mode |
| Malicious Code | Code injection через fork PR | - Только private repos<br>- Review approval для workflows<br>- Ограничение permissions |
| Token Exposure | Утечка TOKEN или credentials | - Short-lived tokens<br>- Ephemeral runners<br>- Secrets management |
| Resource Exhaustion | Job может исчерпать ресурсы | - Docker resource limits<br>- Timeout для jobs<br>- Monitoring |

## Режимы работы

### Ephemeral Mode (Рекомендуется)

```
Контейнер запускается
    ↓
Регистрация runner (--ephemeral)
    ↓
Ожидание job
    ↓
Выполнение ОДНОГО job
    ↓
Автоматическое удаление runner
    ↓
Контейнер завершается
```

**Преимущества:**
- Чистое окружение для каждого job
- Меньше риск накопления артефактов
- Проще масштабирование
- Лучше безопасность

### Persistent Mode

```
Контейнер запускается
    ↓
Регистрация runner
    ↓
Бесконечный цикл:
    ├─ Ожидание job
    ├─ Выполнение job
    ├─ Очистка
    └─ Повтор
```

**Использование:**
- Для тяжелых сетапов (большие dependencies)
- Для быстрого отклика (нет cold start)
- Для кастомного окружения

## Масштабирование

### Вертикальное (Single Host)

```bash
docker-compose up -d --scale github-runner=5
```

```
Host
├─ github-runner-1
├─ github-runner-2
├─ github-runner-3
├─ github-runner-4
└─ github-runner-5
```

### Горизонтальное (Multiple Hosts)

```
Load Balancer / Orchestrator
├─ Host 1
│  ├─ runner-1
│  └─ runner-2
├─ Host 2
│  ├─ runner-3
│  └─ runner-4
└─ Host 3
   ├─ runner-5
   └─ runner-6
```

**Orchestration Options:**
- Docker Swarm
- Kubernetes (actions-runner-controller)
- Nomad
- Custom scripts

## Мониторинг

### Метрики для отслеживания

```yaml
Runner Level:
  - Status: Idle / Busy / Offline
  - Job count
  - Job duration
  - Success/failure rate

Container Level:
  - CPU usage
  - Memory usage
  - Disk I/O
  - Network traffic

Host Level:
  - Available runners
  - Queue length
  - Resource utilization
```

### Логирование

```
GitHub:
  - Workflow logs (visible in UI)
  - Runner events (registration, removal)

Container:
  - entrypoint.sh logs
  - runner logs (via stdout)

Host:
  - Docker daemon logs
  - System logs
```

## Переменные окружения

### Обязательные

- `TOKEN` - Registration token от GitHub
- `GITHUB_URL` - URL репозитория или организации

### Опциональные

- `RUNNER_NAME` - Имя runner'а
- `RUNNER_WORKDIR` - Рабочая директория
- `RUNNER_GROUP` - Группа runner'ов
- `RUNNER_LABELS` - Метки (labels)
- `EPHEMERAL` - Ephemeral режим
- `DISABLE_AUTO_UPDATE` - Отключение автообновлений
- `REPLACE_EXISTING` - Замена существующего runner'а

## Директории и файлы

```
/home/runner/actions-runner/
├── bin/                      # Runner binaries
├── config.sh                 # Configuration script
├── run.sh                    # Runner startup script
├── .runner                   # Runner metadata (JSON)
├── .credentials              # GitHub credentials
├── .credentials_rsaparams    # RSA parameters
├── _work/                    # Working directory
│   ├── _actions/            # Cached actions
│   ├── _temp/               # Temporary files
│   └── <repo>/              # Cloned repository
└── _diag/                   # Diagnostic logs
```

## Обновление Runner

### Автоматическое (по умолчанию)

Runner автоматически обновляется между jobs:
1. Runner завершает job
2. Проверяет наличие обновлений
3. Скачивает и устанавливает новую версию
4. Перезапускается

### Ручное

```bash
# Обновление Docker образа
docker build --build-arg RUNNER_VERSION=2.321.0 -t github-runner .
docker-compose down
docker-compose up -d
```

## Интеграция с CI/CD

### Webhook-based Scaling

```
GitHub Webhook
    ↓
Webhook Handler
    ↓
Check queue length
    ↓
Scale up/down runners
```

### Auto-scaling Script

```bash
#!/bin/bash
QUEUE_LENGTH=$(gh api repos/:owner/:repo/actions/runs \
  --jq '.workflow_runs[] | select(.status=="queued") | .id' | wc -l)

if [ $QUEUE_LENGTH -gt 5 ]; then
  docker-compose up -d --scale github-runner=$((QUEUE_LENGTH + 2))
fi
```

## Дальнейшее развитие

### Возможные улучшения

1. **Auto-token refresh** - Автоматическое обновление токена через API
2. **Health checks** - Проверка здоровья runner'а
3. **Metrics export** - Экспорт метрик в Prometheus
4. **Custom images** - Специализированные образы для разных задач
5. **Runner pools** - Пулы runner'ов с разными возможностями
6. **Cost tracking** - Отслеживание стоимости запусков
