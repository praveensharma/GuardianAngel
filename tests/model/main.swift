import Foundation
import CoreAudio
var checks=0
func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1;print("PASS "+label)}
check(channelNumbers("21/22 REAMP",count:68)==[21,22],"custom suffix")
check(channelNumbers("1/2",count:2)==[1,2],"default pair")
check(channelNumbers("2 Mic",count:2)==[2],"mono")
for bad in ["Muse","0","69","1/3","1/2/3","1.2","1/2Stereo","-1","1/1","01"] {check(channelNumbers(bad,count:68)==nil,"reject "+bad)}
func row(_ name:String,_ pair:String,_ armed:Bool)->[String:Any]{["name":name,"input":"Ext. In","pair":pair,"arm":armed,"routing_verified":true]}
func object(_ rows:[[String:Any]])->[String:Any]{["schema":3,"status":"Connected","tracks":rows]}
let stereo=row("Synth","1/2",false),mono=row("Backup","1",true)
var c=coverage(object([stereo,mono]),count:4)
check(armIssues(c,active:[true,true,false,false]).map{$0.channel}==[2],"armed mono only covers its channel")
check(armIssues(coverage(object([row("Renamed","1/2",true),stereo]),count:2),active:[true,true]).isEmpty,"any armed destination covers stereo")
check(armIssues(c,active:[false,false,false,false]).isEmpty,"silence")
check(armIssues(c,active:[false,false,true,false]).isEmpty,"unused input does not alert")
let reordered=coverage(object([mono,stereo]),count:4)
check(armIssues(reordered,active:[true,true,false,false]).map{$0.channel}==[2],"order irrelevant")
for record in [false,true] {var obj=object([row("Synth","1/2",true)]);obj["recording"]=record;check(armIssues(coverage(obj,count:2),active:[true,true]).isEmpty,"record state irrelevant")}
check(!coverage(object([row("Synth","Keyboard",false)]),count:2).issues.isEmpty,"ambiguous label unresolved")
var ambiguous=stereo;ambiguous["routing_verified"]=false
check(coverage(object([ambiguous]),count:2).routes.isEmpty,"duplicate routing rejected")
check(coverage(["schema":2],count:2).routes.isEmpty,"old bridge rejected")
// Disabled channels do not compact hardware numbering.
check(coverage(object([row("Last","7/8",false)]),count:8).mappedChannels==Set([7,8]),"sparse enabled I/O retains absolute numbers")
for rate in [44100.0,48000,96000] {
    var e=Envelope(rate:rate)
    for _ in 0..<Int(rate*0.51) {e.sample(0.1)}
    check(!e.active,"conservative duration \(rate)")
    for _ in 0..<Int(rate*0.02) {e.sample(0.1)}
    check(e.active && e.events==1,"sustained activity \(rate)")
    for _ in 0..<Int(rate*0.1) {e.sample(0)}
    check(!e.active && e.events==1,"reset \(rate)")
    for _ in 0..<Int(rate*0.6) {e.sample(0.0001)}
    check(!e.active,"below threshold \(rate)")
    for offset in [0,1,5,9] {
        var short=Envelope(rate:rate)
        for _ in 0..<Int(rate*Double(offset)/1000){short.sample(0)}
        for _ in 0..<Int(rate*0.499){short.sample(0.5)}
        for _ in 0..<Int(rate*0.1){short.sample(0)}
        check(short.events==0,"499ms burst \(rate) phase \(offset)")
    }
}
// Exercise the actual callback decoder with interleaved and noninterleaved buffers.
for width in [4,8] {
 for layout in [[2],[1,1]] {
    let detector=Detector();detector.envelopes=[Envelope(rate:48000),Envelope(rate:48000)]
    let list=AudioBufferList.allocate(maximumBuffers:layout.count)
    let memory=UnsafeMutableRawPointer.allocate(byteCount:480*2*width,alignment:8)
    for i in 0..<960 {
        let channel=layout.count==1 ? i%2 : i/480
        let x=channel==0 ? 0.1 : 0.0
        if width==4 {memory.assumingMemoryBound(to:Float.self)[i]=Float(x)} else {memory.assumingMemoryBound(to:Double.self)[i]=x}
    }
    list.unsafeMutablePointer.pointee.mNumberBuffers=UInt32(layout.count)
    var offset=0
    for i in layout.indices {list[i]=AudioBuffer(mNumberChannels:UInt32(layout[i]),mDataByteSize:UInt32(480*layout[i]*width),mData:memory.advanced(by:offset));offset+=480*layout[i]*width}
    let interface=Interface(id:0,uid:"test",name:"test",layout:layout)
    for _ in 0..<53 {detector.ingest(UnsafePointer(list.unsafeMutablePointer),interface:interface,width:width)}
    check(detector.envelopes[0].active && !detector.envelopes[1].active,"decoded L only: \(width) bytes \(layout)")
    memory.deallocate();list.unsafeMutablePointer.deallocate()
 }
}
print("\(checks) checks passed")
