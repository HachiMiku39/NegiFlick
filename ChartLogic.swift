import Foundation
func hiragana(_ text:String)->String { text.applyingTransform(.hiraganaToKatakana,reverse:true) ?? text }
struct Cue: Codable { let time:Double; let parameter:String }
struct Chart: Codable { let events:[Cue];var inputLanguage:NoteInputLanguage?=nil;var noteInputs:[Int:String]?=nil;var noteWords:[Int:String]?=nil }
enum Difficulty:Int,CaseIterable,Identifiable { case easy,normal,hard,extreme,breakLimit; var id:Int {rawValue}; var label:String {["EASY","NORMAL","HARD","EXTREME","BREAK THE LIMIT"][rawValue]} }
enum PlayMode:String,CaseIterable { case play,mv,karaoke }
struct Note:Identifiable { let id:Int;let time:Double;let kana:String;let code:Int;let key:Int;let interlude:Bool;var timingBPM=175;var leadTime=1.7;var supplementary=false;var crimax=false;var inputDirection:Int?=nil;var inputLabel:String?=nil;var inputWord:String?=nil;var displayText:String {inputWord ?? kana}; var playable:Bool {code != 0};var direction:Int {interlude ? 0:(inputDirection ?? directionForKana(kana))} }
let kanaGroups=["あいうえお","かきくけこ","さしすせそ","たちつてと","なにぬねの","はひふへほ","まみむめも","や（ゆ）よ","らりるれろ","わをんー〜"]
func baseKana(_ char:String)->String {
 let h=hiragana(char);let pairs=zip(Array("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔぁぃぅぇぉゃゅょっゎ"),Array("かきくけこさしすせそたちつてとはひふへほはひふへほうあいうえおやゆよつわ"))
 return pairs.first {String($0.0)==h}.map {String($0.1)} ?? h
}
func keyForKana(_ text:String)->Int { kanaGroups.firstIndex { $0.contains(baseKana(text)) } ?? 9 }
// Cue digits enable a note; the kana table supplies its gesture, including voiced/small kana.
func directionForKana(_ text:String)->Int {
 if text=="ー" {return 2}
 let kana=baseKana(text),key=keyForKana(kana)
 return Array(kanaGroups[key]).firstIndex(of:Character(kana)) ?? 0
}
func modified(_ kana:String,mode:Int)->String {
 let b=Array("かきくけこさしすせそたちつてとはひふへほう"),v=Array("がぎぐげござじずぜぞだぢづでどばびぶべぼゔ")
 if mode==1,let i=b.firstIndex(of:Character(kana)){return String(v[i])}
 if mode==2,let i=Array("はひふへほ").firstIndex(of:Character(kana)){return String(Array("ぱぴぷぺぽ")[i])}
 if mode==3,let i=Array("あいうえおやゆよつわ").firstIndex(of:Character(kana)){return String(Array("ぁぃぅぇぉゃゅょっゎ")[i])};return kana
}
func roman(_ char:String)->String {
 let rows=[["a","i","u","e","o"],["ka","ki","ku","ke","ko"],["sa","shi","su","se","so"],["ta","chi","tsu","te","to"],["na","ni","nu","ne","no"],["ha","hi","fu","he","ho"],["ma","mi","mu","me","mo"],["ya","","yu","","yo"],["ra","ri","ru","re","ro"],["wa","wo","n","-","~"]]
 let h=baseKana(char);for (i,g) in kanaGroups.enumerated(){if let j=Array(g).firstIndex(of:Character(h)){return rows[i][j]}};return ""
}
struct ChartCompiler {
 static func notes(_ chart:Chart,_ difficulty:Difficulty)->[Note] {
  var result:[Note]=[];var delay=1.7;var bpm=175
  for (eventIndex,e) in chart.events.enumerated() {
   let c=Array(e.parameter);guard let first=c.first else{continue}
   if first=="7",let ms=Double(String(c.dropFirst())){delay=ms/1000}
   if first=="8",let value=Int(String(c.dropFirst())){bpm=value}
   if first=="0",c.count>=7 {
    // The original dispatcher indexes difficulty + 2. Trailing modifier bytes are preserved in the raw chart.
    let code=Int(String(c[2+difficulty.rawValue])) ?? 0
    let input=chart.inputLanguage == nil || chart.inputLanguage == .japanese ? nil:(chart.noteInputs?[eventIndex] ?? String(c[1]))
    let position=input.flatMap(LetterInputMap.position)
    result.append(Note(id:result.count,time:e.time+delay,kana:String(c[1]),code:code,key:position?.key ?? keyForKana(String(c[1])),interlude:false,timingBPM:bpm,leadTime:delay,inputDirection:position?.direction,inputLabel:input,inputWord:chart.noteWords?[eventIndex]))
   }else if first=="4",c.count>=2 { result.append(Note(id:result.count,time:e.time+delay,kana:String(c[1]),code:0,key:0,interlude:false,timingBPM:bpm,leadTime:delay,supplementary:true)) }
   else if first=="5",c.count>=6 {
    let state=Int(String(c[1+difficulty.rawValue])) ?? 0
    if state == 1 {result.append(Note(id:result.count,time:e.time+delay,kana:"♪",code:1,key:-1,interlude:true,timingBPM:bpm,leadTime:delay))}
   }else if first=="6",c.count>1+difficulty.rawValue,(Int(String(c[1+difficulty.rawValue])) ?? 0) != 0 {
    // Original NoteManager searches the last four created objects, including gray notes.
    if let index=result.indices.suffix(4).reversed().first(where:{!result[$0].interlude && !result[$0].supplementary}) {result[index].crimax=true}
   }
  };return result.sorted { $0.time == $1.time ? $0.id<$1.id : $0.time<$1.time }
 }
}

