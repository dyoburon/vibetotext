# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for VibeToText waveform overlay UI executable (Windows)."""

import os

block_cipher = None

# Path to the source package (two levels up from packaging/windows/)
src_path = os.path.join(os.path.dirname(SPEC), '..', '..', 'src')

a = Analysis(
    [os.path.join(src_path, 'vibetotext', 'ui_tkinter.py')],
    pathex=[src_path],
    binaries=[],
    datas=[],
    hiddenimports=[
        'tkinter',
        'tkinter.ttk',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Not needed for the UI overlay
        'sounddevice',
        'pywhispercpp',
        'numpy',
        'pynput',
        'google',
        'AppKit',
        'Foundation',
        'Quartz',
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
    name='vibetotext-ui',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # Windowed mode - no console window for the overlay
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=os.path.join(os.path.dirname(SPEC), 'vibetotext.ico') if os.path.exists(os.path.join(os.path.dirname(SPEC), 'vibetotext.ico')) else None,
)
