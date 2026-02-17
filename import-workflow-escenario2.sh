#!/usr/bin/env bash
# Importa el workflow "Escenario 2 — KW orgánicas" en tu n8n local vía API.
# Requisitos: .env con N8N_API_URL y N8N_API_KEY (y n8n en marcha).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ No existe .env. Copia .env.example a .env y añade N8N_API_KEY."
  exit 1
fi

# Cargar .env (exporta solo N8N_*)
set -a
source .env 2>/dev/null || true
set +a

URL="${N8N_API_URL:-http://localhost:5678}"
KEY="${N8N_API_KEY:-}"

if [ -z "$KEY" ]; then
  echo "❌ En .env falta N8N_API_KEY."
  echo "   Genera una en n8n: Settings → API → Create an API key."
  exit 1
fi

WORKFLOW_JSON="workflow-escenario2-kw-organicas-slack.json"
if [ ! -f "$WORKFLOW_JSON" ]; then
  echo "❌ No encontrado: $WORKFLOW_JSON"
  exit 1
fi

echo "📤 Enviando workflow a $URL ..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${URL}/api/v1/workflows" \
  -H "X-N8N-API-KEY: $KEY" \
  -H "Content-Type: application/json" \
  -d @"$WORKFLOW_JSON")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Workflow creado en n8n. Ábrelo en: $URL/workflow/..."
  echo "$BODY" | head -c 200
  echo "..."
else
  echo "❌ Error HTTP $HTTP_CODE"
  echo "$BODY"
  exit 1
fi
