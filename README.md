# GitHub Actions Self-Hosted Runner in Docker

Docker container for running GitHub Actions self-hosted runner. Supports automatic registration and graceful shutdown.

## Features

- ✅ Automatic runner registration on container start
- ✅ Graceful shutdown with proper runner removal from GitHub
- ✅ Ephemeral mode support (single-use runners)
- ✅ Docker-in-Docker support for Docker workflows
- ✅ Security: runs as non-privileged user
- ✅ Customizable labels and runner groups
- ✅ Latest Ubuntu 22.04 and GitHub Actions Runner

## Requirements

- Docker 20.10+
- Docker Compose 2.0+ (optional)
- Registration token from GitHub (valid for 1 hour)

## Getting Registration Token

### For Repository:

1. Go to Settings → Actions → Runners
2. Click "New self-hosted runner"
3. Copy the token from the command `./config.sh --url ... --token YOUR_TOKEN`

### For Organization:

1. Go to Organization Settings → Actions → Runners
2. Click "New runner"
3. Copy the token

### Via GitHub API:

```bash
# For repository
curl -X POST \
  -H "Authorization: token YOUR_PAT" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/registration-token

# For organization
curl -X POST \
  -H "Authorization: token YOUR_PAT" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/orgs/ORG/actions/runners/registration-token
```

**Important:** Personal Access Token (PAT) must have `repo` scope (for repository) or `admin:org` (for organization).

## Quick Start

### Option 1: Docker Run

```bash
docker build -t github-runner .

docker run -d \
  --name github-runner \
  -e TOKEN="YOUR_REGISTRATION_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Option 2: Docker Compose

1. Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

2. Edit `.env` and set your values:
```bash
TOKEN=your_token_here
GITHUB_URL=https://github.com/your-org/your-repo
```

3. Start the container:
```bash
docker-compose up -d
```

4. Check logs:
```bash
docker-compose logs -f
```

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `TOKEN` | Registration token from GitHub (valid for 1 hour) | `ABCDEFGHIJKLMNOPQRSTUVWXYZ` |
| `GITHUB_URL` | Repository or organization URL | `https://github.com/owner/repo` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `RUNNER_NAME` | Runner name | container hostname |
| `RUNNER_WORKDIR` | Working directory | `_work` |
| `RUNNER_GROUP` | Runner group | `Default` |
| `RUNNER_LABELS` | Comma-separated labels | `docker,self-hosted` |
| `EPHEMERAL` | Ephemeral mode (single-use) | `true` |
| `DISABLE_AUTO_UPDATE` | Disable auto-updates | `false` |
| `REPLACE_EXISTING` | Replace existing runner | `false` |

## Usage Examples

### Ephemeral Runner (recommended for Docker)

Ephemeral runner processes only one job and then removes itself:

```bash
docker run -d \
  -e TOKEN="YOUR_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -e EPHEMERAL=true \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Persistent Runner

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

### Custom Labels

```bash
docker run -d \
  -e TOKEN="YOUR_TOKEN" \
  -e GITHUB_URL="https://github.com/owner/repo" \
  -e RUNNER_LABELS="docker,self-hosted,gpu,cuda-11.8" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Running Multiple Runners

```bash
docker-compose up -d --scale github-runner=3
```

## Using in Workflows

After starting the runner, use it in your GitHub Actions workflows:

```yaml
name: CI

on: [push]

jobs:
  build:
    runs-on: [self-hosted, docker]  # Use your labels

    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: |
          echo "Running on self-hosted runner!"
          docker --version
```

## Docker-in-Docker

The container mounts the host's Docker socket, allowing Docker commands in workflows:

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

## Security

⚠️ **Important security considerations:**

1. **Do not use self-hosted runners for public repositories** - malicious code from forks can execute on your infrastructure
2. **Docker socket** - mounting `/var/run/docker.sock` gives full access to Docker host
3. **Isolation** - use separate runners for critical projects
4. **Ephemeral mode** - recommended to reduce attack surface
5. **Network isolation** - consider using separate networks for runners

## Monitoring and Logs

### Viewing Logs

```bash
# Docker
docker logs -f github-runner

# Docker Compose
docker-compose logs -f
```

### Checking Status

Check runner status in GitHub:
- Repository: Settings → Actions → Runners
- Organization: Organization Settings → Actions → Runners

## Updating Runner

### Automatic Updates

By default, the runner updates automatically. To disable:

```bash
-e DISABLE_AUTO_UPDATE=true
```

### Updating Docker Image

```bash
# Rebuild image with new version
docker build --build-arg RUNNER_VERSION=2.321.0 -t github-runner .

# Or update version in Dockerfile and rebuild
docker-compose build --no-cache
docker-compose up -d
```

## Troubleshooting

### Runner not registering

1. Check that the token is valid (expires after 1 hour)
2. Verify GITHUB_URL is correct
3. Ensure you have permissions to add runners

### Runner not removed on stop

```bash
# Manually remove runner via GitHub UI or API
curl -X DELETE \
  -H "Authorization: token YOUR_PAT" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/RUNNER_ID
```

### Docker permission denied

Ensure Docker socket is accessible:
```bash
ls -la /var/run/docker.sock
```

## Links

- [GitHub Actions Self-Hosted Runners Documentation](https://docs.github.com/actions/hosting-your-own-runners)
- [Self-Hosted Runner API](https://docs.github.com/rest/actions/self-hosted-runners)
- [GitHub Runner Releases](https://github.com/actions/runner/releases)

## License

MIT
