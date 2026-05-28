#!/usr/bin/env bash
# Build the API image and push it to Docker Hub under hindurable/nurl:latest.
# Run from the repo root. Requires `docker login` to have been done once.
set -euo pipefail

IMAGE="hindurable/nurl:latest"

cd "$(dirname "$0")"

docker build -f nurlapi/Dockerfile -t "$IMAGE" .
docker push "$IMAGE"
