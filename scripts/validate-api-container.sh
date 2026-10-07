#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
  pwd
)"

IMAGE="sre-observability-api:ci"
CONTAINER="sre-observability-api-ci-test"
KEEP_IMAGE="${KEEP_IMAGE:-false}"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

  if [[ "$KEEP_IMAGE" != "true" ]]; then
    docker image rm "$IMAGE" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

cd "$ROOT_DIR"

echo "===== BUILD CONTAINER ====="

docker build \
  --pull=false \
  --tag "$IMAGE" \
  app

echo
echo "===== VERIFY IMAGE USER ====="

IMAGE_USER="$(
  docker image inspect \
    "$IMAGE" \
    --format '{{.Config.User}}'
)"

echo "configured_user=$IMAGE_USER"

if [[ "$IMAGE_USER" != "node" ]]; then
  echo "FAIL: image must use node user"
  exit 1
fi

echo "PASS: image uses non-root node user"

echo
echo "===== START HARDENED CONTAINER ====="

docker run \
  --detach \
  --name "$CONTAINER" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 256m \
  --cpus 0.50 \
  --pids-limit 100 \
  --publish 127.0.0.1::3000 \
  "$IMAGE" \
  >/dev/null

HOST_PORT="$(
  docker port "$CONTAINER" 3000/tcp \
    | awk -F: '{print $NF}' \
    | head -1
)"

if [[ -z "$HOST_PORT" ]]; then
  echo "FAIL: unable to determine mapped API port"
  exit 1
fi

BASE_URL="http://127.0.0.1:${HOST_PORT}"

echo "base_url=$BASE_URL"

echo
echo "===== WAIT FOR API ====="

READY=0

for i in $(seq 1 30); do
  if curl \
    --silent \
    --fail \
    "${BASE_URL}/healthz" \
    >/dev/null 2>&1; then

    READY=1
    break
  fi

  sleep 1
done

if [[ "$READY" -ne 1 ]]; then
  echo "FAIL: API did not become ready"
  docker logs "$CONTAINER"
  exit 1
fi

echo "PASS: API responding"

echo
echo "===== VERIFY NON-ROOT ====="

RUNTIME_UID="$(
  docker exec "$CONTAINER" id -u
)"

echo "runtime_uid=$RUNTIME_UID"

if [[ "$RUNTIME_UID" -eq 0 ]]; then
  echo "FAIL: runtime user is root"
  exit 1
fi

echo "PASS: runtime is non-root"

echo
echo "===== VERIFY RUNTIME HARDENING ====="

READ_ONLY="$(
  docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.ReadonlyRootfs}}'
)"

CAP_DROP="$(
  docker inspect \
    "$CONTAINER" \
    --format '{{json .HostConfig.CapDrop}}'
)"

SECURITY_OPT="$(
  docker inspect \
    "$CONTAINER" \
    --format '{{json .HostConfig.SecurityOpt}}'
)"

MEMORY="$(
  docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.Memory}}'
)"

NANO_CPUS="$(
  docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.NanoCpus}}'
)"

PIDS_LIMIT="$(
  docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.PidsLimit}}'
)"

echo "ReadonlyRootfs=$READ_ONLY"
echo "CapDrop=$CAP_DROP"
echo "SecurityOpt=$SECURITY_OPT"
echo "Memory=$MEMORY"
echo "NanoCPUs=$NANO_CPUS"
echo "PidsLimit=$PIDS_LIMIT"

[[ "$READ_ONLY" == "true" ]] || {
  echo "FAIL: root filesystem is not read-only"
  exit 1
}

[[ "$CAP_DROP" == '["ALL"]' ]] || {
  echo "FAIL: all Linux capabilities were not dropped"
  exit 1
}

grep -q 'no-new-privileges:true' <<< "$SECURITY_OPT" || {
  echo "FAIL: no-new-privileges is missing"
  exit 1
}

[[ "$MEMORY" -eq 268435456 ]] || {
  echo "FAIL: unexpected memory limit"
  exit 1
}

[[ "$NANO_CPUS" -eq 500000000 ]] || {
  echo "FAIL: unexpected CPU limit"
  exit 1
}

[[ "$PIDS_LIMIT" -eq 100 ]] || {
  echo "FAIL: unexpected PID limit"
  exit 1
}

echo "PASS: runtime hardening verified"

echo
echo "===== VERIFY SERVICE ENDPOINTS ====="

curl \
  --silent \
  --fail \
  "${BASE_URL}/healthz" \
  >/dev/null

curl \
  --silent \
  --fail \
  "${BASE_URL}/readyz" \
  >/dev/null

curl \
  --silent \
  --fail \
  "${BASE_URL}/api/work" \
  >/dev/null

echo "PASS: service endpoints healthy"

echo
echo "===== VERIFY FAULT INJECTION DEFAULT ====="

FAULT_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${BASE_URL}/api/error"
)"

echo "fault_status=$FAULT_STATUS"

if [[ "$FAULT_STATUS" != "403" ]]; then
  echo "FAIL: fault injection must be disabled by default"
  exit 1
fi

echo "PASS: fault injection disabled"

echo
echo "===== VERIFY METRICS ====="

METRICS="$(
  curl \
    --silent \
    --fail \
    "${BASE_URL}/metrics"
)"

grep -q \
  'sre_lab_http_requests_total' \
  <<< "$METRICS" || {
    echo "FAIL: request counter missing"
    exit 1
  }

grep -q \
  'sre_lab_http_request_duration_seconds' \
  <<< "$METRICS" || {
    echo "FAIL: request duration histogram missing"
    exit 1
  }

echo "PASS: RED metrics exposed"

echo
echo "===== VERIFY HEALTHCHECK ====="

HEALTH=""

for i in $(seq 1 30); do
  HEALTH="$(
    docker inspect \
      "$CONTAINER" \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}'
  )"

  if [[ "$HEALTH" == "healthy" ]]; then
    break
  fi

  sleep 1
done

echo "health=$HEALTH"

if [[ "$HEALTH" != "healthy" ]]; then
  echo "FAIL: Docker healthcheck did not become healthy"
  exit 1
fi

echo "PASS: Docker healthcheck healthy"

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: hardened API container validation succeeded"
