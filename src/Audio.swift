import Foundation
import CoreAudio

struct Interface {
    let id:AudioDeviceID
    let uid:String
    let name:String
    let layout:[Int]
    var count:Int {layout.reduce(0,+)}
    var signature:String {uid+":"+layout.map(String.init).joined(separator:",")}
}
func audioString(_ id:AudioObjectID,_ selector:AudioObjectPropertySelector)->String? {
    var property=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    var value:Unmanaged<CFString>?
    var bytes=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id,&property,0,nil,&bytes,&value)==noErr else {return nil}
    return value?.takeRetainedValue() as String?
}
func inputLayout(_ id:AudioDeviceID)->[Int]? {
    var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreamConfiguration,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
    var size:UInt32=0
    guard AudioObjectGetPropertyDataSize(id,&address,0,nil,&size)==noErr,size>=MemoryLayout<AudioBufferList>.size else {return nil}
    let memory=UnsafeMutableRawPointer.allocate(byteCount:Int(size),alignment:MemoryLayout<AudioBufferList>.alignment)
    defer{memory.deallocate()}
    guard AudioObjectGetPropertyData(id,&address,0,nil,&size,memory)==noErr else {return nil}
    return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to:AudioBufferList.self)).map{Int($0.mNumberChannels)}
}
func inputFormat(_ id:AudioDeviceID)->AudioStreamBasicDescription? {
    var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreamFormat,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
    var value=AudioStreamBasicDescription();var size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(id,&address,0,nil,&size,&value)==noErr else {return nil}
    return value
}
func uniformInputFormats(_ id:AudioDeviceID, expected:AudioStreamBasicDescription)->Bool {
    var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
    var size:UInt32=0
    guard AudioObjectGetPropertyDataSize(id,&address,0,nil,&size)==noErr,size>0 else{return false}
    var streams=[AudioStreamID](repeating:0,count:Int(size)/MemoryLayout<AudioStreamID>.size)
    guard AudioObjectGetPropertyData(id,&address,0,nil,&size,&streams)==noErr else{return false}
    for stream in streams {
        address=AudioObjectPropertyAddress(mSelector:kAudioStreamPropertyVirtualFormat,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var f=AudioStreamBasicDescription();var bytes=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(stream,&address,0,nil,&bytes,&f)==noErr,f.mFormatID==expected.mFormatID,f.mSampleRate==expected.mSampleRate,f.mBitsPerChannel==expected.mBitsPerChannel,f.mFormatFlags==expected.mFormatFlags else{return false}
    }
    return true
}
func interfaces()->[Interface] {
    var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    let system=AudioObjectID(kAudioObjectSystemObject);var size:UInt32=0
    guard AudioObjectGetPropertyDataSize(system,&address,0,nil,&size)==noErr else{return []}
    var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system,&address,0,nil,&size,&ids)==noErr else{return []}
    return ids.compactMap {id in
        guard let uid=audioString(id,kAudioDevicePropertyDeviceUID),let name=audioString(id,kAudioObjectPropertyName),let layout=inputLayout(id),layout.reduce(0,+)>0 else{return nil}
        return Interface(id:id,uid:uid,name:name,layout:layout)
    }.sorted{$0.name<$1.name}
}
struct AudioSnapshot {
    let fresh:Bool
    let levels:[Double]
    let active:[Bool]
    let events:[Int]
}
final class Detector {
    let queue=DispatchQueue(label:"GuardianAngel.input")
    var selected:Interface?
    var format:AudioStreamBasicDescription?
    var proc:AudioDeviceIOProcID?
    var envelopes=[Envelope]()
    var heartbeat=0.0
    var error="Select an audio interface"
    func start(_ interface:Interface) {
        stop();selected=interface
        guard interface.count<=512,let f=inputFormat(interface.id),f.mFormatID==kAudioFormatLinearPCM,
              f.mFormatFlags & kAudioFormatFlagIsFloat != 0,f.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              f.mFormatFlags & kAudioFormatFlagIsPacked != 0,[32,64].contains(Int(f.mBitsPerChannel)),f.mSampleRate>=8000,f.mSampleRate<=384000 else {
            error="Unsupported input format — this beta needs packed Float32/64 PCM";return
        }
        guard uniformInputFormats(interface.id,expected:f) else {error="Mixed input stream formats are unsupported in this beta";return}
        format=f;envelopes=(0..<interface.count).map{_ in Envelope(rate:f.mSampleRate)};heartbeat=0
        let width=Int(f.mBitsPerChannel)/8
        let created=AudioDeviceCreateIOProcIDWithBlock(&proc,interface.id,queue){[weak self] _,input,_,_,_ in
            guard let self=self else{return}
            self.ingest(input,interface:interface,width:width)
        }
        guard created==noErr,let handle=proc else{error="Input access failed (\(created))";stop();return}
        let status=AudioDeviceStart(interface.id,handle)
        guard status==noErr else{error="Input capture failed (\(status)); check microphone permission and driver";stop();return}
        error=""
    }
    func ingest(_ input:UnsafePointer<AudioBufferList>,interface:Interface,width:Int) {
            let buffers=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input))
            guard buffers.count==interface.layout.count else{heartbeat=0;return}
            for i in buffers.indices {if Int(buffers[i].mNumberChannels) != interface.layout[i] {heartbeat=0;return}}
            var base=0
            for buffer in buffers {
                let channels=Int(buffer.mNumberChannels)
                if channels==0 {continue}
                guard let pointer=buffer.mData,Int(buffer.mDataByteSize)%(width*channels)==0 else{heartbeat=0;return}
                let frames=Int(buffer.mDataByteSize)/(width*channels)
                guard frames>0 else{heartbeat=0;return}
                for ch in 0..<channels {
                    if width==4 {
                        let values=pointer.assumingMemoryBound(to:Float.self)
                        for frame in 0..<frames {envelopes[base+ch].sample(Double(values[frame*channels+ch]))}
                    } else {
                        let values=pointer.assumingMemoryBound(to:Double.self)
                        for frame in 0..<frames {envelopes[base+ch].sample(values[frame*channels+ch])}
                    }
                }
                base+=channels
            }
            heartbeat=ProcessInfo.processInfo.systemUptime
    }
    func formatMatches()->Bool {
        guard let selected=selected,let old=format,let now=inputFormat(selected.id),let layout=inputLayout(selected.id) else{return false}
        return audioString(selected.id,kAudioDevicePropertyDeviceUID)==selected.uid && layout==selected.layout && now.mSampleRate==old.mSampleRate && now.mFormatID==old.mFormatID && now.mFormatFlags==old.mFormatFlags && now.mBitsPerChannel==old.mBitsPerChannel
    }
    func snapshot()->AudioSnapshot {
        queue.sync{AudioSnapshot(fresh:proc != nil && heartbeat>0 && ProcessInfo.processInfo.systemUptime-heartbeat<1,levels:envelopes.map{$0.db},active:envelopes.map{$0.active},events:envelopes.map{$0.events})}
    }
    func stop(){
        if let id=selected?.id,let handle=proc {AudioDeviceStop(id,handle);AudioDeviceDestroyIOProcID(id,handle)}
        proc=nil;queue.sync{};heartbeat=0
    }
}
