#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# deploy-local.sh
# Despliega todos los servicios localmente usando Docker Compose.
# Uso: ./scripts/deploy-local.sh [up|down|logs|status]
# ──────────────────────────────────────────────────────────────────────────────

set -e

ACTION=${1:-up}
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Microservices Demo — Deploy Local ==="
echo "Acción: $ACTION"
echo "Directorio: $ROOT_DIR"
echo ""

case "$ACTION" in
  up)
    echo "▶ Construyendo imágenes y levantando servicios..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" up --build -d

    echo ""
    echo "⏳ Esperando que los servicios estén listos..."
    sleep 10

    echo ""
    echo "✅ Servicios disponibles:"
    echo "   → Vote:   http://localhost:8080"
    echo "   → Result: http://localhost:4000"
    echo ""
    echo "Para ver los logs: ./scripts/deploy-local.sh logs"
    ;;

  down)
    echo "⏹ Deteniendo todos los servicios..."
    docker compose -f "$ROOT_DIR/docker-compose.yml" down -v
    echo "✅ Servicios detenidos y volúmenes eliminados"
    ;;

  logs)
    SERVICE=${2:-""}
    if [ -n "$SERVICE" ]; then
      echo "📋 Logs de $SERVICE:"
      docker compose -f "$ROOT_DIR/docker-compose.yml" logs -f "$SERVICE"
    else
      echo "📋 Logs de todos los servicios:"
      docker compose -f "$ROOT_DIR/docker-compose.yml" logs -f
    fi
    ;;

  status)
    echo "📊 Estado de los servicios:"
    docker compose -f "$ROOT_DIR/docker-compose.yml" ps
    ;;

  restart)
    SERVICE=${2:-""}
    if [ -n "$SERVICE" ]; then
      echo "🔄 Reiniciando $SERVICE..."
      docker compose -f "$ROOT_DIR/docker-compose.yml" restart "$SERVICE"
    else
      echo "🔄 Reiniciando todos los servicios..."
      docker compose -f "$ROOT_DIR/docker-compose.yml" restart
    fi
    ;;

  *)
    echo "Uso: $0 [up|down|logs|status|restart]"
    echo ""
    echo "  up              Construye y levanta todos los servicios"
    echo "  down            Detiene y elimina contenedores y volúmenes"
    echo "  logs [servicio] Muestra logs (vote, worker, result, kafka, postgresql)"
    echo "  status          Muestra el estado de todos los servicios"
    echo "  restart [svc]   Reinicia un servicio específico o todos"
    exit 1
    ;;
esac
