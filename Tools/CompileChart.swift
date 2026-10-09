import Foundation
@main enum CompileChart {
 static func main()throws {
  guard CommandLine.arguments.count==3 else{throw ChartPackageError.invalid("Usage: compile-chart authoring.json chart.json")}
  let source=try JSONDecoder().decode(AuthoredChart.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
  let chart=try ChartAuthoringCompiler.compile(source);try ChartDataValidator.validate(chart,duration:source.duration)
  try JSONEncoder().encode(chart).write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
  for difficulty in Difficulty.allCases {
   let notes=ChartCompiler.notes(chart,difficulty).filter(\.playable)
   var score=OriginalScore(totalNotes:notes.count,totalInterlude:0,btl:difficulty == .breakLimit)
   for note in notes {score.apply(.cool,crimax:note.crimax)}
   print("\(difficulty.label): \(notes.count) notes, \(score.total) points, \(score.rank)")
  }
 }
}
