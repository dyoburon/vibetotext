#!/bin/bash

# VibeToText Stream Startup Script
# Cross-platform startup script for Linux and macOS

# Auto-detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
PID_FILE="$BASE/.vibetotext.pid"

echo "Starting VibeToText..."
echo "Project directory: $BASE"

# Check if virtual environment exists
if [ ! -d "$BASE/.venv" ]; then
    echo "Error: Virtual environment not found at $BASE/.venv"
    echo "Please run: python -m venv .venv && source .venv/bin/activate && pip install -e ."
    exit 1
fi

# Clean up stale PID file if process is not running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ! ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Removing stale PID file..."
        rm "$PID_FILE"
    else
        echo "Warning: VibeToText may already be running (PID: $OLD_PID)"
        echo "If this is incorrect, run vibetotext-stop.sh first"
        exit 1
    fi
fi

# Start VibeToText
cd "$BASE" || exit 1
source .venv/bin/activate
python -m vibetotext &
VIBE_PID=$!

# Save PID
echo "$VIBE_PID" > "$PID_FILE"

echo ""
echo "Waiting for VibeToText to initialize..."
sleep 3

# Verify process is still running
if ps -p "$VIBE_PID" > /dev/null 2>&1; then
    echo "VibeToText startup complete! (PID: $VIBE_PID)"
else
    echo "Error: VibeToText process failed to start"
    rm -f "$PID_FILE"
    exit 1
fi
