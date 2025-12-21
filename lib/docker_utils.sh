#!/bin/bash
################################################################################
# MITMRouter Docker Utilities
# Functions for container management and Docker operations
################################################################################

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    if ! docker ps &>/dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    log_success "Docker is available"
    return 0
}

# Build Docker image
build_docker_image() {
    local dockerfile="${1:-./Dockerfile}"
    local image_name="${2:-mitmrouter:latest}"
    local build_args="${3:-}"
    
    log_info "Building Docker image: ${image_name}"
    log_info "Dockerfile: ${dockerfile}"
    
    # Check if Docker is available
    check_docker || return 1
    
    # Build command
    local build_cmd="docker build -t ${image_name} -f ${dockerfile}"
    
    # Add build arguments if provided
    if [[ -n "${build_args}" ]]; then
        build_cmd+=" ${build_args}"
    fi
    
    build_cmd+=" ."
    
    log_debug "Build command: ${build_cmd}"
    
    # Execute build
    if eval "${build_cmd}"; then
        log_success "Image built successfully: ${image_name}"
        return 0
    else
        log_error "Failed to build image"
        return 1
    fi
}

# Start Docker container
start_docker_container() {
    local image_name="$1"
    local container_name="${2:-mitmrouter}"
    
    log_info "Starting Docker container: ${container_name} (image: ${image_name})"
    
    # Check if Docker is available
    check_docker || return 1
    
    # Check if container already running
    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_warn "Container ${container_name} is already running"
        return 0
    fi
    
    # Remove old container if exists
    if docker ps -a --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_info "Removing old container ${container_name}..."
        docker rm "${container_name}" || true
    fi
    
    # Start container with necessary options
    docker run -d \
        --name "${container_name}" \
        --network host \
        --privileged \
        --cap-add NET_ADMIN \
        --cap-add NET_RAW \
        -v "$(pwd)/config:/opt/mitmrouter/config:ro" \
        -v "$(pwd)/logs:/var/log/mitmrouter" \
        -e "LOG_LEVEL=INFO" \
        "${image_name}" || return 1
    
    log_success "Container started: ${container_name}"
    return 0
}

# Stop Docker container
stop_docker_container() {
    local container_name="${1:-mitmrouter}"
    
    log_info "Stopping Docker container: ${container_name}"
    
    if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker stop "${container_name}" || return 1
        log_success "Container stopped: ${container_name}"
    else
        log_warn "Container ${container_name} is not running"
    fi
    
    return 0
}

# Get container logs
get_docker_container_logs() {
    local container_name="${1:-mitmrouter}"
    local tail_lines="${2:-100}"
    
    docker logs --tail "${tail_lines}" -f "${container_name}"
}

# Execute command in running container
docker_exec() {
    local container_name="$1"
    shift
    local cmd="$*"
    
    docker exec -it "${container_name}" bash -c "${cmd}"
}