# Friend beta 0.6 — validation, 2026-10-28

Ready for informal compatibility testing, not production certification.

## Passed

- 52 native Swift checks: strict numbered-label parsing; ambiguous/out-of-range labels; sparse input numbering; mono/stereo/overlapping coverage; rename/reorder; arming-only policy; unsupported bridge; independent RMS qualification/reset; below threshold and 499 ms bursts at multiple phases; 44.1/48/96 kHz; actual callback decoder with Float32/Float64 and interleaved/noninterleaved synthetic buffers.
- Mocked Live bridge: Python routing-object membership, duplicate labels, track rename/arm/delete, separate session files and cleanup. The bridge has no input-meter or transport dependency.
- Generalized detector executed against the connected RME: discovered 68 channels, captured fresh 48 kHz Float32 input, and reported silence on 21/22 after playback stopped. No RME name, serial or REAMP mapping is built into the product.
- Previous scoped version physically detected active REAMP input with Monitor Off and Arm Off while Live's input meter API returned zero; user observed the warning. This does not establish full end-to-end validation of every path in the generalized beta.
- Apple Silicon app compiles; Intel cross-build compiles with toolchain compatibility-library warnings. Both architectures packaged. Intel runtime remains untested.

## Still needs human/hardware testing

- First-launch app permission, interface selector, extension installer, generalized alert window and mapping display on fresh machines.
- Actual v3 bridge reload/selection in Live; multiple-instance ambiguity handling in real Live sessions.
- Other interfaces, Float64 hardware, noninterleaved hardware, reconnects and sample-rate transitions.
- Physical channel-number agreement on each interface and Live configuration. Label parsing alone is not proof; confirm with a known signal.
- I/O enable/disable changes, renaming input labels, CPU usage, audio dropouts, recorded transient alignment and measured real detection latency.
- No global All Clear or guarantee of audio files written. Unassigned inputs, internal/resampled routing and unnumbered or localized external-input labels remain outside automatic coverage.

The app never records audio, transmits data, or changes Live arm/monitor/routing/transport. Direct input access still consumes CPU and needs recording-impact testing. The beta is ad-hoc signed, not Developer ID signed or notarized.
