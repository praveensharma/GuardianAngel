# GuardianAngel

Warns when sustained audio reaches an input assigned to an Ableton track and no track receiving that channel is armed. Monitor Off works with direct interface monitoring. Arrangement Record and transport do not affect alerts.

GuardianAngel 0.6 is a macOS menu bar app plus an Ableton Live Remote Script.
You need macOS 13 or later, Live 12, and a Core Audio interface used by both
apps. It watches input levels while the Live script reports which tracks are
armed.

## Get the app

Use the supplied friend-beta ZIP if you have it. To build from this repository,
install Xcode or Apple's Command Line Tools and run:

```sh
python3 tools/test.py
python3 tools/build.py
```

The build produces `GuardianAngel.app` and a ZIP in `releases/`.

## Setup

1. Quit any earlier GuardianAngel. Put GuardianAngel.app in Applications and open it. This informal build is locally signed, not Developer ID signed or notarized; macOS may block downloaded builds. If macOS won't open it through its normal Open workflow, stop and send the exact message to the developer. Do not disable system security.
2. Click GuardianAngel in the menu bar → **Install Live extension…**. Select your Ableton **User Library** folder. The installer creates its Remote Scripts folder and backs up any previous GuardianAngel extension.
3. Restart Live when convenient. In Settings → Tempo & MIDI, select **GuardianAngel** in ONE unused Control Surface slot. MIDI Input and Output stay **None**. Preserve other control surfaces.
4. In GuardianAngel → **Audio interface**, choose the same input device used by Live. Confirm the device and grant Microphone permission if macOS asks. GuardianAngel reads levels locally; it saves no audio and sends nothing over the network.
5. Choose **Show input mappings…** and check that input numbers match Live. Play a known input with its track disarmed and Monitor Off: expect a warning. Arm the track: expect the current warning to resolve. Acknowledge removes earlier warnings; an unresolved current warning remains visible.

No track devices, binding buttons, virtual audio drivers or detector tracks are needed. Launch GuardianAngel manually during this test; automatic login startup is not enabled.

## Important assumptions

- **Live must use the same input interface you selected.** The extension cannot verify Live's selected audio-device UID.
- **Numbered Live input labels must correspond to physical device channels.** Labels such as `1`, `1/2`, or `21/22 REAMP` resolve automatically. A label like `Synth` without numbers stays unresolved. Numeric prefixes are an explicit beta convention, not guaranteed universal routing IDs. Confirm one known signal after setup or device changes. No per-track manual mapping is required for supported numbered labels.
- Track names and ordering do not determine coverage. A mono destination covers one channel, a stereo destination covers both. Any armed destination for a channel suppresses its alert.
- Channels without corresponding external-input tracks are outside this beta's alert scope. Unresolved inputs remain visible in the mapping status and do not produce disarm alerts.
- Changed input count/layout requires confirming the interface again. Reconnection and supported sample-rate changes are retried automatically. Live I/O enable/disable changes are re-read; physical numbers are never compacted to dropdown positions.

## Compatibility and limits

macOS 13 or newer; Apple Silicon and Intel executables are included. Intel is compiled but not runtime-tested. Ableton Live 12 with English `Ext. In` routing labels. CoreAudio input devices with packed native little-endian Float32 or Float64 PCM, consistent stream formats, at most 512 inputs, 8–384 kHz. Unsupported formats or drivers that prevent simultaneous input access show Unavailable. Different hardware remains unverified until tested.

Default detection: −50 dBFS RMS for 500 ms, with a conservative 20 ms window-boundary allowance, followed by up to the nominal 250 ms UI interval. Scheduler stalls can add delay. This detects sustained 10 ms RMS-window activity, not every waveform sample above threshold.

This checks arming readiness, not whether recording is running or files are being written. Full recording-timing and CPU acceptance is pending. Try it first in a disposable Set, not during an irreplaceable performance. No Live routing, monitoring, arm or transport state is modified.

## Verification

The 0.6 build receives live levels from an RME MADIface XT and reads Live 12
track routing through the Remote Script. Use the disarm/arm test above to
verify alert behavior with your own interface and Set.

## Feedback

Please report Mac model/macOS, Live version, interface/driver, sample rate, input label, what you expected and what happened. Menu → **Save diagnostic report…** saves local metadata/levels for review; sending it is your choice. No audio is included.

Especially useful tests: mono-left/right/stereo, arming/disarming, silence, short bursts, switching input assignments, enabling/disabling Live inputs, device reconnect, and another sample rate. Check recorded timing and CPU before trusting it for sessions.

## Remove

Quit the app. Select None in GuardianAngel's Control Surface slot, then remove `User Library/Remote Scripts/GuardianAngel`. Other control surfaces are unaffected. Old extension backups are in `User Library/GuardianAngel Backups`. App state and diagnostic metadata are local under `~/Library/Application Support/GuardianAngel`; preferences use the app's bundle ID `studio.guardianangel.watchdog`.
