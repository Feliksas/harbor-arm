#!/usr/bin/env bash
set -e

# Build Harbor base images for ARM64
# This script builds the base Docker images required for Harbor components
# Usage: ./build-base-images.sh <version> <docker_username>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <version>"
    log_info "Example: $0 v2.11.0"
    exit 1
fi

VERSION=$1
VERSION_TAG=$(clean_version_tag "$VERSION")

start_timer

FAILED_REQUIRED_BASE_IMAGES=()
FAILED_OPTIONAL_BASE_IMAGES=()

record_base_image_failure() {
    local component=$1

    if is_optional_component "$component"; then
        if [[ " ${FAILED_OPTIONAL_BASE_IMAGES[*]} " != *" $component "* ]]; then
            FAILED_OPTIONAL_BASE_IMAGES+=("$component")
        fi
        log_warning "Optional base image failed: $component"
    else
        if [[ " ${FAILED_REQUIRED_BASE_IMAGES[*]} " != *" $component "* ]]; then
            FAILED_REQUIRED_BASE_IMAGES+=("$component")
        fi
        log_error "Required base image failed: $component"
    fi
}

log_section "Building Base Images for ARM64"
log_info "Version: $VERSION"
log_info "Version Tag: $VERSION_TAG"
log_info "Architecture: $(uname -m)"

log_info "Using main Photon image instead of legacy"
grep -Rl '[0-9]\-legacy' ./make | xargs -L1 sed -i -e 's/\-legacy//g'

# Verify we're in the Harbor directory
verify_file "make/photon/prepare/Dockerfile.base"

log_section "Patching Photon Base Images for ARM64"

patched_files=0
while IFS= read -r base_dockerfile; do
    if grep -q '^FROM goharbor/photon:5\.0$' "$base_dockerfile"; then
        sed -i 's|^FROM goharbor/photon:5\.0$|FROM photon:5.0|' "$base_dockerfile"
        log_info "Patched $base_dockerfile to use multi-arch photon:5.0"
        patched_files=$((patched_files + 1))
    fi
done < <(find make/photon -name "Dockerfile.base" -type f 2>/dev/null)

if [ "$patched_files" -eq 0 ]; then
    log_warning "No goharbor/photon:5.0 base images found to patch"
else
    log_success "Patched $patched_files Photon base Dockerfile(s)"
fi

# Check what the base Dockerfile is based on
log_section "Checking Base Image Dependencies"
grep "^FROM" make/photon/prepare/Dockerfile.base || true

# Build harbor-prepare-base for ARM64 - this is the critical one
log_section "Building harbor-prepare-base:${VERSION}"

# Use regular docker build (not buildx) since we might be on native ARM64
# This prevents buildx from pulling remote AMD64 images
docker build \
    -t goharbor/harbor-prepare-base:${VERSION} \
    -f make/photon/prepare/Dockerfile.base \
    make/photon/prepare/

# Verify the image was built
verify_image "goharbor/harbor-prepare-base:${VERSION}" || exit_on_error "Failed to build harbor-prepare-base:${VERSION}"

log_success "Successfully built harbor-prepare-base:${VERSION}"

# Also tag with the exact version tag format Harbor expects
docker tag goharbor/harbor-prepare-base:${VERSION} goharbor/prepare:${VERSION_TAG}

# Build other base images if they exist
log_section "Building Additional Base Images"

for base_dockerfile in $(find make/photon -name "Dockerfile.base" 2>/dev/null); do
    if [ -f "$base_dockerfile" ] && [ "$base_dockerfile" != "make/photon/prepare/Dockerfile.base" ]; then
        component_dir=$(dirname "$base_dockerfile")
        component_name=$(basename "$component_dir")

        log_info "Building base image for ${component_name}..."

        if docker build \
            -t goharbor/harbor-${component_name}-base:${VERSION} \
            -f "$base_dockerfile" \
            "$component_dir/"; then
            log_success "Built base image for ${component_name}"
        else
            record_base_image_failure "$component_name"
        fi
    fi
done

# List all built base images
list_images "harbor.*base|prepare"

if [ ${#FAILED_OPTIONAL_BASE_IMAGES[@]} -gt 0 ]; then
    log_warning "Optional base image failures: ${FAILED_OPTIONAL_BASE_IMAGES[*]}"
fi

if [ ${#FAILED_REQUIRED_BASE_IMAGES[@]} -gt 0 ]; then
    log_error "Required base image failures: ${FAILED_REQUIRED_BASE_IMAGES[*]}"
    exit 1
fi

end_timer
log_success "Base images build completed"
