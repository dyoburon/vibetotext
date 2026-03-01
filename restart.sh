#!/bin/bash
# Restart VibeToText engine and Electron history app
# Only targets vibetotext-specific processes

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Stopping VibeToText..."
pkill -9 -f "python.*vibetotext" 2>/dev/null
pkill -9 -f "vibetotext/history-app" 2>/dev/null
sleep 1

echo "Starting VibeToText..."
cd "$SCRIPT_DIR"
source .venv/bin/activate
python -m vibetotext &

echo "VibeToText restarted (PID: $!)"
