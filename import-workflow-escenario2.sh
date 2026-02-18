#!/usr/bin/env bash
set -euo pipefail

echo "[DEPRECATED] No usar import manual para evitar duplicados en n8n."
echo "Usa unicamente: powershell -File ./scripts/sync-workflows.ps1"
exit 1