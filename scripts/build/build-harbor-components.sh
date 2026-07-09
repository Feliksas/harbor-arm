#!/usr/bin/env bash
set -e

# Build Harbor components for ARM64
# This script builds all Harbor Docker images for ARM64 architecture
# Usage: ./build-harbor-components.sh <version> <docker_username>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

TRIVYVERSION=v0.69.3
TRIVYADAPTERVERSION=v0.35.1

# Check arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <version>"
    log_info "Example: $0 v2.11.0"
    exit 1
fi

VERSION=$1
VERSION_TAG=$(clean_version_tag "$VERSION")

TRIVYVERSION=$(grep -m1 TRIVYVERSION Makefile | cut -d '=' -f2)
TRIVYADAPTERVERSION=$(grep -m1 TRIVYADAPTERVERSION Makefile | cut -d '=' -f2)

TRIVY_DOWNLOAD_URL="https://github.com/aquasecurity/trivy/releases/download/${TRIVYVERSION}/trivy_${TRIVYVERSION:1}_Linux-ARM64.tar.gz"
TRIVY_ADAPTER_DOWNLOAD_URL="https://github.com/goharbor/harbor-scanner-trivy/archive/refs/tags/${TRIVYADAPTERVERSION}.tar.gz"

start_timer

FAILED_REQUIRED_COMPONENTS=()
FAILED_OPTIONAL_COMPONENTS=()

record_component_failure() {
    local component=$1

    if is_optional_component "$component"; then
        if [[ " ${FAILED_OPTIONAL_COMPONENTS[*]} " != *" $component "* ]]; then
            FAILED_OPTIONAL_COMPONENTS+=("$component")
        fi
        log_warning "Optional component failed: $component"
    else
        if [[ " ${FAILED_REQUIRED_COMPONENTS[*]} " != *" $component "* ]]; then
            FAILED_REQUIRED_COMPONENTS+=("$component")
        fi
        log_error "Required component failed: $component"
    fi
}

log_section "Building Harbor Components for ARM64"
log_info "Version: $VERSION"
log_info "Version Tag: $VERSION_TAG"
log_info "Trivy version: $TRIVYVERSION"
log_info "Trivy adapter version: $TRIVYADAPTERVERSION"
show_build_env

REQUIRED_GO_VERSION=$(get_harbor_go_version ".") || exit_on_error "Failed to detect Harbor Go version from src/go.mod"
ensure_installed_go_matches_harbor_requirement "." || exit_on_error "Installed Go toolchain does not meet Harbor requirements"
log_info "Using Harbor-required Go build image: golang:${REQUIRED_GO_VERSION}"

# List all our local ARM64 base images
list_images "goharbor"

# Compile the Go binaries (including core, jobservice)
log_section "Compiling Go Binaries"
make compile \
    GOBUILDIMAGE=golang:${REQUIRED_GO_VERSION} \
    COMPILETAG=compile_golangimage \
    BUILDBIN=true \
    NOTARYFLAG=${BUILD_FLAG_NOTARY} \
    TRIVYFLAG=${BUILD_FLAG_TRIVY} \
    GOBUILDTAGS="${BUILD_FLAG_GOBUILDTAGS}"

log_success "Go binaries compiled"

# Compile exporter manually (make target doesn't exist in v2.14.0)
log_section "Compiling Exporter Binary for ARM64"
mkdir -p make/photon/exporter

if [ -d "src/cmd/exporter" ]; then
    log_info "Building exporter from source..."
    cd src/cmd/exporter

    # Build exporter binary for ARM64
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -o ../../../make/photon/exporter/harbor_exporter .

    cd ../../..

    # Set permissions and verify
    chmod +x make/photon/exporter/harbor_exporter

    log_success "Exporter binary created:"
    file make/photon/exporter/harbor_exporter
    ls -lh make/photon/exporter/harbor_exporter
else
    log_warning "Exporter source directory not found"
    record_component_failure "exporter"
fi

# Now build each Docker image manually using regular docker build
log_section "Building Docker Images Manually"

# Build prepare image using our local ARM64 base
log_info "Building prepare image..."
docker build \
    --build-arg harbor_base_namespace=goharbor \
    --build-arg harbor_base_image_version=${VERSION} \
    -t armbuild/prepare:${VERSION_TAG} \
    -f make/photon/prepare/Dockerfile \
    .

# Build core images
for component in core jobservice; do
    log_info "Building $component..."
    if docker build \
        --build-arg harbor_base_namespace=goharbor \
        --build-arg harbor_base_image_version=${VERSION} \
        -t armbuild/harbor-$component:${VERSION_TAG} \
        -f make/photon/$component/Dockerfile \
        .; then
        log_success "Built $component"
    else
        record_component_failure "$component"
    fi
done

# Detect the Node build image Harbor pins in its Makefile (NODEBUILDIMAGE=node:X.Y.Z)
# so the portal's Angular build uses a compatible Node; recent Angular requires
# Node >= 20. Fall back to the configured default if detection fails.
NODE_BUILD_VERSION=$(sed -nE 's/^[[:space:]]*NODEBUILDIMAGE[[:space:]]*[:?+]?=[[:space:]]*node:([^[:space:]#]+).*/\1/p' Makefile | head -n 1)
if [ -z "${NODE_BUILD_VERSION}" ]; then
    NODE_BUILD_VERSION="${BUILD_CONFIG_NODE_VERSION}"
    log_warning "Could not detect NODEBUILDIMAGE from Harbor Makefile; using configured Node ${NODE_BUILD_VERSION}"
else
    log_info "Using Harbor-required Node build image: node:${NODE_BUILD_VERSION}"
fi


