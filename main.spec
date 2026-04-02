# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[('App\\qml', 'App\\qml'), ('App\\resources', 'App\\resources'), ('App\\images', 'App\\images'), ('App\\tihan.png', 'App'), ('App\\qml\\translations_ta.qm', 'App'), ('env\\Lib\\site-packages\\PyQt5\\Qt5\\plugins\\platforms', 'platforms'), ('env\\Lib\\site-packages\\PyQt5\\Qt5\\plugins\\imageformats', 'imageformats'), ('env\\Lib\\site-packages\\PyQt5\\Qt5\\plugins\\geoservices', 'geoservices')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='main',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['App\\tihan1.ico'],
)
