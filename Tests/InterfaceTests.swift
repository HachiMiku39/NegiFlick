import Foundation
@main struct InterfaceCheck {
 static func main() {
  assert(!DeviceOrientationPolicy.supportsLandscape(isPad:false,modelIdentifier:"iPhone18,4"))
  assert(!DeviceOrientationPolicy.supportsLandscape(isPad:false,modelIdentifier:""))
  assert(DeviceOrientationPolicy.supportsLandscape(isPad:false,modelIdentifier:"iPhone19,4"))
  assert(DeviceOrientationPolicy.supportsLandscape(isPad:true,modelIdentifier:"iPad17,1"))
  print("PASS: ordinary iPhones portrait only; iPhone Duo and iPad retain landscape")
  let cases:[([String],Language)]=[(["en-US"],.en),(["ja-JP"],.ja),(["zh-Hans-CN"],.zh),(["zh-Hant-TW"],.zh),(["zh-HK"],.zh),(["fr-FR"],.fr),(["ko-KR","ja-JP","en"],.ko),(["en","zh-Hant"],.en),(["es-MX"],.es),(["de-DE","es-ES","en"],.es),(["de-DE"],.en),([],.en)]
  for (preferences,expected) in cases {let actual=Language.system(preferredLanguages:preferences);assert(actual==expected,"\(preferences): \(actual) != \(expected)")}
  assert(KeyboardStyle.selected(roman:false,full:true) == .original)
  assert(KeyboardStyle.selected(roman:true,full:false) == .romanSupport)
  assert(KeyboardStyle.selected(roman:true,full:true) == .fullRoman)
  assert((0...4).map{KeyboardStyle.guideSprite(direction:$0)} == [0,3,1,4,2])
  assert((1...4).map{KeyboardStyle.flowerSprite(direction:$0)} == [2,0,3,1])
  for style in KeyboardStyle.allCases {
   for kana in "あがぱぁっゃんゔーアガパァッャンヴ".map(String.init){assert(NoteGlyph.lookup(kana,style:style) != nil,"Missing original note glyph: \(kana)")}
   assert(NoteGlyph.lookup("か\u{3099}",style:style)==NoteGlyph.lookup("が",style:style))
   assert(NoteGlyph.lookup("は\u{309A}",style:style)==NoteGlyph.lookup("ぱ",style:style))
   assert(NoteGlyph.lookup("が",style:style)?.x==390)
   assert(NoteGlyph.lookup("ぱ",style:style)?.y==390)
   assert(NoteGlyph.lookup("っ",style:style)?.x==624)
   assert(NoteGlyph.lookup("ー",style:style)?.x==858)
   assert(NoteGlyph.lookup("ゎ",style:style)?.scale==0.72)
   assert(NoteGlyph.lookup("ヴ",style:style)?.atlas=="note_katakana_telop")
   assert(NoteGlyph.lookup("が",style:style,active:false)?.atlas=="note_hiragana_"+style.family+"_blank")
   assert(NoteGlyph.lookup("A",style:style)==nil)
  }
  print("PASS: original note atlases for hiragana/katakana, voiced/semivoiced/small kana, long vowel and Unicode combining marks")
  var ordered=MVPlaybackOrder(songIDs:["a","b","a","c"],loop:false)
  assert(ordered.songIDs == ["a","b","c"] && ordered.currentID == "a")
  assert(ordered.advance() == "b" && ordered.advance() == "c" && ordered.advance() == nil)
  ordered.restart();assert(ordered.currentID == "a")
  var looping=MVPlaybackOrder(songIDs:["a","b"],loop:true)
  assert(looping.advance() == "b" && looping.advance() == "a")
  var single=MVPlaybackOrder(songIDs:["a"],loop:true);assert(single.advance() == "a")
  var empty=MVPlaybackOrder(songIDs:[],loop:true);assert(empty.currentID == nil && empty.advance() == nil)
  let subtitles=SubtitleMap(["テスト　です":" Test line ","未翻訳":" ","ＡＢＣ":"Wide letters"])
  assert(subtitles.translation(for:"テスト です",language:.en) == "Test line")
  assert(subtitles.translation(for:"テスト\nです",language:.zh) == "Test line")
  assert(subtitles.translation(for:"テストです",language:.ja) == nil)
  assert(subtitles.translation(for:"未翻訳",language:.zh) == nil)
  assert(subtitles.translation(for:"missing",language:.en) == nil)
  assert(subtitles.translation(for:"ABC",language:.en) == "Wide letters")
  assert(subtitles.translation(for:"テストです。",language:.zh) == nil)
  let known:Set<String>=["song","pack11.song"]
  func document(_ language:String="zh-Hans",id:String="song",lines:[String:String]=["原文":"Translation"],url:String?="https://example.com/translation",version:Int=1)->SubtitleDocument {SubtitleDocument(formatVersion:version,translations:[SubtitleTrack(songID:id,language:language,lines:lines,sourceURL:url,translator:nil,license:nil)])}
  func rejects(_ value:SubtitleDocument)->Bool {do{try value.validate(songIDs:known);return false}catch{return true}}
  assert(!rejects(document()))
  assert(!rejects(document("en",id:"pack11.song")))
  assert(rejects(document("ja")))
  assert(rejects(document(id:"../song")))
  assert(rejects(document(id:"unknown")))
  assert(rejects(document(url:"file:///etc/passwd")))
  assert(rejects(document(version:2)))
  assert(rejects(document(lines:[:])))
  assert(rejects(document(lines:["  ":"Text"])))
  assert(rejects(document(lines:["原文":"One","原 文":"Two"])))
  assert(!rejects(document(lines:["原文":"One","原 文":"One"])))
  let duplicate=SubtitleDocument(formatVersion:1,translations:document().translations+document("zh").translations)
  assert(rejects(duplicate))
  let mixed=SubtitleDocument(formatVersion:1,translations:document().translations+document("en").translations)
  let encoded=try! JSONEncoder().encode(mixed)
  assert(!rejects(try! JSONDecoder().decode(SubtitleDocument.self,from:encoded)))
  let gameplayNames:[String:String] = ["difficultyEasy":"EASY","difficultyNormal":"NORMAL","difficultyHard":"HARD","difficultyExtreme":"EXTREME","difficultyBreak":"BREAK THE LIMIT","normalMode":"NORMAL MODE","judgementNone":"","judgementWorst":"WORST","judgementSad":"SAD","judgementSafe":"SAFE","judgementFine":"FINE","judgementCool":"COOL","fast":"FAST","late":"LATE"]
  for language in Language.allCases {for (key,expected) in gameplayNames {assert(UIStrings.text(key,language:language)==expected,"Gameplay token changed: \(key), \(language)")}}
  let englishNames:Set<String>=["normalMode","judgementNone","difficultyEasy","difficultyNormal","difficultyHard","difficultyExtreme","difficultyBreak","judgementWorst","judgementSad","judgementSafe","judgementFine","judgementCool","fast","late"]
  for (key,values) in UIStrings.values {
   assert(values.count==6,"Six languages required: \(key)")
   assert(!values[2].isEmpty || key=="judgementNone","Missing Simplified Chinese: \(key)")
   if englishNames.contains(key){for language in Language.allCases{assert(UIStrings.text(key,language:language)==values[0],"English gameplay name required: \(key), \(language)")}}else{assert(values[2] != values[0],"Untranslated Chinese UI: \(key)")}
   for index in 3..<6{assert(!values[index].isEmpty || key=="judgementNone","Missing added language: \(key)")}
  }
  for key in ["paused","inputTiming","score","combo","highScore","totalScore","maxCombo","panelGuide","flower","errorMedia"] {
   let chinese=UIStrings.text(key,language:.zh)
   assert(chinese.unicodeScalars.contains{(0x4E00...0x9FFF).contains($0.value)},"Expected Chinese UI: \(key)")
  }
  assert(String(format:UIStrings.text("songsSelected",language:.zh),2,1,14)=="已选择 2 首 [1 / 14]")
  assert(String(format:UIStrings.text("timingPosition",language:.zh),5.0)=="原版档位 +5")
  assert(BestRank.strongest(["E","B","A","C"])=="A")
  assert(BestRank.strongest(["S","Perfect!","B"])=="Perfect!")
  assert(BestRank.strongest(["B","E"])=="B")
  assert(BestRank.strongest([])==nil && BestRank.strongest(["Unknown"])==nil)
  for language in ["fr","es","ko"]{assert(!rejects(document(language)))}
  assert(TypographyPolicy.fallback(language:.ko)=="AppleSDGothicNeo-Regular")
  assert(TypographyPolicy.latin=="Futura-Medium")
  assert(TypographyPolicy.fallback(language:.zh)=="PingFangSC-Regular")
  let counts=[83,4,0,4,0,0,18,2,602,0,602]
  assert(ResultCountup.rowDuration(0)==0.12)
  assert(ResultCountup.digit(value:602,columnFromRight:0,elapsed:0)==0)
  assert(ResultCountup.digit(value:602,columnFromRight:2,elapsed:0.08)==0)
  assert(ResultCountup.digit(value:602,columnFromRight:0,elapsed:1)==2)
  assert(ResultCountup.digit(value:602,columnFromRight:2,elapsed:1)==6)
  assert(ResultCountup.rowElapsed(0,slot:1,values:counts)<0)
  for (slot,value) in counts.enumerated(){
   let final=ResultCountup.rowElapsed(ResultCountup.totalDuration(counts),slot:slot,values:counts)
   for (column,digit) in String(value).reversed().enumerated(){assert(ResultCountup.digit(value:value,columnFromRight:column,elapsed:final)==Int(String(digit))!)}
   assert(ResultCountup.digit(value:value,columnFromRight:0,elapsed:.infinity)==value%10)
  }
  print("PASS: difficulty, mode, judgement, FAST and LATE are English in all six languages")
  print("PASS: result row sequencing, units-first roll, zero counts, exact final digits and instant skip")
  print("PASS: all \(UIStrings.values.count) dynamic UI strings include Simplified Chinese; formatted copy; Futura/PingFang/Korean system policy")
  print("PASS: iOS preference ordering; Japanese; both Chinese scripts; English fallback; unsupported languages")
  print("PASS: three keyboard styles; panel-guide direction and inward flower sprite mappings")
  print("PASS: MV order, deduplication, stop, restart, loop, best ranks, one-song and empty lists")
  print("PASS: bilingual subtitle lookup, Japanese-only display, missing translation, Unicode/spacing normalization, punctuation distinction")
  print("PASS: subtitle JSON round trip; installed/DLC IDs; language, source URL, path, version, duplicate and conflicting-line validation")
 }
}
