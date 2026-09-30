#!/usr/bin/env bash
# Build the Go host -> build/hosts/go-host
# Needs: Go >= 1.24, a C compiler (wasmtime-go uses cgo) and network access to fetch the module.
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
mkdir -p "$HOST_DIR"

cd "$ROOT/hosts/go"
[ -f go.sum ] || go mod tidy
CGO_ENABLED=1 go build -o "$HOST_DIR/go-host" .

echo "built $HOST_DIR/go-host"
