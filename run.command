#!/usr/bin/env bash
# Launcher macOS: crea/riusa il venv, installa le dipendenze SOLO se
# requirements.txt è cambiato (avvio più rapido, niente warning pip), avvia la GUI.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "⚠️  ffmpeg non trovato. Installa con:  brew install ffmpeg"
fi

if [ ! -d ".venv" ]; then
  echo "Creo il virtualenv…"
  python3 -m venv .venv
fi
source .venv/bin/activate

# installa/aggiorna le dipendenze solo alla prima esecuzione o se
# requirements.txt è cambiato dall'ultima volta
REQ_HASH="$(shasum requirements.txt | cut -d' ' -f1)"
MARKER=".venv/.req_hash"
if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$REQ_HASH" ]; then
  echo "Installo/aggiorno le dipendenze…"
  python -m pip install --upgrade pip -q
  pip install -r requirements.txt -q
  echo "$REQ_HASH" > "$MARKER"
fi

exec streamlit run app.py
