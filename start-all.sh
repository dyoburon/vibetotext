#!/bin/bash

# Start History App and VibeToText

BASE="$(cd "$(dirname "$0")" && pwd)"

echo "Starting History App..."
cd "$BASE/history-app" && npm start &

sleep 2

echo "Starting VibeToText..."
cd "$BASE" && source .venv/bin/activate && python -m vibetotext --model large-v3-turbo &

sleep 3

echo "All services started!"
