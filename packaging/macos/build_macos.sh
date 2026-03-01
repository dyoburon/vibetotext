#!/bin/bash
# Build script for VibeToText on macOS
# Run from the project root: bash packaging/macos/build_macos.sh
#
# Prerequisites:
#   - Python 3.10+
#   - Xcode command line tools (for PyObjC)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Building VibeToText for macOS ==="
echo "Project root: $PROJECT_ROOT"
echo

cd "$PROJECT_ROOT"

# Check Python
if ! command -v python3 &>/dev/null; then
    echo "ERROR: Python 3 not found."
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Python version: $PYTHON_VERSION"

# Create virtual environment if needed
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

source .venv/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install -e ".[gemini]" --quiet
pip install pyinstaller pyobjc --quiet

# Download whisper model if needed
echo
echo "Checking whisper model..."
python3 -c "from pywhispercpp.model import Model; Model('base')" 2>/dev/null || {
    echo "Downloading whisper base model..."
    python3 -c "from pywhispercpp.model import Model; Model('base')"
}

# Build main engine
echo
echo "Building main engine executable..."
pyinstaller packaging/macos/vibetotext-engine.spec --noconfirm --distpath dist --workpath pyinstaller_build

# Build UI
echo
echo "Building UI overlay executable..."
pyinstaller packaging/macos/vibetotext-ui.spec --noconfirm --distpath dist --workpath pyinstaller_build

echo
echo "=== macOS build complete! ==="
echo "  - dist/vibetotext-engine"
echo "  - dist/vibetotext-ui"
echo
