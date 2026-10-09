import Foundation

// Author times are hit times on the media clock, never USM creation times.
struct AuthoredChart: Codable {
 let schemaVersion: Int
 let bpm: Int
 let duration: Double
 let leadTimeMS: Int
 let notes: [AuthoredNote]
 let lyrics: [AuthoredLyric]
 var inputLanguage:String?=nil
}
struct AuthoredNote: Codable {
 let time: Double
 let kana: String
 let difficulties: [String]
 let crimax: Bool
 var input:String?=nil
}
struct AuthoredLyric: Codable { let time: Double; let text: String }
enum ChartPackageError: Error { case invalid(String) }
enum ChartAuthoringCompiler {
 static let slots = ["EASY", "NORMAL", "HARD", "EXTREME", "BTL"]
 static let accepted = Set(Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんー〜がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔぁぃぅぇぉゃゅょっゎ").map(String.init))
 static func compile(_ source: AuthoredChart,declaredLanguage:String?=nil) throws -> Chart {
  if let authored=source.inputLanguage,let declaredLanguage{guard try NoteInputLanguage.parse(authored)==NoteInputLanguage.parse(declaredLanguage) else{throw ChartPackageError.invalid("Conflicting input language declarations")}}
  let language=try InputLanguageResolver.resolve(declared:source.inputLanguage ?? declaredLanguage,targets:source.notes.map(\.kana))
  guard source.schemaVersion == 1, (40...400).contains(source.bpm), source.duration.isFinite, source.duration > 0, source.duration <= 600,
        (1000...5000).contains(source.leadTimeMS), !source.notes.isEmpty, source.notes.count <= 10000 else {
   throw ChartPackageError.invalid("Invalid header or note count")
  }
  let lead = Double(source.leadTimeMS) / 1000
  let probe = Note(id: 0, time: lead, kana: "あ", code: 1, key: 0, interlude: false, timingBPM: source.bpm, leadTime: lead)
  let offset = OriginalRules.justTick(probe, step: 0)
  var events = [Cue(time: 0, parameter: "7\(source.leadTimeMS)"), Cue(time: 0, parameter: "8\(source.bpm)"), Cue(time: 0.05, parameter: "1")]
  var occupied = Array(repeating: Set<Int>(), count: 5)
  var eventInputs:[Int:String]=[:]
  var eventWords:[Int:String]=[:]
  for n in source.notes {
   let kana = hiragana(n.kana)
   let input=language == .japanese ? nil:try InitialInputTarget.resolve(n.kana,input:n.input,language:language)
   guard n.time.isFinite, n.time > 0, n.time < source.duration - 0.5,
         (language == .japanese ? n.kana.count == 1 && accepted.contains(kana) && n.input == nil:input != nil), !n.difficulties.isEmpty,
         Set(n.difficulties).count == n.difficulties.count, n.difficulties.allSatisfy(slots.contains) else {
    throw ChartPackageError.invalid("Invalid note at \(n.time)")
   }
   let target = OriginalRules.tick(n.time), spawn = target - offset
   guard spawn > 0 else { throw ChartPackageError.invalid("First note needs at least \(lead) seconds of preroll") }
   // Put the event inside its 30 Hz tick, away from floating-point boundaries.
   let cueTime = (Double(spawn) - 0.25) / 30
   let mask = slots.map { n.difficulties.contains($0) ? "1" : "0" }.joined()
   for i in slots.indices where n.difficulties.contains(slots[i]) {
    guard occupied[i].insert(target).inserted else { throw ChartPackageError.invalid("Simultaneous notes in \(slots[i]) tick \(target)") }
   }
   if let input{eventInputs[events.count]=input}
   if language == .english{eventWords[events.count]=n.kana}
   let symbol=language == .english ? input!:n.kana
   events.append(Cue(time: cueTime, parameter: "0" + symbol + mask))
   if n.crimax { events.append(Cue(time: cueTime, parameter: "6" + mask)) }
  }
  for l in source.lyrics {
   guard l.time.isFinite, l.time >= 0, l.time < source.duration, l.text.count <= 500 else { throw ChartPackageError.invalid("Invalid lyric") }
   events.append(Cue(time: l.time, parameter: "3" + l.text))
  }
  events.append(Cue(time: source.duration - 0.25, parameter: "2"))
  // Keep initialization and per-note Crimax markers in their authored order.
  let ordered = events.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }.map(\.element)
  let sorted=events.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }
  var inputs:[Int:String]=[:],words:[Int:String]=[:]
  for (newIndex,item) in sorted.enumerated(){if let input=eventInputs[item.offset]{inputs[newIndex]=input};if let word=eventWords[item.offset]{words[newIndex]=word}}
  return Chart(events: ordered,inputLanguage:language,noteInputs:inputs.isEmpty ? nil:inputs,noteWords:words.isEmpty ? nil:words)
 }
}


