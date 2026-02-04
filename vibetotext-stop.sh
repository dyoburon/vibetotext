#!/bin/bash

# VibeToText Stream Teardown Script
# Cross-platform shutdown script for Linux and macOS

# Auto-detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR"
PID_FILE="$BASE/.vibetotext.pid"

echo "Stopping VibeToText..."

# Try to use PID file first for clean shutdown
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Killing VibeToText process (PID: $PID)..."
        kill -9 "$PID" 2>/dev/null
    fi
    rm "$PID_FILE"
fi

# Fallback: kill by pattern (main vibetotext only, NOT history-app)
# This matches "python.*vibetotext" but NOT "vibetotext/history-app"
pkill -9 -f "python.*vibetotext" 2>/dev/null

sleep 1

echo "VibeToText teardown complete!"
