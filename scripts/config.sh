#!/usr/bin/env bash

# Central configuration file for Harbor ARM64 build system
# This file contains all shared configuration variables and mappings

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Harbor ARM64 scripts require Bash 4 or newer because scripts/config.sh uses associative arrays." >&2
    return 1 2>/dev/null || exit 1
fi

# Harbor components list
# These are the components that will be built, tested, and pushed
HARBOR_COMPONENTS=(
    "prepare"
    "core"
    "jobservice"
    "portal"
    "nginx"
    "log"
    "db"
    "redis"
    "registry"
    "registryctl"
    "exporter"
    "trivy-adapter"
)

# Components supported by scripts/build-local.sh's generic Dockerfile builder.
# Exporter stays in HARBOR_COMPONENTS for the CI/published matrix, but is built
# by scripts/build/build-harbor-components.sh because it needs a precompiled
# binary and temporary Dockerfile.
LOCAL_BUILD_COMPONENTS=(
    "prepare"
    "core"
    "jobservice"
    "portal"
    "nginx"
    "log"
    "db"
    "redis"
    "registry"
    "registryctl"
)

OPTIONAL_COMPONENTS=()

# Image name mappings: component_name -> actual_image_name
# Some Harbor components use different names for their Docker images
declare -A HARBOR_IMAGE_NAMES=(
    ["prepare"]="prepare"
    ["core"]="harbor-core"
    ["db"]="harbor-db"
    ["jobservice"]="harbor-jobservice"
    ["log"]="harbor-log"
    ["nginx"]="nginx-photon"
    ["portal"]="harbor-portal"
    ["redis"]="redis-photon"
    ["registry"]="registry-photon"
    ["registryctl"]="harbor-registryctl"
    ["exporter"]="harbor-exporter"
    ["trivy-adapter"]="harbor-trivy-adapter"
)

# Build configuration
BUILD_CONFIG_NODE_VERSION="16.18.0"
BUILD_CONFIG_HARBOR_BASE_NAMESPACE="goharbor"

# Build flags
BUILD_FLAG_NOTARY=false
BUILD_FLAG_TRIVY=true
BUILD_FLAG_GOBUILDTAGS="include_oss include_gcs"

# Registry configuration
REGISTRY_DOCKERHUB="docker.io"
REGISTRY_GHCR="ghcr.io"
IMAGE_SUFFIX="-arm64"

# Testable components (can start standalone)
TESTABLE_COMPONENTS=(
    "redis"
    "db"
)

# Core components for security scanning
SCAN_COMPONENTS=(
    "core"
    "portal"
    "registry"
)

# Retry configuration for network operations
RETRY_MAX_ATTEMPTS=3
RETRY_TIMEOUT_SECONDS=5

# Helper function: Get image name for a component
get_image_name() {
    local component=$1
    echo "${HARBOR_IMAGE_NAMES[$component]}"
}

# Helper function: Build full image reference
get_image_reference() {
    local username=$1
    local component=$2
    local version=$3
    local image_name="${HARBOR_IMAGE_NAMES[$component]}"
    echo "${username}/${image_name}:${version}"
}

# Helper function: Build pushed image reference (with -arm64 suffix)
get_pushed_image_reference() {
    local username=$1
    local component=$2
    local version=$3
    echo "${username}/harbor-${component}${IMAGE_SUFFIX}:${version}"
}

# Helper function: Print built components as comma-separated values
component_list_csv() {
    local IFS=,
    echo "${HARBOR_COMPONENTS[*]}"
}

# Helper function: Print built components as space-separated values
component_list_space() {
    echo "${HARBOR_COMPONENTS[*]}"
}

# Helper function: Check whether a component is optional
is_optional_component() {
    local component=$1
    local optional
    for optional in "${OPTIONAL_COMPONENTS[@]}"; do
        if [ "$optional" = "$component" ]; then
            return 0
        fi
    done
    return 1
}

# Helper function: Build GHCR image reference
get_ghcr_image_reference() {
    local repo_owner=$1
    local component=$2
    local version=$3
    echo "${REGISTRY_GHCR}/${repo_owner}/harbor-${component}${IMAGE_SUFFIX}:${version}"
}

# Export configuration
export HARBOR_COMPONENTS
export LOCAL_BUILD_COMPONENTS
export OPTIONAL_COMPONENTS
export BUILD_CONFIG_NODE_VERSION
export BUILD_CONFIG_HARBOR_BASE_NAMESPACE
export BUILD_FLAG_NOTARY
export BUILD_FLAG_TRIVY
export BUILD_FLAG_GOBUILDTAGS
export REGISTRY_DOCKERHUB
export REGISTRY_GHCR
export IMAGE_SUFFIX
export TESTABLE_COMPONENTS
export SCAN_COMPONENTS
export RETRY_MAX_ATTEMPTS
export RETRY_TIMEOUT_SECONDS

# Export functions
export -f get_image_name
export -f get_image_reference
export -f get_pushed_image_reference
export -f component_list_csv
export -f component_list_space
export -f is_optional_component
export -f get_ghcr_image_reference
