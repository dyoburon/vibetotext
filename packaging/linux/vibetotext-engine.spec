# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for VibeToText main engine executable (Linux)."""

import os
import sys

block_cipher = None

# Path to the source package (two levels up from packaging/linux/)
src_path = os.path.join(os.path.dirname(SPEC), '..', '..', 'src')

a = Analysis(
    [os.path.join(src_path, 'vibetotext', '__main__.py')],
    pathex=[src_path],
    binaries=[],
    datas=[
        # Bundle the tkinter UI script so the engine can spawn it as a subprocess
        (os.path.join(src_path, 'vibetotext', 'ui_tkinter.py'), 'vibetotext'),
        # Bundle the history tkinter UI script
        (os.path.join(src_path, 'vibetotext', 'history_ui_tkinter.py'), 'vibetotext'),
    ],
    hiddenimports=[
        'sounddevice',
        'pywhispercpp',
        'pywhispercpp.model',
        'numpy',
        'pyperclip',
        'pynput',
        'pynput.keyboard',
        'pynput.keyboard._xorg',
        'pynput.mouse',
        'pynput.mouse._xorg',
        'dotenv',
        # Sentiment analysis
        'vaderSentiment',
        'vaderSentiment.vaderSentiment',
        # Optional Gemini support
        'google.genai',
        # SQLite for history
        'sqlite3',
        # Tkinter for UI
        'tkinter',
        'tkinter.ttk',
        # Standard library modules used by vibetotext
        'json',
        'queue',
        'threading',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # macOS-only modules
        'AppKit',
        'Foundation',
        'Quartz',
        'ApplicationServices',
        'PyObjCTools',
        'objc',
        # Windows-only modules
        'winsound',
        'pystray',
        'pystray._win32',
        'pynput.keyboard._win32',
        'pynput.mouse._win32',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

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
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # Console mode for Linux
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