// Confirmed MikuFlick2 1.1.5 tables; gameplay ticks use the media clock, never display frames.
enum Judgement: Int, CaseIterable {
 case none, worst, sad, safe, fine, cool
 var label: String { ["", "WORST", "SAD", "SAFE", "FINE", "COOL"][rawValue] }
 var points: Int { [0, 0, 30, 50, 150, 300][rawValue] }
}
struct OriginalRules {
 static func tick(_ seconds: Double) -> Int { Int(ceil(seconds * 30)) }
 // ARMv7 GetCenterTime and NoteNormal/NoteInterlude init: keep Float32 and
 // truncation, because INPUT TIMING is 21 song-specific positions, not ms.
 static func centerTime(bpm:Int)->Float {
  let bounds=[80,90,100,110,120,130,140,150,160,170,180,190,200,210,220,230,240]
  let seconds:[Float]=[3,2.9,2.8,2.6,2.4,2.2,2.1,2,1.9,1.8,1.7,1.6,1.5,1.4,1.3,1.2,1.1,1]
  return seconds[bounds.firstIndex(where:{bpm<$0}) ?? bounds.count]
 }
 static func inputOffsetTicks(step:Int,bpm:Int)->Int {
  let center=centerTime(bpm:bpm),frames=Int(center*30)
  let speed=abs(Float(-642)/center)
  let pixelsPerTick=Float(Double(speed)/Double(frames))
  let ticksPerPosition=(Float(39)/pixelsPerTick)/10
  return Int(ticksPerPosition*Float(min(10,max(-10,step))))
 }
 static func calibratedTick(_ seconds:Double,step:Int,bpm:Int)->Int {tick(seconds)+inputOffsetTicks(step:step,bpm:bpm)}
 static func baseTick(_ note:Note)->Int {
  tick(note.time-note.leadTime)+Int(floor(note.leadTime*30)-Double(centerTime(bpm:note.timingBPM)*30))
 }
 static func justTick(_ note:Note,step:Int)->Int {
  baseTick(note)+Int(centerTime(bpm:note.timingBPM)*30)+inputOffsetTicks(step:step,bpm:note.timingBPM)
 }
 // NoteNormal::render uses m_Cnt / m_JustFrame, hides the first quarter,
 // and grows the original panel toward its full size at the judgement tick.
 static func panelGuideScale(note:Note,time:Double,step:Int)->Double? {
  guard !note.interlude,note.playable,time.isFinite else{return nil}
  let frames=max(1,Int(centerTime(bpm:note.timingBPM)*30)+inputOffsetTicks(step:step,bpm:note.timingBPM))
  let elapsed=tick(time)-baseTick(note)
  guard elapsed>=0,elapsed<=frames else{return nil}
  let scale=Double(elapsed)/Double(frames)
  return scale>=0.25 ? scale:nil
 }
 static func timing(just: Int, touch: Int) -> Judgement {
  let delta = just - touch, distance = abs(delta)
  guard delta >= -11,delta <= 10 else { return .none }
  if delta >= 0 { return distance <= 2 ? .cool : distance <= 6 ? .fine : distance <= 8 ? .safe : .sad }
  return distance <= 3 ? .cool : distance <= 7 ? .fine : distance <= 9 ? .safe : .sad
 }
 static func flick(just: Int, down: Int, up: Int, boardMatches: Bool, directionMatches: Bool) -> Judgement {
  let start = timing(just: just, touch: down), end = timing(just: just, touch: up)
  guard end != .none else { return .none }
  var result = Judgement(rawValue: min(start.rawValue, end.rawValue))!
  if down < just && result.rawValue < Judgement.safe.rawValue { result = .safe }
  if !directionMatches { result = Judgement(rawValue: min(result.rawValue, Judgement.safe.rawValue))! }
  if !boardMatches { result = .sad }
  return result
 }
}

