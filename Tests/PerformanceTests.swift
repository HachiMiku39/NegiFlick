import Foundation
@main struct PerformanceTests {
 static func main(){
  var a=PerformanceAccumulator();a.reset(time:10,cpu:1)
  a.frame(at:10);for frame in 1...60{a.frame(at:10+Double(frame)/60)}
  let one=a.sample(time:11,cpu:1.25)
  assert(abs(one.cpuPercent!-25)<0.0001);assert(abs(one.uiFPS!-60)<0.0001)
  let multi=a.sample(time:12,cpu:3.25);assert(multi.cpuPercent==200)
  assert(a.sample(time:12,cpu:3.25).cpuPercent==nil)
  a.reset(time:100,cpu:nil);assert(a.sample(time:101,cpu:0.1).cpuPercent==nil)
  assert(a.sample(time:102,cpu:nil).cpuPercent==nil)
  a.reset(time:0,cpu:0);a.frame(at:0);for i in 1...10{a.frame(at:Double(i)/10)}
  assert(a.sample(time:1,cpu:0.2).uiFPS==10)
  a.reset(time:2,cpu:0.5);assert(a.sample(time:3,cpu:0.4).cpuPercent==nil)
  assert(DisplayRefreshPolicy.maximum(screenMaximum:60)==60)
  assert(DisplayRefreshPolicy.maximum(screenMaximum:120)==120)
  assert(DisplayRefreshPolicy.maximum(screenMaximum:240)==120)
  a.reset(time:0,cpu:0);a.frame(at:0)
  for i in 1...120{a.frame(at:Double(i)/120)}
  assert(abs(a.sample(time:1,cpu:0.3).uiFPS!-120)<0.0001)
  a.reset(time:0,cpu:0);a.frame(at:0)
  for i in 1...60{a.frame(at:Double(i)/120)}
  for i in 1...30{a.frame(at:0.5+Double(i)/60)}
  assert(abs(a.sample(time:1,cpu:0.3).uiFPS!-90)<0.0001)
  guard let actual=ProcessPerformanceSample.read() else{fatalError("Process sample unavailable")}
  assert(actual.cpuSeconds>=0);assert(actual.memoryBytes ?? 0 > 0)
  print("PASS: actual process CPU/RAM, per-core percentages, 120/60/10 FPS and changing cadence, invalid samples and background reset")
 }
}
