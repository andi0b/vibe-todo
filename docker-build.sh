#!/bin/bash
# Build Docker images the bash way - no Dockerfiles allowed
set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_DIR="$SCRIPT_DIR/todo-microservices"
BASE_IMAGE="alpine:3.23"
IMAGE_PREFIX="vibe-todo"

step=0
image_id=""

log() { echo -e "\033[1;35m==>\033[0m $*"; }
step_log() { ((++step)); echo "Step $step : $*"; }

build_layer() {
    local instruction="$1"
    shift
    local args=("$@")
    local container_id=""
    local change=()

    step_log "$instruction ${args[*]}"

    case "$instruction" in
        FROM)
            if [[ -z "$(docker images -q "${args[0]}" 2>/dev/null)" ]]; then
                docker pull "${args[0]}"
            fi
            image_id=$(docker inspect "${args[0]}" --format '{{ .Id }}')
            ;;
        RUN)
            container_id=$(docker create "$image_id" /bin/sh -c "${args[*]}")
            docker start -a "$container_id"
            ;;
        WORKDIR)
            container_id=$(docker create "$image_id" /bin/sh -c "mkdir -p ${args[0]}")
            docker start -a "$container_id" 2>/dev/null || true
            change=(-c "WORKDIR ${args[0]}")
            ;;
        COPY)
            local src="${args[0]}"
            local dest="${args[1]}"
            container_id=$(docker create "$image_id" /bin/sh -c "true")
            docker cp "$src" "$container_id:$dest"
            ;;
        CMD)
            container_id=$(docker create "$image_id" /bin/sh -c "true")
            change=(-c "CMD ${args[*]}")
            ;;
        *)
            echo "Unknown instruction: $instruction" >&2
            return 1
            ;;
    esac

    if [[ -n "$container_id" ]]; then
        printf " ---> Running in %.12s\n" "$container_id"
        image_id=$(docker commit "${change[@]}" "$container_id")
        docker rm "$container_id" >/dev/null
    fi
    printf " ---> %.12s\n" "${image_id#sha256:}"
}

tag_image() {
    local name="$1"
    docker tag "$image_id" "$name"
    log "Tagged $name"
}

build_service() {
    local name="$1"
    local script="$2"
    local script_path="$SERVICE_DIR/$name/$script"

    log "Building $IMAGE_PREFIX-$name"
    step=0
    image_id=""

    build_layer FROM "$BASE_IMAGE"
    build_layer RUN "apk add --no-cache bash netcat-openbsd"
    build_layer WORKDIR "/app"
    build_layer COPY "$script_path" "/app/$script"
    build_layer RUN "chmod +x /app/$script"
    build_layer CMD "[\"/app/$script\"]"

    tag_image "$IMAGE_PREFIX-$name"
    echo ""
}

cleanup() {
    docker ps -aq --filter "status=created" | xargs -r docker rm >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Building images without Dockerfiles because we have principles"
echo ""

build_service "storage-service" "storage.sh"
build_service "bashis-service" "bashis.sh"
build_service "todo-service" "todo.sh"
build_service "frontend-service" "frontend.sh"
build_service "api-gateway" "gateway.sh"

# LLM service needs special handling (multiple files + model)
build_llm_service() {
    local name="llm-service"
    local svc_dir="$SERVICE_DIR/$name"

    log "Building $IMAGE_PREFIX-$name (the transformer in bash)"
    step=0
    image_id=""

    build_layer FROM "$BASE_IMAGE"
    build_layer RUN "apk add --no-cache bash netcat-openbsd"
    build_layer WORKDIR "/app"

    # Copy lib directory
    build_layer COPY "$svc_dir/lib" "/app/lib"
    build_layer RUN "chmod +x /app/lib/*.sh"

    # Copy main script
    build_layer COPY "$svc_dir/llm.sh" "/app/llm.sh"
    build_layer RUN "chmod +x /app/llm.sh"

    # Copy model if it exists (optional - can mount at runtime)
    if [[ -d "$svc_dir/model" ]]; then
        build_layer COPY "$svc_dir/model" "/app/model"
    fi

    build_layer CMD "[\"/app/llm.sh\"]"

    tag_image "$IMAGE_PREFIX-$name"
    echo ""
}

build_llm_service

log "All images built. Dockerfiles remain unwritten."
docker images | grep "$IMAGE_PREFIX"