struct CustomPackManifest:Codable {
 let schemaVersion:Int;let id:String;let title:String;let artist:String
 let bpm:Int;let levels:[Int?];let chart:String;let media:String
 var cover:String?;var titleArtwork:String?;var authoring:Bool?;var translations:[String]?;var inputLanguage:String?
 func validate()throws {
  guard schemaVersion==1,!id.isEmpty,id.count<=64,id.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)}),!title.isEmpty,title.count<=200,artist.count<=200,(40...400).contains(bpm),levels.count==5,levels.compactMap({$0}).allSatisfy({(1...99).contains($0)}),media.lowercased().hasSuffix(".mp4") else {throw ChartPackageError.invalid("Invalid package manifest")}
  if let inputLanguage{_ = try NoteInputLanguage.parse(inputLanguage)}
  for path in paths{try Self.validatePath(path)}
 }
 var paths:[String] {[chart,media]+[cover,titleArtwork].compactMap{$0}+(translations ?? [])}
 static func validatePath(_ path:String)throws {
  guard !path.isEmpty,path.count<=240,!path.hasPrefix("/"),!path.contains("\\"),!path.contains("\0"),path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) else{throw ChartPackageError.invalid("Unsafe package path")}
 }
 static func asset(_ path:String,in root:URL)throws->URL {
  try validatePath(path)
  let base=root.resolvingSymlinksInPath().standardizedFileURL
  let url=base.appendingPathComponent(path)
  let resolved=url.resolvingSymlinksInPath().standardizedFileURL
  guard resolved.path.hasPrefix(base.path+"/"),try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile==true else{throw ChartPackageError.invalid("Missing or unsafe asset: \(path)")}
  return url
 }
}
enum ChartDataValidator {
 static func validate(_ chart:Chart,duration:Double)throws {
  guard duration.isFinite,duration>0,duration<=600,!chart.events.isEmpty,chart.events.count<=100000 else{throw ChartPackageError.invalid("Invalid chart duration or size")}
  for (index,input) in chart.noteInputs ?? [:] {
   guard chart.inputLanguage != nil,chart.inputLanguage != .japanese,chart.events.indices.contains(index),chart.events[index].parameter.hasPrefix("0"),LetterInputMap.position(input) != nil else{throw ChartPackageError.invalid("Invalid note input mapping")}
  }
  for (index,word) in chart.noteWords ?? [:] {
   guard chart.inputLanguage == .english,chart.events.indices.contains(index),chart.events[index].parameter.hasPrefix("0"),let initial=InitialInputTarget.englishInitial(word),chart.noteInputs?[index]==initial,Array(chart.events[index].parameter).dropFirst().first.map(String.init)==initial else{throw ChartPackageError.invalid("Invalid word initial mapping")}
  }
  var previous = -1.0
  for (eventIndex,event) in chart.events.enumerated() {
   let c=Array(event.parameter)
   guard event.time.isFinite,event.time>=previous,event.time>=0,event.time<duration,!c.isEmpty,c.count<=501 else{throw ChartPackageError.invalid("Invalid chart event")}
   previous=event.time
   let valid:Bool
   switch c[0] {
   case "0":
    let symbol=c.count>1 ? String(c[1]):""
    let language=chart.inputLanguage ?? .japanese
    let input=chart.noteInputs?[eventIndex] ?? symbol
    valid=c.count==7 && (language == .japanese ? ChartAuthoringCompiler.accepted.contains(hiragana(symbol)):(language == .chinese ? InitialInputTarget.isHan(symbol):InitialInputTarget.englishInitial(symbol)==input.uppercased()) && LetterInputMap.position(input) != nil) && c.dropFirst(2).allSatisfy({"012345".contains($0)})
   case "1","2":valid=c.count==1
   case "3":valid=true
   case "4":valid=(chart.inputLanguage == nil || chart.inputLanguage == .japanese) && c.count==2 && ChartAuthoringCompiler.accepted.contains(hiragana(String(c[1])))
   case "5":valid=c.count==6 && c.dropFirst().allSatisfy({"012".contains($0)})
   case "6":valid=c.count==6 && c.dropFirst().allSatisfy({"01".contains($0)})
   case "7":valid=Int(String(c.dropFirst())).map{(1000...5000).contains($0)} ?? false
   case "8":valid=Int(String(c.dropFirst())).map{(40...400).contains($0)} ?? false
   default:valid=false
   }
   guard valid else{throw ChartPackageError.invalid("Unsupported chart command: \(c[0])")}
  }
  guard Difficulty.allCases.contains(where:{!ChartCompiler.notes(chart,$0).filter(\.playable).isEmpty}) else{throw ChartPackageError.invalid("No playable notes")}
  for difficulty in Difficulty.allCases {
   for note in ChartCompiler.notes(chart,difficulty) where note.playable {
    let hit=Double(OriginalRules.justTick(note,step:0))/30
    guard hit>0,hit<duration else{throw ChartPackageError.invalid("Note falls outside media")}
   }
  }
 }
}
