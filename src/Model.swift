import Foundation

struct Route {
    let name:String
    let channels:[Int]
    let armed:Bool
}
struct Coverage {
    var routes=[Route]()
    var issues=[String]()
    var mappedChannels:Set<Int> {Set(routes.flatMap{$0.channels})}
}
func channelNumbers(_ label:String, count:Int)->[Int]? {
    // This is a numbered-label convention, never a hidden API identifier.
    let pattern="^([1-9][0-9]*)(?:/([1-9][0-9]*))?(?:\\s|$)"
    guard let re=try? NSRegularExpression(pattern:pattern),let match=re.firstMatch(in:label,range:NSRange(label.startIndex...,in:label)),let aRange=Range(match.range(at:1),in:label),let a=Int(label[aRange]),a<=count else {return nil}
    if let bRange=Range(match.range(at:2),in:label) {
        guard let b=Int(label[bRange]),b==a+1,b<=count else {return nil}
        return [a,b]
    }
    return [a]
}
func coverage(_ object:[String:Any], count:Int)->Coverage {
    var result=Coverage()
    guard (object["schema"] as? Int)==3,object["status"] as? String=="Connected",let tracks=object["tracks"] as? [[String:Any]] else {
        result.issues=["Install or reload the friend-test Live extension"];return result
    }
    for track in tracks {
        let name=track["name"] as? String ?? "Unnamed track"
        if track["error"] != nil {result.issues.append(name+": routing unavailable");continue}
        guard track["input"] as? String=="Ext. In" else {continue}
        guard track["routing_verified"] as? Bool==true,let label=track["pair"] as? String,let channels=channelNumbers(label,count:count),let armed=track["arm"] as? Bool else {
            result.issues.append(name+": input numbering is ambiguous");continue
        }
        result.routes.append(Route(name:name,channels:channels,armed:armed))
    }
    return result
}
struct ArmIssue {
    let channel:Int
    let message:String
}
func armIssues(_ coverage:Coverage,active:[Bool])->[ArmIssue] {
    var issues=[ArmIssue]()
    for index in active.indices where active[index] {
        let channel=index+1
        let destinations=coverage.routes.filter{$0.channels.contains(channel)}
        // Friend scope: warn for corresponding disarmed tracks, not unused physical inputs.
        guard !destinations.isEmpty,!destinations.contains(where:{$0.armed}) else {continue}
        let names=Array(Set(destinations.map{$0.name})).sorted().joined(separator:", ")
        issues.append(ArmIssue(channel:channel,message:"Input \(channel) · \(names) is not armed"))
    }
    return issues
}
struct Envelope {
    let window:Int
    var samples=0
    var square=0.0
    var run=0
    var db = -160.0
    var events=0
    var active:Bool {run>=52}
    init(rate:Double){window=max(1,Int((rate*0.01).rounded()))}
    mutating func sample(_ value:Double) {
        if !value.isFinite {samples=0;square=0;run=0;db = -160;return}
        square += value*value;samples += 1
        if samples==window {
            db=10*log10(max(square/Double(window),1e-16))
            run = db >= -50 ? min(run+1,53) : 0
            if run==52 {events += 1}
            samples=0;square=0
        }
    }
}
