FROM ubuntu:22.04

ARG RUNNER_VERSION="2.321.0"
ARG DEBIAN_FRONTEND=noninteractive

# Метаданные
LABEL maintainer="mail@alexovc.ru"
LABEL org.opencontainers.image.title="GitHub Actions Self-Hosted Runner"
LABEL org.opencontainers.image.description="Docker image for GitHub Actions self-hosted runner"
LABEL org.opencontainers.image.version="${RUNNER_VERSION}"

# Установка зависимостей
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    jq \
    tar \
    unzip \
    zip \
    apt-transport-https \
    ca-certificates \
    sudo \
    gnupg \
    software-properties-common \
    build-essential \
    zlib1g-dev \
    gettext \
    libcurl4-openssl-dev \
    inetutils-ping \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Создание пользователя runner с правами sudo
RUN useradd -m -s /bin/bash runner && \
    usermod -aG sudo runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Установка Docker CLI (для docker-in-docker workflows)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Создание рабочей директории для runner
RUN mkdir -p /home/runner/actions-runner && \
    chown -R runner:runner /home/runner

WORKDIR /home/runner/actions-runner

# Скачивание и распаковка GitHub Actions Runner
RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    chown -R runner:runner /home/runner/actions-runner

# Установка зависимостей runner
RUN ./bin/installdependencies.sh

# Копирование entrypoint скрипта
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

# Переключение на пользователя runner
USER runner

ENTRYPOINT ["/home/runner/entrypoint.sh"]