struct PanelGuideHint:Identifiable {
 let note:Note;let scale:Double;let isNearest:Bool
 var id:Int {note.id}
}
enum OriginalVisuals {
 // Keep overdue, unresolved targets in the ordering: a later note stays cyan until
 // the earlier target resolves, even after its own growing guide has disappeared.
 static func target(notes:[Note],resolved:Set<Int>,interlude:Bool)->Note? {
  notes.first{$0.playable && $0.interlude==interlude && !resolved.contains($0.id)}
 }
 static func guides(notes:[Note],resolved:Set<Int>,time:Double,step:Int)->[PanelGuideHint] {
  let nearest=target(notes:notes,resolved:resolved,interlude:false)?.id
  return notes.compactMap {note in
   guard !resolved.contains(note.id),let scale=OriginalRules.panelGuideScale(note:note,time:time,step:step) else{return nil}
   return PanelGuideHint(note:note,scale:scale,isNearest:note.id==nearest)
  }
 }
 static func frame(age:Double,lifetime:Int)->Int {min(lifetime,max(0,Int(floor(max(0,age)*30+0.000001))))}
 static func keyFlash(time:Double,releasedAt:Double)->Bool {let age=time-releasedAt;return age>=0 && age<0.1}
 static func opacity(frame:Int,lifetime:Int)->Double {min(1,max(0,Double(lifetime-frame)/5))}
 static func pulseScale(frame:Int,combo:Int)->Double {1+sin(Double(frame)/10*1.57)*0.92+Double(max(0,Int(Double((combo-50)/5)*0.02)))}
 static func resultScale(frame:Int)->Double {min(1,0.1+Double(frame)*0.15)}
 static func resultStretch(frame:Int)->Double {
  guard frame<15 else{return 1}
  return (1...max(1,frame)).reduce(1.0){value,tick in
   guard tick<=frame else{return value}
   return value+(0x3c3c & (1<<tick) != 0 ? 0.38:0)-(0x3c3c0 & (1<<tick) != 0 ? 0.38:0)
  }
 }
 static func resultOffset(frame:Int,interlude:Bool)->Double {
  -80*(1-pow(0.5,Double(frame)))-sin(Double(frame)/20*1.57)*(interlude ? 100:20)
 }
}
struct GameplayEffect:Identifiable {
 let id:Int;let time:Double;let note:Note;let result:Judgement;let pulse:Bool;let combo:Int;let timingHint:String
}
// WindowManager UI fades: +0.06 / -0.02 per 30 Hz media tick.
struct OriginalUIFade {
 private var startTick=0;private var initial=0.0;private var rate=0.0
 func alpha(time:Double)->Double {min(1,max(0,initial+Double(max(0,OriginalRules.tick(time)-startTick))*rate))}
 mutating func set(visible:Bool,time:Double) {initial=alpha(time:time);startTick=OriginalRules.tick(time);rate=visible ? 0.06:-0.02}
}
struct OriginalScore: Codable {
 var stage = 0, bonus = 0, combo = 0, maxCombo = 0
 var counts = Array(repeating: 0, count: 6)
 var interludeSuccess = 0, interludeResolved = 0
 var gauge = 128.0
 var gameOver = false
 let totalNotes: Int
 let totalInterlude: Int
 let btl: Bool
 var total: Int { stage + bonus }
 var resolved: Int { counts.reduce(0, +) }
 var rank: String {
  if gameOver { return "E" }
  guard totalNotes > 0 else { return "—" }
  let good = counts[5] + counts[4], safe = good + counts[3]
  if counts[5] == totalNotes { return "Perfect!" }
  if good == totalNotes { return "S" }
  if Double(good) / Double(totalNotes) >= 0.95 { return "A" }
  if Double(good) / Double(totalNotes) >= 0.8 { return "B" }
  if Double(safe) / Double(totalNotes) >= 0.7 { return "C" }
  return "D"
 }
 mutating func apply(_ raw: Judgement, interlude: Bool = false, crimax: Bool = false) {
  if interlude {
   interludeResolved += 1
   if raw == .fine || raw == .cool { interludeSuccess += 1; stage += 1 }
   if totalInterlude > 0 && interludeResolved == totalInterlude && interludeSuccess == totalInterlude { stage += 39 }
   return
  }
  let result: Judgement = btl && (raw == .sad || raw == .worst) ? .none : raw
  counts[result.rawValue] += 1; stage += result.points
  if result == .fine || result == .cool {
   combo += 1; maxCombo = max(maxCombo, combo)
   bonus += min(500, ((combo + 5) / 10) * 50)
   if crimax && result == .cool && combo >= 100 { stage += 200 }
  } else if !btl { combo = 0 }
  if !btl {
   let weight = [0, -10, -5, 0, 2, 2][result.rawValue]
   gauge = min(256, max(0, gauge + Double(weight) * (64 / Double(max(1, totalNotes)) + 0.01)))
   let possible = counts[3] + counts[4] + counts[5] + max(0, totalNotes - resolved)
   gameOver = gauge <= 0 || possible * 2 < totalNotes
  }
 }
}

