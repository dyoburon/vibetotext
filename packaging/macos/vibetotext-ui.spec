# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for VibeToText UI subprocess (macOS)."""

import os

block_cipher = None

# Path to the source package (two levels up from packaging/macos/)
src_path = os.path.join(os.path.dirname(SPEC), '..', '..', 'src')

a = Analysis(
    [os.path.join(src_path, 'vibetotext', 'ui_standalone.py')],
    pathex=[src_path],
    binaries=[],
    datas=[],
    hiddenimports=[
        # PyObjC for macOS UI
        'AppKit',
        'Foundation',
        'Quartz',
        'objc',
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

# Single-file executable for the UI
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='vibetotext-ui',
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
