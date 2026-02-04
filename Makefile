.PHONY: help build run stop logs clean shell test

# Переменные
IMAGE_NAME ?= github-runner
CONTAINER_NAME ?= github-runner
RUNNER_VERSION ?= 2.321.0

help:
	@echo "GitHub Actions Runner - Makefile commands:"
	@echo ""
	@echo "  make build          - Собрать Docker образ"
	@echo "  make run            - Запустить контейнер (требуется .env)"
	@echo "  make stop           - Остановить контейнер"
	@echo "  make restart        - Перезапустить контейнер"
	@echo "  make logs           - Показать логи контейнера"
	@echo "  make shell          - Открыть shell в контейнере"
	@echo "  make clean          - Удалить контейнер и образ"
	@echo "  make test           - Проверить конфигурацию"
	@echo ""
	@echo "  make compose-up     - Запустить через docker-compose"
	@echo "  make compose-down   - Остановить docker-compose"
	@echo "  make compose-logs   - Показать логи docker-compose"
	@echo ""

build:
	@echo "Building Docker image..."
	docker build \
		--build-arg RUNNER_VERSION=$(RUNNER_VERSION) \
		-t $(IMAGE_NAME):latest \
		-t $(IMAGE_NAME):$(RUNNER_VERSION) \
		.

run:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found. Copy .env.example to .env and configure it."; \
		exit 1; \
	fi
	@echo "Starting GitHub Runner container..."
	docker run -d \
		--name $(CONTAINER_NAME) \
		--env-file .env \
		-v /var/run/docker.sock:/var/run/docker.sock \
		--restart unless-stopped \
		$(IMAGE_NAME):latest

stop:
	@echo "Stopping container..."
	docker stop $(CONTAINER_NAME) || true
	docker rm $(CONTAINER_NAME) || true

restart: stop run

logs:
	docker logs -f $(CONTAINER_NAME)

shell:
	docker exec -it $(CONTAINER_NAME) /bin/bash

clean: stop
	@echo "Removing image..."
	docker rmi $(IMAGE_NAME):latest $(IMAGE_NAME):$(RUNNER_VERSION) || true

test:
	@echo "Testing configuration..."
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found"; \
		exit 1; \
	fi
	@if ! grep -q "^TOKEN=" .env || [ -z "$$(grep '^TOKEN=' .env | cut -d'=' -f2)" ]; then \
		echo "❌ TOKEN not set in .env"; \
		exit 1; \
	fi
	@if ! grep -q "^GITHUB_URL=" .env || [ -z "$$(grep '^GITHUB_URL=' .env | cut -d'=' -f2)" ]; then \
		echo "❌ GITHUB_URL not set in .env"; \
		exit 1; \
	fi
	@echo "✅ Configuration looks good"

# Docker Compose команды
compose-up:
	docker-compose up -d

compose-down:
	docker-compose down

compose-logs:
	docker-compose logs -f

compose-build:
	docker-compose build --no-cache

compose-restart:
	docker-compose restart
