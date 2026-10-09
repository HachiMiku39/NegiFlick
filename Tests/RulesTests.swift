import Foundation
@main struct RulesTests {
 static func main() {
  for offset in -15...15 {
   let early:[Judgement] = [.cool,.cool,.cool,.fine,.fine,.fine,.fine,.safe,.safe,.sad,.sad]
   let late:[Judgement] = [.cool,.cool,.cool,.cool,.fine,.fine,.fine,.fine,.safe,.safe,.sad,.sad]
   assert(OriginalRules.timing(just:100,touch:100+offset) == (offset < -10 || offset > 11 ? .none:(offset<0 ? early[-offset]:late[offset])))
  }
  assert(OriginalRules.flick(just:100,down:70,up:100,boardMatches:true,directionMatches:true) == .safe)
  assert(OriginalRules.flick(just:100,down:100,up:100,boardMatches:true,directionMatches:false) == .safe)
  assert(OriginalRules.flick(just:100,down:100,up:100,boardMatches:false,directionMatches:true) == .sad)
  // Confirmed ARMv7 calibration examples, including the intentional repeated ms values.
  assert((-10...10).map{OriginalRules.inputOffsetTicks(step:$0,bpm:175)} == [-5,-4,-4,-3,-3,-2,-2,-1,-1,0,0,0,1,1,2,2,3,3,4,4,5])
  for (bpm,ticks) in [(75,16),(100,12),(140,7),(150,6),(175,5),(240,1)] {
   assert(OriginalRules.inputOffsetTicks(step:10,bpm:bpm)==ticks)
   assert(OriginalRules.inputOffsetTicks(step:-10,bpm:bpm)==(-ticks))
   assert(OriginalRules.inputOffsetTicks(step:99,bpm:bpm)==ticks)
  }
  assert(OriginalRules.timing(just:300,touch:305) == .fine)
  assert(OriginalRules.timing(just:OriginalRules.calibratedTick(10,step:10,bpm:175),touch:305) == .cool)
  assert(OriginalRules.timing(just:OriginalRules.calibratedTick(10,step:-10,bpm:175),touch:295) == .cool)
  let bpmChange=Chart(events:[Cue(time:0,parameter:"8100"),Cue(time:1,parameter:"0あ111110"),Cue(time:2,parameter:"8175"),Cue(time:3,parameter:"511111")])
  assert(ChartCompiler.notes(bpmChange,.normal).map(\.timingBPM)==[100,175])
  let guide=Note(id:0,time:3,kana:"あ",code:1,key:0,interlude:false,timingBPM:240,leadTime:1)
  assert(OriginalRules.panelGuideScale(note:guide,time:2,step:0)==nil)
  assert(OriginalRules.panelGuideScale(note:guide,time:2.2,step:0)==nil)
  assert(OriginalRules.panelGuideScale(note:guide,time:2.5,step:0)==0.5)
  assert(OriginalRules.panelGuideScale(note:guide,time:3,step:0)==1)
  assert(OriginalRules.panelGuideScale(note:guide,time:3.1,step:0)==nil)
  assert(OriginalRules.panelGuideScale(note:guide,time:3,step:10)!<1)
  let leadChange=Chart(events:[Cue(time:0,parameter:"72600"),Cue(time:1,parameter:"0あ111110"),Cue(time:2,parameter:"71700"),Cue(time:3,parameter:"0い111110")])
  assert(ChartCompiler.notes(leadChange,.normal).map(\.leadTime)==[2.6,1.7])
  // Enabled digits never change the gesture encoded by the kana itself.
  for digit in 1...5 {
   let chart=Chart(events:[Cue(time:0,parameter:"0く\(digit)\(digit)\(digit)\(digit)\(digit)")])
   assert(ChartCompiler.notes(chart,.normal).first!.direction==2)
  }
  for (kana,direction) in [("が",0),("ぎ",1),("ぐ",2),("げ",3),("ご",4),("ぱ",0),("ぃ",1),("ュ",2),("ん",2),("ー",2)] {assert(directionForKana(kana)==direction)}
  assert(ChartCompiler.notes(Chart(events:[Cue(time:0,parameter:"500000"),Cue(time:1,parameter:"522222")]),.normal).isEmpty)
  let longDelay=Note(id:1,time:3,kana:"い",code:1,key:0,interlude:false,timingBPM:240,leadTime:2)
  assert(OriginalRules.baseTick(longDelay)==60 && OriginalRules.justTick(longDelay,step:0)==90)
  assert(OriginalRules.panelGuideScale(note:longDelay,time:1.9,step:0)==nil)
  assert(OriginalRules.panelGuideScale(note:longDelay,time:2.5,step:0)==0.5)
  let next=Note(id:2,time:3.2,kana:"お",code:1,key:0,interlude:false,timingBPM:240,leadTime:1)
  let grey=Note(id:3,time:2.4,kana:"え",code:0,key:0,interlude:false,timingBPM:240,leadTime:1)
  let pending=[grey,guide,next]
  let before=OriginalVisuals.guides(notes:pending,resolved:[],time:2.7,step:0)
  assert(before.count==2 && before[0].isNearest && !before[1].isNearest)
  // Same-key future hints stay cyan during the preceding target's late window.
  let lateGuide=OriginalVisuals.guides(notes:pending,resolved:[],time:3.1,step:0)
  assert(lateGuide.count==1 && !lateGuide[0].isNearest)
  let consumed=OriginalVisuals.guides(notes:pending,resolved:[guide.id],time:3.1,step:0)
  assert(consumed.count==1 && consumed[0].isNearest)
  assert(OriginalVisuals.guides(notes:pending,resolved:[guide.id,next.id],time:3.1,step:0).isEmpty)
  assert(OriginalVisuals.frame(age:0.2,lifetime:20)==6)
  assert(OriginalVisuals.frame(age:2,lifetime:20)==20)
  assert(OriginalVisuals.opacity(frame:15,lifetime:20)==1 && OriginalVisuals.opacity(frame:20,lifetime:20)==0)
  assert(OriginalVisuals.opacity(frame:10,lifetime:10)==0)
  assert(abs(OriginalVisuals.resultScale(frame:0)-0.1)<0.000001 && abs(OriginalVisuals.resultScale(frame:6)-1)<0.000001)
  assert(OriginalVisuals.resultStretch(frame:0)==1 && OriginalVisuals.resultStretch(frame:15)==1)
  assert(OriginalVisuals.resultOffset(frame:10,interlude:true)<OriginalVisuals.resultOffset(frame:10,interlude:false))
  assert(OriginalVisuals.keyFlash(time:10.05,releasedAt:10))
  assert(!OriginalVisuals.keyFlash(time:10.2,releasedAt:10) && !OriginalVisuals.keyFlash(time:0,releasedAt:10))
  var fade=OriginalUIFade();assert(fade.alpha(time:0)==0)
  fade.set(visible:true,time:1)
  assert(abs(fade.alpha(time:1.1)-0.18)<0.000001 && fade.alpha(time:2)==1)
  fade.set(visible:false,time:2)
  assert(abs(fade.alpha(time:2.5)-0.7)<0.000001 && fade.alpha(time:4)==0)
  let pausedAlpha=fade.alpha(time:2.5);assert(fade.alpha(time:2.5)==pausedAlpha)
  fade.set(visible:true,time:2.5);assert(abs(fade.alpha(time:2.6)-0.88)<0.000001)
  var score=OriginalScore(totalNotes:120,totalInterlude:2,btl:false)
  for _ in 0..<100 {score.apply(.cool)}
  assert(score.stage==30000 && score.combo==100 && score.bonus==25500)
  score.apply(.cool,crimax:true);assert(score.stage==30500)
  let previous=score;score.apply(.fine,interlude:true);score.apply(.cool,interlude:true)
  assert(score.stage==previous.stage+41 && score.combo==previous.combo && score.gauge==previous.gauge && score.counts==previous.counts)
  score.apply(.safe);assert(score.combo==0)
  var btl=OriginalScore(totalNotes:20,totalInterlude:0,btl:true)
  btl.apply(.cool);btl.apply(.safe);btl.apply(.sad);btl.apply(.worst)
  assert(btl.stage==350 && btl.combo==1 && btl.gauge==128 && !btl.gameOver && btl.counts[1]==0 && btl.counts[2]==0)
  var perfect=OriginalScore(totalNotes:10,totalInterlude:0,btl:false)
  for _ in 0..<10 {perfect.apply(.cool)};assert(perfect.rank=="Perfect!")
  var s=OriginalScore(totalNotes:10,totalInterlude:0,btl:false)
  for _ in 0..<10 {s.apply(.fine)};assert(s.rank=="S")
  var fail=OriginalScore(totalNotes:100,totalInterlude:0,btl:false)
  for _ in 0..<51 {fail.apply(.worst)};assert(fail.gameOver && fail.rank=="E")
  for hz in [30,60,120] {let times=(0...hz).map{Double($0)/Double(hz)};assert(OriginalRules.tick(times.last!)==30)}
  // Crimax dispatch is a per-difficulty mark on the last eligible object among four,
  // rather than a time range; supplementary and interlude objects still occupy slots.
  let climaxChart=Chart(events:[Cue(time:0,parameter:"0あ111110"),Cue(time:0.01,parameter:"4い"),Cue(time:0.02,parameter:"511111"),Cue(time:0.03,parameter:"601000")])
  assert(ChartCompiler.notes(climaxChart,.normal).map(\.crimax)==[true,false,false])
  assert(!ChartCompiler.notes(climaxChart,.easy).contains{$0.crimax})
  let beyondFour=Chart(events:[Cue(time:0,parameter:"0あ111110")]+(1...4).map{Cue(time:Double($0)/10,parameter:"4い")}+[Cue(time:0.5,parameter:"611111")])
  assert(!ChartCompiler.notes(beyondFour,.normal).contains{$0.crimax})
  let grayClimax=Chart(events:[Cue(time:0,parameter:"0あ000000"),Cue(time:0.1,parameter:"611111")])
  assert(ChartCompiler.notes(grayClimax,.normal)[0].crimax)
  assert(!OriginalEffects.rainbow(combo:99) && OriginalEffects.rainbow(combo:100) && !OriginalEffects.rainbow(combo:0))
  assert([4,5,24,25,44,45].map{OriginalEffects.whirlLayers(combo:$0)}==[0,1,1,2,2,3])
  assert([14,15,34,35,84,85].map{OriginalEffects.fireworksLayers(combo:$0,interlude:false,frame:0)}==[0,1,1,2,2,3])
  assert(OriginalEffects.fireworksLayers(combo:200,interlude:true,frame:0)==0 && OriginalEffects.fireworksLayers(combo:200,interlude:false,frame:8)==0)
  // Three batched callbacks, a repeated clock and both calibration extremes:
  // every playable target resolves once, while gray guidance remains unjudged.
  let autoplayNotes=[grey,guide,next,Note(id:4,time:3.3,kana:"♪",code:1,key:-1,interlude:true,timingBPM:100,leadTime:1)]
  for step in [-10,0,10] {
   var ids=Set<Int>();var hitOrder:[Int]=[]
   for time in [2.0,3.0,3.0,4.0,4.0] {
    for note in AutoplayScheduler.due(notes:autoplayNotes,resolved:ids,time:time,step:step) {assert(ids.insert(note.id).inserted);hitOrder.append(note.id)}
   }
   assert(Set(hitOrder)==[guide.id,next.id,4] && hitOrder.count==3)
   assert(AutoplayScheduler.due(notes:autoplayNotes,resolved:ids,time:.nan,step:step).isEmpty)
  }
  if CommandLine.arguments.count>1 {
   let root=URL(fileURLWithPath:CommandLine.arguments[1]);let songs=try! JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("songs.json"))) as! [[String:Any]]
   assert(songs.count==11)
   var totalRuns=0
   for song in songs {
    let id=song["id"] as! String;let chart=try! JSONDecoder().decode(Chart.self,from:Data(contentsOf:root.appendingPathComponent(id+".json")))
    for difficulty in Difficulty.allCases {
     let notes=ChartCompiler.notes(chart,difficulty);let regular=notes.filter{$0.playable && !$0.interlude};let interludeNotes=notes.filter{$0.playable && $0.interlude}
     var result=OriginalScore(totalNotes:regular.count,totalInterlude:interludeNotes.count,btl:difficulty == .breakLimit);var ids=Set<Int>()
     let last=notes.map{OriginalRules.justTick($0,step:0)}.max() ?? 0
     for tick in stride(from:0,through:last+10,by:5) {
      for note in AutoplayScheduler.due(notes:notes,resolved:ids,time:Double(tick)/30,step:0) {assert(ids.insert(note.id).inserted);result.apply(.cool,interlude:note.interlude,crimax:note.crimax)}
     }
     assert(result.counts[Judgement.cool.rawValue]==regular.count && result.maxCombo==regular.count && result.interludeSuccess==interludeNotes.count && !result.gameOver)
     assert(result.counts[Judgement.worst.rawValue]==0 && ids.count==regular.count+interludeNotes.count)
     totalRuns+=1
    }
   }
   print("PASS: autoplay all 11 built-in songs × 5 difficulties (\(totalRuns) complete runs), including interludes, catch-up and Crimax bonuses")
  }
  print("PASS: 31 timing boundaries; 21-position BPM calibration; kana-derived direction and enable mask; interlude masks; BPM travel time; simultaneous guides and late-window nearest ordering; media-clock effect lifecycle; flick hold/direction/board; scoring/combo/Crimax; BTL; ranks; failure")
 }
}
