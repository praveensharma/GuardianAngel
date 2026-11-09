import Foundation
let devices=interfaces()
for device in devices {print("\(device.name) | \(device.count) channels | \(device.layout)")}
guard let selected=devices.first(where:{$0.uid==CommandLine.arguments.dropFirst().first}) else {print("Pass the explicit interface UID to test input access");exit(1)}
let detector=Detector();detector.start(selected)
Thread.sleep(forTimeInterval:2)
let value=detector.snapshot()
print("Fresh: \(value.fresh); error: \(detector.error); sample rate: \(detector.format?.mSampleRate ?? 0)")
if value.levels.count>=22 {print("21/22 RMS: \(value.levels[20]), \(value.levels[21]); active: \(value.active[20]), \(value.active[21])")}
print("Channels received: \(value.levels.count)")
detector.stop()
if !value.fresh {exit(2)}
