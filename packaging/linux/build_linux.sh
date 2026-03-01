#!/bin/bash
# Build script for VibeToText on Linux
# Run from the project root: bash packaging/linux/build_linux.sh
#
# Prerequisites:
#   - Python 3.10+
#   - System packages: python3-tk, portaudio19-dev (or equivalent)
#   - For clipboard: xclip or wl-clipboard
#   - For paste: xdotool (X11) or wtype (Wayland)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Building VibeToText for Linux ==="
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

# Check system dependencies
echo "Checking system dependencies..."
python3 -c "import tkinter" 2>/dev/null || {
    echo "ERROR: python3-tk not installed."
    echo "  Ubuntu/Debian: sudo apt install python3-tk"
    echo "  Fedora:        sudo dnf install python3-tkinter"
    echo "  Arch:          sudo pacman -S tk"
    exit 1
}

# Check for audio library
if ! pkg-config --exists portaudio-2.0 2>/dev/null; then
    echo "WARNING: portaudio not found. You may need to install it:"
    echo "  Ubuntu/Debian: sudo apt install portaudio19-dev"
    echo "  Fedora:        sudo dnf install portaudio-devel"
    echo "  Arch:          sudo pacman -S portaudio"
fi

# Create virtual environment if needed
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

source .venv/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install -e ".[gemini,build]" --quiet

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
pyinstaller packaging/linux/vibetotext-engine.spec --noconfirm --distpath dist --workpath pyinstaller_build

echo
echo "=== Linux build complete! ==="
echo "  - dist/vibetotext-engine"
echo
echo "Optional system packages for full functionality:"
echo "  Clipboard: xclip, xsel, or wl-clipboard"
echo "  Paste:     xdotool (X11) or wtype (Wayland)"
echo "  Sound:     pulseaudio-utils (paplay) or alsa-utils (aplay)"
echo