# Build portal with NODE argument
log_info "Building portal..."
if docker build \
    --build-arg harbor_base_namespace=${BUILD_CONFIG_HARBOR_BASE_NAMESPACE} \
    --build-arg harbor_base_image_version=${VERSION} \
    --build-arg NODE=node:${NODE_BUILD_VERSION} \
    -t armbuild/harbor-portal:${VERSION_TAG} \
    -f make/photon/portal/Dockerfile \
    .; then
    log_success "Built portal"
else
    record_component_failure "portal"
fi

# Build nginx, log, db, valkey
for component in nginx log db valkey; do
    if [ ! -d "make/photon/$component" ]; then
        log_warning "Component directory not found: $component"
        record_component_failure "$component"
        continue
    fi

    log_info "Building $component..."

    # Determine output image name
    case $component in
        nginx) image_name="nginx-photon" ;;
        valkey) image_name="valkey-photon" ;;
        *) image_name="harbor-$component" ;;
    esac

    if docker build \
        --build-arg harbor_base_namespace=goharbor \
        --build-arg harbor_base_image_version=${VERSION} \
        -t armbuild/$image_name:${VERSION_TAG} \
        -f make/photon/$component/Dockerfile \
        .; then
        log_success "Built $component"
    else
        record_component_failure "$component"
    fi
done

# Build registry and registryctl (requires registry binary)
log_info "Building registry..."
if docker build \
    --build-arg harbor_base_namespace=goharbor \
    --build-arg harbor_base_image_version=${VERSION} \
    -t armbuild/registry-photon:${VERSION_TAG} \
    -f make/photon/registry/Dockerfile \
    .; then
    log_success "Built registry"
else
    record_component_failure "registry"
fi

log_info "Building registryctl..."
if docker build \
    --build-arg harbor_base_namespace=goharbor \
    --build-arg harbor_base_image_version=${VERSION} \
    -t armbuild/harbor-registryctl:${VERSION_TAG} \
    -f make/photon/registryctl/Dockerfile \
    .; then
    log_success "Built registryctl"
else
    record_component_failure "registryctl"
fi

log_info "Building trivy-adapter..."

mkdir -p "make/photon/trivy-adapter/binary"
mkdir -p /tmp/harbor-scanner
CURL=$(which curl)
${CURL} --connect-timeout 30 -f -k -L $TRIVY_DOWNLOAD_URL | tar xvz -C "make/photon/trivy-adapter/binary" || exit 1
${CURL} --connect-timeout 30 -f -k -L $TRIVY_ADAPTER_DOWNLOAD_URL | tar xvz -C "/tmp/harbor-scanner" || exit 1
CURRENT_DIR=$(pwd)
cd /tmp/harbor-scanner/harbor-scanner-trivy-${TRIVYADAPTERVERSION:1}
go build ./cmd/scanner-trivy
cd $CURRENT_DIR
mv /tmp/harbor-scanner/harbor-scanner-trivy-${TRIVYADAPTERVERSION:1}/scanner-trivy make/photon/trivy-adapter/binary/
if docker build \
    --build-arg harbor_base_namespace=goharbor \
    --build-arg harbor_base_image_version=${VERSION} \
    --build-arg trivy_version=${TRIVYVERSION} \
    -t armbuild/harbor-trivy-adapter:${VERSION_TAG} \
    -f make/photon/trivy-adapter/Dockerfile \
    .; then
    log_success "Built trivy-adapter"
else
    record_component_failure "trivy-adapter"
fi

# Build exporter using our pre-built ARM64 binary
if [ -f "make/photon/exporter/harbor_exporter" ]; then
    log_info "Building exporter..."

    # Create a Dockerfile for exporter
    cat > /tmp/Dockerfile.exporter <<'EOF'
ARG harbor_base_namespace
ARG harbor_base_image_version
FROM ${harbor_base_namespace}/harbor-exporter-base:${harbor_base_image_version}

COPY make/photon/exporter/harbor_exporter /harbor/harbor_exporter
COPY ./make/photon/exporter/entrypoint.sh ./make/photon/common/install_cert.sh /harbor/

RUN chown -R harbor:harbor /etc/pki/tls/certs \
    && chown harbor:harbor /harbor/harbor_exporter && chmod u+x /harbor/harbor_exporter \
    && chown harbor:harbor /harbor/entrypoint.sh && chmod u+x /harbor/entrypoint.sh \
    && chown harbor:harbor /harbor/install_cert.sh && chmod u+x /harbor/install_cert.sh

WORKDIR /harbor
USER harbor

ENTRYPOINT ["/harbor/entrypoint.sh"]
EOF

    if docker build \
        --build-arg harbor_base_namespace=goharbor \
        --build-arg harbor_base_image_version=${VERSION} \
        -t armbuild/harbor-exporter:${VERSION_TAG} \
        -f /tmp/Dockerfile.exporter \
        .; then
        log_success "Built exporter"
    else
        record_component_failure "exporter"
    fi

    rm -f /tmp/Dockerfile.exporter
else
    log_warning "Exporter binary not found, skipping exporter image build"
    record_component_failure "exporter"
fi

# List all built images
log_section "Built Images Summary"
list_images "armbuild"

if [ ${#FAILED_OPTIONAL_COMPONENTS[@]} -gt 0 ]; then
    log_warning "Optional component failures: ${FAILED_OPTIONAL_COMPONENTS[*]}"
fi

if [ ${#FAILED_REQUIRED_COMPONENTS[@]} -gt 0 ]; then
    log_error "Required component failures: ${FAILED_REQUIRED_COMPONENTS[*]}"
    exit 1
fi

end_timer
log_success "Harbor components build completed"
