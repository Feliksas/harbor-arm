#!/bin/bash
set -e

# Tag and push Harbor ARM64 images to registries
# This script tags and pushes built Harbor images to Docker Hub and GHCR
# Usage: ./tag-and-push-images.sh <version> <docker_username> <github_repo_owner> [tag_latest]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

# Check arguments
if [ $# -lt 3 ]; then
    log_error "Usage: $0 <version> <docker_username> <github_repo_owner> [tag_latest]"
    log_info "Example: $0 v2.11.0 myusername myorg false"
    exit 1
fi

VERSION=$1
DOCKER_USERNAME=$2
GITHUB_REPO_OWNER=$3
TAG_LATEST=${4:-false}
VERSION_TAG=$(clean_version_tag "$VERSION")

start_timer

log_section "Tagging and Pushing Harbor ARM64 Images"
log_info "Version: $VERSION"
log_info "Version Tag: $VERSION_TAG"
log_info "Docker Username: $DOCKER_USERNAME"
log_info "GitHub Repo Owner: $GITHUB_REPO_OWNER"
log_info "Update latest tag: $TAG_LATEST"

# List built images to understand naming
log_section "Built Images"
docker images | grep ${DOCKER_USERNAME} || docker images | grep ${VERSION_TAG} || true

# Use centralized image name configuration from config.sh
# Note: IMAGE_NAMES is now defined in scripts/config.sh as HARBOR_IMAGE_NAMES

# Debug: List all docker images to see what was actually built
log_section "All Available Images"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | sort | head -30

# Track success/failure
PUSHED_IMAGES=()
FAILED_IMAGES=()

# Push all built components
log_section "Pushing Images to Registries"

for component in "${HARBOR_COMPONENTS[@]}"; do
    IMAGE_NAME="${HARBOR_IMAGE_NAMES[$component]}"
    SOURCE_IMAGE="${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION_TAG}"

    log_info "Processing ${component}..."

    # Check if image exists
    if docker image inspect ${SOURCE_IMAGE} >/dev/null 2>&1; then
        log_success "Found ${component} image: ${SOURCE_IMAGE}"

        # Tag for Docker Hub with -arm64 suffix
        DOCKERHUB_IMAGE_VERSIONED="${DOCKER_USERNAME}/harbor-${component}${IMAGE_SUFFIX}:${VERSION_TAG}"
        docker tag ${SOURCE_IMAGE} ${DOCKERHUB_IMAGE_VERSIONED}

        # Tag for GHCR
        GHCR_IMAGE_VERSIONED="$(get_ghcr_image_reference ${GITHUB_REPO_OWNER} ${component} ${VERSION_TAG})"
        docker tag ${SOURCE_IMAGE} ${GHCR_IMAGE_VERSIONED}

        if [ "$TAG_LATEST" = "true" ]; then
            DOCKERHUB_IMAGE_LATEST="${DOCKER_USERNAME}/harbor-${component}${IMAGE_SUFFIX}:latest"
            GHCR_IMAGE_LATEST="${REGISTRY_GHCR}/${GITHUB_REPO_OWNER}/harbor-${component}${IMAGE_SUFFIX}:latest"
            docker tag ${SOURCE_IMAGE} ${DOCKERHUB_IMAGE_LATEST}
            docker tag ${SOURCE_IMAGE} ${GHCR_IMAGE_LATEST}
        fi

        # Push to Docker Hub with retry
        log_info "Pushing to Docker Hub..."
        if docker_push_retry ${DOCKERHUB_IMAGE_VERSIONED} && \
           { [ "$TAG_LATEST" != "true" ] || docker_push_retry ${DOCKERHUB_IMAGE_LATEST}; }; then
            log_success "Pushed ${component} to Docker Hub"
        else
            log_warning "Failed to push ${component} to Docker Hub"
        fi

        # Push to GHCR with retry
        log_info "Pushing to GHCR..."
        if docker_push_retry ${GHCR_IMAGE_VERSIONED} && \
           { [ "$TAG_LATEST" != "true" ] || docker_push_retry ${GHCR_IMAGE_LATEST}; }; then
            log_success "Pushed ${component} to GHCR"
        else
            log_warning "Failed to push ${component} to GHCR"
        fi

        PUSHED_IMAGES+=("$component")
    else
        log_error "Image not found: ${SOURCE_IMAGE}"
        FAILED_IMAGES+=("$component")
    fi
done

# Summary
log_section "Push Summary"
log_info "Successfully pushed: ${#PUSHED_IMAGES[@]} images"
for img in "${PUSHED_IMAGES[@]}"; do
    log_success "✓ $img"
done

if [ ${#FAILED_IMAGES[@]} -gt 0 ]; then
    log_warning "Failed to push: ${#FAILED_IMAGES[@]} images"
    for img in "${FAILED_IMAGES[@]}"; do
        log_error "✗ $img"
    done
fi

end_timer

if [ ${#FAILED_IMAGES[@]} -eq 0 ]; then
    log_success "All images tagged and pushed successfully"
    exit 0
else
    log_error "Some images failed to push"
    exit 1
fi
