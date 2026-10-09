import Foundation
@main enum InputLanguageTests {
 static func check(_ actual:NoteInputLanguage,_ expected:NoteInputLanguage){precondition(actual==expected)}
 static func main()throws {
  check(try InputLanguageResolver.resolve(declared:"zh-Hans",targets:["あ"]), .chinese)
  check(try InputLanguageResolver.resolve(declared:"en-US",targets:["A"]), .english)
  check(try InputLanguageResolver.resolve(declared:nil,targets:["あ","ア","ー"]), .japanese)
  check(try InputLanguageResolver.resolve(declared:nil,targets:["hello"]), .english)
  check(try InputLanguageResolver.resolve(declared:nil,targets:["愛"],legacy:true), .japanese)
  for targets in [["你好"],["愛"],["a","あ"],["123"]]{do{_ = try InputLanguageResolver.resolve(declared:nil,targets:targets);fatalError("ambiguous chart accepted")}catch{}}
  do{_ = try InputLanguageResolver.resolve(declared:"ru",targets:["a"]);fatalError("unknown language accepted")}catch{}
  var positions=Set<String>()
  for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {let position=LetterInputMap.position(String(c))!;precondition((1...8).contains(position.key) && (0...3).contains(position.direction));positions.insert("\(position.key):\(position.direction)")}
  precondition(positions.count==26)
  precondition(LetterInputMap.position("ni")==nil && LetterInputMap.position("你")==nil)
  let undeclaredChinese=AuthoredChart(schemaVersion:1,bpm:120,duration:30,leadTimeMS:1700,notes:[AuthoredNote(time:3,kana:"你",difficulties:["NORMAL"],crimax:false,input:"N")],lyrics:[])
  do{_ = try ChartAuthoringCompiler.compile(undeclaredChinese);fatalError("phonetic input hid ambiguous Han display targets")}catch{}
  for (language,symbol,input) in [("en","Z",Optional<String>.none),("zh","你",Optional("n"))] {
   let source=AuthoredChart(schemaVersion:1,bpm:120,duration:30,leadTimeMS:1700,notes:[AuthoredNote(time:3,kana:symbol,difficulties:["NORMAL"],crimax:false,input:input)],lyrics:[],inputLanguage:language)
   let chart=try ChartAuthoringCompiler.compile(source);try ChartDataValidator.validate(chart,duration:30)
   let note=ChartCompiler.notes(chart,.normal).filter(\.playable)[0],position=LetterInputMap.position(input ?? symbol)!
   precondition(note.key==position.key && note.direction==position.direction && note.kana==symbol && note.inputLabel==(input ?? symbol).uppercased())
   let just=OriginalRules.justTick(note,step:0)
   precondition(just==90)
   precondition(OriginalRules.flick(just:just,down:just,up:just,boardMatches:true,directionMatches:true) == .cool)
   precondition(OriginalRules.flick(just:just,down:just,up:just,boardMatches:true,directionMatches:false) == .safe)
  }
  for (text,input,language,expected) in [("你",Optional<String>.none,NoteInputLanguage.chinese,"N"),("重",Optional("C"),.chinese,"C"),("Hello",nil,.english,"H"),("don't",nil,.english,"D")] {
   let initial=try InitialInputTarget.resolve(text,input:input,language:language)
   precondition(initial==expected)
  }
  for (text,input,language) in [("Hello world",Optional<String>.none,NoteInputLanguage.english),("Hello",Optional("L"),.english),("你好",nil,.chinese),("你",Optional("ni"),.chinese),("N",nil,.chinese)] {
   do{_ = try InitialInputTarget.resolve(text,input:input,language:language);fatalError("invalid initial target accepted")}catch{}
  }
  for (language,targets,expected) in [("en",["Hello","world"],["H","W"]),("zh",["你","好"],["N","H"])] {
   let source=AuthoredChart(schemaVersion:1,bpm:120,duration:30,leadTimeMS:1700,notes:targets.enumerated().map{AuthoredNote(time:3+Double($0.offset)*2,kana:$0.element,difficulties:["NORMAL"],crimax:false)},lyrics:[],inputLanguage:language)
   let chart=try ChartAuthoringCompiler.compile(source)
   let restored=try JSONDecoder().decode(Chart.self,from:JSONEncoder().encode(chart))
   try ChartDataValidator.validate(restored,duration:30)
   let notes=ChartCompiler.notes(restored,.normal).filter(\.playable)
   precondition(notes.count==2 && notes.map(\.displayText)==targets && notes.map{$0.inputLabel!}==expected)
   if language=="en" {
    var malformed=restored
    malformed.noteWords![malformed.noteWords!.keys.first!]="wrong word"
    do{try ChartDataValidator.validate(malformed,duration:30);fatalError("malformed word metadata accepted")}catch{}
   }
  }
  print("PASS: one Han character / English word per note; initial derivation, polyphonic override, invalid units, word round-trip and target validation")
  print("PASS: declared language priority, legacy Japanese, kana/Latin detection, Han ambiguity and unsupported-language rejection")
 }
}
