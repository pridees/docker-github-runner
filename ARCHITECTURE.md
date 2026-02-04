# GitHub Actions Self-Hosted Runner Architecture

## Component Overview

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
│  │  │  - Reads TOKEN from env                       │   │  │
│  │  │  - Registers runner (config.sh)              │   │  │
│  │  │  - Starts runner (run.sh)                    │   │  │
│  │  │  - Handles signals (cleanup)                 │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  GitHub Actions Runner                        │   │  │
│  │  │  - Polling for new jobs                       │   │  │
│  │  │  - Executing workflow steps                   │   │  │
│  │  │  - Sending logs                               │   │  │
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
│  │  - Executing docker commands from workflows        │  │
│  │  - Build, run, push containers                      │  │
│  └────────────────────────────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Runner Lifecycle

### 1. Initialization (Startup)

```
Container Start
    ↓
entrypoint.sh
    ↓
Check environment variables
    ├─ TOKEN (required)
    ├─ GITHUB_URL (required)
    └─ Optional (RUNNER_NAME, LABELS, etc.)
    ↓
config.sh --unattended
    ├─ Register with GitHub
    ├─ Get runner ID
    └─ Save configuration (.runner, .credentials)
    ↓
run.sh
    ├─ Connect to GitHub
    ├─ Long-polling for jobs
    └─ Execution loop
```

### 2. Job Execution

```
GitHub sends job
    ↓
Runner receives job
    ↓
Create working directory (_work)
    ↓
Clone repository
    ↓
Execute steps
    ├─ Setup actions (checkout, setup-node, etc.)
    ├─ Run commands
    └─ Docker commands (via mounted socket)
    ↓
Send logs to GitHub
    ↓
Clean up working directory
    ↓
[Ephemeral] Remove runner
[Non-ephemeral] Wait for next job
```

### 3. Graceful Shutdown

```
SIGTERM/SIGINT
    ↓
trap in entrypoint.sh
    ↓
cleanup()
    ├─ Finish current job (if any)
    ├─ config.sh remove --token
    └─ Remove runner from GitHub
    ↓
Container stop
```

## GitHub Integration

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

### Authentication

1. **Registration Token** (short-lived)
   - Valid for: 1 hour
   - Used for: registering new runner
   - Obtained via: UI or API with PAT

2. **Runner Credentials** (long-lived)
   - Created during registration
   - Stored in: `.credentials` and `.runner`
   - Used for: polling and job execution

## Security

### Isolation

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

### Risks and Mitigation

| Risk | Description | Mitigation |
|------|-------------|------------|
| Docker Socket Access | Full Docker daemon access = root on host | - Use only for private repos<br>- Isolate host<br>- Use Docker rootless mode |
| Malicious Code | Code injection via fork PR | - Private repos only<br>- Review approval for workflows<br>- Limit permissions |
| Token Exposure | TOKEN or credentials leak | - Short-lived tokens<br>- Ephemeral runners<br>- Secrets management |
| Resource Exhaustion | Job can exhaust resources | - Docker resource limits<br>- Job timeouts<br>- Monitoring |

## Operating Modes

### Ephemeral Mode (Recommended)

```
Container starts
    ↓
Register runner (--ephemeral)
    ↓
Wait for job
    ↓
Execute ONE job
    ↓
Automatically remove runner
    ↓
Container exits
```

**Advantages:**
- Clean environment for each job
- Less risk of artifact accumulation
- Easier scaling
- Better security

### Persistent Mode

```
Container starts
    ↓
Register runner
    ↓
Infinite loop:
    ├─ Wait for job
    ├─ Execute job
    ├─ Cleanup
    └─ Repeat
```

**Use cases:**
- Heavy setups (large dependencies)
- Fast response (no cold start)
- Custom environment

## Scaling

### Vertical (Single Host)

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

### Horizontal (Multiple Hosts)

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

## Monitoring

### Metrics to Track

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

### Logging

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

## Environment Variables

### Required

- `TOKEN` - Registration token from GitHub
- `GITHUB_URL` - Repository or organization URL

### Optional

- `RUNNER_NAME` - Runner name
- `RUNNER_WORKDIR` - Working directory
- `RUNNER_GROUP` - Runner group
- `RUNNER_LABELS` - Labels
- `EPHEMERAL` - Ephemeral mode
- `DISABLE_AUTO_UPDATE` - Disable auto-updates
- `REPLACE_EXISTING` - Replace existing runner

## Directories and Files

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

## Runner Updates

### Automatic (default)

Runner automatically updates between jobs:
1. Runner finishes job
2. Checks for updates
3. Downloads and installs new version
4. Restarts

### Manual

```bash
# Update Docker image
docker build --build-arg RUNNER_VERSION=2.321.0 -t github-runner .
docker-compose down
docker-compose up -d
```

## CI/CD Integration

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

## Future Improvements

### Possible Enhancements

1. **Auto-token refresh** - Automatic token refresh via API
2. **Health checks** - Runner health monitoring
3. **Metrics export** - Export metrics to Prometheus
4. **Custom images** - Specialized images for different tasks
5. **Runner pools** - Pools of runners with different capabilities
6. **Cost tracking** - Track execution costs
