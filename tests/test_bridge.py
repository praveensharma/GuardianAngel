import importlib.util
from pathlib import Path
import sys, types, json, tempfile
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
class Surface:
    def __init__(self,song):self._song=song
    def song(self):return self._song
    def schedule_message(self,*args):pass
    def log_message(self,*args):pass
    def disconnect(self):pass
sys.modules['_Framework']=types.ModuleType('_Framework')
m=types.ModuleType('_Framework.ControlSurface');m.ControlSurface=Surface;sys.modules[m.__name__]=m
spec=importlib.util.spec_from_file_location('watchdog',ROOT/'bridge/GuardianAngel/watchdog.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
from types import SimpleNamespace as N
source=N(display_name='Ext. In');channel=N(display_name='7/8 Synth')
t=N(name='Synth',has_audio_input=True,is_foldable=False,input_routing_type=source,input_routing_channel=channel,available_input_routing_types=[source],available_input_routing_channels=[channel],arm=False)
# No meters, monitor or transport attributes: a bridge regression must not depend on any.
song=N(tracks=[t])
with tempfile.TemporaryDirectory() as folder,patch.object(module.os.path,'expanduser',return_value=folder):
    a=module.GuardianAngel(song);b=module.GuardianAngel(song)
    files=list(Path(folder).glob('live-*.json'));assert len(files)==2
    def data():return json.loads((Path(folder)/('live-'+a._session+'.json')).read_text())
    assert data()['schema']==3 and data()['tracks'][0]['routing_verified']
    t.name='Renamed';t.arm=True;a._poll();assert data()['tracks'][0]['arm']
    t.available_input_routing_channels=[channel,N(display_name=channel.display_name)];a._poll();assert not data()['tracks'][0]['routing_verified']
    song.tracks=[];a._poll();assert data()['tracks']==[]
    a.disconnect();assert len(list(Path(folder).glob('live-*.json')))==1
    b.disconnect();assert not list(Path(folder).glob('live-*.json'))
print('Bridge checks passed: routing, no meter/transport dependency, arm/rename, duplicate labels, deletion, multiple sessions, cleanup')
