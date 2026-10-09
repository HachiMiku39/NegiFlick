import Foundation
import Darwin

/// App process measurements, not whole-device load. 100% CPU means one busy core.
struct ProcessPerformanceSample {
 let cpuSeconds:Double
 let memoryBytes:UInt64?
 static func read()->Self? {
  var usage=rusage()
  guard getrusage(RUSAGE_SELF,&usage)==0 else{return nil}
  func seconds(_ t:timeval)->Double {Double(t.tv_sec)+Double(t.tv_usec)/1_000_000}
  var vm=task_vm_info_data_t()
  var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
  let result=withUnsafeMutablePointer(to:&vm){pointer in
   pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)){task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)}
  }
  return Self(cpuSeconds:seconds(usage.ru_utime)+seconds(usage.ru_stime),memoryBytes:result == KERN_SUCCESS ? vm.phys_footprint:nil)
 }
}

struct PerformanceAccumulator {
 private var previous:(time:Double,cpu:Double)?
 private var frames=0
 private var frameStart:Double?
 mutating func reset(time:Double,cpu:Double?) {
  previous=cpu.map{(time,$0)};frames=0;frameStart=nil
 }
 mutating func frame(at time:Double) {
  if frameStart == nil {frameStart=time;return}
  frames+=1
 }
 mutating func sample(time:Double,cpu:Double?)->(cpuPercent:Double?,uiFPS:Double?) {
  let percent:Double?
  if let cpu,let p=previous,time>p.time,cpu>=p.cpu {percent=100*(cpu-p.cpu)/(time-p.time)}else{percent=nil}
  previous=cpu.map{(time,$0)}
  let fps=frameStart.flatMap{time>$0 ? Double(frames)/(time-$0):nil}
  frames=0;frameStart=time
  return (percent,fps)
 }
}
