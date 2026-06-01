# Development Guide

Guide for building Harbor ARM64 images locally and contributing to the project.

## Prerequisites

- ARM64 machine or VM (Apple Silicon Mac, AWS Graviton, etc.)
- Docker 20.10+
- Go version required by the selected Harbor release (`harbor/src/go.mod`)
- Git
- Bash 4.0+
- 8GB+ RAM recommended
- 30GB+ free disk space

## Quick Start

### Clone Repository

```bash
git clone https://github.com/hoon-ch/harbor-arm.git
cd harbor-arm
```

### Build Locally

```bash
# Set version to build
VERSION=v2.15.1

# Run local build script
./scripts/build-local.sh $VERSION
```

This will:
1. Clone Harbor repository
2. Build base images
3. Build registry binary
4. Patch build files
5. Build all components
6. Tag images locally

### Test Built Images

```bash
# Run validation tests
./scripts/test/validate-images.sh $VERSION $(whoami)

# Run integration tests
./scripts/test/integration-test-simple.sh $VERSION $(whoami)

# Run benchmarks
./scripts/test/benchmark-simple.sh $VERSION $(whoami)
```

## Project Structure

```
harbor-arm/
├── .github/workflows/      # GitHub Actions CI/CD
├── scripts/
│   ├── build/             # Build phase scripts
│   │   ├── build-base-images.sh
│   │   ├── build-registry-binary.sh
│   │   ├── patch-harbor-build.sh
│   │   ├── build-harbor-components.sh
│   │   └── tag-and-push-images.sh
│   ├── test/              # Test phase scripts
│   │   ├── validate-images.sh
│   │   ├── integration-test-simple.sh
│   │   ├── api-test-simple.sh
│   │   └── benchmark-simple.sh
│   ├── common.sh          # Shared utilities
│   ├── config.sh          # Central configuration
│   └── build-local.sh     # Local build entry point
├── examples/              # Deployment examples
├── docs/                  # Documentation
└── built_versions.txt     # Version tracking
```

## Build System

### Configuration

All shared configuration is in `scripts/config.sh`:

```bash
# Harbor components
HARBOR_COMPONENTS=(
    "prepare" "core" "jobservice" "portal"
    "nginx" "log" "db" "redis"
    "registry" "registryctl" "exporter"
)

# Build settings
BUILD_CONFIG_NODE_VERSION="16.18.0"

# Registry settings
REGISTRY_DOCKERHUB="docker.io"
REGISTRY_GHCR="ghcr.io"
IMAGE_SUFFIX="-arm64"
```

### Build Scripts

The build scripts expect a checked-out Harbor tree and read the required Go
version from `src/go.mod`. Local and CI builds fail fast if the installed Go
toolchain is older than the Harbor release requires.

#### 1. build-base-images.sh

Builds Harbor base images:
- `harbor-prepare-base`
- `harbor-core-base`
- `harbor-db-base`
- etc.

```bash
./scripts/build/build-base-images.sh v2.15.1 myusername
```

#### 2. build-registry-binary.sh

Compiles Docker registry binary for ARM64:

```bash
./scripts/build/build-registry-binary.sh
```

#### 3. patch-harbor-build.sh

Patches Harbor build files:
- Disables API linting
- Updates Dockerfiles for ARM64
- Adds `--pull=false` to prevent pulling amd64 images

```bash
./scripts/build/patch-harbor-build.sh v2.15.1
```

#### 4. build-harbor-components.sh

Builds all Harbor components:

```bash
./scripts/build/build-harbor-components.sh v2.15.1 myusername
```

#### 5. tag-and-push-images.sh

Tags and pushes images to registries:

```bash
./scripts/build/tag-and-push-images.sh v2.15.1 myusername github-org
```

### Common Utilities

`scripts/common.sh` provides:
- Logging functions (`log_info`, `log_success`, `log_error`)
- Image verification
- Retry logic for network operations
- Architecture detection
- Timer functions

Example usage:

```bash
source scripts/common.sh

log_info "Building component..."
if verify_image "myimage:tag"; then
    log_success "Image verified"
else
    log_error "Image not found"
fi

# Retry docker operations
docker_push_retry myimage:tag
```

## Testing

### Validation Tests

Tests image existence, architecture, and basic functionality:

```bash
./scripts/test/validate-images.sh v2.15.1 myusername

# With full security scan
./scripts/test/validate-images.sh v2.15.1 myusername --full
```

### Integration Tests

Tests container startup and basic functionality:

```bash
./scripts/test/integration-test-simple.sh v2.15.1 myusername
```

### API Tests

Tests API components:

```bash
./scripts/test/api-test-simple.sh v2.15.1 myusername http://localhost:8080
```

### Benchmarks

Measures performance:

```bash
./scripts/test/benchmark-simple.sh v2.15.1 myusername http://localhost:8080
```

## CI/CD Pipeline

### Workflow Stages

