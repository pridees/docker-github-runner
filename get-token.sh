#!/bin/bash

# Скрипт для получения registration token через GitHub API
# Использование:
#   ./get-token.sh repo OWNER REPO
#   ./get-token.sh org ORG_NAME

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

usage() {
    echo "Usage:"
    echo "  $0 repo OWNER REPO    - Get token for repository"
    echo "  $0 org ORG_NAME       - Get token for organization"
    echo ""
    echo "Environment variables:"
    echo "  GITHUB_TOKEN or GITHUB_PAT - Personal Access Token"
    echo ""
    echo "Required scopes:"
    echo "  - For repos: 'repo'"
    echo "  - For orgs: 'admin:org'"
    echo ""
    echo "Example:"
    echo "  export GITHUB_TOKEN=ghp_your_token_here"
    echo "  $0 repo myuser myrepo"
    echo "  $0 org myorg"
    exit 1
}

# Проверка аргументов
if [ $# -lt 2 ]; then
    usage
fi

TYPE=$1
shift

# Получение GitHub PAT из переменных окружения
GITHUB_PAT="${GITHUB_TOKEN:-${GITHUB_PAT}}"

if [ -z "$GITHUB_PAT" ]; then
    error "GITHUB_TOKEN or GITHUB_PAT environment variable is required"
fi

# Формирование API URL в зависимости от типа
case "$TYPE" in
    repo|repository)
        if [ $# -ne 2 ]; then
            error "For repository, provide: OWNER REPO"
        fi
        OWNER=$1
        REPO=$2
        API_URL="https://api.github.com/repos/${OWNER}/${REPO}/actions/runners/registration-token"
        GITHUB_URL="https://github.com/${OWNER}/${REPO}"
        info "Getting registration token for repository: ${OWNER}/${REPO}"
        ;;
    org|organization)
        if [ $# -ne 1 ]; then
            error "For organization, provide: ORG_NAME"
        fi
        ORG=$1
        API_URL="https://api.github.com/orgs/${ORG}/actions/runners/registration-token"
        GITHUB_URL="https://github.com/${ORG}"
        info "Getting registration token for organization: ${ORG}"
        ;;
    *)
        error "Invalid type: $TYPE. Use 'repo' or 'org'"
        ;;
esac

# Запрос токена через API
info "Requesting token from GitHub API..."

RESPONSE=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${API_URL}")

# Проверка ответа
if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message')
    error "GitHub API error: $MESSAGE"
fi

# Извлечение токена
TOKEN=$(echo "$RESPONSE" | jq -r '.token')
EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    error "Failed to get token. Response: $RESPONSE"
fi

# Вывод результата
info "✅ Token received successfully!"
echo ""
echo "Token: $TOKEN"
echo "Expires at: $EXPIRES_AT"
echo "GitHub URL: $GITHUB_URL"
echo ""

warn "⚠️  Token is valid for 1 hour only!"
echo ""

# Предложение обновить .env файл
if [ -f .env ]; then
    read -p "Update .env file with this token? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Создание резервной копии
        cp .env .env.backup

        # Обновление токена
        if grep -q "^TOKEN=" .env; then
            sed -i.tmp "s|^TOKEN=.*|TOKEN=$TOKEN|" .env
            rm -f .env.tmp
        else
            echo "TOKEN=$TOKEN" >> .env
        fi

        # Обновление URL если нужно
        if grep -q "^GITHUB_URL=" .env; then
            sed -i.tmp "s|^GITHUB_URL=.*|GITHUB_URL=$GITHUB_URL|" .env
            rm -f .env.tmp
        else
            echo "GITHUB_URL=$GITHUB_URL" >> .env
        fi

        info "✅ .env file updated (backup saved as .env.backup)"
    fi
else
    warn ".env file not found. You can create it from .env.example"
fi

echo ""
info "To start the runner, run:"
echo "  docker-compose up -d"
echo "or:"
echo "  make run"
