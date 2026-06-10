#!/usr/bin/env bash
set -e

# Build registry binary for ARM64
# This script builds the Docker registry binary from source for ARM64 architecture
# Usage: ./build-registry-binary.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

start_timer

log_section "Building Registry Binary for ARM64"

check_command "go"
check_command "git"

HARBOR_GO_VERSION=$(get_harbor_go_version ".") || exit_on_error "Failed to detect Harbor Go version from src/go.mod"
ensure_installed_go_matches_harbor_requirement "." || exit_on_error "Installed Go toolchain does not meet Harbor requirements"
log_info "Using installed Go toolchain compatible with Harbor requirement ${HARBOR_GO_VERSION}"

# Create directories for registry binaries
CURRENT_DIR=$(pwd)
mkdir -p make/photon/registry/binary

# Get the vmajor.minor.patch version component
REGISTRY_VERSION=$(grep -m1 REGISTRY_SRC_TAG Makefile | cut -d '=' -f2 | cut -d '-' -f1)
REGISTRY_BINARY_URL="https://github.com/distribution/distribution/releases/download/${REGISTRY_VERSION}/registry_${REGISTRY_VERSION:1}_linux_arm64.tar.gz"

log_info "Registry version: ${REGISTRY_VERSION}"
CURL=$(which curl)
${CURL} --connect-timeout 30 -f -k -L "$REGISTRY_BINARY_URL" | tar xvz -C "make/photon/registry/binary" || exit 1
verify_file "make/photon/registry/binary/registry"

# Build registryctl binary for ARM64
log_info "Building registryctl binary for ARM64..."
SRC_DIR="${CURRENT_DIR}/src"
cd "$SRC_DIR"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -o /tmp/harbor_registryctl ./registryctl

# Copy to Harbor build directories
log_info "Copying registryctl binary to Harbor directories..."
cp /tmp/harbor_registryctl "${CURRENT_DIR}/make/photon/registryctl/harbor_registryctl"

cd "$CURRENT_DIR"

# Cleanup
rm -rf "$DIST_DIR"

# Verify the binaries
log_section "Registry Binary Build Summary"
log_info "Registry binary location:"
ls -lh make/photon/registry/binary/registry
log_info "Registryctl binary location:"
ls -lh make/photon/registryctl/harbor_registryctl

log_info "Binary architecture:"
file make/photon/registry/binary/registry
file make/photon/registryctl/harbor_registryctl

end_timer
log_success "Registry binary build completed"