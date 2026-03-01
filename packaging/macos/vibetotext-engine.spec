# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for VibeToText engine (macOS)."""

import os

block_cipher = None

# Path to the source package (two levels up from packaging/macos/)
src_path = os.path.join(os.path.dirname(SPEC), '..', '..', 'src')

a = Analysis(
    [os.path.join(src_path, 'vibetotext', '__main__.py')],
    pathex=[src_path],
    binaries=[],
    datas=[],
    hiddenimports=[
        # Core dependencies
        'numpy',
        'sounddevice',
        'pynput',
        'pynput.keyboard',
        'pynput.keyboard._darwin',
        'pyperclip',
        'pywhispercpp',
        'pywhispercpp.model',
        # Sentiment analysis
        'vaderSentiment',
        'vaderSentiment.vaderSentiment',
        # Google AI for LLM
        'google.genai',
        # PyObjC for macOS UI
        'AppKit',
        'Foundation',
        'Quartz',
        'objc',
        # All vibetotext modules
        'vibetotext',
        'vibetotext.recorder',
        'vibetotext.transcriber',
        'vibetotext.context',
        'vibetotext.output',
        'vibetotext.greppy',
        'vibetotext.llm',
        'vibetotext.history',
        'vibetotext.history_ui',
        'vibetotext.ui',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# Single-file executable for embedding in Electron app
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='vibetotext-engine',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,  # No terminal window
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