1. **check-release**: Detects new Harbor releases
2. **build-harbor**: Builds all components on ARM64 runner
3. **validate-images**: Validates images (parallel)
4. **integration-test**: Integration tests (parallel)
5. **api-test**: API tests (parallel)
6. **benchmark**: Performance benchmarks (parallel)
7. **update-version-file**: Updates version tracking

### GitHub Actions Configuration

```yaml
# .github/workflows/build-harbor-arm64.yml

# Runs on native ARM64 runners
runs-on: ubuntu-24.04-arm

# Features:
# - Go module caching
# - Docker layer caching
# - Parallel test execution
# - Multi-registry publishing
```

### Secrets Required

- `DOCKERHUB_USERNAME`: Docker Hub username
- `DOCKERHUB_TOKEN`: Docker Hub access token
- `GITHUB_TOKEN`: Automatically provided

### Manual Trigger

```bash
# Using GitHub CLI
gh workflow run build-harbor-arm64.yml -f version=v2.15.1

# Or via GitHub UI
# https://github.com/hoon-ch/harbor-arm/actions
```

## Contributing

### Development Workflow

1. **Fork the repository**

```bash
git clone https://github.com/your-username/harbor-arm.git
cd harbor-arm
git remote add upstream https://github.com/hoon-ch/harbor-arm.git
```

2. **Create feature branch**

```bash
git checkout -b feature/my-improvement
```

3. **Make changes**

```bash
# Edit scripts or documentation
vim scripts/build/build-harbor-components.sh

# Test locally
./scripts/build-local.sh v2.15.1
```

4. **Run tests**

```bash
# Validate changes
./scripts/test/validate-images.sh v2.15.1 $(whoami)
```

5. **Commit changes**

```bash
git add .
git commit -m "feat: add new optimization"
```

6. **Push and create PR**

```bash
git push origin feature/my-improvement
# Create PR on GitHub
```

### Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Test additions/changes
- `chore:` Build process or auxiliary tool changes

Examples:

```
feat: add retry logic to network operations
fix: correct image naming in tag-and-push script
docs: update deployment guide for k8s
refactor: centralize configuration in config.sh
```

### Code Style

- Use 2-space indentation
- Add comments for complex logic
- Follow existing patterns
- Use shellcheck for bash scripts:

```bash
shellcheck scripts/**/*.sh
```

## Debugging

### Enable Verbose Output

```bash
# Add to script
set -x  # Enable command tracing

# Or run with
bash -x scripts/build-local.sh v2.15.1
```

### Check Build Logs

```bash
# View GitHub Actions logs
gh run view --log

# Local build logs
docker logs harbor-core 2>&1 | less
```

### Interactive Debugging

```bash
# Enter container
docker exec -it harbor-core /bin/bash

# Check process
ps aux

# Check files
ls -la /etc/core/
```

## Performance Optimization

### Build Performance

- Use Docker buildx cache
- Parallel job execution
- Go module caching
- Incremental builds

### Resource Usage

Monitor during build:

```bash
# CPU and memory
docker stats

# Disk usage
docker system df
```

## Tools and Utilities

### Required Tools

```bash
# Install on macOS
brew install docker go jq curl git

# Install on Ubuntu/Debian
apt-get install docker.io golang jq curl git

# Verify installation
docker --version
go version
jq --version
```

### Optional Tools

```bash
# Trivy for security scanning
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh

# Hadolint for Dockerfile linting
brew install hadolint

# Shellcheck for bash linting
brew install shellcheck
```

## Release Process

1. **Automated Release Detection**
   - Runs daily at 00:00 UTC
   - Checks official `goharbor/harbor-core` image tags for the highest stable Harbor version
   - Skips if version already built

2. **Build Execution**
   - Native ARM64 build on ubuntu-24.04-arm
   - All components built in single job
   - Comprehensive testing

3. **Publishing**
   - Tagged with version
   - Tagged as `latest` only when building the highest stable Harbor image version
   - Pushed to Docker Hub
   - Pushed to GHCR

4. **Version Tracking**
   - Updates `built_versions.txt`
   - Commits to repository

## Troubleshooting Development Issues

### Build Failures

```bash
# Clean Docker cache
docker builder prune -af

# Remove old images
docker rmi $(docker images -q hoon-ch/harbor-*)

# Retry build
./scripts/build-local.sh v2.15.1
```

### Go Module Issues

```bash
# Clear Go cache
go clean -modcache

# Update dependencies
go mod tidy
go mod download
```

### Permission Errors

```bash
# Fix Docker permissions (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Fix script permissions
chmod +x scripts/**/*.sh
```

## Resources

- [Harbor Development Guide](https://github.com/goharbor/harbor/blob/main/docs/compile_guide.md)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Go Documentation](https://go.dev/doc/)

## Support

- **Issues**: [GitHub Issues](https://github.com/hoon-ch/harbor-arm/issues)
- **Discussions**: [GitHub Discussions](https://github.com/hoon-ch/harbor-arm/discussions)
- **Harbor Community**: [Harbor Slack](https://cloud-native.slack.com/#harbor)
