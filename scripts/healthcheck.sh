#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# healthcheck.sh
# Verifica que todos los servicios estén respondiendo correctamente.
# Uso: ./scripts/healthcheck.sh
# ──────────────────────────────────────────────────────────────────────────────

VOTE_URL=${VOTE_URL:-"http://localhost:8080"}
RESULT_URL=${RESULT_URL:-"http://localhost:4000"}

echo "=== Microservices Demo — Health Check ==="
echo ""

check_http() {
  local name=$1
  local url=$2
  local code

  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
  if [ "$code" = "200" ]; then
    echo "✅ $name ($url) → HTTP $code OK"
  else
    echo "❌ $name ($url) → HTTP $code FAIL"
  fi
}

check_container() {
  local name=$1
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "running")
    echo "✅ Container $name → $status"
  else
    echo "❌ Container $name → NOT RUNNING"
  fi
}

echo "--- Containers ---"
check_container postgresql
check_container kafka
check_container vote
check_container worker
check_container result

echo ""
echo "--- HTTP Endpoints ---"
check_http "Vote UI"   "$VOTE_URL"
check_http "Result UI" "$RESULT_URL"

echo ""
echo "--- PostgreSQL ---"
if docker exec postgresql pg_isready -U okteto -d votes > /dev/null 2>&1; then
  echo "✅ PostgreSQL → accepting connections"
  VOTE_COUNT=$(docker exec postgresql psql -U okteto -d votes -t -c "SELECT COUNT(*) FROM votes;" 2>/dev/null | tr -d ' \n' || echo "N/A")
  echo "   Total votos registrados: $VOTE_COUNT"
else
  echo "❌ PostgreSQL → not ready"
fi
