import Foundation
@main struct CustomChartTests {
 static func rejects(_ f:()->Void){}
 static func rejection(_ f:()throws->Void){var failed=false;do{try f()}catch{failed=true};precondition(failed)}
 static func main()throws {
  let source=try JSONDecoder().decode(AuthoredChart.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
  let chart=try ChartAuthoringCompiler.compile(source);try ChartDataValidator.validate(chart,duration:30)
  for difficulty in Difficulty.allCases{
   let notes=ChartCompiler.notes(chart,difficulty).filter(\.playable)
   let expected=source.notes.filter{$0.difficulties.contains(ChartAuthoringCompiler.slots[difficulty.rawValue])}.sorted{$0.time<$1.time}
   precondition(notes.count==expected.count)
   for(n,a) in zip(notes,expected){precondition(OriginalRules.justTick(n,step:0)==OriginalRules.tick(a.time));precondition(n.kana==a.kana && n.crimax==a.crimax)}
  }
  for path in ["../escape.mp4","/absolute.mp4","a//b","a/./b","a/../b","a\\b",""]{rejection{try CustomPackManifest.validatePath(path)}}
  let dup=AuthoredNote(time:5,kana:"あ",difficulties:["NORMAL"],crimax:false)
  rejection{_ = try ChartAuthoringCompiler.compile(AuthoredChart(schemaVersion:1,bpm:120,duration:30,leadTimeMS:1700,notes:[dup,dup],lyrics:[]))}
  for bad in [Cue(time:.nan,parameter:"1"),Cue(time:0,parameter:"execute"),Cue(time:0,parameter:"7-100"),Cue(time:0,parameter:"80000"),Cue(time:0,parameter:"0あ11111script")]{rejection{try ChartDataValidator.validate(Chart(events:[bad]),duration:30)}}
  let fm=FileManager.default,temp=fm.temporaryDirectory.appendingPathComponent("NegiPaths-"+UUID().uuidString);try fm.createDirectory(at:temp,withIntermediateDirectories:true);defer{try? fm.removeItem(at:temp)}
  try fm.createSymbolicLink(at:temp.appendingPathComponent("escape"),withDestinationURL:temp.deletingLastPathComponent())
  rejection{_ = try CustomPackManifest.asset("escape/something",in:temp)}
  let trace=chart.events.filter{$0.parameter.hasPrefix("6")};precondition(!trace.isEmpty)
  print("PASS: five difficulty masks, exact 30 Hz hit ticks, Crimax pairing, duplicate rejection, bounded data-only commands, archive paths and symlink escape")
 }
}
