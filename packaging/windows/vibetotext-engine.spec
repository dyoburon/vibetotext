# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for VibeToText main engine executable (Windows)."""

import os
import sys

block_cipher = None

# Path to the source package (two levels up from packaging/windows/)
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
        'pynput.keyboard._win32',
        'pynput.mouse',
        'pynput.mouse._win32',
        'pystray',
        'pystray._win32',
        'PIL',
        'PIL.Image',
        'PIL.ImageDraw',
        'PIL.ImageFont',
        'dotenv',
        # Optional Gemini support
        'google.generativeai',
        # SQLite for history
        'sqlite3',
        # Standard library modules used by vibetotext
        'json',
        'queue',
        'threading',
        'ctypes',
        'winsound',
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
    console=True,  # Console mode for debug output; set to False for release
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=os.path.join(os.path.dirname(SPEC), 'vibetotext.ico') if os.path.exists(os.path.join(os.path.dirname(SPEC), 'vibetotext.ico')) else None,
)
