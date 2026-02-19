#!/bin/bash

set -e

# Функция для логирования
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Функция для обработки ошибок
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Функция для cleanup при остановке контейнера
cleanup() {
    log "Removing runner from GitHub..."
    if [ -f ".runner" ]; then
        ./config.sh remove --token "${TOKEN}"
    fi
    log "Runner removed successfully"
}

# Установка trap для graceful shutdown
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Настройка доступа к Docker socket
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    if [ "${DOCKER_GID}" = "0" ]; then
        sudo usermod -aG root runner
    elif getent group docker > /dev/null 2>&1; then
        sudo groupmod -g "${DOCKER_GID}" docker
        sudo usermod -aG docker runner
    else
        sudo groupadd -g "${DOCKER_GID}" docker
        sudo usermod -aG docker runner
    fi
    log "Docker socket detected (GID: ${DOCKER_GID}), access configured"
fi

# Проверка обязательных переменных окружения
log "Checking required environment variables..."

if [ -z "${TOKEN}" ]; then
    error_exit "TOKEN environment variable is required"
fi

if [ -z "${GITHUB_URL}" ]; then
    error_exit "GITHUB_URL environment variable is required (e.g., https://github.com/owner/repo or https://github.com/org)"
fi

# Опциональные переменные с значениями по умолчанию
RUNNER_NAME="${RUNNER_NAME:-${HOSTNAME}}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
RUNNER_LABELS="${RUNNER_LABELS:-docker,self-hosted}"
EPHEMERAL="${EPHEMERAL:-true}"
DISABLE_AUTO_UPDATE="${DISABLE_AUTO_UPDATE:-false}"
RUNNER_ALLOW_RUNASROOT="${RUNNER_ALLOW_RUNASROOT:-false}"

log "Configuration:"
log "  GITHUB_URL: ${GITHUB_URL}"
log "  RUNNER_NAME: ${RUNNER_NAME}"
log "  RUNNER_GROUP: ${RUNNER_GROUP}"
log "  RUNNER_LABELS: ${RUNNER_LABELS}"
log "  RUNNER_WORKDIR: ${RUNNER_WORKDIR}"
log "  EPHEMERAL: ${EPHEMERAL}"
log "  DISABLE_AUTO_UPDATE: ${DISABLE_AUTO_UPDATE}"

# Построение команды конфигурации
CONFIG_OPTS=(
    --unattended
    --url "${GITHUB_URL}"
    --token "${TOKEN}"
    --name "${RUNNER_NAME}"
    --work "${RUNNER_WORKDIR}"
    --labels "${RUNNER_LABELS}"
    --runnergroup "${RUNNER_GROUP}"
)

# Добавление опциональных параметров
if [ "${EPHEMERAL}" = "true" ]; then
    log "Configuring as ephemeral runner (will handle only one job)"
    CONFIG_OPTS+=(--ephemeral)
fi

if [ "${DISABLE_AUTO_UPDATE}" = "true" ]; then
    log "Auto-update disabled"
    CONFIG_OPTS+=(--disableupdate)
fi

# Если указано, заменить существующий runner с таким же именем
if [ "${REPLACE_EXISTING}" = "true" ]; then
    log "Will replace existing runner with the same name"
    CONFIG_OPTS+=(--replace)
fi

# Конфигурация runner
log "Configuring GitHub Actions Runner..."
./config.sh "${CONFIG_OPTS[@]}" || error_exit "Failed to configure runner"

log "Runner configured successfully"
log "Starting runner..."

# Запуск runner
# Используем exec чтобы run.sh получил PID 1 и мог правильно обрабатывать сигналы
exec ./run.sh & wait $!
