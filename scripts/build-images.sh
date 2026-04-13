#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# build-images.sh
# Construye las imágenes Docker de todos los servicios.
# Uso: ./scripts/build-images.sh [vote|worker|result|all]
# ──────────────────────────────────────────────────────────────────────────────

set -e

SERVICE=${1:-all}
REGISTRY=${REGISTRY:-"ghcr.io/juanamor8/microservices-demo"}
TAG=${TAG:-"local"}
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Microservices Demo — Build Images ==="
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo ""

build_service() {
  local name=$1
  local context="$ROOT_DIR/$name"
  local image="$REGISTRY/$name:$TAG"

  echo "▶ Building $name → $image"
  docker build -t "$image" "$context"
  echo "✅ $name built successfully"
  echo ""
}

case "$SERVICE" in
  vote)   build_service vote ;;
  worker) build_service worker ;;
  result) build_service result ;;
  all)
    build_service vote
    build_service worker
    build_service result
    echo "✅ Todas las imágenes construidas con tag: $TAG"
    echo ""
    echo "Para publicar en GHCR:"
    echo "  docker push $REGISTRY/vote:$TAG"
    echo "  docker push $REGISTRY/worker:$TAG"
    echo "  docker push $REGISTRY/result:$TAG"
    ;;
  *)
    echo "Uso: $0 [vote|worker|result|all]"
    echo "Variables de entorno opcionales:"
    echo "  REGISTRY=<registry>  (default: ghcr.io/juanamor8/microservices-demo)"
    echo "  TAG=<tag>            (default: local)"
    exit 1
    ;;
esac
