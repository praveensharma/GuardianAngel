"""Read-only bridge for GuardianAngel friend beta. No audio metering or Live writes."""
import json
import os
import time
import uuid
from _Framework.ControlSurface import ControlSurface

class GuardianAngel(ControlSurface):
    def __init__(self, c_instance):
        super(GuardianAngel, self).__init__(c_instance)
        self._closed = False
        self._session = str(uuid.uuid4())
        self._folder = os.path.expanduser('~/Library/Application Support/GuardianAngel')
        os.makedirs(self._folder, exist_ok=True)
        self._poll()

    def _poll(self):
        if self._closed:
            return
        result = {'schema': 3, 'session': self._session, 'timestamp': time.time(),
                  'status': 'Connected', 'tracks': []}
        try:
            for track in self.song().tracks:
                row = {'name': str(track.name)}
                try:
                    if not track.has_audio_input or track.is_foldable:
                        continue
                    typ, channel = track.input_routing_type, track.input_routing_channel
                    row.update(input=str(typ.display_name), pair=str(channel.display_name), arm=bool(track.arm))
                    if row['input'] == 'Ext. In':
                        types = list(track.available_input_routing_types)
                        channels = list(track.available_input_routing_channels)
                        row['routing_verified'] = (
                            sum(x == typ for x in types) == 1 and
                            sum(x == channel for x in channels) == 1 and
                            sum(str(x.display_name) == row['input'] for x in types) == 1 and
                            sum(str(x.display_name) == row['pair'] for x in channels) == 1)
                except Exception as exc:
                    row['error'] = str(exc)
                result['tracks'].append(row)
        except Exception as exc:
            result.update(status='Unavailable', error=str(exc), tracks=[])
        try:
            # Separate session files prevent two open Live instances overwriting one another.
            target = os.path.join(self._folder, 'live-' + self._session + '.json')
            with open(target + '.tmp', 'w') as stream:
                json.dump(result, stream)
            os.replace(target + '.tmp', target)
        except Exception as exc:
            self.log_message('GuardianAngel bridge write failed: ' + str(exc))
        self.schedule_message(5, self._poll)

    def disconnect(self):
        self._closed = True
        try:
            os.unlink(os.path.join(self._folder, 'live-' + self._session + '.json'))
        except OSError:
            pass
        super(GuardianAngel, self).disconnect()
