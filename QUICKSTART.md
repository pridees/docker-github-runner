# Quick Start Guide

Get your GitHub Actions Runner running in Docker in 5 minutes.

## Step 1: Clone the repository

```bash
git clone <your-repo-url>
cd docker-github-runner
```

## Step 2: Create .env file

```bash
cp .env.example .env
```

## Step 3: Get Registration Token

### Option A: Via GitHub UI (Simple)

1. Open GitHub:
   - **For repository**: `https://github.com/OWNER/REPO/settings/actions/runners/new`
   - **For organization**: `https://github.com/organizations/ORG/settings/actions/runners/new`

2. Select Linux and copy the token from the command:
   ```bash
   ./config.sh --url https://github.com/... --token YOUR_TOKEN
   ```

3. Paste the token in `.env`:
   ```bash
   TOKEN=YOUR_TOKEN_HERE
   GITHUB_URL=https://github.com/your-org/your-repo
   ```

### Option B: Via API (Automatic)

1. Create Personal Access Token:
   - Open: https://github.com/settings/tokens/new
   - Scopes: `repo` (for repository) or `admin:org` (for organization)
   - Copy the token

2. Use the script:
   ```bash
   export GITHUB_TOKEN=ghp_your_personal_access_token

   # For repository
   ./get-token.sh repo OWNER REPO

   # For organization
   ./get-token.sh org ORG_NAME
   ```

   The script will automatically update the `.env` file.

## Step 4: Start the Runner

### Option A: Docker Compose (Recommended)

```bash
docker-compose up -d
```

### Option B: Docker Run

```bash
docker build -t github-runner .

docker run -d \
  --name github-runner \
  --env-file .env \
  -v /var/run/docker.sock:/var/run/docker.sock \
  github-runner
```

### Option C: Makefile

```bash
make build
make run
```

## Step 5: Check Status

```bash
# Logs
docker-compose logs -f
# or
docker logs -f github-runner

# Status in GitHub
# Open: Settings → Actions → Runners
# You should see your runner with status "Idle"
```

## Step 6: Use in Workflow

Create `.github/workflows/test.yml`:

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

Commit and push - the job will run on your runner!

## Troubleshooting

### Token expired

Registration token is valid for only 1 hour. Get a new one:

```bash
./get-token.sh repo OWNER REPO  # updates .env
docker-compose restart          # restarts runner
```

### Runner doesn't appear in GitHub

1. Check logs: `docker-compose logs`
2. Verify TOKEN and GITHUB_URL in `.env`
3. Ensure you have permissions to add runners

### Permission denied (Docker socket)

```bash
# Linux
sudo usermod -aG docker $USER
# Re-login after this

# macOS
# Ensure Docker Desktop is running
```

## Useful Commands

```bash
# View logs
make logs
# or
docker-compose logs -f

# Stop
make stop
# or
docker-compose down

# Restart
make restart
# or
docker-compose restart

# Check configuration
make test

# Cleanup
make clean
```

## What's Next?

- Read full documentation in [README.md](README.md)
- Configure custom labels in `.env`
- Run multiple runners: `docker-compose up -d --scale github-runner=3`
- Set up automatic token refresh via GitHub API

## Important Notes

- ⚠️ Registration token is valid for only 1 hour
- ⚠️ Do not use self-hosted runners for public repositories
- ✅ Recommended to use ephemeral mode (`EPHEMERAL=true`)
- ✅ Runner is automatically removed from GitHub when container stops

Done! Your self-hosted runner is up and running. 🚀
