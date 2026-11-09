#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
def run(*args):subprocess.run(args,check=True)
run('python3',str(root/'tests/test_bridge.py'))
with tempfile.TemporaryDirectory(prefix='guardianangel-check-') as folder:
    binary=str(Path(folder)/'test')
    run('swiftc','-O','-module-cache-path',str(Path(folder)/'cache'),str(root/'src/Model.swift'),str(root/'src/Audio.swift'),str(root/'tests/model/main.swift'),'-o',binary,'-framework','CoreAudio')
    run(binary)
# Audio safety: only register/read input buffers; no APIs that set Live/driver properties.
source=(root/'src/Audio.swift').read_text()
assert 'AudioObjectSetPropertyData' not in source
bridge=(root/'bridge/GuardianAngel/watchdog.py').read_text()
assert '.arm =' not in bridge and '.current_monitoring_state =' not in bridge
assert 'input_meter_' not in bridge
print('Read-only routing/API source checks passed')
