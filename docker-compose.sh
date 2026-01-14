#!/bin/bash
# docker-compose.sh - because YAML is just JSON with anxiety
# Usage: ./docker-compose.sh up -d | down | ps
set -euo pipefail

PROJECT_NAME="vibe-todo"
IMAGE_PREFIX="vibe-todo"
NETWORK_NAME="${PROJECT_NAME}_default"
VOLUME_NAME="${PROJECT_NAME}_data"

log_up() { echo -e "\033[1;32m==>\033[0m $*"; }
log_down() { echo -e "\033[1;33m==>\033[0m $*"; }
err() { echo -e "\033[1;31m==>\033[0m $*" >&2; }

# Labels that make Docker Desktop recognize us as a compose project
compose_labels() {
    local service="$1"
    echo "--label=com.docker.compose.project=$PROJECT_NAME"
    echo "--label=com.docker.compose.service=$service"
    echo "--label=com.docker.compose.version=2.0.0-bash"
    echo "--label=com.docker.compose.oneoff=False"
    echo "--label=com.docker.compose.project.config_files=docker-compose.sh"
    echo "--label=com.docker.compose.project.working_dir=$(pwd)"
    echo "--label=com.docker.compose.container-number=1"
}

setup_network() {
    if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
        log_up "Creating network $NETWORK_NAME"
        docker network create \
            --label "com.docker.compose.project=$PROJECT_NAME" \
            --label "com.docker.compose.network=default" \
            --label "com.docker.compose.version=2.0.0-bash" \
            "$NETWORK_NAME"
    fi
}

setup_volume() {
    if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
        log_up "Creating volume $VOLUME_NAME"
        docker volume create \
            --label "com.docker.compose.project=$PROJECT_NAME" \
            --label "com.docker.compose.volume=data" \
            --label "com.docker.compose.version=2.0.0-bash" \
            "$VOLUME_NAME"
    fi
}

wait_for_service() {
    local name="$1"
    local port="$2"
    local max_attempts=30

    log_up "Waiting for $name..."
    for ((i=1; i<=max_attempts; i++)); do
        if docker exec "${PROJECT_NAME}-${name}-1" nc -z localhost "$port" 2>/dev/null; then
            log_up "$name is ready"
            return 0
        fi
        sleep 0.5
    done
    err "$name failed to start"
    return 1
}

run_service() {
    local service="$1"
    local image="$2"
    shift 2
    local extra_args=("$@")
    local container_name="${PROJECT_NAME}-${service}-1"

    docker rm -f "$container_name" 2>/dev/null || true

    log_up "Starting $service"
    # shellcheck disable=SC2046
    docker run -d \
        --name "$container_name" \
        --hostname "$service" \
        --network "$NETWORK_NAME" \
        --network-alias "$service" \
        --restart unless-stopped \
        $(compose_labels "$service") \
        "${extra_args[@]}" \
        "$image"
}

cmd_up() {
    local detach=false
    for arg in "$@"; do
        [[ "$arg" == "-d" ]] && detach=true
    done

    log_up "Starting $PROJECT_NAME stack"
    echo ""

    setup_network
    setup_volume

    # Storage service
    run_service "storage" "$IMAGE_PREFIX-storage-service" \
        -v "$VOLUME_NAME:/data" \
        -e "DATA_DIR=/data"
    wait_for_service "storage" 8001

    # Todo service
    run_service "todo" "$IMAGE_PREFIX-todo-service" \
        -e "STORAGE_HOST=storage" \
        -e "STORAGE_PORT=8001"
    wait_for_service "todo" 8002

    # Frontend service
    run_service "frontend" "$IMAGE_PREFIX-frontend-service"
    wait_for_service "frontend" 8003

    # API Gateway
    run_service "gateway" "$IMAGE_PREFIX-api-gateway" \
        -p "8000:8000" \
        -e "TODO_HOST=todo" \
        -e "TODO_PORT=8002" \
        -e "FRONTEND_HOST=frontend" \
        -e "FRONTEND_PORT=8003"
    wait_for_service "gateway" 8000

    echo ""
    log_up "All services running on http://localhost:8000"
    echo ""
    cmd_ps

    if [[ "$detach" == false ]]; then
        echo ""
        log_up "Attaching to logs (Ctrl+C to detach)..."
        docker logs -f "${PROJECT_NAME}-gateway-1"
    fi
}

cmd_down() {
    log_down "Stopping $PROJECT_NAME stack"

    local containers
    containers=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT_NAME" 2>/dev/null || true)

    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs docker stop >/dev/null 2>&1 || true
        echo "$containers" | xargs docker rm >/dev/null 2>&1 || true
        log_down "Containers removed"
    fi

    if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
        docker network rm "$NETWORK_NAME" >/dev/null
        log_down "Network removed"
    fi

    log_down "Stack stopped. Volume '$VOLUME_NAME' preserved."
}

cmd_ps() {
    echo "NAME                      SERVICE    STATUS              PORTS"
    docker ps \
        --filter "label=com.docker.compose.project=$PROJECT_NAME" \
        --format "{{.Names}}\t{{.Label \"com.docker.compose.service\"}}\t{{.Status}}\t{{.Ports}}" \
        2>/dev/null | column -t -s $'\t' || echo "(no containers running)"
}

cmd_logs() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        docker logs -f "${PROJECT_NAME}-${service}-1"
    else
        docker logs -f "${PROJECT_NAME}-gateway-1"
    fi
}

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  up [-d]     Start the stack (use -d to detach)"
    echo "  down        Stop and remove containers"
    echo "  ps          List containers"
    echo "  logs [svc]  Follow logs (default: gateway)"
    echo ""
    echo "A docker-compose replacement written in bash, because YAML is for the weak."
}

case "${1:-}" in
    up)
        shift
        cmd_up "$@"
        ;;
    down)
        cmd_down
        ;;
    ps)
        cmd_ps
        ;;
    logs)
        shift
        cmd_logs "$@"
        ;;
    *)
        usage
        exit 1
        ;;
esac
