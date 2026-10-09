import Foundation

// Supply user-owned original resources and the app's converted Mov_0 folder.
// No original recordings or charts are included in this repository.
@main struct LegacyInitialPackTests {
 static func main() throws {
  let args=CommandLine.arguments
  guard args.count==3 else{fatalError("Usage: legacy-initial-tests ORIGINAL_ASSETS IMPORTED_MOV_0")}
  let original=URL(fileURLWithPath:args[1]),installed=URL(fileURLWithPath:args[2])
  let ids=["Just_be_friends","cloverclub","hajimete_no_oto","hatsune_miku_no_gekisyou","koi_wa_sensou","magnet","migikata_no_tyou","promise","roshin_yuukai","tajyuumirai_no_quartet","ura_omote_lovers"]
  let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:installed.appendingPathComponent("miku64-songs.json"))) as! [[String:Any]]
  assert(manifest.count==ids.count)
  assert(Set(manifest.compactMap{$0["id"] as? String})==Set(ids.map{"pack0."+$0}))
  assert(manifest.allSatisfy{($0["artist"] as? String).map{!$0.isEmpty && $0 != "$null"} ?? false})
  for id in ids {
   let raw=try UTFTable.chart(original.appendingPathComponent(id+".usm"))
   let converted=try JSONDecoder().decode(Chart.self,from:Data(contentsOf:installed.appendingPathComponent("Playback/"+id+".json")))
   assert(converted.inputLanguage == .japanese)
   assert(raw.events.count==converted.events.count)
   assert(zip(raw.events,converted.events).allSatisfy{$0.time==$1.time && $0.parameter==$1.parameter})
   for difficulty in Difficulty.allCases {
    let before=ChartCompiler.notes(raw,difficulty),after=ChartCompiler.notes(converted,difficulty)
    assert(before.count==after.count)
    assert(zip(before,after).allSatisfy{$0.time==$1.time && $0.kana==$1.kana && $0.code==$1.code && $0.key==$1.key && $0.direction==$1.direction && $0.interlude==$1.interlude && $0.crimax==$1.crimax && $0.timingBPM==$1.timingBPM})
    let playable=after.filter(\.playable),normal=playable.filter{!$0.interlude},interlude=playable.filter(\.interlude)
    assert(!normal.isEmpty && normal.allSatisfy{(0...9).contains($0.key) && (0...4).contains($0.direction) && $0.inputLabel==nil})
    var score=OriginalScore(totalNotes:normal.count,totalInterlude:interlude.count,btl:difficulty == .breakLimit)
    for note in playable{score.apply(.cool,interlude:note.interlude,crimax:note.crimax)}
    assert(score.counts[5]==normal.count && score.maxCombo==normal.count && !score.gameOver)
    print("\(id) \(difficulty.label): \(normal.count) COOL, \(interlude.count) interlude, \(score.stage) + \(score.bonus) = \(score.total)")
   }
  }
  print("PASS: 11 registered songs; original cue equality and five difficulties (55 charts), Japanese key/direction mapping and scoring.")
 }
}
