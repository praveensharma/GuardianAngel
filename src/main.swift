import Cocoa
import AVFoundation

final class Guardian:NSObject,NSApplicationDelegate,NSMenuDelegate {
    var menuOpen=false
    func menuWillOpen(_ menu:NSMenu){menuOpen=true}
    func menuDidClose(_ menu:NSMenu){menuOpen=false}
    let root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GuardianAngel")
    let defaults=UserDefaults.standard
    let detector=Detector()
    var item:NSStatusItem!
    var timer:Timer?
    var tick=0
    var available=[Interface]()
    var uid:String? {defaults.string(forKey:"selectedInterface")}
    var lastEvents=[Int]()
    var prior=Set<String>()
    var pending=[String:String]()
    var panel:NSPanel?
    var state="Starting"
    var detail=""
    var latest=[String:Any]()
    var authorizing=false
    func applicationDidFinishLaunching(_ notification:Notification){
        // Avoid duplicate captures if the beta is opened twice.
        if NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "").count>1 {NSApp.terminate(nil);return}
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        pending=defaults.dictionary(forKey:"pendingChannelWarnings") as? [String:String] ?? [:]
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        available=interfaces();reconcile()
        update();timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true){_ in self.update()}
    }
    func add(_ menu:NSMenu,_ title:String){menu.addItem(NSMenuItem(title:title,action:nil,keyEquivalent:""))}
    func action(_ menu:NSMenu,_ title:String,_ selector:Selector,object:Any?=nil){
        let entry=NSMenuItem(title:title,action:selector,keyEquivalent:"");entry.target=self;entry.representedObject=object;menu.addItem(entry)
    }
    func reconcile(){
        guard !authorizing else{return}
        guard let saved=uid,let interface=available.first(where:{$0.uid==saved}) else{detector.stop();return}
        guard defaults.string(forKey:"confirmedLayout")==interface.signature else{detector.stop();return}
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .notDetermined:
            authorizing=true;detector.error="Waiting for Microphone permission"
            AVCaptureDevice.requestAccess(for:.audio){[weak self] _ in DispatchQueue.main.async{self?.authorizing=false;self?.reconcile()}}
            return
        case .authorized:break
        default:detector.stop();detector.error="Enable GuardianAngel in System Settings → Privacy & Security → Microphone";return
        }
        if detector.selected?.uid != saved || detector.selected?.id != interface.id || detector.proc==nil || !detector.formatMatches() || !detector.snapshot().fresh {
            // Reconnects and rate changes restart qualification; history remains latched.
            lastEvents=[];detector.start(interface)
        }
    }
    func liveSnapshot()->[String:Any]? {
        let files=(try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
        var fresh=[[String:Any]]()
        for path in files where path.lastPathComponent.hasPrefix("live-") && path.pathExtension=="json" {
            if let bytes=try? Data(contentsOf:path),let obj=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],let time=obj["timestamp"] as? Double,abs(Date().timeIntervalSince1970-time)<3 {fresh.append(obj)}
        }
        guard fresh.count==1 else {detail=fresh.isEmpty ? "Waiting for Live — install/select the extension" : "Multiple Live extensions are active — keep one enabled";return nil}
        return fresh[0]
    }
    func update(){
        tick+=1
        if tick%8==0 {available=interfaces();reconcile()}
        state="Unavailable";detail="";var issues=[String]();var current=[String:String]()
        let audio=detector.snapshot()
        var levels=audio.levels
        var mappedCount=0
        if let saved=uid,let interface=available.first(where:{$0.uid==saved}) {
            if defaults.string(forKey:"confirmedLayout") != interface.signature {detail="Input layout changed — select and confirm this interface again"}
            else if !audio.fresh || !detector.formatMatches() {detail=detector.error.isEmpty ? "Input stream unavailable; check Microphone permission" : detector.error}
            else if let live=liveSnapshot() {
                let result=coverage(live,count:interface.count);issues=result.issues;mappedCount=result.mappedChannels.count
                var active=audio.active
                if lastEvents.count==audio.events.count {for i in active.indices {active[i] = active[i] || audio.events[i]>lastEvents[i]}}
                for problem in armIssues(result,active:active){current[interface.uid+":"+String(problem.channel)]=problem.message}
                state=result.routes.isEmpty ? "No resolved external input tracks" : "Watching \(mappedCount) mapped input channels"
                if !issues.isEmpty {state="Some input mappings need attention"}
                detail=interface.name
            }
        } else {detail=uid==nil ? "Choose the same interface used by Live" : "Selected interface disconnected — waiting"}
        lastEvents=audio.events
        let newKeys=Set(current.keys).subtracting(prior)
        if !newKeys.isEmpty {
            for key in newKeys {pending[key]=current[key]}
            defaults.set(pending,forKey:"pendingChannelWarnings")
            showAlert(newKeys.sorted().compactMap{current[$0]}.joined(separator:"\n"))
        }
        prior=Set(current.keys)
        item.button?.title = !current.isEmpty ? "⚠ Input not armed" : (!pending.isEmpty ? "⚠ GuardianAngel" : (audio.fresh && mappedCount>0 && issues.isEmpty ? "◉ GuardianAngel" : "◌ GuardianAngel"))
        let menu=NSMenu()
        add(menu,current.isEmpty ? state : "Audio is arriving on disarmed inputs")
        add(menu,detail)
        for message in current.values.sorted(){add(menu,message)}
        for (key,message) in pending.sorted(by:{$0.key<$1.key}) where current[key]==nil {add(menu,"Earlier: "+message)}
        if !issues.isEmpty {add(menu,"Unresolved: "+issues.prefix(4).joined(separator:"; "))}
        menu.addItem(.separator())
        let chooser=NSMenu();for interface in available {
            action(chooser,"\(interface.name) — \(interface.count) inputs",#selector(choose(_:)),object:interface.uid)
            chooser.items.last?.state = interface.uid==uid ? .on : .off
        }
        let parent=NSMenuItem(title:"Audio interface",action:nil,keyEquivalent:"");parent.submenu=chooser;menu.addItem(parent)
        action(menu,"Install Live extension…",#selector(installExtension))
        action(menu,"Show input mappings…",#selector(showMappings))
        action(menu,"Save diagnostic report…",#selector(saveReport))
        action(menu,"Acknowledge earlier warnings",#selector(acknowledge))
        add(menu,"GuardianAngel 0.6 friend beta · −50 dBFS / 500 ms")
        action(menu,"Quit GuardianAngel",#selector(quitApp));menu.delegate=self;if !menuOpen {item.menu=menu}
        if levels.count>512 {levels=[]}
        latest=["version":"0.6-friend-beta","timestamp":Date().timeIntervalSince1970,"state":state,"detail":detail,"inputFresh":audio.fresh,"mappedChannels":mappedCount,"unresolved":issues,"levelsDb":levels,"currentWarnings":current,"pendingWarnings":pending,"assumption":"Live uses the selected interface; numbered Live labels refer to physical channels"]
        if tick%4==0,let bytes=try? JSONSerialization.data(withJSONObject:latest,options:.prettyPrinted) {try? bytes.write(to:root.appendingPathComponent("friend-detector-status.json"),options:.atomic)}
    }
    @objc func choose(_ sender:NSMenuItem){
        guard let key=sender.representedObject as? String,let interface=available.first(where:{$0.uid==key}) else{return}
        let alert=NSAlert();alert.messageText="Use \(interface.name)?"
        alert.informativeText="Confirm Live uses this same input device. This beta maps numbered Live labels (for example 1/2 or 21/22 REAMP) to those physical input numbers. Custom labels without numbers remain unresolved. Test one known signal after selecting."
        alert.addButton(withTitle:"Use this interface");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        detector.stop();defaults.set(key,forKey:"selectedInterface");defaults.set(interface.signature,forKey:"confirmedLayout");lastEvents=[];prior=[];reconcile();update()
    }
    @objc func showMappings(){
        let alert=NSAlert();alert.messageText="Input mapping status"
        var lines=[state,detail,"\nNumbered labels are a mapping convention, not proof of physical routing."]
        if let interface=available.first(where:{$0.uid==uid}),let live=liveSnapshot(){
            let result=coverage(live,count:interface.count)
            lines += result.routes.map{"Input \($0.channels.map(String.init).joined(separator:"/")) → \($0.name) · \($0.armed ? "armed" : "disarmed")"}
            lines += result.issues
        }
        let view=NSTextView(frame:NSRect(x:0,y:0,width:600,height:330));view.isEditable=false;view.string=lines.joined(separator:"\n")
        let scroll=NSScrollView(frame:view.frame);scroll.documentView=view;scroll.hasVerticalScroller=true;alert.accessoryView=scroll;alert.runModal()
    }
    func showAlert(_ text:String){
        if panel==nil {let p=NSPanel(contentRect:NSRect(x:0,y:0,width:540,height:180),styleMask:[.titled,.closable,.nonactivatingPanel],backing:.buffered,defer:false);p.title="GuardianAngel — input not armed";p.level = .floating;p.isReleasedWhenClosed=false;p.center();panel=p}
        let view=NSTextField(wrappingLabelWithString:text);view.frame=NSRect(x:20,y:20,width:500,height:140);view.font = .systemFont(ofSize:17,weight:.medium)
        panel?.contentView?.subviews.forEach{$0.removeFromSuperview()};panel?.contentView?.addSubview(view);panel?.orderFrontRegardless()
    }
    @objc func acknowledge(){pending=[:];defaults.set(pending,forKey:"pendingChannelWarnings");panel?.orderOut(nil);update()}
    @objc func saveReport(){let dialog=NSSavePanel();dialog.nameFieldStringValue="GuardianAngel-diagnostic.json";guard dialog.runModal() == .OK,let url=dialog.url,let bytes=try? JSONSerialization.data(withJSONObject:latest,options:.prettyPrinted) else{return};try? bytes.write(to:url,options:.atomic)}
    @objc func installExtension(){
        let dialog=NSOpenPanel();dialog.title="Select your Ableton User Library";dialog.prompt="Install extension";dialog.canChooseFiles=false;dialog.canChooseDirectories=true
        dialog.directoryURL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Ableton/User Library")
        guard dialog.runModal() == .OK,let library=dialog.url,let source=Bundle.main.resourceURL?.appendingPathComponent("GuardianAngel") else{return}
        do {
            let folder=library.appendingPathComponent("Remote Scripts");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let target=folder.appendingPathComponent("GuardianAngel")
            let staged=folder.appendingPathComponent(".guardianangel-install-"+UUID().uuidString)
            defer{try? FileManager.default.removeItem(at:staged)}
            try FileManager.default.copyItem(at:source,to:staged)
            var backup:URL?
            if FileManager.default.fileExists(atPath:target.path){
                let backups=library.appendingPathComponent("GuardianAngel Backups")
                try FileManager.default.createDirectory(at:backups,withIntermediateDirectories:true)
                let path=backups.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at:target,to:path);backup=path
            }
            do {try FileManager.default.moveItem(at:staged,to:target)}
            catch {if let path=backup {try? FileManager.default.moveItem(at:path,to:target)};throw error}
            let note=NSAlert();note.messageText="Extension installed";note.informativeText="At your next Live restart, select GuardianAngel in an unused Control Surface slot. Leave MIDI Input and Output set to None. Enable only one GuardianAngel slot.";note.runModal()
        }catch{let note=NSAlert(error:error);note.runModal()}
    }
    @objc func quitApp(){detector.stop();NSApp.terminate(nil)}
    func applicationWillTerminate(_ notification:Notification){detector.stop()}
}
let app=NSApplication.shared
let delegate=Guardian();app.delegate=delegate;app.setActivationPolicy(.accessory);app.run()
