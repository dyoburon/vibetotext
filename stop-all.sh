#!/bin/bash

# Stop History App and VibeToText

echo "Stopping VibeToText..."
pkill -9 -f "python.*vibetotext" 2>/dev/null

echo "Stopping History App..."
pkill -9 -f "vibetotext/history-app" 2>/dev/null

sleep 1

echo "All services stopped!"
