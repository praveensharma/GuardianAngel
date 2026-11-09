#!/usr/bin/env python3
"""Single-source native macOS friend-beta builder. Does not modify Live or install scripts."""
from pathlib import Path
import json, plistlib, shutil, subprocess, tempfile, hashlib
ROOT=Path(__file__).resolve().parents[1]
def run(*args):subprocess.run(args,check=True)
def build():
    app=ROOT/'GuardianAngel.app'
    contents=app/'Contents';binary=contents/'MacOS/GuardianAngel'
    binary.parent.mkdir(parents=True,exist_ok=True)
    resources=contents/'Resources';resources.mkdir(exist_ok=True)
    # One source of truth: bridge is copied to the app for one-click installation.
    target=resources/'GuardianAngel'
    if target.exists():shutil.rmtree(target)
    shutil.copytree(ROOT/'bridge/GuardianAngel',target,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    info={'CFBundleExecutable':'GuardianAngel','CFBundleIdentifier':'studio.guardianangel.watchdog','CFBundleName':'GuardianAngel',
          'CFBundleDisplayName':'GuardianAngel','CFBundlePackageType':'APPL','CFBundleVersion':'0.6','CFBundleShortVersionString':'0.6',
          'LSUIElement':True,'LSMinimumSystemVersion':'13.0',
          'NSMicrophoneUsageDescription':'GuardianAngel measures input levels locally to warn about disarmed Ableton tracks. Audio is never saved or transmitted.'}
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    with tempfile.TemporaryDirectory(prefix='guardianangel-build-') as scratch:
        work=Path(scratch);outputs=[]
        for arch in ('arm64','x86_64'):
            output=work/arch;outputs.append(str(output))
            run('swiftc','-O','-module-cache-path',str(Path(tempfile.gettempdir())/('guardianangel-swift-modules-'+arch)),'-target',arch+'-apple-macos13.0',
                *map(str,sorted((ROOT/'src').glob('*.swift'))),'-o',str(output),'-framework','Cocoa','-framework','CoreAudio','-framework','AVFoundation')
        run('lipo','-create',*outputs,'-output',str(binary))
    run('codesign','--force','--sign','-',str(app))
    run('codesign','--verify','--deep','--strict',str(app))
    release=ROOT/'releases';release.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='guardianangel-package-') as scratch:
        folder=Path(scratch)/'GuardianAngel';folder.mkdir()
        shutil.copytree(app,folder/app.name)
        for name in ('START_HERE.md','TEST_REPORT.md'):shutil.copy2(ROOT/name,folder/name)
        zipfile=release/'GuardianAngel-0.6-friend-beta.zip'
        run('ditto','-c','-k','--sequesterRsrc','--keepParent',str(folder),str(zipfile))
        (release/'SHA256.txt').write_text(hashlib.sha256(zipfile.read_bytes()).hexdigest()+'  '+zipfile.name+'\n')
    print('Built',app,'and',zipfile)
if __name__=='__main__':build()