// Developer autoplay uses the same calibrated media ticks as manual judgement.
// A delayed callback catches up in note order; resolved IDs prevent duplicate hits.
enum AutoplayScheduler {
 static func due(notes:[Note],resolved:Set<Int>,time:Double,step:Int)->[Note] {
  guard time.isFinite else{return []}
  let tick=OriginalRules.tick(time)
  return notes.filter{$0.playable && !resolved.contains($0.id) && OriginalRules.justTick($0,step:step)<=tick}.sorted {
   let a=OriginalRules.justTick($0,step:step),b=OriginalRules.justTick($1,step:step)
   return a==b ? $0.id<$1.id:a<b
  }
 }
}
enum OriginalEffects {
 static func rainbow(combo:Int)->Bool {combo>=100}
 static func whirlLayers(combo:Int)->Int {combo>=45 ? 3:combo>=25 ? 2:combo>=5 ? 1:0}
 static func fireworksLayers(combo:Int,interlude:Bool,frame:Int)->Int {
  guard !interlude,frame<8 else{return 0}
  return combo>=85 ? 3:combo>=35 ? 2:combo>=15 ? 1:0
 }
 static func fireworksScale(layer:Int,combo:Int)->Double {
  if combo>=95{return 1.4}
  if layer<2 && combo>=75{return 1.35}
  if layer==1 && combo>=65 || layer==2{return 1.25}
  if layer==1 && combo>=55{return 1.15}
  return 1
 }
 static let rainbowRGB:[[Double]] = [[134, 253, 135], [164, 253, 135], [194, 253, 135], [224, 253, 135], [255, 254, 136], [255, 244, 121], [255, 230, 106], [255, 218, 91], [255, 202, 74], [255, 187, 118], [255, 172, 152], [255, 157, 200], [255, 136, 254], [235, 144, 254], [215, 152, 254], [190, 160, 254], [168, 168, 255], [143, 175, 255], [118, 182, 255], [93, 189, 255], [78, 199, 254], [93, 211, 254], [108, 225, 254], [123, 239, 254], [136, 254, 254], [136, 254, 224], [136, 254, 194], [136, 254, 164]]
 static func rainbowColorIndex(note:Note,time:Double)->Int {
  max(0,OriginalRules.tick(time)-OriginalRules.baseTick(note)+1+10)%28
 }
}
