#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
  pwd
)"

PROM_IMAGE="prom/prometheus@sha256:6976aa8a60fec930796ce5772b8d12da7a318a5daa8d40d69c5c7819a05eeed7"

cd "$ROOT_DIR"

echo "===== PROMETHEUS CONFIG ====="

docker run \
  --rm \
  --entrypoint /bin/promtool \
  --volume "$ROOT_DIR/observability/prometheus:/etc/prometheus:ro" \
  "$PROM_IMAGE" \
  check config /etc/prometheus/prometheus.yml

echo "PASS: Prometheus configuration valid"

echo
echo "===== PROMETHEUS RULES ====="

docker run \
  --rm \
  --entrypoint /bin/promtool \
  --volume "$ROOT_DIR/observability/prometheus:/etc/prometheus:ro" \
  "$PROM_IMAGE" \
  check rules /etc/prometheus/recording-rules.yml

echo "PASS: Prometheus recording rules valid"

echo
echo "===== DOCKER COMPOSE ====="

docker compose config --quiet

echo "PASS: Docker Compose configuration valid"

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: Prometheus validation succeeded"
